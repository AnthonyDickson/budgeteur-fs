import budgeteur/balance_sheet_page/side.{type Side}
import budgeteur/balance_sheet_page/term.{type Term}
import budgeteur/shared/date
import budgeteur/shared/money
import gleam/json
import gleam/time/calendar.{type Date}

/// What the item form saves.
pub type ItemWriteRequest {
  /// A new item with its first value.
  CreateItem(name: String, side: Side, term: Term, first: ValueEntry)
  /// An item's details. Its side is fixed at creation, and its values are
  /// observations.
  UpdateItem(name: String, term: Term)
}

/// A value entered by hand, recorded as an observation on the server.
pub type ValueEntry {
  ValueEntry(
    // The positive magnitude of the item's value. Direction is implied by its
    // side.
    value: Float,
    // The date the value is accurate as of.
    as_of: Date,
  )
}

pub fn to_json(request: ItemWriteRequest) -> json.Json {
  case request {
    CreateItem(name:, side:, term:, first:) ->
      json.object([
        #("name", json.string(name)),
        #("side", side.to_json(side)),
        #("term", term.to_json(term)),
        #("value", money.encode_decimal(first.value)),
        #("asOf", date.encode(first.as_of)),
      ])
    UpdateItem(name:, term:) ->
      json.object([
        #("name", json.string(name)),
        #("term", term.to_json(term)),
      ])
  }
}

/// The record-value request.
pub fn value_entry_json(entry: ValueEntry) -> json.Json {
  json.object([
    #("value", money.encode_decimal(entry.value)),
    #("asOf", date.encode(entry.as_of)),
  ])
}
