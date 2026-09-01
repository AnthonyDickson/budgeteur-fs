import budgeteur/shared/api_error.{ApiError}
import budgeteur/shared/effect
import budgeteur/shared/http_effect
import budgeteur/shared/out_msg
import budgeteur/shared/toast
import budgeteur/transaction/transaction
import budgeteur/transaction/transaction_delete_modal.{
  Confirming, Deleting, Hidden,
}
import budgeteur/transaction/transaction_form
import budgeteur/transaction/transaction_page
import budgeteur/transaction/transaction_page_data
import gleam/json
import gleam/option.{None, Some}
import gleam/string
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
    is_transfer: False,
    account_id: None,
    tag_id: None,
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
    transaction_page.Model(
      transactions: [transaction],
      modal: transaction_form.empty_modal(),
      delete_modal: transaction_delete_modal.empty(),
    )

  let #(new_model, _, _) =
    transaction_page.update(
      model,
      transaction_page.UserRequestedEditForm(transaction.id),
    )

  let assert transaction_form.Edit(edit_id) = new_model.modal.mode
  edit_id |> should.equal(transaction.id)
  let assert transaction_form.ValidAmount(value: amount, input: "12.50") =
    new_model.modal.form.amount
  amount |> should.equal(12.5)
  new_model.modal.form.type_ |> should.equal(transaction_form.Debit)
  let assert transaction_form.ValidDescription(input: "Coffee") =
    new_model.modal.form.description
  let assert transaction_form.ValidDate(value: date, ..) =
    new_model.modal.form.date
  date |> should.equal(calendar.Date(2026, calendar.January, 2))
}

pub fn user_requested_edit_form_unknown_id_is_noop_test() {
  let assert Ok(missing_id) =
    uuid.from_string("00000000-0000-0000-0000-000000000099")
  let model =
    transaction_page.Model(
      transactions: [sample_transaction()],
      modal: transaction_form.empty_modal(),
      delete_modal: transaction_delete_modal.empty(),
    )

  let #(new_model, _, _) =
    transaction_page.update(
      model,
      transaction_page.UserRequestedEditForm(missing_id),
    )

  new_model.modal.mode |> should.equal(transaction_form.Create)
}

pub fn submitting_edit_issues_put_request_test() {
  let transaction = sample_transaction()
  let model =
    transaction_page.Model(
      transactions: [transaction],
      modal: transaction_form.edit_modal(transaction),
      delete_modal: transaction_delete_modal.empty(),
    )

  let #(new_model, effect, _) =
    transaction_page.update(model, transaction_page.UserSubmittedForm)

  let assert effect.HttpRequest(method: method, url: url, ..) = effect
  method |> should.equal(http_effect.Put)
  url
  |> should.equal("/api/transactions/" <> uuid.to_string(transaction.id))
  new_model.modal.submitting |> should.be_true
}

pub fn submitting_create_issues_post_request_test() {
  let model =
    transaction_page.Model(
      transactions: [],
      modal: valid_create_modal(),
      delete_modal: transaction_delete_modal.empty(),
    )

  let #(new_model, effect, _) =
    transaction_page.update(model, transaction_page.UserSubmittedForm)

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
    transaction_page.Model(
      transactions: [transaction],
      modal: transaction_form.empty_modal(),
      delete_modal: transaction_delete_modal.empty(),
    )

  let #(new_model, _, _) =
    transaction_page.update(
      model,
      transaction_page.ServerUpdatedTransaction(Ok(updated)),
    )

  new_model.transactions |> should.equal([updated])
  new_model.modal.mode |> should.equal(transaction_form.Create)
  new_model.modal.submitting |> should.be_false
}

