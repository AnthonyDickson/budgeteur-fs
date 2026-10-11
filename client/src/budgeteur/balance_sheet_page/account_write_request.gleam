import budgeteur/balance_sheet_page/term.{type Term}
import budgeteur/shared/date
import budgeteur/shared/money
import gleam/json
import gleam/option.{type Option}
import gleam/time/calendar.{type Date}

pub type AccountWriteRequest {
  AccountWriteRequest(
    // The user's alias for the account.
    name: String,
    // The number statements identify the account by; None for no number.
    number: Option(String),
    // Whether the account is current or non-current.
    term: Term,
    // A new balance to record, or None to keep the balance history as it is.
    balance: Option(BalanceEntry),
  )
}

/// A balance entered by hand, recorded as an observation on the server.
pub type BalanceEntry {
  BalanceEntry(
    // Signed: positive is held, negative is owed.
    balance: Float,
    // The date the balance is accurate as of.
    as_of: Date,
  )
}

pub fn to_json(request: AccountWriteRequest) -> json.Json {
  let AccountWriteRequest(name:, number:, term:, balance:) = request
  json.object([
    #("name", json.string(name)),
    #("number", json.nullable(number, json.string)),
    #("term", term.to_json(term)),
    #(
      "balance",
      json.nullable(balance, fn(entry: BalanceEntry) {
        json.object([
          #("balance", money.encode_decimal(entry.balance)),
          #("asOf", date.encode(entry.as_of)),
        ])
      }),
    ),
  ])
}
