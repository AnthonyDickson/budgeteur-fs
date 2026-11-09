@file:UseSerializers(UuidSerializer::class)

package budgeteur.feature.report

import arrow.core.NonEmptyList
import arrow.core.raise.Raise
import arrow.core.raise.context.ensureNotNull
import arrow.core.raise.context.withError
import arrow.core.raise.context.zipOrAccumulate
import budgeteur.data.readBalanceSheetHistory
import budgeteur.data.readEntries
import budgeteur.data.readFirstTransactionDate
import budgeteur.data.readTransactionsAfterClose
import budgeteur.domain.BalanceSheet
import budgeteur.domain.Frequency
import budgeteur.domain.Side
import budgeteur.domain.StatementLine
import budgeteur.domain.TagColor
import budgeteur.domain.Term
import budgeteur.domain.formatCalendarDate
import budgeteur.domain.parseCalendarDate
import budgeteur.shared.DATE_FORMAT
import budgeteur.shared.DECIMAL_PATTERN
import budgeteur.shared.Db
import budgeteur.shared.DomainError
import budgeteur.shared.EnumOf
import budgeteur.shared.MONEY_PATTERN
import budgeteur.shared.UuidSerializer
import budgeteur.shared.errors
import budgeteur.shared.handle
import budgeteur.shared.json
import budgeteur.shared.log
import budgeteur.shared.userId
import io.ktor.http.HttpStatusCode
import io.ktor.http.Parameters
import io.ktor.openapi.JsonSchema
import io.ktor.openapi.JsonType
import io.ktor.server.response.respond
import io.ktor.server.routing.Route
import io.ktor.server.routing.get
import io.ktor.server.routing.openapi.describe
import java.time.LocalDate
import java.util.UUID
import kotlinx.serialization.Serializable
import kotlinx.serialization.UseSerializers

/** A magnitude: never negative, its direction given by the side. */
private const val MAGNITUDE_PATTERN = """^\d+(\.\d+)?$"""

@Serializable
@JsonSchema.Description("Net worth and working capital on one date.")
data class PositionResponse(
    @JsonSchema.Description("Total assets minus total liabilities.")
    @JsonSchema.Pattern(MONEY_PATTERN)
    val netWorth: String,
    @JsonSchema.Description("Current assets minus current liabilities.")
    @JsonSchema.Pattern(MONEY_PATTERN)
    val workingCapital: String,
)

@Serializable
@JsonSchema.Description(
    "A line on the closing balance sheet: an item or an account with a known balance."
)
data class ReportSheetLineResponse(
    @JsonSchema.Description("The item's or account's id.") @JsonSchema.Format("uuid") val id: UUID,
    val name: String,
    @JsonSchema.Description("For an account, from the sign of its balance.")
    @EnumOf(Side::class)
    val side: String,
    @EnumOf(Term::class) val term: String,
    @JsonSchema.Description(
        "The magnitude of the line's value or balance. Direction is implied by Side."
    )
    @JsonSchema.Pattern(MAGNITUDE_PATTERN)
    val amount: String,
    @JsonSchema.Description("The date of the observation the amount comes from.")
    @JsonSchema.Format(DATE_FORMAT)
    val asOf: String,
)

@Serializable
@JsonSchema.Description("The balance sheet at the end of the report's period.")
data class ReportSheetResponse(
    @JsonSchema.Description("Total value of everything owned.")
    @JsonSchema.Pattern(MAGNITUDE_PATTERN)
    val totalAssets: String,
    @JsonSchema.Description("Total value of everything owed.")
    @JsonSchema.Pattern(MAGNITUDE_PATTERN)
    val totalLiabilities: String,
    @JsonSchema.Pattern(MONEY_PATTERN) val netWorth: String,
    @JsonSchema.Pattern(MONEY_PATTERN) val workingCapital: String,
    @JsonSchema.Description("Items, then accounts with a known balance.")
    val lines: List<ReportSheetLineResponse>,
    @JsonSchema.Description("The names of accounts without any balance, left out of the totals.")
    val unknownBalances: List<String>,
)

@Serializable
@JsonSchema.Description(
    "One tag's net amount for the period, or the untagged income or untagged expenses."
)
data class ReportLineResponse(
    @JsonSchema.Description("The tag, or none for an untagged line.")
    @JsonSchema.Format("uuid")
    val tagId: UUID?,
    @JsonSchema.Description("The tag's name, or \"Untagged income\" or \"Untagged expenses\".")
    val name: String,
    @JsonSchema.Description("The tag's colour, or none for an untagged line.")
    @EnumOf(TagColor::class)
    val color: String?,
    @JsonSchema.Pattern(MONEY_PATTERN) val amount: String,
    @JsonSchema.Description(
        "An expense line's percentage of total expenses. None for income lines, and when total " +
            "expenses are zero or negative."
    )
    @JsonSchema.Pattern(DECIMAL_PATTERN)
    val share: String?,
)

