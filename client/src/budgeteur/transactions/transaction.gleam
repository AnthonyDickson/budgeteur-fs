import budgeteur/date
import budgeteur/money
import gleam/dynamic/decode
import gleam/json
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

fn uuid_decoder() -> decode.Decoder(Uuid) {
  decode.string
  |> decode.then(fn(s) {
    case uuid.from_string(s) {
      Ok(uuid) -> decode.success(uuid)
      Error(Nil) -> decode.failure(uuid.nil, "Uuid")
    }
  })
}

pub fn transaction_decoder() -> decode.Decoder(Transaction) {
  use id <- decode.field("id", uuid_decoder())
  use amount <- decode.field("amount", money.decode_decimal())
  use description <- decode.field("description", decode.string)
  use date <- decode.field("date", date.decoder())
  use is_transfer <- decode.field("isTransfer", decode.bool)
  use account_id <- decode.optional_field(
    "accountId",
    None,
    decode.optional(uuid_decoder()),
  )
  use tag_id <- decode.optional_field(
    "tagId",
    None,
    decode.optional(uuid_decoder()),
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

pub fn transaction_to_json(transaction: Transaction) -> json.Json {
  let Transaction(
    id:,
    amount:,
    description:,
    date:,
    is_transfer:,
    account_id:,
    tag_id:,
  ) = transaction
  json.object([
    #("id", json.string(uuid.to_string(id))),
    #("amount", money.encode_decimal(amount)),
    #("description", json.string(description)),
    #("date", date.encode(date)),
    #("isTransfer", json.bool(is_transfer)),
    #("accountId", case account_id {
      None -> json.null()
      option.Some(value) -> json.string(uuid.to_string(value))
    }),
    #("tagId", case tag_id {
      None -> json.null()
      option.Some(value) -> json.string(uuid.to_string(value))
    }),
  ])
}
