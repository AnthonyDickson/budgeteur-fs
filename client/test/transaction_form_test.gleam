import budgeteur/transactions/transaction_form.{
  Credit, Debit, EmptyDate, EmptyDescription, NotADate, NotANumber, NotPositive,
  TooLong,
}
import gleam/option.{Some}
import gleam/string
import gleeunit/should

pub fn clip_amount_allows_up_to_two_decimal_places_test() {
  transaction_form.clip_amount_to_two_dp("12.3")
  |> should.equal("12.3")
}

pub fn clip_amount_truncates_extra_decimal_places_test() {
  transaction_form.clip_amount_to_two_dp("12.345")
  |> should.equal("12.34")
}

pub fn clip_amount_preserves_trailing_decimal_point_test() {
  transaction_form.clip_amount_to_two_dp("12.")
  |> should.equal("12.")
}

pub fn clip_amount_ignores_additional_decimal_points_test() {
  transaction_form.clip_amount_to_two_dp("12.34.56")
  |> should.equal("12.34")
}

pub fn clip_amount_leaves_whole_numbers_untouched_test() {
  transaction_form.clip_amount_to_two_dp("123")
  |> should.equal("123")
}

pub fn clip_amount_handles_negative_values_test() {
  transaction_form.clip_amount_to_two_dp("-12.345")
  |> should.equal("-12.34")
}

pub fn clip_amount_handles_empty_string_test() {
  transaction_form.clip_amount_to_two_dp("")
  |> should.equal("")
}

pub fn set_amount_clips_to_two_decimal_places_test() {
  let form =
    transaction_form.empty()
    |> transaction_form.set_amount("12.345")
  form.amount |> should.equal("12.34")
}

pub fn set_amount_records_not_a_number_error_test() {
  let form =
    transaction_form.empty()
    |> transaction_form.set_amount("abc")
  form.error.amount |> should.equal(Some(NotANumber))
}

pub fn set_amount_records_not_positive_error_test() {
  let form =
    transaction_form.empty()
    |> transaction_form.set_amount("-5")
  form.error.amount |> should.equal(Some(NotPositive))
}

pub fn set_amount_accepts_zero_test() {
  let form =
    transaction_form.empty()
    |> transaction_form.set_amount("0")
  form.error.amount |> should.be_none
}

pub fn set_description_records_empty_error_test() {
  let form =
    transaction_form.empty()
    |> transaction_form.set_description("  ")
  form.error.description |> should.equal(Some(EmptyDescription))
}

pub fn set_description_records_too_long_error_test() {
  let form =
    transaction_form.empty()
    |> transaction_form.set_description(string.repeat(
      "a",
      transaction_form.max_description_length + 1,
    ))
  form.error.description |> should.equal(Some(TooLong))
}

pub fn set_date_records_empty_error_test() {
  let form =
    transaction_form.empty()
    |> transaction_form.set_date("")
  form.error.date |> should.equal(Some(EmptyDate))
}

pub fn set_date_records_not_a_date_error_test() {
  let form =
    transaction_form.empty()
    |> transaction_form.set_date("not a date")
  form.error.date |> should.equal(Some(NotADate))
}

pub fn from_prefills_without_validation_errors_test() {
  let form = transaction_form.from("12.5", Debit, "Coffee", "2026-01-02")
  form.error.amount |> should.be_none
  form.error.description |> should.be_none
  form.error.date |> should.be_none
  transaction_form.validate(form) |> should.be_ok
}

pub fn set_type_switches_to_credit_test() {
  let form =
    transaction_form.empty()
    |> transaction_form.set_type_(Credit)
  transaction_form.validate(form) |> should.be_error
}

pub fn validate_negates_debit_amounts_test() {
  let form =
    transaction_form.empty()
    |> transaction_form.set_amount("12.5")
    |> transaction_form.set_description("Coffee")
    |> transaction_form.set_date("2026-01-02")
  let request = transaction_form.validate(form) |> should.be_ok
  request.amount |> should.equal(-12.5)
}

pub fn validate_keeps_credit_amounts_positive_test() {
  let form =
    transaction_form.empty()
    |> transaction_form.set_type_(Credit)
    |> transaction_form.set_amount("12.5")
    |> transaction_form.set_description("Salary")
    |> transaction_form.set_date("2026-01-02")
  let request = transaction_form.validate(form) |> should.be_ok
  request.amount |> should.equal(12.5)
}

pub fn validate_returns_all_errors_test() {
  let form =
    transaction_form.empty()
    |> transaction_form.set_amount("abc")
    |> transaction_form.set_date("")
  let error = transaction_form.validate(form) |> should.be_error
  error.amount |> should.equal(Some(NotANumber))
  error.description |> should.equal(Some(EmptyDescription))
  error.date |> should.equal(Some(EmptyDate))
}
