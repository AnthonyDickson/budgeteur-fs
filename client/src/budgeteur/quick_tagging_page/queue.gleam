//// A batch of the quick tagging queue, as read from the server.

import budgeteur/shared/date
import budgeteur/shared/money
import budgeteur/shared/uuid as uuid_codec
import gleam/dynamic/decode
import gleam/option.{type Option, None}
import gleam/time/calendar.{type Date}
import youid/uuid.{type Uuid}

/// Up to 50 of the user's untagged non-transfer transactions, newest first,
/// and how many the whole queue holds.
pub type Queue {
  Queue(transactions: List(QueuedTransaction), total: Int)
}

/// A transaction waiting for a tag.
pub type QueuedTransaction {
  QueuedTransaction(
    id: Uuid,
    amount: Float,
    description: String,
    date: Date,
    account_name: Option(String),
  )
}

pub fn decoder() -> decode.Decoder(Queue) {
  use transactions <- decode.field(
    "transactions",
    decode.list(transaction_decoder()),
  )
  use total <- decode.field("total", decode.int)
  decode.success(Queue(transactions:, total:))
}

fn transaction_decoder() -> decode.Decoder(QueuedTransaction) {
  use id <- decode.field("id", uuid_codec.decoder())
  use amount <- decode.field("amount", money.decode_decimal())
  use description <- decode.field("description", decode.string)
  use date <- decode.field("date", date.decoder())
  use account_name <- decode.optional_field(
    "accountName",
    None,
    decode.optional(decode.string),
  )
  decode.success(QueuedTransaction(
    id:,
    amount:,
    description:,
    date:,
    account_name:,
  ))
}
