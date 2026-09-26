import gleam/dynamic/decode
import gleam/json

/// Whether the item is an asset or a liability.
pub type ItemKind {
  Asset
  Liability
}

/// The encoded string for an `ItemKind`. Mirrors the server's `toString`.
pub fn to_string(item_kind: ItemKind) -> String {
  case item_kind {
    Asset -> "Asset"
    Liability -> "Liability"
  }
}

/// Parse an `ItemKind` from its encoded string.
pub fn parse(value: String) -> Result(ItemKind, Nil) {
  case value {
    "Asset" -> Ok(Asset)
    "Liability" -> Ok(Liability)
    _ -> Error(Nil)
  }
}

pub fn to_json(item_kind: ItemKind) -> json.Json {
  json.string(to_string(item_kind))
}

pub fn decoder() -> decode.Decoder(ItemKind) {
  use variant <- decode.then(decode.string)
  case parse(variant) {
    Ok(item_kind) -> decode.success(item_kind)
    Error(Nil) -> decode.failure(Asset, "ItemKind")
  }
}
