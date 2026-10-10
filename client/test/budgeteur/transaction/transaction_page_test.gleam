import budgeteur/shared/api_error.{ApiError}
import budgeteur/shared/delete_modal
import budgeteur/shared/effect
import budgeteur/shared/field
import budgeteur/shared/form_modal
import budgeteur/shared/http_effect
import budgeteur/shared/out_msg
import budgeteur/shared/remote
import budgeteur/shared/toast
import budgeteur/transaction_page/transaction
import budgeteur/transaction_page/transaction_delete_modal
import budgeteur/transaction_page/transaction_modal
import budgeteur/transaction_page/transaction_page
import gleam/option.{None, Some}
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

/// Apply a page message, keeping only the resulting model.
fn run(
  model: transaction_page.Model,
  msg: transaction_page.Msg,
) -> transaction_page.Model {
  let #(model, _, _) = transaction_page.update(model, msg)
  model
}

/// Fill the open create form via page messages.
fn fill_create_form(model: transaction_page.Model) -> transaction_page.Model {
  model
  |> run(
    transaction_page.TransactionModalMsg(transaction_modal.AmountChanged("5")),
  )
  |> run(
    transaction_page.TransactionModalMsg(transaction_modal.DescriptionChanged(
      "Snack",
    )),
  )
  |> run(
    transaction_page.TransactionModalMsg(transaction_modal.DateChanged(
      "2026-01-03",
    )),
  )
}

/// Open the create modal and fill it (fresh open).
fn open_create_form(model: transaction_page.Model) -> transaction_page.Model {
  model
  |> run(transaction_page.UserRequestedCreationForm)
  |> fill_create_form
}

/// Submit the open create form, leaving the modal `Submitting`.
fn submit_create_form(model: transaction_page.Model) -> transaction_page.Model {
  run(
    model,
    transaction_page.TransactionModalMsg(transaction_modal.SaveRequested),
  )
}

/// Open, fill, and submit the create form.
fn submitting_create_form(
  model: transaction_page.Model,
) -> transaction_page.Model {
  model |> open_create_form |> submit_create_form
}

/// Submit the open edit form.
fn submit_edit_form(
  model: transaction_page.Model,
  id: uuid.Uuid,
) -> transaction_page.Model {
  model
  |> run(transaction_page.UserRequestedEditForm(id))
  |> run(transaction_page.TransactionModalMsg(transaction_modal.SaveRequested))
}

pub fn user_requested_edit_form_prefills_modal_test() {
  let transaction = sample_transaction()
  let model = empty_model() |> with_transaction(transaction)

  let new_model =
    run(model, transaction_page.UserRequestedEditForm(transaction.id))

  let assert form_modal.Active(form:, mode: form_modal.Edit(edit_id)) =
    new_model.modal
  edit_id |> should.equal(transaction.id)
  let assert field.Valid(value: amount, input: "12.50") = form.amount
  amount |> should.equal(12.5)
  form.type_ |> should.equal(transaction_modal.Debit)
  let assert field.Valid(value: "Coffee", input: "Coffee") = form.description
  let assert field.Valid(value: date, ..) = form.date
  date |> should.equal(calendar.Date(2026, calendar.January, 2))
}

pub fn user_requested_edit_form_unknown_id_is_noop_test() {
  let assert Ok(missing_id) =
    uuid.from_string("00000000-0000-0000-0000-000000000099")
  let model = empty_model() |> with_transaction(sample_transaction())

  let #(new_model, noop_effect, _) =
    transaction_page.update(
      model,
      transaction_page.UserRequestedEditForm(missing_id),
    )

  new_model |> should.equal(model)
  noop_effect |> should.equal(effect.none())
}

pub fn opening_the_create_form_starts_fresh_test() {
  // D2: opening always builds an empty form; no values are retained.
  let #(new_model, effect, _) =
    transaction_page.update(
      empty_model(),
      transaction_page.UserRequestedCreationForm,
    )

  let assert form_modal.Active(form:, mode: form_modal.Create) = new_model.modal
  let assert field.Empty("") = form.amount
  let assert field.Empty("") = form.description
  let assert field.Empty("") = form.date
  effect |> should.equal(effect.none())
}

