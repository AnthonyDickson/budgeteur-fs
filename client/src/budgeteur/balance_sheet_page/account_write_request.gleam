import budgeteur/balance_sheet_page/term.{type Term}
import budgeteur/shared/date
import budgeteur/shared/money
import gleam/json
import gleam/option.{type Option}
import gleam/time/calendar.{type Date}

/// What the account form saves. Creating an account sends its details and
/// opening balance; updating one sends only its details.
pub type AccountWriteRequest {
  AccountWriteRequest(
    // The user's alias for the account.
    name: String,
    // The number statements identify the account by; None for no number.
    number: Option(String),
    // Whether the account is current or non-current.
    term: Term,
    // The balance to record with a new account, or None to leave it unknown.
    // Always None when editing, since the edit form has no balance.
    opening_balance: Option(BalanceEntry),
  )
}

/// A balance entered by hand, recorded as an observation on the server.
pub type BalanceEntry {
  BalanceEntry(
    // Signed: positive is an asset (owned), negative a liability (owed).
    balance: Float,
    // The date the balance is accurate as of.
    as_of: Date,
  )
}

/// The create request: the details and the opening balance.
pub fn create_json(request: AccountWriteRequest) -> json.Json {
  json.object([
    #("name", json.string(request.name)),
    #("number", json.nullable(request.number, json.string)),
    #("term", term.to_json(request.term)),
    #("balance", json.nullable(request.opening_balance, balance_entry_json)),
  ])
}

/// The update request: the details only.
pub fn update_json(request: AccountWriteRequest) -> json.Json {
  json.object([
    #("name", json.string(request.name)),
    #("number", json.nullable(request.number, json.string)),
    #("term", term.to_json(request.term)),
  ])
}

/// The record-balance request.
pub fn balance_entry_json(entry: BalanceEntry) -> json.Json {
  json.object([
    #("balance", money.encode_decimal(entry.balance)),
    #("asOf", date.encode(entry.as_of)),
  ])
}
