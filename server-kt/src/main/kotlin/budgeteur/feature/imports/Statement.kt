package budgeteur.feature.imports

import arrow.core.Either
import arrow.core.NonEmptyList
import arrow.core.flattenOrAccumulate
import arrow.core.getOrElse
import arrow.core.nonEmptyListOf
import arrow.core.raise.Raise
import arrow.core.raise.context.bind
import arrow.core.raise.context.either
import arrow.core.raise.context.ensure
import arrow.core.raise.context.ensureNotNull
import arrow.core.raise.context.raise
import arrow.core.raise.context.withError
import arrow.core.raise.context.zipOrAccumulate
import arrow.core.raise.recover
import arrow.core.toNonEmptyListOrNull
import budgeteur.domain.AccountNumber
import budgeteur.domain.BalanceObservation
import budgeteur.domain.Money
import budgeteur.domain.TransactionDescription
import java.math.BigDecimal
import java.time.LocalDate

/**
 * The balance a row's running-balance column reports: the account's balance once the row is
 * applied, and the date it is accurate as of, which may differ from the transaction date.
 */
data class BalanceAfter(val date: LocalDate, val balance: Money)

/** A statement row read into domain types. */
data class StatementRow(
    /** The row's line number in the file. */
    val line: Int,
    val date: LocalDate,
    val description: TransactionDescription,
    /** Signed as the app stores it: money in is positive. */
    val amount: Money,
    /** When the format has a running balance. */
    val balance: BalanceAfter?,
    /** When the row names the other party's account and it is an account number. */
    val otherPartyAccount: AccountNumber?,
    /** Recognises the row in a later import. See decision 6 in docs/csv-import.md. */
    val importHash: String,
)

/** Why a file, or a row in it, cannot be imported. */
data class ImportError(
    val fileName: String,
    /** Null for a problem with the file as a whole. */
    val line: Int?,
    val message: String,
) {
    fun describe() = if (line != null) "$fileName line $line: $message" else "$fileName: $message"
}

/**
 * One CSV file read into domain types: the transactions of one account, and its daily closing
 * balances when the statement has them.
 */
data class Statement(
    val fileName: String,
    /** The name of the format the file was read with. */
    val format: String,
    val account: StatementAccount,
    val rows: List<StatementRow>,
    /**
     * One per balance date: the balance after the date's last row, by the format's row order. See
     * decision 3 in docs/csv-import.md.
     */
    val observations: List<BalanceObservation>,
) {
    // The interpreter for formats: detection, then reading each row. This is the adapter between
    // the banks' exports and the domain. See decisions 5 and 7 in docs/csv-import.md.
    companion object {
        /**
         * Reads a file with the first format it matches. Fails with every problem found: no
         * matching format, or each row that cannot be read.
         */
        fun parse(
            formats: List<Format>,
            fileName: String,
            text: String,
        ): Either<NonEmptyList<ImportError>, Statement> = either {
            fun error(line: Int?, message: String) = ImportError(fileName, line, message)

            val lines = Csv.lines(text)
            val detected =
                withError({ message: String -> nonEmptyListOf(error(null, message)) }) {
                    detect(formats, lines)
                }
            val header =
                either<String, _> { Csv.fields(detected.format.header) }.getOrElse { emptyList() }
            val read =
                detected.rows
                    .map { line ->
                        readRow(detected.format, detected.account?.number, header, line).mapLeft {
                            messages ->
                            messages.map { error(line.number, it) }
                        }
                    }
                    .flattenOrAccumulate()
                    .bind()
            val account =
                withError({ errors: NonEmptyList<Pair<Int?, String>> ->
                    errors.map { (line, message) -> error(line, message) }
                }) {
                    account(detected, read)
                }
            val rows = read.map { it.row }
            val observations =
                withError({ (line, message): Pair<Int, String> ->
                    nonEmptyListOf(error(line, message))
                }) {
                    observations(detected.format, rows)
                }
            Statement(fileName, detected.format.name, account, rows, observations)
        }

        /** Reads every file, failing with the problems of all of them. */
        fun parseAll(
            formats: List<Format>,
            files: List<Pair<String, String>>,
        ): Either<NonEmptyList<ImportError>, List<Statement>> =
            files.map { (fileName, text) -> parse(formats, fileName, text) }.flattenOrAccumulate()
    }
}

