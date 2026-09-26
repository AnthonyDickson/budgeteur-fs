import budgeteur/shared/money
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

// Parsing user input. `gleam/float.parse` rejects whole numbers, so these pin
// the `int.parse` fallback that makes "400000" a valid amount.

pub fn parse_decimal_accepts_whole_numbers_test() {
  money.parse_decimal("400000")
  |> should.equal(Ok(400_000.0))
}

pub fn parse_decimal_accepts_negative_whole_numbers_test() {
  money.parse_decimal("-5")
  |> should.equal(Ok(-5.0))
}

pub fn parse_decimal_accepts_decimal_values_test() {
  money.parse_decimal("12.50")
  |> should.equal(Ok(12.5))
}

pub fn parse_decimal_rejects_non_numeric_input_test() {
  money.parse_decimal("abc")
  |> should.equal(Error(Nil))
}

pub fn parse_decimal_rejects_malformed_decimal_points_test() {
  money.parse_decimal("12..")
  |> should.equal(Error(Nil))
}

pub fn clip_to_two_dp_allows_up_to_two_decimal_places_test() {
  money.clip_to_two_dp("12.3")
  |> should.equal("12.3")
}

pub fn clip_to_two_dp_truncates_extra_decimal_places_test() {
  money.clip_to_two_dp("12.345")
  |> should.equal("12.34")
}

pub fn clip_to_two_dp_preserves_trailing_decimal_point_test() {
  money.clip_to_two_dp("12.")
  |> should.equal("12.")
}

pub fn clip_to_two_dp_leaves_whole_numbers_untouched_test() {
  money.clip_to_two_dp("123")
  |> should.equal("123")
}

pub fn clip_to_two_dp_leaves_malformed_input_untouched_test() {
  money.clip_to_two_dp("12..")
  |> should.equal("12..")
  money.clip_to_two_dp("1.2.3")
  |> should.equal("1.2.3")
}
