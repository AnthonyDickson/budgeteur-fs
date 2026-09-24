import gleam/dynamic/decode
import gleam/json
import gleam/time/calendar
import gleam/time/timestamp.{type Timestamp}

pub fn to_json(timestamp: Timestamp) -> json.Json {
  json.string(timestamp.to_rfc3339(timestamp, calendar.utc_offset))
}

pub fn decoder() -> decode.Decoder(Timestamp) {
  use raw_string <- decode.then(decode.string)

  case timestamp.parse_rfc3339(raw_string) {
    Ok(timestamp) -> decode.success(timestamp)
    Error(Nil) -> decode.failure(timestamp.unix_epoch, "Timestamp")
  }
}