pub fn submitting_edit_issues_put_request_test() {
  let transaction = sample_transaction()
  let model = empty_model() |> with_transaction(transaction)

  let #(new_model, effect, _) =
    transaction_page.update(
      run(model, transaction_page.UserRequestedEditForm(transaction.id)),
      transaction_page.TransactionModalMsg(transaction_modal.SaveRequested),
    )

  let assert effect.HttpRequest(method: method, url: url, timeout: timeout, ..) =
    effect
  method |> should.equal(http_effect.Put)
  url
  |> should.equal("/api/transactions/" <> uuid.to_string(transaction.id))
  timeout |> should.equal(Some(form_modal.submit_timeout_ms))
  let assert form_modal.Submitting(mode: form_modal.Edit(..), ..) =
    new_model.modal
}

pub fn submitting_create_issues_post_request_test() {
  let #(new_model, effect, _) =
    transaction_page.update(
      empty_model() |> open_create_form,
      transaction_page.TransactionModalMsg(transaction_modal.SaveRequested),
    )

  let assert effect.HttpRequest(method: method, url: url, timeout: timeout, ..) =
    effect
  method |> should.equal(http_effect.Post)
  url |> should.equal("/api/transactions")
  timeout |> should.equal(Some(form_modal.submit_timeout_ms))
  let assert form_modal.Submitting(mode: form_modal.Create, ..) =
    new_model.modal
}

pub fn double_submit_while_submitting_arms_a_single_request_test() {
  let submitting = empty_model() |> submitting_create_form

  // A second submit while the request is in flight is a no-op: the reducer
  // ignores SaveRequested while Submitting, so no second request goes out.
  let #(still, second_effect, _) =
    transaction_page.update(
      submitting,
      transaction_page.TransactionModalMsg(transaction_modal.SaveRequested),
    )
  still.modal |> should.equal(submitting.modal)
  second_effect |> should.equal(effect.none())
}

pub fn server_created_transaction_closes_modal_and_updates_list_test() {
  let transaction = sample_transaction()
  let submitting = empty_model() |> submitting_create_form

  let #(new_model, effect, out_msg) =
    transaction_page.update(
      submitting,
      transaction_page.TransactionModalMsg(
        transaction_modal.SaveCompleted(Ok(transaction)),
      ),
    )

  new_model.transactions |> should.equal(remote.Loaded([transaction]))
  new_model.modal |> should.equal(transaction_modal.hidden())
  let assert Some(out_msg.PageRequestedToast(level: toast.Success, ..)) =
    out_msg
  effect |> should.equal(effect.none())
}

pub fn server_updated_transaction_replaces_row_in_place_test() {
  let transaction = sample_transaction()
  let updated =
    transaction.Transaction(
      ..transaction,
      amount: -15.0,
      description: "Flat White",
    )
  let submitting =
    empty_model()
    |> with_transaction(transaction)
    |> submit_edit_form(transaction.id)

  let #(new_model, _, _) =
    transaction_page.update(
      submitting,
      transaction_page.TransactionModalMsg(
        transaction_modal.SaveCompleted(Ok(updated)),
      ),
    )

  new_model.transactions |> should.equal(remote.Loaded([updated]))
  new_model.modal |> should.equal(transaction_modal.hidden())
}

pub fn server_save_error_shows_inline_error_and_keeps_the_modal_open_test() {
  let transaction = sample_transaction()
  let submitting =
    empty_model()
    |> with_transaction(transaction)
    |> submit_edit_form(transaction.id)

  let #(new_model, effect, out_msg) =
    transaction_page.update(
      submitting,
      transaction_page.TransactionModalMsg(
        transaction_modal.SaveCompleted(
          Error(ApiError(
            error: "boom",
            details: "boom",
            status_code: None,
            request_id: None,
          )),
        ),
      ),
    )

  // D1: the dialog stays open in the Errored state with an inline banner; no
  // failure toast behind the backdrop.
  let assert form_modal.Errored(mode: form_modal.Edit(..), error: details, ..) =
    new_model.modal
  details |> should.equal("boom")
  new_model.transactions |> should.equal(remote.Loaded([transaction]))
  out_msg |> should.equal(None)
  let assert effect.LogError(_) = effect
}

