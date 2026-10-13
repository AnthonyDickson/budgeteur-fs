import budgeteur/balance_sheet_page/item_kind.{type ItemKind}
import budgeteur/balance_sheet_page/term.{type Term}
import budgeteur/shared/date
import budgeteur/shared/money
import gleam/json
import gleam/time/calendar.{type Date}

pub type ItemWriteRequest {
  ItemWriteRequest(
    // A human-readable name, e.g. "Chequing account" or "Mortgage".
    name: String,
    // Whether the item is an asset or a liability.
    kind: ItemKind,
    // Whether the item is current or non-current.
    term: Term,
    // The positive magnitude of the item's value. Direction is implied by Kind.
    balance: Float,
    // The date the balance is accurate as of.
    as_of: Date,
  )
}

pub fn to_json(item_write_request: ItemWriteRequest) -> json.Json {
  let ItemWriteRequest(name:, kind:, term:, balance:, as_of:) =
    item_write_request
  json.object([
    #("name", json.string(name)),
    #("kind", item_kind.to_json(kind)),
    #("term", term.to_json(term)),
    #("balance", money.encode_decimal(balance)),
    #("asOf", date.encode(as_of)),
  ])
}