/** A file that matched a format: the account its preamble names, if any, and the rows after it. */
private data class Detected(
    val format: Format,
    val account: StatementAccount?,
    val rows: List<CsvLine>,
)

/**
 * The file in the format, when its header is one of the file's lines, with no lines before it for a
 * format without a preamble, or lines the preamble function reads. Raises null when the header is
 * missing, and a reason when the preamble does not fit.
 */
context(_: Raise<String?>)
private fun detectAs(lines: List<CsvLine>, format: Format): Detected {
    val index = lines.indexOfFirst { it.text == format.header }
    ensure(index >= 0) { null }
    val rows = lines.drop(index + 1)
    return when (val source = format.account) {
        is AccountSource.Column -> {
            ensure(index == 0) { "the ${format.name} header is not on the first line" }
            Detected(format, null, rows)
        }
        is AccountSource.Preamble -> {
            val account =
                source
                    .read(lines.take(index).map { it.text })
                    .mapLeft { "$it for the ${format.name} format" }
                    .bind()
            Detected(format, account, rows)
        }
    }
}

/** The message for a file that matches no format: its start and each format's header. */
private fun noFormat(formats: List<Format>, lines: List<CsvLine>, reasons: List<String>): String {
    // Continuation lines are indented, so a reader of the joined errors of several files can tell
    // where this one ends.
    fun indent(text: String) = "    $text"
    return buildList {
            add("matches no known format.")
            reasons.forEach { add("  It looks close, but $it.") }
            add("  The file starts with:")
            lines.take(3).forEach { add(indent(it.text)) }
            add("  Expected one of these headers:")
            formats.forEach { add(indent("${it.name}: ${it.header}")) }
        }
        .joinToString("\n")
}

context(_: Raise<String>)
private fun detect(formats: List<Format>, lines: List<CsvLine>): Detected {
    val results = formats.map { format -> either { detectAs(lines, format) } }
    return results.firstNotNullOfOrNull { it.getOrNull() }
        ?: raise(noFormat(formats, lines, results.mapNotNull { it.leftOrNull() }))
}

/** A row read into domain types, with the account number the row or the preamble names. */
private data class ReadRow(val row: StatementRow, val accountNumber: AccountNumber)

/**
 * A sign and a decimal point, but no thousands separators or exponents, which no statement uses.
 * Either side of the point may be empty, as .NET's decimal parsing allows.
 */
private val amountPattern = Regex("""[+-]?(\d+\.?\d*|\.\d+)""")

/** The longest amount a `Long` of cents always holds. */
private const val MAX_AMOUNT_DIGITS = 17

/** An amount in the import hash's canonical form, e.g. -8.50, however the statement wrote it. */
private fun canonical(money: Money) = money.toString()

/** One row's fields by column name, read by the format. */
private class Fields(val format: Format, val values: Map<String, String>) {
    context(_: Raise<String>)
    fun text(column: String): String =
        ensureNotNull(values[column]) { "the format has no column \"$column\"" }.trim()

    context(_: Raise<String>)
    fun date(column: String): LocalDate {
        val value = text(column)
        return ensureNotNull(format.dateFormat.parse(value)) {
            "$column \"$value\" is not a date like ${format.dateFormat.pattern}"
        }
    }

    context(_: Raise<String>)
    fun money(column: String): Money {
        val value = text(column)
        val digits = value.trimStart('+', '-').substringBefore('.')
        ensure(amountPattern.matches(value) && digits.length <= MAX_AMOUNT_DIGITS) {
            "$column \"$value\" is not an amount"
        }
        return Money.round(BigDecimal(value))
    }

    context(_: Raise<String>)
    fun description(): TransactionDescription {
        val joined =
            format.description.map { text(it) }.filter { it.isNotEmpty() }.joinToString(" ")
        val description = joined.ifEmpty { text(format.transactionType) }
        return withError({ _: String -> "the row has no description" }) {
            TransactionDescription.create(description.take(TransactionDescription.MAX_LENGTH))
        }
    }

    context(_: Raise<String>)
    fun amount(): Money {
        val amount = money(format.amount)
        return when (format.sign) {
            Sign.AsGiven -> amount
            Sign.Negated -> -amount
        }
    }

    context(_: Raise<String>)
    fun balance(): BalanceAfter? =
        format.balance?.let { BalanceAfter(date(it.dateColumn), money(it.column)) }

