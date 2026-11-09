@file:UseSerializers(UuidSerializer::class)

package budgeteur.feature.dashboard

import arrow.core.raise.Raise
import arrow.core.raise.context.ensureNotNull
import arrow.core.raise.context.withError
import budgeteur.data.readBalanceSheetHistory
import budgeteur.data.readEntries
import budgeteur.data.readFirstTransactionDate
import budgeteur.domain.Frequency
import budgeteur.domain.Money
import budgeteur.domain.ReportingPeriod
import budgeteur.domain.TagColor
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
import io.ktor.openapi.JsonSchema
import io.ktor.openapi.JsonType
import io.ktor.server.response.respond
import io.ktor.server.routing.Route
import io.ktor.server.routing.get
import io.ktor.server.routing.openapi.describe
import java.math.BigDecimal
import java.time.LocalDate
import java.util.UUID
import kotlinx.serialization.Serializable
import kotlinx.serialization.UseSerializers

@Serializable
@JsonSchema.Description("Where the user stands today.")
data class DashboardPositionResponse(
    @JsonSchema.Description("Whether the balance sheet has no items or accounts.")
    val isEmpty: Boolean,
    @JsonSchema.Description("Total assets minus total liabilities.")
    @JsonSchema.Pattern(MONEY_PATTERN)
    val netWorth: String,
    @JsonSchema.Description("Current assets minus current liabilities.")
    @JsonSchema.Pattern(MONEY_PATTERN)
    val workingCapital: String,
    @JsonSchema.Description(
        "Working capital in months of average expenses, to one decimal place. Zero when " +
            "working capital is negative. None when there are no baseline months or their " +
            "average expenses are zero or negative."
    )
    @JsonSchema.Pattern(DECIMAL_PATTERN)
    val runway: String?,
    @JsonSchema.Description(
        "The earliest as-of date among the balance sheet's lines with a known balance."
    )
    @JsonSchema.Format(DATE_FORMAT)
    val oldestAsOf: String?,
)

@Serializable
@JsonSchema.Description(
    "A total for the month to date against its baseline. The baseline fields are none while " +
        "there are no baseline months."
)
data class FigureResponse(
    @JsonSchema.Pattern(MONEY_PATTERN) val amount: String,
    @JsonSchema.Description(DashboardDocs.BASELINE)
    @JsonSchema.Pattern(MONEY_PATTERN)
    val baseline: String?,
    @JsonSchema.Description(DashboardDocs.CHANGE)
    @JsonSchema.Pattern(MONEY_PATTERN)
    val change: String?,
    @JsonSchema.Description(DashboardDocs.CHANGE_PERCENT)
    @JsonSchema.Pattern(DECIMAL_PATTERN)
    val changePercent: String?,
)

@Serializable
@JsonSchema.Description(
    "One tag's net amount for the month to date, or the untagged income or expenses, against " +
        "its baseline."
)
data class MonthLineResponse(
    @JsonSchema.Description("The tag, or none for an untagged line.")
    @JsonSchema.Format("uuid")
    val tagId: UUID?,
    @JsonSchema.Description("The tag's name, or \"Untagged income\" or \"Untagged expenses\".")
    val name: String,
    @JsonSchema.Description("The tag's colour, or none for an untagged line.")
    @EnumOf(TagColor::class)
    val color: String?,
    @JsonSchema.Description("Zero for a tag with nothing this month but an amount in the baseline.")
    @JsonSchema.Pattern(MONEY_PATTERN)
    val amount: String,
    @JsonSchema.Description(
        "An expense line's percentage of the month's expenses. None for income lines, and " +
            "when expenses are zero or negative."
    )
    @JsonSchema.Pattern(DECIMAL_PATTERN)
    val share: String?,
    @JsonSchema.Description(DashboardDocs.BASELINE)
    @JsonSchema.Pattern(MONEY_PATTERN)
    val baseline: String?,
    @JsonSchema.Description(DashboardDocs.CHANGE)
    @JsonSchema.Pattern(MONEY_PATTERN)
    val change: String?,
    @JsonSchema.Description(DashboardDocs.CHANGE_PERCENT)
    @JsonSchema.Pattern(DECIMAL_PATTERN)
    val changePercent: String?,
)

