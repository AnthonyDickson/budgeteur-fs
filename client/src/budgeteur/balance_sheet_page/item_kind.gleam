import gleam/dynamic/decode
import gleam/json

/// Whether the item is an asset or a liability.
pub type ItemKind {
  Asset
  Liability
}

pub fn to_json(item_kind: ItemKind) -> json.Json {
  case item_kind {
    Asset -> json.string("Asset")
    Liability -> json.string("Liability")
  }
}

pub fn decoder() -> decode.Decoder(ItemKind) {
  use variant <- decode.then(decode.string)
  case variant {
    "Asset" -> decode.success(Asset)
    "Liability" -> decode.success(Liability)
    _ -> decode.failure(Asset, "ItemKind")
  }
}
