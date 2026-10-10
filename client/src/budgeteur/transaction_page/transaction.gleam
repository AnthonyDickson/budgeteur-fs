import budgeteur/shared/date
import budgeteur/shared/money
import budgeteur/shared/uuid as uuid_codec
import gleam/dynamic/decode
import gleam/option.{type Option, None}
import gleam/time/calendar.{type Date}
import youid/uuid.{type Uuid}

pub type Transaction {
  Transaction(
    // Unique identifier for the transaction item.
    id: Uuid,
    amount: Float,
    // The title or description of the transaction.
    description: String,
    // Date when the transaction occurred.
    date: Date,
    // Whether the transaction represents an internal transfer between one's own accounts.
    is_transfer: Bool,
    account_id: Option(Uuid),
    tag_id: Option(Uuid),
  )
}

pub fn transaction_decoder() -> decode.Decoder(Transaction) {
  use id <- decode.field("id", uuid_codec.decoder())
  use amount <- decode.field("amount", money.decode_decimal())
  use description <- decode.field("description", decode.string)
  use date <- decode.field("date", date.decoder())
  use is_transfer <- decode.field("isTransfer", decode.bool)
  use account_id <- decode.optional_field(
    "accountId",
    None,
    decode.optional(uuid_codec.decoder()),
  )
  use tag_id <- decode.optional_field(
    "tagId",
    None,
    decode.optional(uuid_codec.decoder()),
  )
  decode.success(Transaction(
    id:,
    amount:,
    description:,
    date:,
    is_transfer:,
    account_id:,
    tag_id: tag_id,
  ))
}