@Serializable
@JsonSchema.Description("The month to date against its baseline.")
data class MonthResponse(
    @JsonSchema.Description("The month's name, e.g. \"October 2026\".") val label: String,
    @JsonSchema.Description("The month's first day.")
    @JsonSchema.Format(DATE_FORMAT)
    val from: String,
    @JsonSchema.Description("The client's today.") @JsonSchema.Format(DATE_FORMAT) val to: String,
    val income: FigureResponse,
    val expenses: FigureResponse,
    val netIncome: FigureResponse,
    @JsonSchema.Description(
        "Net income as a percentage of income. None when income is zero or negative."
    )
    @JsonSchema.Pattern(DECIMAL_PATTERN)
    val savingsRate: String?,
    @JsonSchema.Description("The savings rate of the baseline income and net income.")
    @JsonSchema.Pattern(DECIMAL_PATTERN)
    val savingsRateBaseline: String?,
    @JsonSchema.Description("The savings rate minus its baseline, in percentage points.")
    @JsonSchema.Pattern(DECIMAL_PATTERN)
    val savingsRateChange: String?,
    @JsonSchema.Description(
        "How many months the baselines are the mean of. Zero while the baseline is still " +
            "building."
    )
    val baselineMonthCount: Int,
    @JsonSchema.Description("The date of the month's latest transaction.")
    @JsonSchema.Format(DATE_FORMAT)
    val latestTransaction: String?,
    @JsonSchema.Description("Largest first, untagged last.")
    val incomeLines: List<MonthLineResponse>,
    @JsonSchema.Description("Largest first, untagged last.")
    val expenseLines: List<MonthLineResponse>,
)

@Serializable
@JsonSchema.Description("One month of the history.")
data class HistoryMonthResponse(
    @JsonSchema.Description("The month's name, e.g. \"October 2026\".") val label: String,
    @JsonSchema.Description("The month's first day.")
    @JsonSchema.Format(DATE_FORMAT)
    val from: String,
    @JsonSchema.Description("The month's last day, or the client's today for the month to date.")
    @JsonSchema.Format(DATE_FORMAT)
    val closingDate: String,
    @JsonSchema.Description("False for the month to date.") val complete: Boolean,
    @JsonSchema.Pattern(MONEY_PATTERN) val income: String,
    @JsonSchema.Pattern(MONEY_PATTERN) val expenses: String,
    @JsonSchema.Pattern(MONEY_PATTERN) val netIncome: String,
    @JsonSchema.Description(
        "Net worth on the closing date. None when no line has a known balance then."
    )
    @JsonSchema.Pattern(MONEY_PATTERN)
    val netWorth: String?,
    @JsonSchema.Description("Working capital on the closing date. None when net worth is.")
    @JsonSchema.Pattern(MONEY_PATTERN)
    val workingCapital: String?,
)

@Serializable
@JsonSchema.Description(
    "The baseline months' whole-month figures taken together. None while there are no " +
        "baseline months."
)
data class HistoryTotalsResponse(
    @JsonSchema.Description("How many months the totals cover, from one to twelve.")
    val monthCount: Int,
    @JsonSchema.Pattern(MONEY_PATTERN) val income: String,
    @JsonSchema.Pattern(MONEY_PATTERN) val expenses: String,
    @JsonSchema.Pattern(MONEY_PATTERN) val netIncome: String,
    @JsonSchema.Description(
        "Net income over income for the whole span. None when income is zero or negative."
    )
    @JsonSchema.Pattern(DECIMAL_PATTERN)
    val savingsRate: String?,
    @JsonSchema.Pattern(MONEY_PATTERN) val averageIncome: String,
    @JsonSchema.Description("The figure runway divides by.")
    @JsonSchema.Pattern(MONEY_PATTERN)
    val averageExpenses: String,
    @JsonSchema.Pattern(MONEY_PATTERN) val averageNetIncome: String,
)

@Serializable
@JsonSchema.Description("Every figure on the dashboard. See docs/dashboard.md.")
data class DashboardResponse(
    val position: DashboardPositionResponse,
    val month: MonthResponse,
    @JsonSchema.Description("Up to twelve complete months and the month to date, oldest first.")
    val history: List<HistoryMonthResponse>,
    // Described on the type, so Ktor documents it once.
    val totals: HistoryTotalsResponse?,
)

/** Field descriptions the responses share. */
internal object DashboardDocs {
    const val BASELINE = "The mean over the same days of the baseline months."
    const val CHANGE = "The amount minus its baseline."
    const val CHANGE_PERCENT =
        "The change as a percentage of the baseline. None also when the baseline is zero or " +
            "negative."
}

private fun Figure.toResponse() =
    FigureResponse(
        amount.toString(),
        comparison?.baseline?.toString(),
        comparison?.change?.toString(),
        comparison?.changePercent?.toPlainString(),
    )

