import budgeteur/api_error.{ApiError}
import budgeteur/effect
import budgeteur/http_effect
import budgeteur/transactions/transaction
import budgeteur/transactions/transaction_form
import budgeteur/transactions/transactions_page
import gleam/option.{None}
import gleam/time/calendar
import gleeunit/should
import youid/uuid

fn sample_transaction() -> transaction.Transaction {
  let assert Ok(id) = uuid.from_string("00000000-0000-0000-0000-000000000001")
  transaction.Transaction(
    id: id,
    amount: -12.5,
    description: "Coffee",
    date: calendar.Date(2026, calendar.January, 2),
    account_id: None,
    category_id: None,
  )
}

fn valid_create_modal() -> transaction_form.ModalState {
  transaction_form.empty_modal()
  |> transaction_form.set_amount("5")
  |> transaction_form.set_description("Snack")
  |> transaction_form.set_date("2026-01-03")
}

pub fn user_requested_edit_form_prefills_modal_test() {
  let transaction = sample_transaction()
  let model =
    transactions_page.Model(
      transactions: [transaction],
      modal: transaction_form.empty_modal(),
    )

  let #(new_model, _, _) =
    transactions_page.update(
      model,
      transactions_page.UserRequestedEditForm(transaction.id),
    )

  let assert transaction_form.Edit(edit_id) = new_model.modal.mode
  edit_id |> should.equal(transaction.id)
  new_model.modal.form.amount |> should.equal("12.50")
  new_model.modal.form.type_ |> should.equal(transaction_form.Debit)
  new_model.modal.form.description |> should.equal("Coffee")
  new_model.modal.form.date |> should.equal("2026-01-02")
}

pub fn user_requested_edit_form_unknown_id_is_noop_test() {
  let assert Ok(missing_id) =
    uuid.from_string("00000000-0000-0000-0000-000000000099")
  let model =
    transactions_page.Model(
      transactions: [sample_transaction()],
      modal: transaction_form.empty_modal(),
    )

  let #(new_model, _, _) =
    transactions_page.update(
      model,
      transactions_page.UserRequestedEditForm(missing_id),
    )

  new_model.modal.mode |> should.equal(transaction_form.Create)
}

pub fn submitting_edit_issues_put_request_test() {
  let transaction = sample_transaction()
  let model =
    transactions_page.Model(
      transactions: [transaction],
      modal: transaction_form.edit_modal(transaction),
    )

  let #(new_model, effect, _) =
    transactions_page.update(model, transactions_page.UserSubmittedForm)

  let assert effect.HttpRequest(method: method, url: url, ..) = effect
  method |> should.equal(http_effect.Put)
  url
  |> should.equal("/api/transactions/" <> uuid.to_string(transaction.id))
  new_model.modal.submitting |> should.be_true
}

pub fn submitting_create_issues_post_request_test() {
  let model =
    transactions_page.Model(transactions: [], modal: valid_create_modal())

  let #(new_model, effect, _) =
    transactions_page.update(model, transactions_page.UserSubmittedForm)

  let assert effect.HttpRequest(method: method, url: url, ..) = effect
  method |> should.equal(http_effect.Post)
  url |> should.equal("/api/transactions")
  new_model.modal.submitting |> should.be_true
}

pub fn server_updated_transaction_replaces_row_in_place_test() {
  let transaction = sample_transaction()
  let updated =
    transaction.Transaction(
      ..transaction,
      amount: -15.0,
      description: "Flat White",
    )
  let model =
    transactions_page.Model(
      transactions: [transaction],
      modal: transaction_form.empty_modal(),
    )

  let #(new_model, _, _) =
    transactions_page.update(
      model,
      transactions_page.ServerUpdatedTransaction(Ok(updated)),
    )

  new_model.transactions |> should.equal([updated])
  new_model.modal.mode |> should.equal(transaction_form.Create)
  new_model.modal.submitting |> should.be_false
}

pub fn server_updated_transaction_error_keeps_modal_open_test() {
  let transaction = sample_transaction()
  let model =
    transactions_page.Model(
      transactions: [transaction],
      modal: transaction_form.edit_modal(transaction)
        |> transaction_form.set_amount("20"),
    )

  let #(new_model, _, _) =
    transactions_page.update(
      model,
      transactions_page.ServerUpdatedTransaction(
        Error(ApiError(
          error: "boom",
          details: "boom",
          status_code: None,
          request_id: None,
        )),
      ),
    )

  new_model.modal.submitting |> should.be_false
  let assert transaction_form.Edit(_) = new_model.modal.mode
}
