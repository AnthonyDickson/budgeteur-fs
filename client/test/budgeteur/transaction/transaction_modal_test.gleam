import budgeteur/shared/api_error.{ApiError}
import budgeteur/shared/field
import budgeteur/shared/form_modal.{
  Active, CloseDialog, Create, Edit, Errored, Hidden, NoChange, Post, Put,
  Submitting,
}
import budgeteur/transaction_page/transaction
import budgeteur/transaction_page/transaction_modal.{
  AmountChanged, AmountRequired, CancelRequested, CreateRequested, Credit,
  DateChanged, DateRequired, Debit, DescriptionChanged, DescriptionRequired,
  DialogDismissed, EditRequested, IsTransferChanged, NotADate, NotANumber,
  NotPositive, SaveCompleted, SaveRequested, TooLong, TypeChanged,
}
import gleam/option.{None, Some}
import gleam/string
import gleam/time/calendar
import gleeunit/should
import youid/uuid

/// Open the create modal (the page sends `CreateRequested` to `update`).
fn opened() -> transaction_modal.Modal {
  let #(modal, _, _) =
    transaction_modal.update(transaction_modal.hidden(), CreateRequested)
  modal
}

/// Apply a form message, keeping only the resulting modal.
fn send(
  state: transaction_modal.Modal,
  msg: transaction_modal.Msg,
) -> transaction_modal.Modal {
  let #(modal, _, _) = transaction_modal.update(state, msg)
  modal
}

fn form_of(modal: transaction_modal.Modal) -> transaction_modal.Form {
  case modal {
    Active(form:, ..) -> form
    Errored(form:, ..) -> form
    _ -> panic as "expected an open form modal"
  }
}

pub fn clip_amount_allows_up_to_two_decimal_places_test() {
  transaction_modal.clip_amount_to_two_dp("12.3")
  |> should.equal("12.3")
}

pub fn clip_amount_truncates_extra_decimal_places_test() {
  transaction_modal.clip_amount_to_two_dp("12.345")
  |> should.equal("12.34")
}

pub fn clip_amount_preserves_trailing_decimal_point_test() {
  transaction_modal.clip_amount_to_two_dp("12.")
  |> should.equal("12.")
}

pub fn clip_amount_leaves_multiple_decimal_points_untouched_test() {
  transaction_modal.clip_amount_to_two_dp("12.34.56")
  |> should.equal("12.34.56")
}

pub fn clip_amount_leaves_whole_numbers_untouched_test() {
  transaction_modal.clip_amount_to_two_dp("123")
  |> should.equal("123")
}

pub fn set_amount_clips_to_two_decimal_places_test() {
  let form = opened() |> send(AmountChanged("12.345")) |> form_of
  let assert field.Valid(value: amount, input: "12.34") = form.amount
  amount |> should.equal(12.34)
}

pub fn set_amount_records_not_a_number_error_test() {
  let form = opened() |> send(AmountChanged("abc")) |> form_of
  let assert field.Invalid(input: "abc", error: NotANumber) = form.amount
}

pub fn set_amount_records_not_positive_error_test() {
  let form = opened() |> send(AmountChanged("-5")) |> form_of
  let assert field.Invalid(input: "-5", error: NotPositive) = form.amount
}

pub fn set_amount_accepts_zero_test() {
  let form = opened() |> send(AmountChanged("0")) |> form_of
  let assert field.Valid(value: 0.0, ..) = form.amount
}

pub fn set_amount_blank_field_is_empty_state_test() {
  let form = opened() |> send(AmountChanged("")) |> form_of
  let assert field.Empty("") = form.amount
}

pub fn set_amount_double_dot_is_not_a_number_error_test() {
  let form = opened() |> send(AmountChanged("12..")) |> form_of
  let assert field.Invalid(input: "12..", error: NotANumber) = form.amount
}

pub fn set_amount_digit_between_dots_is_not_a_number_error_test() {
  let form = opened() |> send(AmountChanged("1.2.3")) |> form_of
  let assert field.Invalid(input: "1.2.3", error: NotANumber) = form.amount
}

pub fn clip_amount_leaves_malformed_dot_input_untouched_test() {
  "12.." |> transaction_modal.clip_amount_to_two_dp() |> should.equal("12..")
  "1.2.3" |> transaction_modal.clip_amount_to_two_dp() |> should.equal("1.2.3")
  "12." |> transaction_modal.clip_amount_to_two_dp() |> should.equal("12.")
}

pub fn set_description_blank_field_is_empty_state_test() {
  let form = opened() |> send(DescriptionChanged("  ")) |> form_of
  let assert field.Empty(_) = form.description
}

pub fn set_description_records_too_long_error_test() {
  let form =
    opened()
    |> send(
      DescriptionChanged(string.repeat(
        "a",
        transaction_modal.max_description_length + 1,
      )),
    )
    |> form_of
  let assert field.Invalid(error: TooLong, ..) = form.description
}

pub fn set_date_blank_field_is_empty_state_test() {
  let form = opened() |> send(DateChanged("")) |> form_of
  let assert field.Empty("") = form.date
}

pub fn set_date_records_not_a_date_error_test() {
  let form = opened() |> send(DateChanged("not a date")) |> form_of
  let assert field.Invalid(input: "not a date", error: NotADate) = form.date
}

pub fn validate_includes_is_transfer_test() {
  let assert #(submitting, [Post(request)], NoChange) =
    transaction_modal.update(
      opened()
        |> send(AmountChanged("12.5"))
        |> send(DescriptionChanged("Coffee"))
        |> send(DateChanged("2026-01-02"))
        |> send(IsTransferChanged(True)),
      SaveRequested,
    )
  let assert Submitting(mode: Create, ..) = submitting
  request.is_transfer |> should.be_true
}

