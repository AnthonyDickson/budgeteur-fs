package budgeteur.feature.balancesheet

import budgeteur.data.db.tables.references.ACCOUNTS
import budgeteur.data.db.tables.references.CURRENT_BALANCES
import budgeteur.data.readTransactionsAfterClose
import budgeteur.data.toAccountBalance
import budgeteur.domain.Account
import budgeteur.domain.BalanceSheet
import budgeteur.domain.ItemValue
import budgeteur.domain.TransactionsAfterClose
import budgeteur.shared.Db
import budgeteur.shared.MONEY_PATTERN
import budgeteur.shared.errors
import budgeteur.shared.handle
import budgeteur.shared.json
import budgeteur.shared.log
import budgeteur.shared.userId
import io.ktor.http.HttpStatusCode
import io.ktor.openapi.JsonSchema
import io.ktor.server.response.respond
import io.ktor.server.routing.Route
import io.ktor.server.routing.get
import io.ktor.server.routing.openapi.describe
import java.util.UUID
import kotlinx.serialization.Serializable
import org.jooq.DSLContext

@Serializable
@JsonSchema.Description(
    "The user's balance sheet. It carries no statement date: the client draws it for its own " +
        "today, and each line has an as-of date. Closed lines are listed apart and left out of " +
        "the totals."
)
data class BalanceSheetResponse(
    @JsonSchema.Description("Every asset and liability that is not an account.")
    val items: List<BalanceSheetItemResponse>,
    @JsonSchema.Description("Every account with a known balance, as a line.")
    val accounts: List<AccountLineResponse>,
    @JsonSchema.Description("Accounts whose balance is unknown, left out of the totals.")
    val unknownBalances: List<UnknownBalanceResponse>,
    @JsonSchema.Description("Items that were sold or repaid, left out of the sheet.")
    val closedItems: List<BalanceSheetItemResponse>,
    @JsonSchema.Description("Accounts that were closed, left out of the sheet.")
    val closedAccounts: List<ClosedAccountResponse>,
    @JsonSchema.Description(
        "Total value of assets expected to be realised within the current period."
    )
    @JsonSchema.Pattern(MAGNITUDE_PATTERN)
    val totalCurrentAssets: String,
    @JsonSchema.Description(
        "Total value of liabilities expected to be settled within the current period."
    )
    @JsonSchema.Pattern(MAGNITUDE_PATTERN)
    val totalCurrentLiabilities: String,
    @JsonSchema.Description(
        "Total value of assets **not** expected to be realised within the current period."
    )
    @JsonSchema.Pattern(MAGNITUDE_PATTERN)
    val totalNonCurrentAssets: String,
    @JsonSchema.Description(
        "Total value of liabilities **not** expected to be settled within the current period."
    )
    @JsonSchema.Pattern(MAGNITUDE_PATTERN)
    val totalNonCurrentLiabilities: String,
    @JsonSchema.Description("Total value of everything owned, both current and non-current.")
    @JsonSchema.Pattern(MAGNITUDE_PATTERN)
    val totalAssets: String,
    @JsonSchema.Description("Total value of everything owed, both current and non-current.")
    @JsonSchema.Pattern(MAGNITUDE_PATTERN)
    val totalLiabilities: String,
    @JsonSchema.Description("Total assets minus total liabilities.")
    @JsonSchema.Pattern(MONEY_PATTERN)
    val netWorth: String,
    @JsonSchema.Description(
        "Current assets minus current liabilities: the near-term position. Unlike net worth it " +
            "excludes non-current debt, so it stays sensitive to near-term decisions."
    )
    @JsonSchema.Pattern(MONEY_PATTERN)
    val workingCapital: String,
)

/** What the sheet is drawn from: the open lines, and apart from them the closed ones. */
private data class SheetData(
    val sheet: BalanceSheet,
    val closedItems: List<ItemValue>,
    val closedAccounts: List<Account>,
    val afterClose: Map<UUID, TransactionsAfterClose>,
)

/**
 * The user's open items and accounts, and the closed ones apart. A close date cannot be in the
 * future, so every closed line is left out of the current sheet.
 */
private fun DSLContext.readSheet(userId: String): SheetData {
    val (closedItems, openItems) = readAllItems(userId).partition { it.item.closedOn != null }
    val (closedAccounts, openAccounts) =
        select(ACCOUNTS.fields().toList() + CURRENT_BALANCES.AS_OF + CURRENT_BALANCES.BALANCE)
            .from(ACCOUNTS)
            .leftJoin(CURRENT_BALANCES)
            .on(CURRENT_BALANCES.ACCOUNT_ID.eq(ACCOUNTS.ID))
            .where(ACCOUNTS.USER_ID.eq(userId))
            .orderBy(ACCOUNTS.NAME)
            .fetch { it.toAccountBalance() }
            .partition { it.account.closedOn != null }
    val afterClose =
        readTransactionsAfterClose(userId)
            .groupBy({ (accountId, _) -> accountId }) { it.second }
            .mapNotNull { (id, dates) -> TransactionsAfterClose.of(dates)?.let { id to it } }
            .toMap()
    return SheetData(
        BalanceSheet(openItems, openAccounts),
        closedItems,
        closedAccounts.map { it.account },
        afterClose,
    )
}

private fun SheetData.toResponse() =
    BalanceSheetResponse(
        items = sheet.items.map { it.toResponse() },
        accounts = sheet.accounts.mapNotNull { it.toLine() },
        unknownBalances = sheet.unknownBalances.map { it.toUnknownBalance() },
        closedItems = closedItems.map { it.toResponse() },
        closedAccounts = closedAccounts.mapNotNull { it.toClosed(afterClose[it.id]) },
        totalCurrentAssets = sheet.totalCurrentAssets.toString(),
        totalCurrentLiabilities = sheet.totalCurrentLiabilities.toString(),
        totalNonCurrentAssets = sheet.totalNonCurrentAssets.toString(),
        totalNonCurrentLiabilities = sheet.totalNonCurrentLiabilities.toString(),
        totalAssets = sheet.totalAssets.toString(),
        totalLiabilities = sheet.totalLiabilities.toString(),
        netWorth = sheet.netWorth.toString(),
        workingCapital = sheet.workingCapital.toString(),
    )

fun Route.readBalanceSheet(db: Db) =
    get("/api/balance-sheet") {
            call.handle {
                val userId = call.userId
                val data = db.transaction { readSheet(userId) }

                call.log.info("Returned balance sheet")
                call.respond(data.toResponse())
            }
        }
        .describe {
            summary = "Get balance sheet"
            description = "Returns the user's balance sheet. A user with no lines has an empty one."
            tag("Balance Sheets")
            responses {
                json<BalanceSheetResponse>(HttpStatusCode.OK)
                errors(HttpStatusCode.Unauthorized)
            }
        }