@Serializable
@JsonSchema.Description(
    "The position and performance for one reporting period. See docs/reports.md."
)
data class ReportResponse(
    @EnumOf(Frequency::class) val frequency: String,
    @JsonSchema.Description(
        "The period's name, e.g. \"March 2026\", \"Q1 2026\", \"2026\", or \"2026/27\"."
    )
    val label: String,
    @JsonSchema.Description("The period's first day.")
    @JsonSchema.Format(DATE_FORMAT)
    val from: String,
    @JsonSchema.Description("The period's last day.")
    @JsonSchema.Format(DATE_FORMAT)
    val to: String,
    @JsonSchema.Description(
        "The closing balance sheet's statement date, and the last day of the income statement: " +
            "the period's last day, or the client's today for a report to date."
    )
    @JsonSchema.Format(DATE_FORMAT)
    val closingDate: String,
    @JsonSchema.Description("False for a report to date.") val complete: Boolean,
    @JsonSchema.Description("Whether the period before has a report.") val hasPrevious: Boolean,
    @JsonSchema.Description("Whether the period after has a report.") val hasNext: Boolean,
    // Described on the type, so Ktor documents it once.
    val opening: PositionResponse,
    val closing: ReportSheetResponse,
    @JsonSchema.Description(
        "Closing net worth minus opening net worth. None when the opening balance sheet has no " +
            "lines, where it is not meaningful."
    )
    @JsonSchema.Pattern(MONEY_PATTERN)
    val changeInNetWorth: String?,
    @JsonSchema.Description(
        "The change in net worth minus net income: revaluations, money that never passes " +
            "through a tracked account, and missing transactions. None when the change is."
    )
    @JsonSchema.Pattern(MONEY_PATTERN)
    val otherChanges: String?,
    @JsonSchema.Description(
        "Closing working capital minus opening working capital. None when the change in net " +
            "worth is."
    )
    @JsonSchema.Pattern(MONEY_PATTERN)
    val changeInWorkingCapital: String?,
    @JsonSchema.Pattern(MONEY_PATTERN) val income: String,
    @JsonSchema.Pattern(MONEY_PATTERN) val expenses: String,
    @JsonSchema.Pattern(MONEY_PATTERN) val netIncome: String,
    @JsonSchema.Description(
        "Net income as a percentage of income. None when income is zero or negative."
    )
    @JsonSchema.Pattern(DECIMAL_PATTERN)
    val savingsRate: String?,
    @JsonSchema.Description(
        "The names of closed accounts with transactions in the period dated after their close " +
            "date. The income statement counts them, but the balance sheets leave the accounts " +
            "out, so other changes are off by their net amount."
    )
    val closedAccountsWithTransactions: List<String>,
    val incomeLines: List<ReportLineResponse>,
    val expenseLines: List<ReportLineResponse>,
)

private fun BalanceSheet.toPosition() =
    PositionResponse(netWorth.toString(), workingCapital.toString())

private fun BalanceSheet.toResponse(): ReportSheetResponse {
    val items = items.map {
        ReportSheetLineResponse(
            id = it.item.id,
            name = it.item.name.value,
            side = it.item.side.name,
            term = it.item.term.name,
            amount = it.current.value.amount.toString(),
            asOf = it.current.asOf.formatCalendarDate(),
        )
    }
    val accounts = accounts.mapNotNull { line ->
        line.current?.let { current ->
            val (side, amount) = BalanceSheet.accountSide(current.balance)
            ReportSheetLineResponse(
                id = line.account.id,
                name = line.account.name.value,
                side = side.name,
                term = line.account.term.name,
                amount = amount.toString(),
                asOf = current.asOf.formatCalendarDate(),
            )
        }
    }
    return ReportSheetResponse(
        totalAssets = totalAssets.toString(),
        totalLiabilities = totalLiabilities.toString(),
        netWorth = netWorth.toString(),
        workingCapital = workingCapital.toString(),
        lines = items + accounts,
        unknownBalances = unknownBalances.map { it.name.value },
    )
}

private fun StatementLine.toResponse(untaggedName: String) =
    ReportLineResponse(
        tagId = tag?.id,
        name = tag?.name?.value ?: untaggedName,
        color = tag?.color?.name,
        amount = amount.toString(),
        share = share?.toPlainString(),
    )

