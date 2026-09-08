import budgeteur/shared/field
import gleam/int
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should

fn parse_int(input: String) -> Result(Int, String) {
  case int.parse(string.trim(input)) {
    Ok(n) -> Ok(n)
    Error(_) -> Error("not a number")
  }
}

fn is_required(error: String) -> Bool {
  error == "required"
}

fn parse_number(input: String) -> Result(Int, String) {
  case input {
    "1" | "2" | "3" -> Ok(1)
    _ -> Error("not a number")
  }
}

pub fn validate_blank_input_is_empty_test() {
  let f: field.Field(Int, String) = field.validate("", parse_int, is_required)
  f |> should.equal(field.Empty(input: ""))
}

pub fn validate_blank_input_keeps_raw_input_test() {
  // The parse function is not consulted for a blank input; the field is Empty
  // regardless of what parse would have said.
  let f: field.Field(Int, String) =
    field.validate("", fn(_) { Error("not a number") }, fn(_) { False })
  f |> should.equal(field.Empty(input: ""))
}

pub fn validate_whitespace_only_with_required_error_is_empty_test() {
  // A whitespace-only string parses to the required error; is_required flags
  // it, so the field stays Empty (no inline error while typing) but the raw
  // input survives for finalize to promote on submit.
  let f: field.Field(String, String) =
    field.validate("   ", parse_required, fn(error) { error == "required" })
  f |> should.equal(field.Empty(input: "   "))
}

fn parse_required(input: String) -> Result(String, String) {
  case string.trim(input) {
    "" -> Error("required")
    _ -> Ok(input)
  }
}

pub fn validate_parse_error_is_invalid_test() {
  let f: field.Field(Int, String) =
    field.validate("abc", parse_int, is_required)
  f |> should.equal(field.Invalid(input: "abc", error: "not a number"))
}

pub fn validate_parse_error_keeps_raw_input_test() {
  let f: field.Field(Int, String) =
    field.validate("  12.5  ", parse_int, is_required)
  f
  |> should.equal(field.Invalid(input: "  12.5  ", error: "not a number"))
}

pub fn validate_parse_ok_stores_value_and_raw_input_test() {
  let f: field.Field(Int, String) =
    field.validate("  12  ", parse_int, is_required)
  f |> should.equal(field.Valid(value: 12, input: "  12  "))
}

pub fn validate_non_required_parse_error_is_invalid_test() {
  // An error that is_required does not flag is a real error, not a blank.
  let f: field.Field(Int, String) =
    field.validate("x", parse_number, is_required)
  f |> should.equal(field.Invalid(input: "x", error: "not a number"))
}

pub fn input_accessor_returns_raw_input_test() {
  field.input(field.Empty(input: "")) |> should.equal("")
  field.input(field.Empty(input: " ")) |> should.equal(" ")
  field.input(field.Valid(value: 1, input: " 1 ")) |> should.equal(" 1 ")
  field.input(field.Invalid(input: "a", error: "not a number"))
  |> should.equal("a")
}

pub fn value_accessor_test() {
  field.value(field.Valid(value: 1, input: "1")) |> should.equal(Some(1))
  field.value(field.Empty(input: "")) |> should.equal(None)
  field.value(field.Invalid(input: "a", error: "not a number"))
  |> should.equal(None)
}

pub fn error_accessor_test() {
  field.error(field.Invalid(input: "a", error: "not a number"))
  |> should.equal(Some("not a number"))
  field.error(field.Empty(input: "")) |> should.equal(None)
  field.error(field.Valid(value: 1, input: "1")) |> should.equal(None)
}

pub fn has_error_is_true_only_for_invalid_test() {
  field.has_error(field.Invalid(input: "a", error: "not a number"))
  |> should.be_true
  field.has_error(field.Empty(input: "")) |> should.be_false
  field.has_error(field.Valid(value: 1, input: "1")) |> should.be_false
}

pub fn finalize_promotes_blank_to_required_error_test() {
  let f: field.Field(Int, String) = field.Empty(input: "")
  field.finalize(f, fn() { "required" })
  |> should.equal(field.Invalid(input: "", error: "required"))
}

pub fn finalize_promotes_whitespace_blank_to_required_error_test() {
  let f: field.Field(String, String) = field.Empty(input: "   ")
  field.finalize(f, fn() { "required" })
  |> should.equal(field.Invalid(input: "   ", error: "required"))
}

pub fn finalize_leaves_valid_untouched_test() {
  let f: field.Field(Int, String) = field.Valid(value: 1, input: "1")
  field.finalize(f, fn() { "required" }) |> should.equal(f)
}

pub fn finalize_leaves_invalid_untouched_test() {
  let f: field.Field(Int, String) =
    field.Invalid(input: "x", error: "not a number")
  field.finalize(f, fn() { "required" }) |> should.equal(f)
}

pub fn mark_invalid_keeps_raw_input_test() {
  let f: field.Field(Int, String) = field.Valid(value: 1, input: " 1 ")
  field.mark_invalid(f, "duplicate")
  |> should.equal(field.Invalid(input: " 1 ", error: "duplicate"))
}

pub fn mark_invalid_replaces_an_existing_error_test() {
  let f: field.Field(Int, String) =
    field.Invalid(input: "1", error: "not a number")
  field.mark_invalid(f, "duplicate")
  |> should.equal(field.Invalid(input: "1", error: "duplicate"))
}
