import gleam/dynamic/decode
import gleam/json

/// Which side of the balance sheet a line is on: fixed for an item, from the
/// balance's sign for an account.
pub type Side {
  Asset
  Liability
}

/// The encoded string for a `Side`. Mirrors the server's `toString`.
pub fn to_string(side: Side) -> String {
  case side {
    Asset -> "Asset"
    Liability -> "Liability"
  }
}

/// Parse a `Side` from its encoded string.
pub fn parse(value: String) -> Result(Side, Nil) {
  case value {
    "Asset" -> Ok(Asset)
    "Liability" -> Ok(Liability)
    _ -> Error(Nil)
  }
}

pub fn to_json(side: Side) -> json.Json {
  json.string(to_string(side))
}

pub fn decoder() -> decode.Decoder(Side) {
  use variant <- decode.then(decode.string)
  case parse(variant) {
    Ok(side) -> decode.success(side)
    Error(Nil) -> decode.failure(Asset, "Side")
  }
}
