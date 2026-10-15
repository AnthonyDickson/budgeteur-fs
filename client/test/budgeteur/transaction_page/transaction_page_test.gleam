import budgeteur/shared/api_error.{ApiError}
import budgeteur/shared/delete_modal
import budgeteur/shared/effect
import budgeteur/shared/field
import budgeteur/shared/form_modal
import budgeteur/shared/http_effect
import budgeteur/shared/out_msg
import budgeteur/shared/remote
import budgeteur/shared/toast
import budgeteur/transaction_page/import_modal
import budgeteur/transaction_page/transaction
import budgeteur/transaction_page/transaction_delete_modal
import budgeteur/transaction_page/transaction_modal
import budgeteur/transaction_page/transaction_page
import budgeteur/transaction_page/transaction_search
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
    account_name: None,
    tag: None,
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

  new_model |> shown |> should.equal(remote.Loaded([transaction]))
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

  new_model |> shown |> should.equal(remote.Loaded([updated]))
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
  new_model |> shown |> should.equal(remote.Loaded([transaction]))
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
  closed |> shown |> should.equal(remote.Loaded([transaction]))
  effect |> should.equal(effect.none())
}

pub fn delete_in_the_edit_form_opens_the_confirmation_test() {
  let transaction = sample_transaction()
  let model = empty_model() |> with_transaction(transaction)

  // Delete in the transaction's edit dialog swaps the dialog for the
  // confirmation.
  let #(editing, _, _) =
    transaction_page.update(
      model,
      transaction_page.UserRequestedEditForm(transaction.id),
    )
  let #(opened, effect, _) =
    transaction_page.update(
      editing,
      transaction_page.TransactionModalMsg(transaction_modal.DeleteRequested),
    )

  opened.modal |> should.equal(transaction_modal.hidden())
  opened.delete_modal
  |> should.equal(transaction_delete_modal.open(transaction))
  effect |> should.equal(effect.none())
}

pub fn confirming_delete_issues_delete_request_test() {
  let transaction = sample_transaction()
  let model =
    transaction_page.Model(
      ..empty_model(),
      results: loaded([transaction]),
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
      results: loaded([transaction]),
      delete_modal: delete_modal.Deleting(target: transaction, context: Nil),
    )

  let #(new_model, _, _) =
    transaction_page.update(
      model,
      transaction_page.ServerDeletedTransaction(transaction, Ok(Nil)),
    )

  new_model |> shown |> should.equal(remote.Loaded([]))
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

  new_model |> shown |> should.equal(remote.Loaded([]))
}

