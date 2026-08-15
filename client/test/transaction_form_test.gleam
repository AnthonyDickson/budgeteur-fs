import budgeteur/transactions/transaction
import budgeteur/transactions/transaction_form.{
  Credit, Debit, EmptyDate, EmptyDescription, NotADate, NotANumber, NotPositive,
  TooLong,
}
import gleam/option.{None, Some}
import gleam/string
import gleam/time/calendar
import gleeunit/should
import youid/uuid

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

pub fn empty_modal_starts_in_create_mode_test() {
  let state = transaction_form.empty_modal()
  state.mode |> should.equal(transaction_form.Create)
  state.submitting |> should.be_false
}

pub fn set_amount_clips_to_two_decimal_places_test() {
  let state =
    transaction_form.empty_modal()
    |> transaction_form.set_amount("12.345")
  state.form.amount |> should.equal("12.34")
}

pub fn set_amount_records_not_a_number_error_test() {
  let state =
    transaction_form.empty_modal()
    |> transaction_form.set_amount("abc")
  state.form.error.amount |> should.equal(Some(NotANumber))
}

pub fn set_amount_records_not_positive_error_test() {
  let state =
    transaction_form.empty_modal()
    |> transaction_form.set_amount("-5")
  state.form.error.amount |> should.equal(Some(NotPositive))
}

pub fn set_amount_accepts_zero_test() {
  let state =
    transaction_form.empty_modal()
    |> transaction_form.set_amount("0")
  state.form.error.amount |> should.be_none
}

pub fn set_description_records_empty_error_test() {
  let state =
    transaction_form.empty_modal()
    |> transaction_form.set_description("  ")
  state.form.error.description |> should.equal(Some(EmptyDescription))
}

pub fn set_description_records_too_long_error_test() {
  let state =
    transaction_form.empty_modal()
    |> transaction_form.set_description(string.repeat(
      "a",
      transaction_form.max_description_length + 1,
    ))
  state.form.error.description |> should.equal(Some(TooLong))
}

pub fn set_date_records_empty_error_test() {
  let state =
    transaction_form.empty_modal()
    |> transaction_form.set_date("")
  state.form.error.date |> should.equal(Some(EmptyDate))
}

pub fn set_date_records_not_a_date_error_test() {
  let state =
    transaction_form.empty_modal()
    |> transaction_form.set_date("not a date")
  state.form.error.date |> should.equal(Some(NotADate))
}

pub fn set_type_switches_to_credit_test() {
  let state =
    transaction_form.empty_modal()
    |> transaction_form.set_type_(Credit)
  transaction_form.validate(state) |> should.be_error
}

pub fn set_is_transfer_toggles_field_test() {
  let state =
    transaction_form.empty_modal()
    |> transaction_form.set_is_transfer(True)
  state.form.is_transfer |> should.be_true
}

pub fn validate_includes_is_transfer_test() {
  let state =
    transaction_form.empty_modal()
    |> transaction_form.set_amount("12.5")
    |> transaction_form.set_description("Coffee")
    |> transaction_form.set_date("2026-01-02")
    |> transaction_form.set_is_transfer(True)
  let request = transaction_form.validate(state) |> should.be_ok
  request.is_transfer |> should.be_true
}

pub fn validate_negates_debit_amounts_test() {
  let state =
    transaction_form.empty_modal()
    |> transaction_form.set_amount("12.5")
    |> transaction_form.set_description("Coffee")
    |> transaction_form.set_date("2026-01-02")
  let request = transaction_form.validate(state) |> should.be_ok
  request.amount |> should.equal(-12.5)
}

pub fn validate_keeps_credit_amounts_positive_test() {
  let state =
    transaction_form.empty_modal()
    |> transaction_form.set_type_(Credit)
    |> transaction_form.set_amount("12.5")
    |> transaction_form.set_description("Salary")
    |> transaction_form.set_date("2026-01-02")
  let request = transaction_form.validate(state) |> should.be_ok
  request.amount |> should.equal(12.5)
}

pub fn validate_returns_all_errors_test() {
  let state =
    transaction_form.empty_modal()
    |> transaction_form.set_amount("abc")
    |> transaction_form.set_date("")
  let error = transaction_form.validate(state) |> should.be_error
  error.amount |> should.equal(Some(NotANumber))
  error.description |> should.equal(Some(EmptyDescription))
  error.date |> should.equal(Some(EmptyDate))
}

pub fn edit_modal_prefills_transaction_test() {
  let assert Ok(id) = uuid.from_string("00000000-0000-0000-0000-000000000001")
  let transaction =
    transaction.Transaction(
      id: id,
      amount: -12.5,
      description: "Coffee",
      date: calendar.Date(2026, calendar.January, 2),
      is_transfer: False,
      account_id: None,
      category_id: None,
    )
  let state = transaction_form.edit_modal(transaction)
  let assert transaction_form.Edit(state_id) = state.mode
  state_id |> should.equal(id)
  state.submitting |> should.be_false
  state.form.amount |> should.equal("12.50")
  state.form.type_ |> should.equal(Debit)
  state.form.description |> should.equal("Coffee")
  state.form.date |> should.equal("2026-01-02")
}

pub fn edit_modal_maps_credit_transaction_test() {
  let assert Ok(id) = uuid.from_string("00000000-0000-0000-0000-000000000002")
  let transaction =
    transaction.Transaction(
      id: id,
      amount: 2500.0,
      description: "Salary",
      date: calendar.Date(2026, calendar.March, 15),
      is_transfer: False,
      account_id: None,
      category_id: None,
    )
  let state = transaction_form.edit_modal(transaction)
  let assert transaction_form.Edit(state_id) = state.mode
  state_id |> should.equal(id)
  state.form.amount |> should.equal("2500.00")
  state.form.type_ |> should.equal(Credit)
  state.form.description |> should.equal("Salary")
  state.form.date |> should.equal("2026-03-15")
}

pub fn from_transaction_maps_debit_sign_to_type_test() {
  let assert Ok(id) = uuid.from_string("00000000-0000-0000-0000-000000000003")
  let transaction =
    transaction.Transaction(
      id: id,
      amount: -42.5,
      description: "Groceries",
      date: calendar.Date(2026, calendar.January, 2),
      is_transfer: False,
      account_id: None,
      category_id: None,
    )
  let form = transaction_form.from_transaction(transaction)
  form.amount |> should.equal("42.50")
  form.type_ |> should.equal(Debit)
}

pub fn from_transaction_maps_credit_sign_to_type_test() {
  let assert Ok(id) = uuid.from_string("00000000-0000-0000-0000-000000000004")
  let transaction =
    transaction.Transaction(
      id: id,
      amount: 42.5,
      description: "Refund",
      date: calendar.Date(2026, calendar.January, 2),
      is_transfer: False,
      account_id: None,
      category_id: None,
    )
  let form = transaction_form.from_transaction(transaction)
  form.amount |> should.equal("42.50")
  form.type_ |> should.equal(Credit)
}
