//// The income statement as returned by `GET /api/income-statement`. The
//// server owns every total; the client only displays them.

import budgeteur/shared/date
import budgeteur/shared/money
import budgeteur/shared/uuid as uuid_codec
import gleam/dynamic/decode
import gleam/option.{type Option}
import gleam/time/calendar.{type Date}
import youid/uuid.{type Uuid}

pub type IncomeStatement {
  IncomeStatement(
    from: Date,
    to: Date,
    income: Float,
    expenses: Float,
    net_income: Float,
    income_lines: List(IncomeLine),
    expense_lines: List(ExpenseLine),
    untagged_count: Int,
  )
}

/// One income tag's net amount, or the untagged income (no tag id or color).
pub type IncomeLine {
  IncomeLine(
    tag_id: Option(Uuid),
    name: String,
    color: Option(String),
    amount: Float,
  )
}

/// One expense tag's net amount spent, or the untagged expenses, with its
/// percentage of total expenses when that total is positive.
pub type ExpenseLine {
  ExpenseLine(
    tag_id: Option(Uuid),
    name: String,
    color: Option(String),
    amount: Float,
    share: Option(Float),
  )
}

/// Whether the period has no income or expense lines, i.e. no transactions.
pub fn is_empty(statement: IncomeStatement) -> Bool {
  statement.income_lines == [] && statement.expense_lines == []
}

pub fn decoder() -> decode.Decoder(IncomeStatement) {
  use from <- decode.field("from", date.decoder())
  use to <- decode.field("to", date.decoder())
  use income <- decode.field("income", money.decode_decimal())
  use expenses <- decode.field("expenses", money.decode_decimal())
  use net_income <- decode.field("netIncome", money.decode_decimal())
  use income_lines <- decode.field(
    "incomeLines",
    decode.list(income_line_decoder()),
  )
  use expense_lines <- decode.field(
    "expenseLines",
    decode.list(expense_line_decoder()),
  )
  use untagged_count <- decode.field("untaggedCount", decode.int)
  decode.success(IncomeStatement(
    from:,
    to:,
    income:,
    expenses:,
    net_income:,
    income_lines:,
    expense_lines:,
    untagged_count:,
  ))
}

fn income_line_decoder() -> decode.Decoder(IncomeLine) {
  use tag_id <- decode.field("tagId", decode.optional(uuid_codec.decoder()))
  use name <- decode.field("name", decode.string)
  use color <- decode.field("color", decode.optional(decode.string))
  use amount <- decode.field("amount", money.decode_decimal())
  decode.success(IncomeLine(tag_id:, name:, color:, amount:))
}

fn expense_line_decoder() -> decode.Decoder(ExpenseLine) {
  use tag_id <- decode.field("tagId", decode.optional(uuid_codec.decoder()))
  use name <- decode.field("name", decode.string)
  use color <- decode.field("color", decode.optional(decode.string))
  use amount <- decode.field("amount", money.decode_decimal())
  use share <- decode.field("share", decode.optional(money.decode_decimal()))
  decode.success(ExpenseLine(tag_id:, name:, color:, amount:, share:))
}
