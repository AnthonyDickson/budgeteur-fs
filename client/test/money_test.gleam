import budgeteur/money
import gleeunit/should

pub fn to_string_pads_single_decimal_place_test() {
  money.to_string(3.5)
  |> should.equal("3.50")
}

pub fn to_string_rounds_to_two_decimal_places_test() {
  money.to_string(3.14159)
  |> should.equal("3.14")
}

pub fn to_string_handles_whole_numbers_test() {
  money.to_string(3.0)
  |> should.equal("3.00")
}

pub fn to_string_handles_negative_values_test() {
  money.to_string(-3.14159)
  |> should.equal("-3.14")
}

pub fn to_string_handles_zero_test() {
  money.to_string(0.0)
  |> should.equal("0.00")
}

pub fn to_string_handles_float_accumulation_error_test() {
  money.to_string(0.1 +. 0.2)
  |> should.equal("0.30")
}

pub fn format_includes_currency_symbol_test() {
  money.format(3.5)
  |> should.equal("$3.50")
}

pub fn format_handles_negative_values_test() {
  money.format(-3.14159)
  |> should.equal("-$3.14")
}
