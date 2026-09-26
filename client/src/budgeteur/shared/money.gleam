//// Monetary values are represented with the decimal type on the backend, but
//// JavaScript doesn't support this type. The coders here intentionally use
//// floats as the decode target to keep things simple but assumes the following:
//// - all operations that aggregrate monetary values are done on the backend using the decimal type
//// - the frontend only ever displays values and never aggregates it.
//// - occassional rounding errors of about one cent are acceptable
//// 
//// If the above assumptions are invalidated, the API responses should be modified
//// to represent monetary values in minor units as integers (dollar amount * 100,
//// i.e. cents) and possibly the formatted currency string. This gives accurate
//// values up to JavaScript max integer value (2^53) which is more money than
//// I'll ever have.

import gleam/dynamic/decode
import gleam/float
import gleam/int
import gleam/json
import gleam/string

fn float_decoder() -> decode.Decoder(Float) {
  decode.string
  |> decode.then(fn(raw_string) {
    case float.parse(raw_string) {
      Ok(parsed_float) -> decode.success(parsed_float)
      Error(Nil) -> decode.failure(0.0, "Float")
    }
  })
}

fn int_to_float_decoder() -> decode.Decoder(Float) {
  decode.string
  |> decode.then(fn(raw_string) {
    case int.parse(raw_string) {
      Ok(parsed_float) -> decode.success(int.to_float(parsed_float))
      Error(Nil) -> decode.failure(0.0, "Float")
    }
  })
}

pub fn decode_decimal() -> decode.Decoder(Float) {
  decode.one_of(float_decoder(), or: [int_to_float_decoder()])
}

pub fn encode_decimal(amount: Float) -> json.Json {
  // Encode the amount as a string since the backend expects a decimal value.
  // This avoids having to write custom decoders.
  amount |> to_string |> json.string
}

/// Parse a user-entered amount. `gleam/float.parse` requires a decimal point,
/// so whole numbers such as "400000" fall back to `int.parse`. Mirrors
/// `decode_decimal`, which accepts both shapes from the server.
///
/// # Example
/// ```gleam
/// assert parse_decimal("400000") == Ok(400000.0)
/// assert parse_decimal("12.50") == Ok(12.5)
/// assert parse_decimal("abc") == Error(Nil)
/// ```
pub fn parse_decimal(input: String) -> Result(Float, Nil) {
  case float.parse(input) {
    Ok(amount) -> Ok(amount)
    Error(Nil) ->
      case int.parse(input) {
        Ok(amount) -> Ok(int.to_float(amount))
        Error(Nil) -> Error(Nil)
      }
  }
}

/// Truncate a user-entered amount to two decimal places, so the value on screen
/// matches the cents the server stores. Only well-formed amounts are clipped;
/// malformed input such as "12.." or "1.2.3" passes through unchanged for the
/// validation layer to report.
pub fn clip_to_two_dp(input: String) -> String {
  case string.split(input, ".") {
    [whole, fraction] ->
      whole <> "." <> string.slice(from: fraction, at_index: 0, length: 2)
    _ -> input
  }
}

/// Convert an amount to a string with exactly two decimal places, without a
/// currency symbol.
///
/// # Example
/// ```gleam
/// assert to_string(3.5) == "3.50"
/// assert to_string(-3.14159) == "-3.14"
/// ```
pub fn to_string(amount: Float) -> String {
  amount
  |> float.to_precision(2)
  |> float.to_string
  |> fn(string) {
    case string.split(string, ".") {
      [whole] -> whole <> ".00"
      [whole, fraction] ->
        whole <> "." <> string.pad_end(fraction, to: 2, with: "0")
      _ -> string
    }
  }
}

/// Format a monetary amount.
///
/// # Example
/// ```gleam
/// assert format(3.14159) == "$3.14"
/// assert format(-3.14159) == "-$3.14"
/// ```
pub fn format(amount: Float) -> String {
  let is_negative = amount <. 0.0
  let prefix = case is_negative {
    True -> "-$"
    False -> "$"
  }

  prefix <> to_string(amount |> float.absolute_value)
}
