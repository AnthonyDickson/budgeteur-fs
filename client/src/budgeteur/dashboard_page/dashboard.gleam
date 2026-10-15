//// The dashboard as returned by `GET /api/dashboard`. The server owns every
//// figure; the client only displays them. See docs/dashboard.md.

import budgeteur/shared/date
import budgeteur/shared/money
import budgeteur/shared/tag.{type TagColor}
import gleam/dynamic/decode
import gleam/option.{type Option}
import gleam/time/calendar.{type Date}

pub type Dashboard {
  Dashboard(
    position: Position,
    month: Month,
    /// Up to twelve complete months and the month to date, oldest first.
    history: List(HistoryMonth),
    /// None while there are no baseline months.
    totals: Option(Totals),
  )
}

/// Where the user stands today.
pub type Position {
  Position(
    /// Whether the balance sheet has no items or accounts, so the page shows
    /// an empty state instead of zero figures.
    is_empty: Bool,
    net_worth: Float,
    working_capital: Float,
    /// Working capital in months of average expenses. None without baseline
    /// months or expenses.
    runway: Option(Float),
    oldest_as_of: Option(Date),
  )
}

/// A figure for the month to date against its baseline. The baseline and
/// change are None while there are no baseline months; the percentage is also
/// None when the baseline is zero or negative.
pub type Figure {
  Figure(
    amount: Float,
    baseline: Option(Float),
    change: Option(Float),
    change_percent: Option(Float),
  )
}

/// One tag's net amount for the month, or the untagged income or expenses (no
/// color).
pub type Line {
  Line(
    name: String,
    color: Option(TagColor),
    figure: Figure,
    /// An expense line's percentage of the month's expenses.
    share: Option(Float),
  )
}

pub type Month {
  Month(
    /// The month's name, e.g. "October 2026".
    label: String,
    from: Date,
    to: Date,
    income: Figure,
    expenses: Figure,
    net_income: Figure,
    savings_rate: Option(Float),
    savings_rate_baseline: Option(Float),
    /// In percentage points.
    savings_rate_change: Option(Float),
    /// Zero while the baseline is still building.
    baseline_month_count: Int,
    latest_transaction: Option(Date),
    income_lines: List(Line),
    expense_lines: List(Line),
  )
}

/// One month of the history.
pub type HistoryMonth {
  HistoryMonth(
    /// The month's name, e.g. "October 2026".
    label: String,
    from: Date,
    /// The month's last day, or today for the month to date.
    closing_date: Date,
    /// False for the month to date.
    complete: Bool,
    income: Float,
    expenses: Float,
    net_income: Float,
    /// None when no balance is known on the closing date.
    net_worth: Option(Float),
    working_capital: Option(Float),
  )
}

/// The baseline months' whole-month figures taken together.
pub type Totals {
  Totals(
    month_count: Int,
    income: Float,
    expenses: Float,
    net_income: Float,
    savings_rate: Option(Float),
    average_income: Float,
    /// The figure runway divides by.
    average_expenses: Float,
    average_net_income: Float,
  )
}

pub fn decoder() -> decode.Decoder(Dashboard) {
  use position <- decode.field("position", position_decoder())
  use month <- decode.field("month", month_decoder())
  use history <- decode.field("history", decode.list(history_month_decoder()))
  use totals <- decode.optional_field(
    "totals",
    option.None,
    decode.optional(totals_decoder()),
  )
  decode.success(Dashboard(position:, month:, history:, totals:))
}

fn history_month_decoder() -> decode.Decoder(HistoryMonth) {
  use label <- decode.field("label", decode.string)
  use from <- decode.field("from", date.decoder())
  use closing_date <- decode.field("closingDate", date.decoder())
  use complete <- decode.field("complete", decode.bool)
  use income <- decode.field("income", money.decode_decimal())
  use expenses <- decode.field("expenses", money.decode_decimal())
  use net_income <- decode.field("netIncome", money.decode_decimal())
  use net_worth <- optional_decimal("netWorth")
  use working_capital <- optional_decimal("workingCapital")
  decode.success(HistoryMonth(
    label:,
    from:,
    closing_date:,
    complete:,
    income:,
    expenses:,
    net_income:,
    net_worth:,
    working_capital:,
  ))
}

