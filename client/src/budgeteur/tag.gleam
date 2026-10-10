import budgeteur/shared/uuid as uuid_codec
import gleam/dynamic/decode
import gleam/json
import youid/uuid.{type Uuid}

pub type Tag {
  Tag(
    // Unique identifier for the tag.
    id: Uuid,
    // Display name of the tag.
    name: String,
    // Hex color used for the tag's swatch, e.g. "#6366F1".
    color: String,
    // Which side of the income statement the tag's transactions are on.
    kind: TagKind,
  )
}

/// Which side of the income statement a tag's transactions are on.
pub type TagKind {
  Income
  Expense
}

/// The encoded string for a `TagKind`. Mirrors the server's `toString`.
pub fn kind_to_string(kind: TagKind) -> String {
  case kind {
    Income -> "Income"
    Expense -> "Expense"
  }
}

/// Parse a `TagKind` from its encoded string.
pub fn parse_kind(value: String) -> Result(TagKind, Nil) {
  case value {
    "Income" -> Ok(Income)
    "Expense" -> Ok(Expense)
    _ -> Error(Nil)
  }
}

pub fn kind_to_json(kind: TagKind) -> json.Json {
  json.string(kind_to_string(kind))
}

pub fn kind_decoder() -> decode.Decoder(TagKind) {
  use value <- decode.then(decode.string)
  case parse_kind(value) {
    Ok(kind) -> decode.success(kind)
    Error(Nil) -> decode.failure(Expense, "TagKind")
  }
}

pub fn tag_decoder() -> decode.Decoder(Tag) {
  use id <- decode.field("id", uuid_codec.decoder())
  use name <- decode.field("name", decode.string)
  use color <- decode.field("color", decode.string)
  use kind <- decode.field("kind", kind_decoder())
  decode.success(Tag(id:, name:, color:, kind:))
}
