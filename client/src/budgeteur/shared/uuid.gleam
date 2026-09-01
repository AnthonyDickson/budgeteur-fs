import gleam/dynamic/decode
import youid/uuid.{type Uuid}

/// Decode a UUID string.
pub fn decoder() -> decode.Decoder(Uuid) {
  decode.string
  |> decode.then(fn(s) {
    case uuid.from_string(s) {
      Ok(uuid) -> decode.success(uuid)
      Error(Nil) -> decode.failure(uuid.nil, "Uuid")
    }
  })
}