pub fn validate_negates_debit_amounts_test() {
  let assert #(_, [Post(request)], NoChange) =
    transaction_modal.update(
      opened()
        |> send(AmountChanged("12.5"))
        |> send(DescriptionChanged("Coffee"))
        |> send(DateChanged("2026-01-02")),
      SaveRequested,
    )
  request.amount |> should.equal(-12.5)
}

pub fn validate_keeps_credit_amounts_positive_test() {
  let assert #(_, [Post(request)], NoChange) =
    transaction_modal.update(
      opened()
        |> send(TypeChanged(Credit))
        |> send(AmountChanged("12.5"))
        |> send(DescriptionChanged("Salary"))
        |> send(DateChanged("2026-01-02")),
      SaveRequested,
    )
  request.amount |> should.equal(12.5)
}

pub fn validate_returns_all_errors_test() {
  let assert #(modal, requests, NoChange) =
    transaction_modal.update(
      opened() |> send(AmountChanged("abc")) |> send(DateChanged("")),
      SaveRequested,
    )
  requests |> should.equal([])
  let form = form_of(modal)
  let assert field.Invalid(error: NotANumber, ..) = form.amount
  let assert field.Invalid(error: DescriptionRequired, ..) = form.description
  let assert field.Invalid(error: DateRequired, ..) = form.date
}

pub fn validate_reports_required_errors_for_blank_fields_test() {
  let assert #(modal, requests, NoChange) =
    transaction_modal.update(
      opened() |> send(DateChanged("2026-01-02")),
      SaveRequested,
    )
  requests |> should.equal([])
  let form = form_of(modal)
  let assert field.Invalid(error: AmountRequired, ..) = form.amount
  let assert field.Invalid(error: DescriptionRequired, ..) = form.description
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
      tag_id: None,
    )
  let #(modal, _, _) =
    transaction_modal.update(
      transaction_modal.hidden(),
      EditRequested(transaction),
    )
  let assert Active(form:, mode: Edit(edit_id)) = modal
  edit_id |> should.equal(id)
  let assert field.Valid(value: amount, input: "12.50") = form.amount
  amount |> should.equal(12.5)
  form.type_ |> should.equal(Debit)
  let assert field.Valid(value: "Coffee", input: "Coffee") = form.description
  let assert field.Valid(value: date, ..) = form.date
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
      tag_id: None,
    )
  let #(modal, _, _) =
    transaction_modal.update(
      transaction_modal.hidden(),
      EditRequested(transaction),
    )
  let assert Active(form:, mode: Edit(edit_id)) = modal
  edit_id |> should.equal(id)
  let assert field.Valid(value: amount, input: "2500.00") = form.amount
  amount |> should.equal(2500.0)
  form.type_ |> should.equal(Credit)
  let assert field.Valid(value: "Salary", input: "Salary") = form.description
  let assert field.Valid(value: date, ..) = form.date
  date |> should.equal(calendar.Date(2026, calendar.March, 15))
}

pub fn editing_negates_debit_amounts_in_the_update_request_test() {
  let assert Ok(id) = uuid.from_string("00000000-0000-0000-0000-000000000001")
  let transaction =
    transaction.Transaction(
      id: id,
      amount: -12.5,
      description: "Coffee",
      date: calendar.Date(2026, calendar.January, 2),
      is_transfer: False,
      account_id: None,
      tag_id: None,
    )
  let assert #(_, [Put(put_id, request)], NoChange) =
    transaction_modal.update(
      send(opened(), EditRequested(transaction))
        |> send(AmountChanged("20")),
      SaveRequested,
    )
  put_id |> should.equal(id)
  request.amount |> should.equal(-20.0)
}

pub fn save_failure_moves_the_modal_to_errored_test() {
  let submitting =
    send(
      send(
        send(send(opened(), AmountChanged("5")), DescriptionChanged("Snack")),
        DateChanged("2026-01-03"),
      ),
      SaveRequested,
    )
  let assert Submitting(..) = submitting

  let error =
    ApiError(
      error: "Conflict",
      details: "boom",
      status_code: Some(409),
      request_id: None,
    )
  let assert #(modal, requests, NoChange) =
    transaction_modal.update(submitting, SaveCompleted(Error(error)))
  requests |> should.equal([])
  let assert Errored(mode: Create, error: message, ..) = modal
  message |> should.equal("boom")
}

pub fn cancel_requests_dialog_close_but_dismiss_does_not_test() {
  let assert #(modal, requests, NoChange) =
    transaction_modal.update(opened(), CancelRequested)
  modal |> should.equal(Hidden)
  requests |> should.equal([CloseDialog])

  let assert #(modal, requests, NoChange) =
    transaction_modal.update(opened(), DialogDismissed)
  modal |> should.equal(Hidden)
  requests |> should.equal([])
}

pub fn double_submit_while_submitting_is_a_no_op_test() {
  let submitting =
    send(
      send(
        send(send(opened(), AmountChanged("5")), DescriptionChanged("Snack")),
        DateChanged("2026-01-03"),
      ),
      SaveRequested,
    )
  let assert Submitting(..) = submitting

  // A second SaveRequested while the first is in flight emits nothing.
  let #(still, requests, outcome) =
    transaction_modal.update(submitting, SaveRequested)
  still |> should.equal(submitting)
  requests |> should.equal([])
  outcome |> should.equal(NoChange)
}
