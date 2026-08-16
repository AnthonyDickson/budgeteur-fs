import budgeteur/transactions/transaction
import budgeteur/transactions/transaction_form.{
  AmountRequired, Credit, DateRequired, Debit, DescriptionRequired, NotADate,
  NotANumber, NotPositive, TooLong,
}
import gleam/option.{None}
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

pub fn set_amount_clips_to_two_decimal_places_test() {
  let state =
    transaction_form.empty_modal()
    |> transaction_form.set_amount("12.345")
  let assert transaction_form.ValidAmount(value: amount, input: "12.34") =
    state.form.amount
  amount |> should.equal(12.34)
}

pub fn set_amount_records_not_a_number_error_test() {
  let state =
    transaction_form.empty_modal()
    |> transaction_form.set_amount("abc")
  let assert transaction_form.InvalidAmount(input: "abc", error: NotANumber) =
    state.form.amount
}

pub fn set_amount_records_not_positive_error_test() {
  let state =
    transaction_form.empty_modal()
    |> transaction_form.set_amount("-5")
  let assert transaction_form.InvalidAmount(input: "-5", error: NotPositive) =
    state.form.amount
}

pub fn set_amount_accepts_zero_test() {
  let state =
    transaction_form.empty_modal()
    |> transaction_form.set_amount("0")
  let assert transaction_form.ValidAmount(value: 0.0, ..) = state.form.amount
}

pub fn set_amount_blank_field_is_empty_state_test() {
  let state =
    transaction_form.empty_modal()
    |> transaction_form.set_amount("")
  let assert transaction_form.EmptyAmount("") = state.form.amount
}

pub fn set_description_blank_field_is_empty_state_test() {
  let state =
    transaction_form.empty_modal()
    |> transaction_form.set_description("  ")
  let assert transaction_form.EmptyDescription(_) = state.form.description
}

pub fn set_description_records_too_long_error_test() {
  let state =
    transaction_form.empty_modal()
    |> transaction_form.set_description(string.repeat(
      "a",
      transaction_form.max_description_length + 1,
    ))
  let assert transaction_form.InvalidDescription(error: TooLong, ..) =
    state.form.description
}

pub fn set_date_blank_field_is_empty_state_test() {
  let state =
    transaction_form.empty_modal()
    |> transaction_form.set_date("")
  let assert transaction_form.EmptyDate("") = state.form.date
}

pub fn set_date_records_not_a_date_error_test() {
  let state =
    transaction_form.empty_modal()
    |> transaction_form.set_date("not a date")
  let assert transaction_form.InvalidDate(input: "not a date", error: NotADate) =
    state.form.date
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
  let error_form = transaction_form.validate(state) |> should.be_error
  let assert transaction_form.InvalidAmount(error: NotANumber, ..) =
    error_form.amount
  let assert transaction_form.InvalidDescription(error: DescriptionRequired, ..) =
    error_form.description
  let assert transaction_form.InvalidDate(error: DateRequired, ..) =
    error_form.date
}

pub fn validate_reports_required_errors_for_blank_fields_test() {
  let state =
    transaction_form.empty_modal()
    |> transaction_form.set_date("2026-01-02")
  let error_form = transaction_form.validate(state) |> should.be_error
  let assert transaction_form.InvalidAmount(error: AmountRequired, ..) =
    error_form.amount
  let assert transaction_form.InvalidDescription(error: DescriptionRequired, ..) =
    error_form.description
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
  let assert transaction_form.ValidAmount(value: amount, input: "12.50") =
    state.form.amount
  amount |> should.equal(12.5)
  state.form.type_ |> should.equal(Debit)
  let assert transaction_form.ValidDescription(input: "Coffee") =
    state.form.description
  let assert transaction_form.ValidDate(value: date, ..) = state.form.date
  date |> should.equal(calendar.Date(2026, calendar.January, 2))
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
  state.submitting |> should.be_false
  let assert transaction_form.ValidAmount(value: amount, input: "2500.00") =
    state.form.amount
  amount |> should.equal(2500.0)
  state.form.type_ |> should.equal(Credit)
  let assert transaction_form.ValidDescription(input: "Salary") =
    state.form.description
  let assert transaction_form.ValidDate(value: date, ..) = state.form.date
  date |> should.equal(calendar.Date(2026, calendar.March, 15))
}
