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
import gleam/json

pub fn decode_decimal() -> decode.Decoder(Float) {
  decode.string
  |> decode.then(fn(raw_string) {
    case float.parse(raw_string) {
      Ok(parsed_float) -> decode.success(parsed_float)
      Error(Nil) -> decode.failure(0.0, "Float")
    }
  })
}

pub fn encode_decimal(amount: Float) -> json.Json {
  // Encode the amount as a string since the backend expects a decimal value.
  // This avoids having to write custom decoders.
  json.string(amount |> float.to_precision(2) |> float.to_string)
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

  amount
  |> float.absolute_value
  |> float.to_precision(2)
  |> float.to_string
  |> fn(amount) { prefix <> amount }
}