pub fn server_delete_error_shows_inline_error_test() {
  let transaction = sample_transaction()
  let model =
    transaction_page.Model(
      ..empty_model(),
      results: loaded([transaction]),
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
  new_model |> shown |> should.equal(remote.Loaded([transaction]))
  out_msg |> should.equal(None)
  let assert effect.LogError(_) = effect
}

pub fn server_delete_error_404_is_treated_as_success_test() {
  let transaction = sample_transaction()
  let model =
    transaction_page.Model(
      ..empty_model(),
      results: loaded([transaction]),
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

  new_model |> shown |> should.equal(remote.Loaded([]))
  let assert delete_modal.Hidden = new_model.delete_modal
  let assert Some(out_msg.PageRequestedToast(level: toast.Success, ..)) =
    out_msg
}

pub fn user_cancelled_delete_modal_closes_test() {
  let transaction = sample_transaction()
  let model =
    transaction_page.Model(
      ..empty_model(),
      results: loaded([transaction]),
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

pub fn init_asks_for_today_then_searches_test() {
  let #(model, effect) = transaction_page.init()

  model.results |> should.equal(remote.Loading)
  let assert effect.Batch([
    effect.GetLocalDate(_),
    effect.HttpRequest(url: tags_url, ..),
    effect.HttpRequest(url: accounts_url, ..),
  ]) = effect
  tags_url |> should.equal("/api/tags")
  accounts_url |> should.equal("/api/accounts")

  // The first search waits for today, which the server resolves date presets
  // from.
  let #(_, effect, _) =
    transaction_page.update(model, transaction_page.ClientGotToday(today()))
  let assert effect.HttpRequest(method:, url:, body:, ..) = effect
  method |> should.equal(http_effect.Post)
  url |> should.equal("/api/transactions/search")
  body |> string.contains("\"today\":\"2026-03-15\"") |> should.be_true
  body |> string.contains("\"cursor\":null") |> should.be_true
}

pub fn a_search_shows_matches_in_the_servers_order_test() {
  let older = sample_transaction()
  let newer = other_transaction()
  let #(model, _) = transaction_page.init()

  let #(new_model, effect, out_msg) =
    transaction_page.update(
      model,
      transaction_page.ClientSearched(
        transaction_search.new(),
        Ok(page([newer, older], None)),
      ),
    )

  new_model |> shown |> should.equal(remote.Loaded([newer, older]))
  effect |> should.equal(effect.none())
  out_msg |> should.equal(None)
}

pub fn a_response_for_other_criteria_is_ignored_test() {
  let model =
    transaction_page.Model(..empty_model(), search: with_text("coffee"))

  let #(new_model, effect, _) =
    transaction_page.update(
      model,
      transaction_page.ClientSearched(
        transaction_search.new(),
        Ok(page([sample_transaction()], None)),
      ),
    )

  new_model |> should.equal(model)
  effect |> should.equal(effect.none())
}

pub fn a_failed_first_load_offers_a_retry_test() {
  let #(model, _) = transaction_page.init()
  let model = run(model, transaction_page.ClientGotToday(today()))

  let #(failed, effect, out_msg) =
    transaction_page.update(
      model,
      transaction_page.ClientSearched(
        transaction_search.new(),
        Error(server_error()),
      ),
    )

  failed.results |> should.equal(remote.Failed)
  let assert effect.LogError(_) = effect
  out_msg |> should.equal(None)

  let #(retrying, effect, _) =
    transaction_page.update(failed, transaction_page.UserRequestedReload)

  retrying.results |> should.equal(remote.Loading)
  let assert effect.Batch([
    effect.GetLocalDate(_),
    effect.HttpRequest(url: "/api/tags", ..),
    effect.HttpRequest(url: "/api/accounts", ..),
  ]) = effect
}

pub fn a_failed_search_keeps_the_results_test() {
  let transaction = sample_transaction()
  let model = empty_model() |> with_transaction(transaction)

  let #(new_model, effect, out_msg) =
    transaction_page.update(
      model,
      transaction_page.ClientSearched(
        transaction_search.new(),
        Error(server_error()),
      ),
    )

  new_model |> shown |> should.equal(remote.Loaded([transaction]))
  let assert effect.LogError(_) = effect
  let assert Some(out_msg.PageRequestedToast(level: toast.Error, ..)) = out_msg
}

// ── Paging ───────────────────────────────────────────────────────────────────

pub fn load_more_appends_the_next_page_test() {
  let first = sample_transaction()
  let second = other_transaction()
  let model =
    transaction_page.Model(..empty_model(), results: loaded_with_next([first]))

  let #(loading, effect, _) =
    transaction_page.update(model, transaction_page.UserRequestedMore)

  loading.loading_more |> should.be_true
  let assert effect.HttpRequest(url:, body:, ..) = effect
  url |> should.equal("/api/transactions/search")
  body |> string.contains("\"cursor\":\"next\"") |> should.be_true

  // A second click while the page loads sends nothing.
  let #(_, effect, _) =
    transaction_page.update(loading, transaction_page.UserRequestedMore)
  effect |> should.equal(effect.none())

  let #(loaded, _, _) =
    transaction_page.update(
      loading,
      transaction_page.ClientFetchedMore(
        transaction_search.new(),
        "next",
        Ok(page([second], None)),
      ),
    )

  loaded |> shown |> should.equal(remote.Loaded([first, second]))
  loaded.loading_more |> should.be_false
  let assert remote.Loaded(transaction_page.Results(next: None, ..)) =
    loaded.results
}

pub fn load_more_skips_rows_already_shown_test() {
  // A created transaction was added at the top and is also on the next page.
  let created = other_transaction()
  let first = sample_transaction()
  let model =
    transaction_page.Model(
      ..empty_model(),
      results: loaded_with_next([created, first]),
      loading_more: True,
    )

  let #(loaded, _, _) =
    transaction_page.update(
      model,
      transaction_page.ClientFetchedMore(
        transaction_search.new(),
        "next",
        Ok(page([created], None)),
      ),
    )

  loaded |> shown |> should.equal(remote.Loaded([created, first]))
}

pub fn a_page_for_replaced_results_is_ignored_test() {
  let model =
    transaction_page.Model(
      ..empty_model(),
      results: loaded([sample_transaction()]),
    )

  let #(new_model, effect, _) =
    transaction_page.update(
      model,
      transaction_page.ClientFetchedMore(
        transaction_search.new(),
        "next",
        Ok(page([other_transaction()], None)),
      ),
    )

  new_model |> should.equal(model)
  effect |> should.equal(effect.none())
}

pub fn a_failed_load_more_keeps_the_results_test() {
  let transaction = sample_transaction()
  let model =
    transaction_page.Model(
      ..empty_model(),
      results: loaded_with_next([transaction]),
      loading_more: True,
    )

  let #(new_model, effect, out_msg) =
    transaction_page.update(
      model,
      transaction_page.ClientFetchedMore(
        transaction_search.new(),
        "next",
        Error(server_error()),
      ),
    )

  new_model |> shown |> should.equal(remote.Loaded([transaction]))
  new_model.loading_more |> should.be_false
  let assert effect.LogError(_) = effect
  let assert Some(out_msg.PageRequestedToast(level: toast.Error, ..)) = out_msg
}

fn with_text(text: String) -> transaction_search.Search {
  transaction_search.Search(..transaction_search.new(), text:)
}

fn today() -> calendar.Date {
  calendar.Date(2026, calendar.March, 15)
}

fn other_transaction() -> transaction.Transaction {
  let assert Ok(id) = uuid.from_string("00000000-0000-0000-0000-000000000002")
  transaction.Transaction(
    ..sample_transaction(),
    id:,
    description: "Lunch",
    date: calendar.Date(2026, calendar.February, 1),
  )
}

fn page(
  transactions: List(transaction.Transaction),
  next: option.Option(String),
) -> transaction_search.Page {
  transaction_search.Page(transactions:, next:, from: None, to: None)
}

/// The results of the search with no criteria, on its last page.
fn loaded(
  transactions: List(transaction.Transaction),
) -> remote.Remote(transaction_page.Results) {
  remote.Loaded(transaction_page.Results(
    search: transaction_search.new(),
    transactions:,
    next: None,
    from: None,
    to: None,
  ))
}

/// The results of the search with no criteria, with a next page.
fn loaded_with_next(
  transactions: List(transaction.Transaction),
) -> remote.Remote(transaction_page.Results) {
  remote.Loaded(transaction_page.Results(
    search: transaction_search.new(),
    transactions:,
    next: Some("next"),
    from: None,
    to: None,
  ))
}

/// The transactions the page shows.
fn shown(
  model: transaction_page.Model,
) -> remote.Remote(List(transaction.Transaction)) {
  remote.map(model.results, fn(results) { results.transactions })
}

fn empty_model() -> transaction_page.Model {
  transaction_page.Model(
    today: Some(today()),
    search: transaction_search.new(),
    results: loaded([]),
    searching: False,
    loading_more: False,
    filters_open: False,
    tags: [],
    accounts: [],
    modal: transaction_modal.hidden(),
    delete_modal: transaction_delete_modal.empty(),
    import_modal: import_modal.Hidden,
  )
}

fn with_transaction(
  model: transaction_page.Model,
  transaction: transaction.Transaction,
) -> transaction_page.Model {
  transaction_page.Model(..model, results: loaded([transaction]))
}

fn import_result() -> import_modal.ImportResult {
  import_modal.ImportResult(
    imported: 218,
    skipped_duplicates: 0,
    transfers: 40,
    tagged_by_rules: 26,
    accounts_created: ["12-3456-0789012-000"],
  )
}

pub fn an_import_reads_the_files_then_posts_them_test() {
  let #(model, _, _) =
    transaction_page.update(
      empty_model(),
      transaction_page.ImportModalMsg(import_modal.OpenRequested),
    )
  let model =
    run(model, transaction_page.ImportModalMsg(import_modal.FilesChosen(2)))

  // Submitting reads the chosen files: the files stay in the DOM, so the
  // effect hands back their text.
  let #(model, effect, _) =
    transaction_page.update(
      model,
      transaction_page.ImportModalMsg(import_modal.SubmitRequested),
    )
  let assert effect.ReadFiles(input_id:, ..) = effect
  input_id |> should.equal(import_modal.file_input_id)

  let #(model, effect, _) =
    transaction_page.update(
      model,
      transaction_page.ImportModalMsg(
        import_modal.FilesRead(Ok([#("chequing.csv", "Account number,...")])),
      ),
    )
  let assert effect.HttpRequest(method:, url:, body:, ..) = effect
  method |> should.equal(http_effect.Post)
  url |> should.equal("/api/imports")
  body
  |> should.equal(
    "{\"files\":[{\"name\":\"chequing.csv\",\"content\":\"Account number,...\"}]}",
  )

  // Success closes the dialog, toasts the counts, and reloads the table.
  let #(model, effect, out_msg) =
    transaction_page.update(
      model,
      transaction_page.ImportModalMsg(
        import_modal.ImportCompleted(Ok(import_result())),
      ),
    )
  model.import_modal |> should.equal(import_modal.Hidden)
  let assert Some(out_msg.PageRequestedToast(level: toast.Success, body:, ..)) =
    out_msg
  body
  |> should.equal(
    "Imported 218 transactions (40 transfers, 26 tagged by rules). Skipped 0 already imported. Created accounts: 12-3456-0789012-000.",
  )
  let assert effect.Batch([
    effect.HttpRequest(url: "/api/transactions/search", ..),
    effect.HttpRequest(url: "/api/accounts", ..),
  ]) = effect
}

// ── Changes to the rows shown ────────────────────────────────────────────────

pub fn a_created_transaction_is_added_at_the_top_whatever_its_date_test() {
  let newer = other_transaction()
  let created = sample_transaction()
  let submitting =
    empty_model() |> with_transaction(newer) |> submitting_create_form

  let #(new_model, _, _) =
    transaction_page.update(
      submitting,
      transaction_page.TransactionModalMsg(
        transaction_modal.SaveCompleted(Ok(created)),
      ),
    )

  new_model |> shown |> should.equal(remote.Loaded([created, newer]))
}

pub fn an_updated_transaction_keeps_its_place_test() {
  let first = other_transaction()
  let second = sample_transaction()
  // Now the newest, and it may no longer match the search.
  let updated =
    transaction.Transaction(
      ..second,
      date: calendar.Date(2026, calendar.March, 1),
    )
  let submitting =
    transaction_page.Model(..empty_model(), results: loaded([first, second]))
    |> submit_edit_form(second.id)

  let #(new_model, effect, _) =
    transaction_page.update(
      submitting,
      transaction_page.TransactionModalMsg(
        transaction_modal.SaveCompleted(Ok(updated)),
      ),
    )

  new_model |> shown |> should.equal(remote.Loaded([first, updated]))
  // A change never runs the search again.
  effect |> should.equal(effect.none())
}

// ── Searching ────────────────────────────────────────────────────────────────

pub fn typing_searches_once_typing_pauses_test() {
  let #(typed, effect, _) =
    transaction_page.update(
      empty_model(),
      transaction_page.UserChangedText("coffee"),
    )

  typed.search |> should.equal(with_text("coffee"))
  effect |> should.equal(effect.none())

  let #(searching, effect, _) =
    transaction_page.update(typed, transaction_page.UserPausedTyping("coffee"))

  searching.searching |> should.be_true
  let assert effect.HttpRequest(url:, body:, ..) = effect
  url |> should.equal("/api/transactions/search")
  body |> string.contains("\"text\":\"coffee\"") |> should.be_true

  // The previous results stay until the search returns.
  searching.results |> should.equal(empty_model().results)

  let match = sample_transaction()
  let #(searched, _, _) =
    transaction_page.update(
      searching,
      transaction_page.ClientSearched(
        with_text("coffee"),
        Ok(page([match], None)),
      ),
    )

  searched.searching |> should.be_false
  searched |> shown |> should.equal(remote.Loaded([match]))
}

pub fn a_response_for_text_since_changed_is_ignored_test() {
  let searching =
    empty_model()
    |> run(transaction_page.UserChangedText("cof"))
    |> run(transaction_page.UserPausedTyping("cof"))
    |> run(transaction_page.UserChangedText("coffee"))
    |> run(transaction_page.UserPausedTyping("coffee"))

  let #(new_model, _, _) =
    transaction_page.update(
      searching,
      transaction_page.ClientSearched(
        with_text("cof"),
        Ok(page([sample_transaction()], None)),
      ),
    )

  new_model |> should.equal(searching)
}

pub fn clearing_resets_the_criteria_and_searches_test() {
  let model =
    empty_model()
    |> run(transaction_page.UserChangedText("coffee"))
    |> run(transaction_page.UserPausedTyping("coffee"))

  let #(cleared, effect, _) =
    transaction_page.update(model, transaction_page.UserClearedSearch)

  cleared.search |> should.equal(transaction_search.new())
  cleared.searching |> should.be_true
  let assert effect.HttpRequest(body:, ..) = effect
  body |> string.contains("\"text\":\"\"") |> should.be_true

  // A pause from before the clear runs no search.
  let #(_, effect, _) =
    transaction_page.update(
      cleared,
      transaction_page.UserPausedTyping("coffee"),
    )
  effect |> should.equal(effect.none())
}

pub fn a_failed_search_stops_searching_test() {
  let model =
    empty_model()
    |> run(transaction_page.UserChangedText("coffee"))
    |> run(transaction_page.UserPausedTyping("coffee"))

  let #(failed, _, out_msg) =
    transaction_page.update(
      model,
      transaction_page.ClientSearched(
        with_text("coffee"),
        Error(server_error()),
      ),
    )

  failed.searching |> should.be_false
  failed.results |> should.equal(model.results)
  let assert Some(out_msg.PageRequestedToast(level: toast.Error, ..)) = out_msg
}

// ── Filters ──────────────────────────────────────────────────────────────────

pub fn choosing_a_date_preset_searches_and_shows_its_days_test() {
  let #(searching, effect, _) =
    transaction_page.update(
      empty_model(),
      transaction_page.UserChangedDatePreset(transaction_search.LastMonth),
    )

  searching.searching |> should.be_true
  let assert effect.HttpRequest(body:, ..) = effect
  body
  |> string.contains("\"preset\":\"LastMonth\",\"from\":null,\"to\":null")
  |> should.be_true

  let from = calendar.Date(2026, calendar.February, 1)
  let to = calendar.Date(2026, calendar.February, 28)
  let #(searched, _, _) =
    transaction_page.update(
      searching,
      transaction_page.ClientSearched(
        searching.search,
        Ok(transaction_search.Page(
          transactions: [],
          next: None,
          from: Some(from),
          to: Some(to),
        )),
      ),
    )

  let assert remote.Loaded(results) = searched.results
  #(results.from, results.to) |> should.equal(#(Some(from), Some(to)))
}

pub fn custom_dates_are_sent_as_typed_test() {
  let model =
    empty_model()
    |> run(transaction_page.UserChangedDatePreset(transaction_search.Custom))

  let #(_, effect, _) =
    transaction_page.update(
      model,
      transaction_page.UserChangedFromDate("2026-02-01"),
    )

  let assert effect.HttpRequest(body:, ..) = effect
  body
  |> string.contains(
    "\"preset\":\"Custom\",\"from\":\"2026-02-01\",\"to\":null",
  )
  |> should.be_true
}

pub fn a_first_day_after_the_last_day_sends_nothing_test() {
  let model =
    empty_model()
    |> run(transaction_page.UserChangedDatePreset(transaction_search.Custom))
    |> run(transaction_page.UserChangedFromDate("2026-03-01"))

  let #(invalid, effect, _) =
    transaction_page.update(
      model,
      transaction_page.UserChangedToDate("2026-02-01"),
    )

  effect |> should.equal(effect.none())
  invalid.searching |> should.be_false
  let assert Error(transaction_search.Invalid(dates: Some(_))) =
    transaction_search.validate(invalid.search)
}

pub fn the_filters_button_toggles_the_panel_test() {
  let opened = run(empty_model(), transaction_page.UserToggledFilters)
  opened.filters_open |> should.be_true

  let closed = run(opened, transaction_page.UserToggledFilters)
  closed.filters_open |> should.be_false
}
