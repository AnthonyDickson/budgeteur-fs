package budgeteur.feature.imports

import budgeteur.domain.Account
import budgeteur.domain.AccountName
import budgeteur.domain.AccountNumber
import budgeteur.domain.Categorisation
import budgeteur.domain.Rule
import budgeteur.domain.Term
import budgeteur.domain.Transaction
import budgeteur.domain.winner
import java.util.UUID

// The import workflow's rules, apart from the handler: which accounts to create, which rows are
// duplicates, which are transfers, and their tags. See decisions 4, 6, 8, and 9 in
// docs/csv-import.md.

/** A statement row to insert as a transaction. */
data class NewTransaction(
    val transaction: Transaction,
    val importHash: String,
    /**
     * A detected transfer, or for any other row the winning rule's tag if the policy applies it.
     */
    val categorisation: Categorisation?,
)

/** What an import did with the rows of its statements. */
data class ImportCounts(
    /** Rows inserted as transactions, transfers included. */
    val imported: Int,
    /** Rows the user had already imported, or that repeat an earlier row of the request. */
    val skippedDuplicates: Int,
    /** Imported rows between the user's own accounts. */
    val transfers: Int,
    /** Imported rows a rule tagged. */
    val taggedByRules: Int,
)

/** The statements' accounts the user has no account for, once each, in the statements' order. */
fun missingAccounts(
    userNumbers: Set<AccountNumber>,
    statements: List<Statement>,
): List<StatementAccount> =
    statements.map { it.account }.distinctBy { it.number }.filter { it.number !in userNumbers }

/**
 * An account created on import: named after its number and product, current, with an unknown
 * balance until its observations are recorded.
 */
fun createAccount(id: UUID, account: StatementAccount) =
    Account(
        id = id,
        number = account.number,
        name = AccountName.ofNumber(account.number, account.productName),
        term = Term.Current,
    )

/**
 * The rows to import: those whose hash the user does not have, keeping the first of rows that share
 * a hash within the request. Returns them with each row's statement, and the number skipped.
 */
fun dropDuplicates(
    userHashes: Set<String>,
    statements: List<Statement>,
): Pair<List<Pair<Statement, StatementRow>>, Int> {
    val rows = statements.flatMap { statement -> statement.rows.map { statement to it } }
    val seen = userHashes.toMutableSet()
    val kept = rows.filter { (_, row) -> seen.add(row.importHash) }
    return kept to rows.size - kept.size
}

/** Whether a row moves money between the user's own accounts: its other party's is theirs. */
fun isTransfer(userNumbers: Set<AccountNumber>, row: StatementRow): Boolean =
    row.otherPartyAccount in userNumbers

/**
 * The transactions to insert for the statements' new rows, and the counts. [accountIds] maps every
 * account number of the user, including accounts this import creates, to its account. A row
 * detection identifies is a detected transfer; any other row gets the winning rule's proposal
 * through the policy, so a row a transfer rule wins stays untagged. See decision 8 in
 * docs/transfer-rules.md.
 */
fun plan(
    newId: () -> UUID,
    accountIds: Map<AccountNumber, UUID>,
    userHashes: Set<String>,
    rules: List<Rule>,
    statements: List<Statement>,
): Pair<List<NewTransaction>, ImportCounts> {
    val (rows, skipped) = dropDuplicates(userHashes, statements)
    val winner = winner(rules)
    val transactions = rows.map { (statement, row) ->
        val categorisation =
            if (isTransfer(accountIds.keys, row)) {
                Categorisation.detectedTransfer
            } else {
                Categorisation.tagUntagged(
                    winner(row.description)?.let { Categorisation.applyRule(it.target) },
                    null,
                )
            }
        NewTransaction(
            Transaction(
                id = newId(),
                amount = row.amount,
                description = row.description,
                date = row.date,
                accountId = accountIds[statement.account.number],
            ),
            row.importHash,
            categorisation,
        )
    }
    return transactions to
        ImportCounts(
            imported = transactions.size,
            skippedDuplicates = skipped,
            transfers = transactions.count { it.categorisation is Categorisation.Transfer },
            taggedByRules = transactions.count { it.categorisation is Categorisation.Tagged },
        )
}
