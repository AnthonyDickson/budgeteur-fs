import budgeteur/balance_sheet_page/item_kind.{type ItemKind}
import budgeteur/balance_sheet_page/term.{type Term}
import budgeteur/shared/money
import budgeteur/shared/uuid as uuid_decoder
import gleam/dynamic/decode
import gleam/json
import youid/uuid.{type Uuid}

pub type BalanceSheetItem {
  BalanceSheetItem(
    // Unique identifier for the item.
    id: Uuid,
    // A human-readable name, e.g. "Chequing account" or "Mortgage".
    name: String,
    // Whether the item is an asset or a liability.
    kind: ItemKind,
    // Whether the item is current or non-current.
    term: Term,
    // The positive magnitude of the item's value. Direction is implied by Kind.
    balance: Float,
  )
}

pub fn to_json(balance_sheet_item: BalanceSheetItem) -> json.Json {
  let BalanceSheetItem(id:, name:, kind:, term:, balance:) = balance_sheet_item
  json.object([
    #("id", uuid.to_string(id) |> json.string),
    #("name", json.string(name)),
    #("kind", item_kind.to_json(kind)),
    #("term", term.to_json(term)),
    #("balance", money.encode_decimal(balance)),
  ])
}

pub fn decoder() -> decode.Decoder(BalanceSheetItem) {
  use id <- decode.field("id", uuid_decoder.decoder())
  use name <- decode.field("name", decode.string)
  use kind <- decode.field("kind", item_kind.decoder())
  use term <- decode.field("term", term.decoder())
  use balance <- decode.field("balance", money.decode_decimal())
  decode.success(BalanceSheetItem(id:, name:, kind:, term:, balance:))
}
