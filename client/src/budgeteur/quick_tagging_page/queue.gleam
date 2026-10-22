//// A batch of the quick tagging queue, as read from the server.

import budgeteur/shared/date
import budgeteur/shared/money
import budgeteur/shared/uuid as uuid_codec
import gleam/dynamic/decode
import gleam/json
import gleam/option.{type Option, None, Some}
import gleam/time/calendar.{type Date}
import youid/uuid.{type Uuid}

/// Up to 50 of the user's untagged non-transfer transactions, newest first,
/// and how many the whole queue holds. With a filter, only those suggested the
/// filter's target, and how many are. `suggestions` counts each suggested
/// target over the whole queue, whatever the filter, in the order of the row
/// buttons.
pub type Queue {
  Queue(
    transactions: List(QueuedTransaction),
    total: Int,
    suggestions: List(SuggestionCount),
  )
}

/// How many queued transactions are suggested a target.
pub type SuggestionCount {
  SuggestionCount(target: Target, count: Int)
}

/// A transaction waiting for a tag.
pub type QueuedTransaction {
  QueuedTransaction(
    id: Uuid,
    amount: Float,
    description: String,
    date: Date,
    account_name: Option(String),
    // What the winning rule suggests, from the user's current rules.
    suggestion: Option(Suggestion),
  )
}

/// A categorisation the queue suggests for a transaction: a tag or a transfer.
pub type Target {
  TagTarget(tag_id: Uuid)
  TransferTarget
}

/// The suggestion for a queued transaction, and the pattern of the rule that
/// suggests it, so the user can check why.
pub type Suggestion {
  Suggestion(target: Target, pattern: String)
}

pub fn decoder() -> decode.Decoder(Queue) {
  use transactions <- decode.field(
    "transactions",
    decode.list(transaction_decoder()),
  )
  use total <- decode.field("total", decode.int)
  use suggestions <- decode.field(
    "suggestions",
    decode.list(suggestion_count_decoder()),
  )
  decode.success(Queue(transactions:, total:, suggestions:))
}

fn suggestion_count_decoder() -> decode.Decoder(SuggestionCount) {
  use target <- decode.then(target_decoder())
  use count <- decode.field("count", decode.int)
  decode.success(SuggestionCount(target:, count:))
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
  use suggestion <- decode.optional_field(
    "suggestion",
    None,
    decode.optional(suggestion_decoder()),
  )
  decode.success(QueuedTransaction(
    id:,
    amount:,
    description:,
    date:,
    account_name:,
    suggestion:,
  ))
}

fn suggestion_decoder() -> decode.Decoder(Suggestion) {
  use target <- decode.then(target_decoder())
  use pattern <- decode.field("pattern", decode.string)
  decode.success(Suggestion(target:, pattern:))
}

/// The server sends a target as a kind and an optional tag id, since its
/// OpenAPI document cannot describe a union with fields.
fn target_decoder() -> decode.Decoder(Target) {
  use kind <- decode.field("target", decode.string)
  use tag_id <- decode.optional_field(
    "tagId",
    None,
    decode.optional(uuid_codec.decoder()),
  )
  case kind, tag_id {
    "Tag", Some(tag_id) -> decode.success(TagTarget(tag_id))
    "Transfer", None -> decode.success(TransferTarget)
    _, _ -> decode.failure(TransferTarget, "Target")
  }
}

/// The target as query parameters, for filtering the queue by it.
pub fn target_query(target: Target) -> List(#(String, String)) {
  case target {
    TagTarget(tag_id:) -> [
      #("target", "Tag"),
      #("tagId", uuid.to_string(tag_id)),
    ]
    TransferTarget -> [#("target", "Transfer")]
  }
}

/// The target as request fields, for approving it.
pub fn target_fields(target: Target) -> List(#(String, json.Json)) {
  case target {
    TagTarget(tag_id:) -> [
      #("target", json.string("Tag")),
      #("tagId", json.string(uuid.to_string(tag_id))),
    ]
    TransferTarget -> [#("target", json.string("Transfer"))]
  }
}
