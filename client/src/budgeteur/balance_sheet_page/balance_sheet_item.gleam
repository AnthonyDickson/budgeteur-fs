import budgeteur/balance_sheet_page/side.{type Side}
import budgeteur/balance_sheet_page/term.{type Term}
import budgeteur/shared/date
import budgeteur/shared/money
import budgeteur/shared/uuid as uuid_decoder
import gleam/dynamic/decode
import gleam/option.{type Option, None}
import gleam/time/calendar.{type Date}
import youid/uuid.{type Uuid}

pub type BalanceSheetItem {
  BalanceSheetItem(
    // Unique identifier for the item.
    id: Uuid,
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
    // The date the item was sold or repaid; None while it is held.
    closed_on: Option(Date),
  )
}

pub fn decoder() -> decode.Decoder(BalanceSheetItem) {
  use id <- decode.field("id", uuid_decoder.decoder())
  use name <- decode.field("name", decode.string)
  use side <- decode.field("side", side.decoder())
  use term <- decode.field("term", term.decoder())
  use value <- decode.field("value", money.decode_decimal())
  use as_of <- decode.field("asOf", date.decoder())
  use closed_on <- decode.optional_field(
    "closedOn",
    None,
    decode.optional(date.decoder()),
  )
  decode.success(BalanceSheetItem(
    id:,
    name:,
    side:,
    term:,
    value:,
    as_of:,
    closed_on:,
  ))
}
