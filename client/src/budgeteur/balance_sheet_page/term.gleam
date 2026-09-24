import gleam/dynamic/decode
import gleam/json

/// Whether the item is current or non-current.
pub type Term {
  Current
  NonCurrent
}

pub fn to_json(term: Term) -> json.Json {
  case term {
    Current -> json.string("Current")
    NonCurrent -> json.string("NonCurrent")
  }
}

pub fn decoder() -> decode.Decoder(Term) {
  use variant <- decode.then(decode.string)
  case variant {
    "Current" -> decode.success(Current)
    "NonCurrent" -> decode.success(NonCurrent)
    _ -> decode.failure(Current, "Term")
  }
}
