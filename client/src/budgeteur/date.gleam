//// Helpers for encoding and decoding ISO-8601 date strings.

import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/result
import gleam/string
import gleam/time/calendar.{type Date, Date}

/// Parse an ISO-8601 date.
///
/// # Example
///
/// ```gleam
/// let assert Ok(calendar.Date(2026, 8, 9)) = parse_date("2026-08-09")
/// let assert Error(Nil) = parse_date("9 Aug, 2026")
/// ```
pub fn parse(date_string: String) -> Result(Date, Nil) {
  case string.split(date_string, on: "-") {
    [year, month, day] -> {
      use year <- result.try(int.parse(year))
      use month_int <- result.try(int.parse(month))
      use day <- result.try(int.parse(day))
      use month <- result.try(calendar.month_from_int(month_int))
      Ok(Date(year, month, day))
    }
    _ -> Error(Nil)
  }
}

/// Decode a string as a ISO-8601 date.
pub fn decoder() -> decode.Decoder(Date) {
  use date_string <- decode.then(decode.string)
  case parse(date_string) {
    Ok(date) -> decode.success(date)
    Error(Nil) -> decode.failure(Date(1970, calendar.January, 1), "Date")
  }
}

/// Format a `calendar.Date` as an ISO-8601 date.
///
/// # Example
///
/// ```gleam
/// let assert "2026-08-10" = format(calendar.Date(2026, 8, 10))
/// ```
pub fn format(date: Date) -> String {
  let year = date.year |> int.to_string |> string.pad_start(to: 4, with: "0")
  let month =
    date.month
    |> calendar.month_to_int
    |> int.to_string
    |> string.pad_start(to: 2, with: "0")
  let day = date.day |> int.to_string |> string.pad_start(to: 2, with: "0")

  year <> "-" <> month <> "-" <> day
}

/// Encode a `calendar.Date` as an ISO-8601 date.
pub fn encode(date: Date) -> json.Json {
  json.string(format(date))
}
