import budgeteur/shared/uuid as uuid_codec
import gleam/dynamic/decode
import gleam/json
import gleam/list
import youid/uuid.{type Uuid}

pub type Tag {
  Tag(
    // Unique identifier for the tag.
    id: Uuid,
    // Display name of the tag.
    name: String,
    // The colour of the tag's swatch.
    color: TagColor,
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

/// A tag's colour: one of Catppuccin's accent colours, by name. The swatch
/// draws it in the active flavour, so a tag keeps its colour in light and dark
/// mode. Mirrors the server's `TagColor`.
pub type TagColor {
  Rosewater
  Flamingo
  Pink
  Mauve
  Red
  Maroon
  Peach
  Yellow
  Green
  Teal
  Sky
  Sapphire
  Blue
  Lavender
}

/// Every colour, in Catppuccin's order.
pub const colors = [
  Rosewater,
  Flamingo,
  Pink,
  Mauve,
  Red,
  Maroon,
  Peach,
  Yellow,
  Green,
  Teal,
  Sky,
  Sapphire,
  Blue,
  Lavender,
]

/// The encoded string for a `TagColor`. Mirrors the server's `toString`.
pub fn color_to_string(color: TagColor) -> String {
  case color {
    Rosewater -> "Rosewater"
    Flamingo -> "Flamingo"
    Pink -> "Pink"
    Mauve -> "Mauve"
    Red -> "Red"
    Maroon -> "Maroon"
    Peach -> "Peach"
    Yellow -> "Yellow"
    Green -> "Green"
    Teal -> "Teal"
    Sky -> "Sky"
    Sapphire -> "Sapphire"
    Blue -> "Blue"
    Lavender -> "Lavender"
  }
}

/// Parse a `TagColor` from its encoded string.
pub fn parse_color(value: String) -> Result(TagColor, Nil) {
  list.find(colors, fn(color) { color_to_string(color) == value })
}

pub fn color_to_json(color: TagColor) -> json.Json {
  json.string(color_to_string(color))
}

pub fn color_decoder() -> decode.Decoder(TagColor) {
  use value <- decode.then(decode.string)
  case parse_color(value) {
    Ok(color) -> decode.success(color)
    Error(Nil) -> decode.failure(Mauve, "TagColor")
  }
}

pub fn tag_decoder() -> decode.Decoder(Tag) {
  use id <- decode.field("id", uuid_codec.decoder())
  use name <- decode.field("name", decode.string)
  use color <- decode.field("color", color_decoder())
  use kind <- decode.field("kind", kind_decoder())
  decode.success(Tag(id:, name:, color:, kind:))
}
