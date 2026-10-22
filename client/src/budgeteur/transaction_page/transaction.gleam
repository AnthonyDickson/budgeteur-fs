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
    // The name of the transaction's account, when it has one.
    account_name: Option(String),
    // The transaction's tag, or None when it is untagged.
    tag: Option(TransactionTag),
  )
}

/// A transaction's tag and where it came from.
pub type TransactionTag {
  TransactionTag(id: Uuid, source: TagSource)
}

/// Who decided the tag. Re-tag recomputes only rule tags, so `Rule` is the only
/// source the client treats differently. The server's sources are shared with
/// transfers, so `Detected` is accepted though a tag never has it.
pub type TagSource {
  // The user chose the tag without a suggestion.
  Manual
  // The user chose the suggested tag.
  Accepted
  // A rule applied the tag.
  Rule
  // Import detected a transfer.
  Detected
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
  use account_name <- decode.optional_field(
    "accountName",
    None,
    decode.optional(decode.string),
  )
  use tag <- decode.optional_field(
    "tag",
    None,
    decode.optional(transaction_tag_decoder()),
  )
  decode.success(Transaction(
    id:,
    amount:,
    description:,
    date:,
    is_transfer:,
    account_id:,
    account_name:,
    tag:,
  ))
}

fn transaction_tag_decoder() -> decode.Decoder(TransactionTag) {
  use id <- decode.field("id", uuid_codec.decoder())
  use source <- decode.field("source", tag_source_decoder())
  decode.success(TransactionTag(id:, source:))
}

fn tag_source_decoder() -> decode.Decoder(TagSource) {
  use source <- decode.then(decode.string)
  case source {
    "Manual" -> decode.success(Manual)
    "Accepted" -> decode.success(Accepted)
    "Rule" -> decode.success(Rule)
    "Detected" -> decode.success(Detected)
    _ -> decode.failure(Manual, "TagSource")
  }
}
