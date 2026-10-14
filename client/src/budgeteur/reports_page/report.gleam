//// A report as returned by `GET /api/reports`. The server owns every figure;
//// the client only displays them. See docs/reports.md.

import budgeteur/shared/date
import budgeteur/shared/money
import budgeteur/shared/side.{type Side}
import budgeteur/shared/term.{type Term}
import budgeteur/shared/uuid as uuid_codec
import gleam/dynamic/decode
import gleam/option.{type Option, None}
import gleam/time/calendar.{type Date}
import youid/uuid.{type Uuid}

/// How long a reporting period is.
pub type Frequency {
  Monthly
  Quarterly
  CalendarYear
  FinancialYear
}

pub const default_frequency = Monthly

/// Every frequency, in the order the page offers them.
pub const frequencies = [Monthly, Quarterly, CalendarYear, FinancialYear]

/// The encoded string for a frequency. Mirrors the server's `toString`.
pub fn frequency_to_string(frequency: Frequency) -> String {
  case frequency {
    Monthly -> "Monthly"
    Quarterly -> "Quarterly"
    CalendarYear -> "CalendarYear"
    FinancialYear -> "FinancialYear"
  }
}

pub fn parse_frequency(value: String) -> Result(Frequency, Nil) {
  case value {
    "Monthly" -> Ok(Monthly)
    "Quarterly" -> Ok(Quarterly)
    "CalendarYear" -> Ok(CalendarYear)
    "FinancialYear" -> Ok(FinancialYear)
    _ -> Error(Nil)
  }
}

/// The label shown to the user.
pub fn frequency_label(frequency: Frequency) -> String {
  case frequency {
    Monthly -> "Monthly"
    Quarterly -> "Quarterly"
    CalendarYear -> "Calendar year"
    FinancialYear -> "Financial year"
  }
}

pub type Report {
  Report(
    // The period's name, e.g. "March 2026" or "2026/27".
    label: String,
    from: Date,
    to: Date,
    // The closing balance sheet's date: `to`, or today for a report to date.
    closing_date: Date,
    complete: Bool,
    has_previous: Bool,
    has_next: Bool,
    opening_net_worth: Float,
    opening_working_capital: Float,
    closing: Sheet,
    // None when not meaningful: the opening balance sheet has no lines.
    change_in_net_worth: Option(Float),
    other_changes: Option(Float),
    income: Float,
    expenses: Float,
    net_income: Float,
    // None when income is zero or negative.
    savings_rate: Option(Float),
    income_lines: List(Line),
    expense_lines: List(Line),
  )
}

/// The balance sheet at the end of the period.
pub type Sheet {
  Sheet(
    total_assets: Float,
    total_liabilities: Float,
    net_worth: Float,
    working_capital: Float,
    lines: List(SheetLine),
    // The names of accounts without any balance, left out of the totals.
    unknown_balances: List(String),
  )
}

pub type SheetLine {
  SheetLine(
    id: Uuid,
    name: String,
    side: Side,
    term: Term,
    amount: Float,
    as_of: Date,
  )
}

/// One tag's net amount, or the untagged income or expenses.
pub type Line {
  Line(
    tag_id: Option(Uuid),
    name: String,
    color: Option(String),
    amount: Float,
    // An expense line's percentage of total expenses.
    share: Option(Float),
  )
}

pub fn decoder() -> decode.Decoder(Report) {
  use label <- decode.field("label", decode.string)
  use from <- decode.field("from", date.decoder())
  use to <- decode.field("to", date.decoder())
  use closing_date <- decode.field("closingDate", date.decoder())
  use complete <- decode.field("complete", decode.bool)
  use has_previous <- decode.field("hasPrevious", decode.bool)
  use has_next <- decode.field("hasNext", decode.bool)
  use #(opening_net_worth, opening_working_capital) <- decode.field("opening", {
    use net_worth <- decode.field("netWorth", money.decode_decimal())
    use working_capital <- decode.field(
      "workingCapital",
      money.decode_decimal(),
    )
    decode.success(#(net_worth, working_capital))
  })
  use closing <- decode.field("closing", sheet_decoder())
  use change_in_net_worth <- optional_money("changeInNetWorth")
  use other_changes <- optional_money("otherChanges")
  use income <- decode.field("income", money.decode_decimal())
  use expenses <- decode.field("expenses", money.decode_decimal())
  use net_income <- decode.field("netIncome", money.decode_decimal())
  use savings_rate <- optional_money("savingsRate")
  use income_lines <- decode.field("incomeLines", decode.list(line_decoder()))
  use expense_lines <- decode.field("expenseLines", decode.list(line_decoder()))
  decode.success(Report(
    label:,
    from:,
    to:,
    closing_date:,
    complete:,
    has_previous:,
    has_next:,
    opening_net_worth:,
    opening_working_capital:,
    closing:,
    change_in_net_worth:,
    other_changes:,
    income:,
    expenses:,
    net_income:,
    savings_rate:,
    income_lines:,
    expense_lines:,
  ))
}

/// A decimal the server may leave out or send as null.
fn optional_money(
  name: String,
  next: fn(Option(Float)) -> decode.Decoder(a),
) -> decode.Decoder(a) {
  decode.optional_field(
    name,
    None,
    decode.optional(money.decode_decimal()),
    next,
  )
}

fn sheet_decoder() -> decode.Decoder(Sheet) {
  use total_assets <- decode.field("totalAssets", money.decode_decimal())
  use total_liabilities <- decode.field(
    "totalLiabilities",
    money.decode_decimal(),
  )
  use net_worth <- decode.field("netWorth", money.decode_decimal())
  use working_capital <- decode.field("workingCapital", money.decode_decimal())
  use lines <- decode.field("lines", decode.list(sheet_line_decoder()))
  use unknown_balances <- decode.field(
    "unknownBalances",
    decode.list(decode.string),
  )
  decode.success(Sheet(
    total_assets:,
    total_liabilities:,
    net_worth:,
    working_capital:,
    lines:,
    unknown_balances:,
  ))
}

fn sheet_line_decoder() -> decode.Decoder(SheetLine) {
  use id <- decode.field("id", uuid_codec.decoder())
  use name <- decode.field("name", decode.string)
  use side <- decode.field("side", side.decoder())
  use term <- decode.field("term", term.decoder())
  use amount <- decode.field("amount", money.decode_decimal())
  use as_of <- decode.field("asOf", date.decoder())
  decode.success(SheetLine(id:, name:, side:, term:, amount:, as_of:))
}

fn line_decoder() -> decode.Decoder(Line) {
  use tag_id <- decode.optional_field(
    "tagId",
    None,
    decode.optional(uuid_codec.decoder()),
  )
  use name <- decode.field("name", decode.string)
  use color <- decode.optional_field(
    "color",
    None,
    decode.optional(decode.string),
  )
  use amount <- decode.field("amount", money.decode_decimal())
  use share <- optional_money("share")
  decode.success(Line(tag_id:, name:, color:, amount:, share:))
}