fn totals_decoder() -> decode.Decoder(Totals) {
  use month_count <- decode.field("monthCount", decode.int)
  use income <- decode.field("income", money.decode_decimal())
  use expenses <- decode.field("expenses", money.decode_decimal())
  use net_income <- decode.field("netIncome", money.decode_decimal())
  use savings_rate <- optional_decimal("savingsRate")
  use average_income <- decode.field("averageIncome", money.decode_decimal())
  use average_expenses <- decode.field(
    "averageExpenses",
    money.decode_decimal(),
  )
  use average_net_income <- decode.field(
    "averageNetIncome",
    money.decode_decimal(),
  )
  decode.success(Totals(
    month_count:,
    income:,
    expenses:,
    net_income:,
    savings_rate:,
    average_income:,
    average_expenses:,
    average_net_income:,
  ))
}

fn optional_decimal(
  name: String,
  next: fn(Option(Float)) -> decode.Decoder(a),
) {
  decode.optional_field(
    name,
    option.None,
    decode.optional(money.decode_decimal()),
    next,
  )
}

fn optional_date(name: String, next: fn(Option(Date)) -> decode.Decoder(a)) {
  decode.optional_field(
    name,
    option.None,
    decode.optional(date.decoder()),
    next,
  )
}

fn position_decoder() -> decode.Decoder(Position) {
  use is_empty <- decode.field("isEmpty", decode.bool)
  use net_worth <- decode.field("netWorth", money.decode_decimal())
  use working_capital <- decode.field("workingCapital", money.decode_decimal())
  use runway <- optional_decimal("runway")
  use oldest_as_of <- optional_date("oldestAsOf")
  decode.success(Position(
    is_empty:,
    net_worth:,
    working_capital:,
    runway:,
    oldest_as_of:,
  ))
}

/// A figure's fields, from a figure or a line object.
fn figure_decoder() -> decode.Decoder(Figure) {
  use amount <- decode.field("amount", money.decode_decimal())
  use baseline <- optional_decimal("baseline")
  use change <- optional_decimal("change")
  use change_percent <- optional_decimal("changePercent")
  decode.success(Figure(amount:, baseline:, change:, change_percent:))
}

fn line_decoder() -> decode.Decoder(Line) {
  use name <- decode.field("name", decode.string)
  use color <- decode.optional_field(
    "color",
    option.None,
    decode.optional(tag.color_decoder()),
  )
  use figure <- decode.then(figure_decoder())
  use share <- optional_decimal("share")
  decode.success(Line(name:, color:, figure:, share:))
}

fn month_decoder() -> decode.Decoder(Month) {
  use label <- decode.field("label", decode.string)
  use from <- decode.field("from", date.decoder())
  use to <- decode.field("to", date.decoder())
  use income <- decode.field("income", figure_decoder())
  use expenses <- decode.field("expenses", figure_decoder())
  use net_income <- decode.field("netIncome", figure_decoder())
  use savings_rate <- optional_decimal("savingsRate")
  use savings_rate_baseline <- optional_decimal("savingsRateBaseline")
  use savings_rate_change <- optional_decimal("savingsRateChange")
  use baseline_month_count <- decode.field("baselineMonthCount", decode.int)
  use latest_transaction <- optional_date("latestTransaction")
  use income_lines <- decode.field("incomeLines", decode.list(line_decoder()))
  use expense_lines <- decode.field("expenseLines", decode.list(line_decoder()))
  decode.success(Month(
    label:,
    from:,
    to:,
    income:,
    expenses:,
    net_income:,
    savings_rate:,
    savings_rate_baseline:,
    savings_rate_change:,
    baseline_month_count:,
    latest_transaction:,
    income_lines:,
    expense_lines:,
  ))
}