pub fn server_updated_transaction_error_keeps_modal_open_test() {
  let transaction = sample_transaction()
  let model =
    transaction_page.Model(
      transactions: [transaction],
      modal: transaction_form.edit_modal(transaction)
        |> transaction_form.set_amount("20"),
      delete_modal: transaction_delete_modal.empty(),
    )

  let #(new_model, _, _) =
    transaction_page.update(
      model,
      transaction_page.ServerUpdatedTransaction(
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

pub fn user_requested_delete_form_sets_target_and_opens_test() {
  let transaction = sample_transaction()
  let model =
    transaction_page.Model(
      transactions: [transaction],
      modal: transaction_form.empty_modal(),
      delete_modal: transaction_delete_modal.empty(),
    )

  let #(new_model, effect, _) =
    transaction_page.update(
      model,
      transaction_page.UserRequestedDeleteForm(transaction),
    )

  let assert Confirming(target) = new_model.delete_modal
  target |> should.equal(transaction)
  let assert effect.ShowDialog(selector: selector) = effect
  selector |> should.equal(transaction_delete_modal.dom_id_selector)
}

pub fn confirming_delete_issues_delete_request_test() {
  let transaction = sample_transaction()
  let model =
    transaction_page.Model(
      transactions: [transaction],
      modal: transaction_form.empty_modal(),
      delete_modal: transaction_delete_modal.open(transaction),
    )

  let #(new_model, effect, _) =
    transaction_page.update(model, transaction_page.UserConfirmedDelete)

  let assert effect.HttpRequest(method: method, url: url, ..) = effect
  method |> should.equal(http_effect.Delete)
  url
  |> should.equal("/api/transactions/" <> uuid.to_string(transaction.id))
  let assert Deleting(_) = new_model.delete_modal
}

pub fn server_deleted_transaction_removes_row_test() {
  let transaction = sample_transaction()
  let model =
    transaction_page.Model(
      transactions: [transaction],
      modal: transaction_form.empty_modal(),
      delete_modal: transaction_delete_modal.Deleting(transaction),
    )

  let #(new_model, _, _) =
    transaction_page.update(
      model,
      transaction_page.ServerDeletedTransaction(transaction, Ok(Nil)),
    )

  new_model.transactions |> should.equal([])
  let assert Hidden = new_model.delete_modal
}

pub fn server_deleted_transaction_removes_row_even_if_modal_closed_test() {
  let transaction = sample_transaction()
  let model =
    transaction_page.Model(
      transactions: [transaction],
      modal: transaction_form.empty_modal(),
      delete_modal: transaction_delete_modal.empty(),
    )

  let #(new_model, _, _) =
    transaction_page.update(
      model,
      transaction_page.ServerDeletedTransaction(transaction, Ok(Nil)),
    )

  new_model.transactions |> should.equal([])
}

pub fn server_delete_error_returns_to_confirming_test() {
  let transaction = sample_transaction()
  let model =
    transaction_page.Model(
      transactions: [transaction],
      modal: transaction_form.empty_modal(),
      delete_modal: transaction_delete_modal.Deleting(transaction),
    )

  let #(new_model, _, out_msg) =
    transaction_page.update(
      model,
      transaction_page.ServerDeletedTransaction(
        transaction,
        Error(ApiError(
          error: "boom",
          details: "boom",
          status_code: None,
          request_id: None,
        )),
      ),
    )

  let assert Confirming(target) = new_model.delete_modal
  target |> should.equal(transaction)
  new_model.transactions |> should.equal([transaction])
  let assert Some(out_msg.PageRequestedToast(level: level, ..)) = out_msg
  level |> should.equal(toast.Error)
}

pub fn user_cancelled_delete_modal_closes_test() {
  let transaction = sample_transaction()
  let model =
    transaction_page.Model(
      transactions: [transaction],
      modal: transaction_form.empty_modal(),
      delete_modal: transaction_delete_modal.open(transaction),
    )

  let #(new_model, effect, _) =
    transaction_page.update(model, transaction_page.UserCancelledDeleteModal)

  let assert Hidden = new_model.delete_modal
  let assert effect.CloseDialog(selector: selector) = effect
  selector |> should.equal(transaction_delete_modal.dom_id_selector)
}

// ── Local backup ─────────────────────────────────────────────────────────────

pub fn init_restores_from_store_test() {
  let #(_, effect) = transaction_page.init()

  let assert effect.Batch([
    effect.LoadFromStore(key: key, ..),
    effect.HttpRequest(..),
  ]) = effect
  key |> should.equal("budgeteur.transactions")
}

pub fn stored_transactions_round_trip_test() {
  let transaction = sample_transaction()

  let stored = transaction_page_data.data_to_string([transaction])
  let assert Ok(restored) =
    json.parse(stored, using: transaction_page_data.data_decoder())
  restored |> should.equal([transaction])
}

pub fn client_restored_transactions_sets_list_test() {
  let transaction = sample_transaction()
  let model = empty_model()

  let #(new_model, effect, out_msg) =
    transaction_page.update(
      model,
      transaction_page.ClientRestoredTransactions(Some([transaction])),
    )

  new_model.transactions |> should.equal([transaction])
  out_msg |> should.equal(None)
  // Restored data came from the store, so it is not written straight back.
  effect |> should.equal(effect.none())
}

pub fn client_restored_transactions_none_is_noop_test() {
  let transaction = sample_transaction()
  let model = empty_model() |> with_transaction(transaction)

  let #(new_model, effect, out_msg) =
    transaction_page.update(
      model,
      transaction_page.ClientRestoredTransactions(None),
    )

  new_model |> should.equal(model)
  effect |> should.equal(effect.none())
  out_msg |> should.equal(None)
}

pub fn server_created_transaction_persists_to_store_test() {
  let transaction = sample_transaction()
  let model = empty_model()

  let #(new_model, effect, _) =
    transaction_page.update(
      model,
      transaction_page.ServerCreatedTransaction(Ok(transaction)),
    )

  new_model.transactions |> should.equal([transaction])
  let assert effect.Batch([
    effect.CloseDialog(..),
    effect.SaveToStore(key:, value:),
  ]) = effect
  key |> should.equal("budgeteur.transactions")
  value |> string.starts_with("{\"transactions\":[") |> should.be_true
}

pub fn server_updated_transaction_persists_to_store_test() {
  let transaction = sample_transaction()
  let updated =
    transaction.Transaction(..transaction, description: "Flat White")
  let model = empty_model() |> with_transaction(transaction)

  let #(new_model, effect, _) =
    transaction_page.update(
      model,
      transaction_page.ServerUpdatedTransaction(Ok(updated)),
    )

  new_model.transactions |> should.equal([updated])
  let assert effect.Batch([
    effect.CloseDialog(..),
    effect.SaveToStore(key:, value:),
  ]) = effect
  key |> should.equal("budgeteur.transactions")
  value |> string.starts_with("{\"transactions\":[") |> should.be_true
}

pub fn server_deleted_transaction_persists_to_store_test() {
  let transaction = sample_transaction()
  let model = empty_model() |> with_transaction(transaction)

  let #(new_model, effect, _) =
    transaction_page.update(
      model,
      transaction_page.ServerDeletedTransaction(transaction, Ok(Nil)),
    )

  new_model.transactions |> should.equal([])
  let assert effect.Batch([
    effect.CloseDialog(..),
    effect.SaveToStore(key:, value:),
  ]) = effect
  key |> should.equal("budgeteur.transactions")
  value |> should.equal("{\"transactions\":[]}")
}

pub fn server_fetched_transactions_persists_to_store_test() {
  let transaction = sample_transaction()
  let model = empty_model()

  let #(new_model, effect, _) =
    transaction_page.update(
      model,
      transaction_page.ClientFetchedTransactions(Ok([transaction])),
    )

  new_model.transactions |> should.equal([transaction])
  let assert effect.Batch([effect.None, effect.SaveToStore(key:, value:)]) =
    effect
  key |> should.equal("budgeteur.transactions")
  value |> string.starts_with("{\"transactions\":[") |> should.be_true
}

pub fn non_mutating_message_does_not_persist_test() {
  let transaction = sample_transaction()
  let model = empty_model() |> with_transaction(transaction)

  let #(new_model, effect, _) =
    transaction_page.update(model, transaction_page.UserUpdatedFormAmount("5"))

  new_model.transactions |> should.equal([transaction])
  effect |> should.equal(effect.none())
}

fn empty_model() -> transaction_page.Model {
  transaction_page.Model(
    transactions: [],
    modal: transaction_form.empty_modal(),
    delete_modal: transaction_delete_modal.empty(),
  )
}

fn with_transaction(
  model: transaction_page.Model,
  transaction: transaction.Transaction,
) -> transaction_page.Model {
  transaction_page.Model(..model, transactions: [transaction])
}