private fun MonthLine.toResponse(untaggedName: String) =
    MonthLineResponse(
        tagId = tag?.id,
        name = tag?.name?.value ?: untaggedName,
        color = tag?.color?.name,
        amount = amount.toString(),
        share = share?.toPlainString(),
        baseline = comparison?.baseline?.toString(),
        change = comparison?.change?.toString(),
        changePercent = comparison?.changePercent?.toPlainString(),
    )

private fun BigDecimal.format() = toPlainString()

private fun Money?.format() = this?.toString()

fun DashboardFigures.toResponse(): DashboardResponse =
    DashboardResponse(
        position =
            DashboardPositionResponse(
                isEmpty = position.isEmpty,
                netWorth = position.netWorth.toString(),
                workingCapital = position.workingCapital.toString(),
                runway = position.runway?.format(),
                oldestAsOf = position.oldestAsOf?.formatCalendarDate(),
            ),
        month =
            MonthResponse(
                label = ReportingPeriod.containing(Frequency.Monthly, month.period.to).label,
                from = month.period.from.formatCalendarDate(),
                to = month.period.to.formatCalendarDate(),
                income = month.income.toResponse(),
                expenses = month.expenses.toResponse(),
                netIncome = month.netIncome.toResponse(),
                savingsRate = month.savingsRate?.format(),
                savingsRateBaseline = month.savingsRateBaseline?.format(),
                savingsRateChange = month.savingsRateChange?.format(),
                baselineMonthCount = month.baselineMonthCount,
                latestTransaction = month.latestTransaction?.formatCalendarDate(),
                incomeLines = month.incomeLines.map { it.toResponse("Untagged income") },
                expenseLines = month.expenseLines.map { it.toResponse("Untagged expenses") },
            ),
        history =
            history.map {
                HistoryMonthResponse(
                    label = it.month.label,
                    from = it.month.from.formatCalendarDate(),
                    closingDate = it.closingDate.formatCalendarDate(),
                    complete = it.complete,
                    income = it.income.toString(),
                    expenses = it.expenses.toString(),
                    netIncome = it.netIncome.toString(),
                    netWorth = it.netWorth.format(),
                    workingCapital = it.workingCapital.format(),
                )
            },
        totals =
            totals?.let {
                HistoryTotalsResponse(
                    monthCount = it.monthCount,
                    income = it.income.toString(),
                    expenses = it.expenses.toString(),
                    netIncome = it.netIncome.toString(),
                    savingsRate = it.savingsRate?.format(),
                    averageIncome = it.averageIncome.toString(),
                    averageExpenses = it.averageExpenses.toString(),
                    averageNetIncome = it.averageNetIncome.toString(),
                )
            },
    )

/** The `today` query parameter: the client's local date. */
context(_: Raise<DomainError>)
fun parseToday(raw: String?): LocalDate {
    val value =
        ensureNotNull(raw?.takeIf { it.isNotBlank() }) {
            DomainError.ValidationFailed("The query parameter 'today' is required")
        }
    return withError({ _: String ->
        DomainError.ValidationFailed(
            "The query parameter 'today' must be a date in the format yyyy-MM-dd, got '$value'"
        )
    }) {
        parseCalendarDate(value)
    }
}

fun Route.readDashboard(db: Db) =
    get("/api/dashboard") {
            call.handle {
                val userId = call.userId
                val today = parseToday(call.request.queryParameters["today"])

                val (figures, count) =
                    db.sql {
                        val history = readBalanceSheetHistory(userId)
                        val periods = periodsFor(today, history, readFirstTransactionDate(userId))
                        val entries = readEntries(userId, readPeriod(periods))
                        compute(periods, history, entries) to entries.size
                    }

                call.log.info("Returned the dashboard from $count transactions", "count" to count)
                call.respond(figures.toResponse())
            }
        }
        .describe {
            summary = "Get the dashboard"
            description =
                "Returns today's position and runway, the month to date against the same days " +
                    "of up to twelve earlier months, and the history of up to twelve complete " +
                    "months and the month to date with their totals. Transfers are excluded."
            tag("Dashboard")
            parameters {
                query("today") {
                    required = true
                    description = "The client's local date, e.g. 2026-10-14."
                    schema = JsonSchema(type = JsonType.STRING, format = DATE_FORMAT)
                }
            }
            responses {
                json<DashboardResponse>(HttpStatusCode.OK)
                errors(HttpStatusCode.BadRequest, HttpStatusCode.Unauthorized)
            }
        }
