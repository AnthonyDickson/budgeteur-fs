import gleam/dynamic/decode
import gleam/json

/// Whether the item is current or non-current.
pub type Term {
  Current
  NonCurrent
}

/// The encoded string for a `Term`. Mirrors the server's `toString`.
pub fn to_string(term: Term) -> String {
  case term {
    Current -> "Current"
    NonCurrent -> "NonCurrent"
  }
}

/// Parse a `Term` from its encoded string.
pub fn parse(value: String) -> Result(Term, Nil) {
  case value {
    "Current" -> Ok(Current)
    "NonCurrent" -> Ok(NonCurrent)
    _ -> Error(Nil)
  }
}

pub fn to_json(term: Term) -> json.Json {
  json.string(to_string(term))
}

pub fn decoder() -> decode.Decoder(Term) {
  use variant <- decode.then(decode.string)
  case parse(variant) {
    Ok(term) -> decode.success(term)
    Error(Nil) -> decode.failure(Current, "Term")
  }
}