fun Report.toResponse(): ReportResponse {
    val statement = incomeStatement
    return ReportResponse(
        frequency = period.frequency.name,
        label = period.label,
        from = period.from.formatCalendarDate(),
        to = period.to.formatCalendarDate(),
        closingDate = closingDate.formatCalendarDate(),
        complete = complete,
        hasPrevious = hasPrevious,
        hasNext = hasNext,
        opening = opening.toPosition(),
        closing = closing.toResponse(),
        changeInNetWorth = change?.netWorth?.toString(),
        otherChanges = change?.otherChanges?.toString(),
        changeInWorkingCapital = change?.workingCapital?.toString(),
        income = statement.income.toString(),
        expenses = statement.expenses.toString(),
        netIncome = statement.netIncome.toString(),
        savingsRate = statement.savingsRate?.toPlainString(),
        closedAccountsWithTransactions = closedAccountsWithTransactions.map { it.name.value },
        incomeLines = statement.incomeLines.map { it.toResponse("Untagged income") },
        expenseLines = statement.expenseLines.map { it.toResponse("Untagged expenses") },
    )
}

/** What the request asks for: the frequency, the client's today, and maybe a date in the period. */
data class ReportQuery(val frequency: Frequency, val today: LocalDate, val date: LocalDate?)

private fun Parameters.nonBlank(name: String): String? = get(name)?.takeIf { it.isNotBlank() }

context(_: Raise<String>)
private fun required(name: String, value: String?): String =
    ensureNotNull(value) { "The query parameter '$name' is required" }

context(_: Raise<String>)
private fun queryDate(name: String, value: String): LocalDate =
    withError({ _: String ->
        "The query parameter '$name' must be a date in the format yyyy-MM-dd, got '$value'"
    }) {
        parseCalendarDate(value)
    }

/** The query parameters, reporting every failure in one error. */
context(_: Raise<DomainError>)
fun parseQuery(query: Parameters): ReportQuery =
    withError({ errors: NonEmptyList<String> ->
        DomainError.ValidationFailed(errors.joinToString("; "))
    }) {
        zipOrAccumulate(
            { Frequency.parse(required("frequency", query.nonBlank("frequency"))) },
            { queryDate("today", required("today", query.nonBlank("today"))) },
            { query.nonBlank("date")?.let { queryDate("date", it) } },
        ) { frequency, today, date ->
            ReportQuery(frequency, today, date)
        }
    }

fun Route.readReport(db: Db) =
    get("/api/reports") {
            call.handle {
                val userId = call.userId
                val query = parseQuery(call.request.queryParameters)

                val report = db.sql {
                    val history = readBalanceSheetHistory(userId)
                    val range =
                        range(
                            query.frequency,
                            query.today,
                            firstDate(history, readFirstTransactionDate(userId)),
                        )
                    period(range, query.date)?.let { period ->
                        compute(
                            query.today,
                            range,
                            period,
                            history,
                            readEntries(userId, statementPeriod(query.today, period)),
                            readTransactionsAfterClose(userId),
                        )
                    }
                }
                ensureNotNull(report) { DomainError.NotFound("There is no report for that period") }

                call.log.info(
                    "Returned the report for ${report.period.label}",
                    "period" to report.period.label,
                )
                call.respond(report.toResponse())
            }
        }
        .describe {
            summary = "Get a report"
            description =
                "Returns the report for the period of a frequency containing a date: its opening " +
                    "and closing positions, change in net worth, and income statement. Without " +
                    "a date, returns the latest complete period. Periods run from the one " +
                    "containing the user's first data to the one containing today; any other " +
                    "date is 404."
            tag("Reports")
            parameters {
                query("frequency") {
                    required = true
                    description = "Monthly, Quarterly, CalendarYear, or FinancialYear."
                    schema = JsonSchema(type = JsonType.STRING)
                }
                query("today") {
                    required = true
                    description = "The client's local date, e.g. 2026-10-14."
                    schema = JsonSchema(type = JsonType.STRING, format = DATE_FORMAT)
                }
                query("date") {
                    description = "Any date in the period, e.g. 2026-09-01."
                    schema = JsonSchema(type = JsonType.STRING, format = DATE_FORMAT)
                }
            }
            responses {
                json<ReportResponse>(HttpStatusCode.OK)
                errors(
                    HttpStatusCode.BadRequest,
                    HttpStatusCode.Unauthorized,
                    HttpStatusCode.NotFound,
                )
            }
        }
