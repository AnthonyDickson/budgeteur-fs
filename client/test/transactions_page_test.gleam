import budgeteur/transactions/transactions_page
import gleeunit/should

pub fn clip_amount_allows_up_to_two_decimal_places_test() {
  transactions_page.clip_amount_to_two_dp("12.3")
  |> should.equal("12.3")
}

pub fn clip_amount_truncates_extra_decimal_places_test() {
  transactions_page.clip_amount_to_two_dp("12.345")
  |> should.equal("12.34")
}

pub fn clip_amount_preserves_trailing_decimal_point_test() {
  transactions_page.clip_amount_to_two_dp("12.")
  |> should.equal("12.")
}

pub fn clip_amount_ignores_additional_decimal_points_test() {
  transactions_page.clip_amount_to_two_dp("12.34.56")
  |> should.equal("12.34")
}

pub fn clip_amount_leaves_whole_numbers_untouched_test() {
  transactions_page.clip_amount_to_two_dp("123")
  |> should.equal("123")
}

pub fn clip_amount_handles_negative_values_test() {
  transactions_page.clip_amount_to_two_dp("-12.345")
  |> should.equal("-12.34")
}

pub fn clip_amount_handles_empty_string_test() {
  transactions_page.clip_amount_to_two_dp("")
  |> should.equal("")
}