    context(_: Raise<String>)
    fun accountNumber(statementNumber: AccountNumber?): AccountNumber =
        when (val source = format.account) {
            is AccountSource.Column -> AccountNumber.create(text(source.name))
            is AccountSource.Preamble ->
                ensureNotNull(statementNumber) { "the preamble names no account" }
        }

    /**
     * Another party's account may be anything the bank recorded, so a value that is not an account
     * number is no account.
     */
    context(_: Raise<String>)
    fun otherPartyAccount(): AccountNumber? =
        format.otherPartyAccount?.let { column ->
            val value = text(column)
            recover({ AccountNumber.create(value) }) { null }
        }

    context(_: Raise<String>)
    fun identity(amount: Money, balance: BalanceAfter?): List<String> =
        format.identity.map { field ->
            when (field) {
                is IdentityField.Column -> text(field.name)
                is IdentityField.DateColumn -> date(field.name).toString()
                IdentityField.Amount -> canonical(amount)
                IdentityField.Balance ->
                    canonical(
                        ensureNotNull(balance) {
                                "the format identifies rows by a running balance it does not have"
                            }
                            .balance
                    )
            }
        }
}

/**
 * Reads one row's fields by the format, reporting every field that fails. [statementNumber] is the
 * account number the preamble names, if the format has one.
 */
private fun readRow(
    format: Format,
    statementNumber: AccountNumber?,
    header: List<String>,
    line: CsvLine,
): Either<NonEmptyList<String>, ReadRow> = either {
    val values = withError(::nonEmptyListOf) { Csv.fields(line.text) }
    ensure(values.size == header.size) {
        nonEmptyListOf("expected ${header.size} fields like the header, but found ${values.size}")
    }
    val fields = Fields(format, header.zip(values).toMap())
    zipOrAccumulate(
        { fields.date(format.date) },
        { fields.description() },
        { fields.amount() },
        { fields.balance() },
        { fields.accountNumber(statementNumber) },
        { fields.otherPartyAccount() },
    ) { date, description, amount, balance, accountNumber, otherPartyAccount ->
        val identity = withError(::nonEmptyListOf) { fields.identity(amount, balance) }
        ReadRow(
            StatementRow(
                line = line.number,
                date = date,
                description = description,
                amount = amount,
                balance = balance,
                otherPartyAccount = otherPartyAccount,
                importHash = ImportHash.compute(accountNumber, identity),
            ),
            accountNumber,
        )
    }
}

/**
 * The statement's account: the preamble's, or the account column of the first row, which every
 * other row must repeat, since one statement holds one account.
 */
context(_: Raise<NonEmptyList<Pair<Int?, String>>>)
private fun account(detected: Detected, rows: List<ReadRow>): StatementAccount {
    detected.account?.let {
        return it
    }
    val first =
        rows.firstOrNull()
            ?: raise(nonEmptyListOf(null to "has no transactions, so its account is unknown"))
    val others = rows.filter { it.accountNumber != first.accountNumber }
    others.toNonEmptyListOrNull()?.let { differing ->
        raise(
            differing.map {
                it.row.line to
                    "the account number differs from the first row's, but a statement holds one " +
                        "account"
            }
        )
    }
    return StatementAccount(first.accountNumber)
}

/** The closing balance of each date, after checking the balance dates run in the row order. */
context(_: Raise<Pair<Int, String>>)
private fun observations(format: Format, rows: List<StatementRow>): List<BalanceObservation> {
    val balance = format.balance ?: return emptyList()
    val dated = rows.mapNotNull { row -> row.balance?.let { row.line to it } }
    dated
        .zipWithNext()
        .firstOrNull { (previous, next) ->
            when (balance.order) {
                RowOrder.OldestFirst -> next.second.date < previous.second.date
                RowOrder.NewestFirst -> next.second.date > previous.second.date
            }
        }
        ?.let { (previous, next) ->
            raise(
                next.first to
                    "the ${balance.dateColumn} ${next.second.date} is out of order after " +
                        "${previous.second.date}: ${format.name} statements list rows " +
                        balance.order.listed
            )
        }
    val inOrder =
        when (balance.order) {
            RowOrder.OldestFirst -> dated
            RowOrder.NewestFirst -> dated.reversed()
        }
    // A later row on a date replaces the earlier one's balance.
    return inOrder
        .associate { (_, after) -> after.date to after.balance }
        .toSortedMap()
        .map { (date, balance) -> BalanceObservation(date, balance) }
}
