import gleam/dynamic/decode
import gleam/time/timestamp.{type Timestamp}

pub fn decoder() -> decode.Decoder(Timestamp) {
  use raw_string <- decode.then(decode.string)

  case timestamp.parse_rfc3339(raw_string) {
    Ok(timestamp) -> decode.success(timestamp)
    Error(Nil) -> decode.failure(timestamp.unix_epoch, "Timestamp")
  }
}
