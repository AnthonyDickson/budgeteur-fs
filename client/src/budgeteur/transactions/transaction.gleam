import budgeteur/date
import budgeteur/money
import gleam/dynamic/decode
import gleam/json
import gleam/option.{type Option, None}
import gleam/time/calendar.{type Date}
import youid/uuid.{type Uuid}

pub type Transaction {
  Transaction(
    // <summary>Unique identifier for the transaction item.</summary>
    id: Uuid,
    amount: Float,
    // The title or description of the transaction.</summary>
    description: String,
    // Date when the transaction occurred.
    date: Date,
    account_id: Option(Uuid),
    category_id: Option(Uuid),
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
  use account_id <- decode.optional_field(
    "account_id",
    None,
    decode.optional(uuid_decoder()),
  )
  use category_id <- decode.optional_field(
    "category_id",
    None,
    decode.optional(uuid_decoder()),
  )
  decode.success(Transaction(
    id:,
    amount:,
    description:,
    date:,
    account_id:,
    category_id:,
  ))
}

pub fn transaction_to_json(transaction: Transaction) -> json.Json {
  let Transaction(id:, amount:, description:, date:, account_id:, category_id:) =
    transaction
  json.object([
    #("id", json.string(uuid.to_string(id))),
    #("amount", money.encode_decimal(amount)),
    #("description", json.string(description)),
    #("date", date.encode(date)),
    #("account_id", case account_id {
      None -> json.null()
      option.Some(value) -> json.string(uuid.to_string(value))
    }),
    #("category_id", case category_id {
      None -> json.null()
      option.Some(value) -> json.string(uuid.to_string(value))
    }),
  ])
}
