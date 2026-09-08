//// A tri-state text field shared by the transaction, tag, and rule forms.
////
//// A text input's value lives in one of three states: blank (`Empty`), holding
//// a successfully parsed value (`Valid`), or holding the input that failed to
//// parse plus the error (`Invalid`). The raw input the user typed is always
//// preserved in every state so the input element can be re-rendered from it
//// on every keystroke without eating spaces mid-typing; trimming and parsing
//// happen through `validate`, and the parsed `value` is what save-time code
//// consumes.
////
//// The module is deliberately stateless per keystroke: `validate` derives a
//// new `Field` from the raw input, `finalize` promotes a blank field to an
//// `Invalid` required error at submit time, and `mark_invalid` lets save-time
//// duplicate checks replace a `Valid` value with an error. The generic `error`
//// type is per-feature (e.g. `NameError`), so message rendering stays in the
//// feature's view.

import gleam/option.{type Option, None, Some}

pub type Field(value, error) {
  /// The input is blank (or only whitespace that parsed as a required error);
  /// it is not shown as an error until submit time.
  Empty(input: String)
  /// The input parsed successfully. `value` is the parsed result (e.g. a
  /// trimmed string or a parsed number); `input` is what the user typed.
  Valid(value: value, input: String)
  /// The input failed to parse or failed a save-time check; `error` drives the
  /// inline message. `input` is preserved so the field keeps showing what the
  /// user typed.
  Invalid(input: String, error: error)
}

/// The raw input string in every state.
pub fn input(field: Field(value, error)) -> String {
  case field {
    Empty(input) -> input
    Valid(input:, ..) -> input
    Invalid(input:, ..) -> input
  }
}

/// The parsed value when the field is `Valid`.
pub fn value(field: Field(value, error)) -> Option(value) {
  case field {
    Valid(value:, ..) -> Some(value)
    Empty(..) | Invalid(..) -> None
  }
}

/// The error when the field is `Invalid`.
pub fn error(field: Field(value, error)) -> Option(error) {
  case field {
    Invalid(error:, ..) -> Some(error)
    Empty(..) | Valid(..) -> None
  }
}

/// Whether the field currently holds an error. Errors are cleared as soon as
/// the user types something that parses or blanks the field, so the submit
/// button re-enables on the next keystroke.
pub fn has_error(field: Field(value, error)) -> Bool {
  case field {
    Invalid(..) -> True
    Empty(..) | Valid(..) -> False
  }
}

/// Keystroke validation. A truly blank input lands in `Empty`; a parse error
/// that `is_required` flags (e.g. a whitespace-only string in a required
/// field) also lands in `Empty` so the field is not shown as an error while
/// the user is still typing; any other parse error lands in `Invalid`. The
/// raw input is always preserved.
pub fn validate(
  input: String,
  parse: fn(String) -> Result(value, error),
  is_required: fn(error) -> Bool,
) -> Field(value, error) {
  case input {
    "" -> Empty(input)
    _ ->
      case parse(input) {
        Ok(value) -> Valid(value:, input:)
        Error(error) ->
          case is_required(error) {
            True -> Empty(input)
            False -> Invalid(input:, error:)
          }
      }
  }
}

/// Submit-time finalize: promote a blank field to `Invalid` with the required
/// error so the inline message appears. `Valid` and already-`Invalid` fields
/// are returned unchanged.
pub fn finalize(
  field: Field(value, error),
  required_error: fn() -> error,
) -> Field(value, error) {
  case field {
    Empty(input) -> Invalid(input:, error: required_error())
    Valid(..) | Invalid(..) -> field
  }
}

/// Save-time check helper: turn the field into an `Invalid` carrying `error`
/// (e.g. a duplicate), keeping the raw input. Used after `validate` has
/// confirmed the field parses but the surrounding context (e.g. the other
/// tags) rejects the value.
pub fn mark_invalid(
  field: Field(value, error),
  error: error,
) -> Field(value, error) {
  Invalid(input: input(field), error:)
}