pub fn cancelling_the_form_after_a_failed_save_keeps_the_list_test() {
  let transaction = sample_transaction()
  let failed =
    empty_model()
    |> with_transaction(transaction)
    |> submit_edit_form(transaction.id)
    |> run(
      transaction_page.TransactionModalMsg(
        transaction_modal.SaveCompleted(
          Error(ApiError(
            error: "boom",
            details: "boom",
            status_code: None,
            request_id: None,
          )),
        ),
      ),
    )

  let #(closed, effect, _) =
    transaction_page.update(
      failed,
      transaction_page.TransactionModalMsg(transaction_modal.CancelRequested),
    )

  closed.modal |> should.equal(transaction_modal.hidden())
  closed.transactions |> should.equal(remote.Loaded([transaction]))
  effect |> should.equal(effect.none())
}

pub fn user_requested_delete_form_sets_target_and_opens_test() {
  let transaction = sample_transaction()
  let model = empty_model() |> with_transaction(transaction)

  let #(new_model, effect, _) =
    transaction_page.update(
      model,
      transaction_page.UserRequestedDeleteForm(transaction),
    )

  let assert delete_modal.Confirming(target:, ..) = new_model.delete_modal
  target |> should.equal(transaction)
  effect |> should.equal(effect.none())
}

pub fn confirming_delete_issues_delete_request_test() {
  let transaction = sample_transaction()
  let model =
    transaction_page.Model(
      ..empty_model(),
      transactions: remote.Loaded([transaction]),
      delete_modal: transaction_delete_modal.open(transaction),
    )

  let #(new_model, effect, _) =
    transaction_page.update(model, transaction_page.UserConfirmedDelete)

  let assert effect.HttpRequest(method: method, url: url, timeout: timeout, ..) =
    effect
  method |> should.equal(http_effect.Delete)
  url
  |> should.equal("/api/transactions/" <> uuid.to_string(transaction.id))
  timeout |> should.equal(Some(delete_modal.delete_timeout_ms))
  let assert delete_modal.Deleting(..) = new_model.delete_modal
}

pub fn server_deleted_transaction_removes_row_test() {
  let transaction = sample_transaction()
  let model =
    transaction_page.Model(
      ..empty_model(),
      transactions: remote.Loaded([transaction]),
      delete_modal: delete_modal.Deleting(target: transaction, context: Nil),
    )

  let #(new_model, _, _) =
    transaction_page.update(
      model,
      transaction_page.ServerDeletedTransaction(transaction, Ok(Nil)),
    )

  new_model.transactions |> should.equal(remote.Loaded([]))
  let assert delete_modal.Hidden = new_model.delete_modal
}

pub fn server_deleted_transaction_removes_row_even_if_modal_closed_test() {
  let transaction = sample_transaction()
  let model = empty_model() |> with_transaction(transaction)

  let #(new_model, _, _) =
    transaction_page.update(
      model,
      transaction_page.ServerDeletedTransaction(transaction, Ok(Nil)),
    )

  new_model.transactions |> should.equal(remote.Loaded([]))
}

pub fn server_delete_error_shows_inline_error_test() {
  let transaction = sample_transaction()
  let model =
    transaction_page.Model(
      ..empty_model(),
      transactions: remote.Loaded([transaction]),
      delete_modal: delete_modal.Deleting(target: transaction, context: Nil),
    )

  let #(new_model, effect, out_msg) =
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

  let assert delete_modal.Errored(error: details, ..) = new_model.delete_modal
  details |> should.equal("boom")
  new_model.transactions |> should.equal(remote.Loaded([transaction]))
  out_msg |> should.equal(None)
  let assert effect.LogError(_) = effect
}

