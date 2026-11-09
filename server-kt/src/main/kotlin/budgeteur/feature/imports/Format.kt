package budgeteur.feature.imports

import arrow.core.Either
import arrow.core.raise.context.either
import arrow.core.raise.context.ensureNotNull
import arrow.core.raise.context.withError
import budgeteur.domain.AccountNumber
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.time.format.DateTimeParseException
import java.time.format.ResolverStyle

/** The date formats statements use, each parsed exactly and independent of locale. */
enum class DateFormat(val pattern: String) {
    IsoDate("yyyy-MM-dd"),
    SlashedDate("yyyy/MM/dd");

    // `uuuu` is the proleptic year, which strict resolution needs; `yyyy` is year of era.
    private val formatter =
        DateTimeFormatter.ofPattern(pattern.replace("yyyy", "uuuu"))
            .withResolverStyle(ResolverStyle.STRICT)

    fun parse(text: String): LocalDate? =
        try {
            LocalDate.parse(text, formatter)
        } catch (_: DateTimeParseException) {
            null
        }
}

/** How a statement signs its amounts. */
enum class Sign {
    /** Money in is positive, as the app stores it. */
    AsGiven,

    /** Money out is positive, as on a credit card statement. */
    Negated,
}

/** The order a statement lists its rows in. */
enum class RowOrder(val listed: String) {
    OldestFirst("oldest first"),
    NewestFirst("newest first"),
}

/** A statement's running balance: the account's balance after each row, and the date it changed. */
data class RunningBalance(
    val column: String,
    val dateColumn: String,
    /** Decides which row closes each date. A file whose balance dates run the other way fails. */
    val order: RowOrder,
)

/** The account a statement belongs to, as the statement names it. */
data class StatementAccount(
    val number: AccountNumber,
    /** The bank's name for the product, e.g. "Visa Light", when the statement gives one. */
    val productName: String? = null,
)

/** Where a format finds the statement's account number. */
sealed interface AccountSource {
    /** A column on every row. */
    data class Column(val name: String) : AccountSource

    /**
     * The lines before the header, read by a function that fails with a reason when they are not
     * the format's preamble.
     */
    data class Preamble(val read: (List<String>) -> Either<String, StatementAccount>) :
        AccountSource
}

/**
 * A field of a row that identifies the transaction across exports, for the import hash. See
 * decision 6 in docs/csv-import.md.
 */
sealed interface IdentityField {
    /** A column's text, trimmed. */
    data class Column(val name: String) : IdentityField

    /** A date column, in ISO form. */
    data class DateColumn(val name: String) : IdentityField

    /** The signed amount, with two decimal places. */
    data object Amount : IdentityField

    /** The running balance, with two decimal places. */
    data object Balance : IdentityField
}

/**
 * How to read one bank's CSV export, held as data and read by one interpreter. Fields name their
 * columns by header name, and the header must match exactly, so any change to the columns fails
 * detection instead of reading the wrong field. See decision 5 in docs/csv-import.md.
 */
data class Format(
    val name: String,
    /** The exact header line. */
    val header: String,
    val account: AccountSource,
    /** The date the transaction happened, not when it was processed. */
    val date: String,
    val dateFormat: DateFormat,
    /** Joined with a space, skipping empty ones. */
    val description: List<String>,
    /** The description when the description columns are empty. */
    val transactionType: String,
    val amount: String,
    val sign: Sign,
    val balance: RunningBalance?,
    /** The other party's account number, for transfer detection. */
    val otherPartyAccount: String?,
    /**
     * Chosen deliberately per format: a hash over fields that change when the export changes makes
     * every overlapping row look new.
     */
    val identity: List<IdentityField>,
)

/** The built-in formats. */
object Formats {
    val kiwibank =
        Format(
            name = "Kiwibank",
            header =
                "Account number,Effective Date,Transaction Date,Description,Transaction Code," +
                    "Particulars,Code,Reference,Other Party Name,Other Party Account Number," +
                    "Other Party Particulars,Other Party Code,Other Party Reference,Amount,Balance",
            account = AccountSource.Column("Account number"),
            date = "Effective Date",
            dateFormat = DateFormat.IsoDate,
            description = listOf("Description"),
            transactionType = "Transaction Code",
            amount = "Amount",
            sign = Sign.AsGiven,
            balance = RunningBalance("Balance", "Transaction Date", RowOrder.OldestFirst),
            otherPartyAccount = "Other Party Account Number",
            // The running balance tells apart two identical purchases on one day, and the
            // transaction date is the one the balance changes on, so both come from the same
            // ledger entry.
            identity =
                listOf(
                    IdentityField.DateColumn("Transaction Date"),
                    IdentityField.Amount,
                    IdentityField.Balance,
                ),
        )

    /** The line naming the card, e.g. "Card Number XXXX-XXXX-XXXX-1234 (Visa Light)". */
    private val cardLine = Regex("""^Card Number (\S+)(?: \((.+)\))?$""")

    /** ASB card statements start with when they were created, the card, and the date range. */
    private fun asbCardPreamble(lines: List<String>): Either<String, StatementAccount> = either {
        val card =
            ensureNotNull(lines.firstNotNullOfOrNull { cardLine.matchEntire(it.trim()) }) {
                "the lines before the header name no card number"
            }
        val number = card.groupValues[1]
        val account =
            withError({ _: String -> "\"$number\" is not a card number" }) {
                AccountNumber.create(number)
            }
        StatementAccount(account, card.groups[2]?.value)
    }

    val asbCard =
        Format(
            name = "ASB card",
            header =
                "Date Processed,Date of Transaction,Unique Id,Tran Type,Reference,Description," +
                    "Amount",
            account = AccountSource.Preamble(::asbCardPreamble),
            date = "Date of Transaction",
            dateFormat = DateFormat.SlashedDate,
            description = listOf("Description"),
            transactionType = "Tran Type",
            amount = "Amount",
            sign = Sign.Negated,
            balance = null,
            otherPartyAccount = null,
            // A date and a sequence number per card.
            identity = listOf(IdentityField.Column("Unique Id")),
        )

    val all = listOf(kiwibank, asbCard)
}
