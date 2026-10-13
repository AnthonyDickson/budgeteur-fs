import budgeteur/balance_sheet_page/side.{type Side}
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
    side: Side,
    // Whether the item is current or non-current.
    term: Term,
    // The positive magnitude of the item's value. Direction is implied by side.
    value: Float,
    // The date the value is accurate as of.
    as_of: Date,
  )
}

pub fn to_json(item_write_request: ItemWriteRequest) -> json.Json {
  let ItemWriteRequest(name:, side:, term:, value:, as_of:) = item_write_request
  json.object([
    #("name", json.string(name)),
    #("side", side.to_json(side)),
    #("term", term.to_json(term)),
    #("value", money.encode_decimal(value)),
    #("asOf", date.encode(as_of)),
  ])
}