pub fn server_delete_error_404_is_treated_as_success_test() {
  let transaction = sample_transaction()
  let model =
    transaction_page.Model(
      ..empty_model(),
      transactions: remote.Loaded([transaction]),
      delete_modal: delete_modal.Deleting(target: transaction, context: Nil),
    )

  let #(new_model, _, out_msg) =
    transaction_page.update(
      model,
      transaction_page.ServerDeletedTransaction(
        transaction,
        Error(ApiError(
          error: "Not Found",
          details: "No such transaction",
          status_code: Some(404),
          request_id: None,
        )),
      ),
    )

  new_model.transactions |> should.equal(remote.Loaded([]))
  let assert delete_modal.Hidden = new_model.delete_modal
  let assert Some(out_msg.PageRequestedToast(level: toast.Success, ..)) =
    out_msg
}

pub fn user_cancelled_delete_modal_closes_test() {
  let transaction = sample_transaction()
  let model =
    transaction_page.Model(
      ..empty_model(),
      transactions: remote.Loaded([transaction]),
      delete_modal: transaction_delete_modal.open(transaction),
    )

  let #(new_model, effect, _) =
    transaction_page.update(model, transaction_page.UserCancelledDeleteModal)

  let assert delete_modal.Hidden = new_model.delete_modal
  effect |> should.equal(effect.none())
}

// ── Loading ──────────────────────────────────────────────────────────────────

fn server_error() -> api_error.ApiError {
  ApiError(
    error: "boom",
    details: "boom",
    status_code: Some(500),
    request_id: None,
  )
}

pub fn init_fetches_transactions_and_tags_test() {
  let #(model, effect) = transaction_page.init()

  model.transactions |> should.equal(remote.Loading)
  let assert effect.Batch([
    effect.HttpRequest(url: transactions_url, ..),
    effect.HttpRequest(url: tags_url, ..),
  ]) = effect
  transactions_url |> should.equal("/api/transactions")
  tags_url |> should.equal("/api/tags")
}

pub fn fetched_transactions_are_loaded_newest_first_test() {
  let older = sample_transaction()
  let assert Ok(newer_id) =
    uuid.from_string("00000000-0000-0000-0000-000000000002")
  let newer =
    transaction.Transaction(
      ..older,
      id: newer_id,
      date: calendar.Date(2026, calendar.February, 1),
    )
  let #(model, _) = transaction_page.init()

  let #(new_model, effect, out_msg) =
    transaction_page.update(
      model,
      transaction_page.ClientFetchedTransactions(Ok([older, newer])),
    )

  new_model.transactions |> should.equal(remote.Loaded([newer, older]))
  effect |> should.equal(effect.none())
  out_msg |> should.equal(None)
}

pub fn a_failed_first_load_offers_a_retry_test() {
  let #(model, _) = transaction_page.init()

  let #(failed, effect, out_msg) =
    transaction_page.update(
      model,
      transaction_page.ClientFetchedTransactions(Error(server_error())),
    )

  failed.transactions |> should.equal(remote.Failed)
  let assert effect.LogError(_) = effect
  out_msg |> should.equal(None)

  let #(retrying, effect, _) =
    transaction_page.update(failed, transaction_page.UserRequestedReload)

  retrying.transactions |> should.equal(remote.Loading)
  let assert effect.Batch([
    effect.HttpRequest(url: "/api/transactions", ..),
    effect.HttpRequest(url: "/api/tags", ..),
  ]) = effect
}

pub fn a_failed_refetch_keeps_the_loaded_list_test() {
  let transaction = sample_transaction()
  let model = empty_model() |> with_transaction(transaction)

  let #(new_model, effect, out_msg) =
    transaction_page.update(
      model,
      transaction_page.ClientFetchedTransactions(Error(server_error())),
    )

  new_model.transactions |> should.equal(remote.Loaded([transaction]))
  let assert effect.LogError(_) = effect
  let assert Some(out_msg.PageRequestedToast(level: toast.Error, ..)) = out_msg
}

fn empty_model() -> transaction_page.Model {
  transaction_page.Model(
    transactions: remote.Loaded([]),
    tags: [],
    modal: transaction_modal.hidden(),
    delete_modal: transaction_delete_modal.empty(),
  )
}

fn with_transaction(
  model: transaction_page.Model,
  transaction: transaction.Transaction,
) -> transaction_page.Model {
  transaction_page.Model(..model, transactions: remote.Loaded([transaction]))
}
