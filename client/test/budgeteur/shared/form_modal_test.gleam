import budgeteur/shared/api_error
import budgeteur/shared/form_modal
import gleam/int
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should
import youid/uuid

type Form {
  Form(name: String)
}

fn form(name: String) -> Form {
  Form(name:)
}

fn api_error(details: String) -> api_error.ApiError {
  api_error.ApiError(
    error: "Conflict",
    details:,
    status_code: Some(409),
    request_id: None,
  )
}

fn id(n: Int) -> uuid.Uuid {
  let assert Ok(id) =
    uuid.from_string("00000000-0000-0000-0000-00000000000" <> int.to_string(n))
  id
}

fn prefixed(name: String) -> String {
  "x" <> name
}

// ── constructors ──────────────────────────────────────────────────────────────

pub fn hidden_is_hidden_test() {
  let modal: form_modal.Modal(Form) = form_modal.hidden()
  modal |> should.equal(form_modal.Hidden)
}

pub fn create_opens_an_active_create_modal_test() {
  form_modal.create(form(""))
  |> should.equal(form_modal.Active(form: form(""), mode: form_modal.Create))
}

pub fn edit_opens_an_active_edit_modal_test() {
  let id = id(1)
  form_modal.edit(id, form("Tea"))
  |> should.equal(form_modal.Active(
    form: form("Tea"),
    mode: form_modal.Edit(id),
  ))
}

pub fn mode_reports_the_open_modes_mode_test() {
  let id = id(1)
  form_modal.hidden() |> form_modal.mode |> should.equal(None)
  form_modal.create(form(""))
  |> form_modal.mode
  |> should.equal(Some(form_modal.Create))
  form_modal.edit(id, form("Tea"))
  |> form_modal.mode
  |> should.equal(Some(form_modal.Edit(id)))
  let submitting =
    form_modal.Submitting(form: form("Tea"), mode: form_modal.Create)
  submitting |> form_modal.mode |> should.equal(None)
}

// ── set_form ──────────────────────────────────────────────────────────────────

pub fn set_form_updates_active_and_errored_forms_test() {
  form_modal.create(form("Tea"))
  |> form_modal.set_form(fn(f) { form(prefixed(f.name)) })
  |> should.equal(form_modal.Active(form: form("xTea"), mode: form_modal.Create))

  let errored =
    form_modal.Errored(
      form: form("Tea"),
      mode: form_modal.Create,
      error: "boom",
    )
  errored
  |> form_modal.set_form(fn(f) { form(prefixed(f.name)) })
  |> should.equal(form_modal.Errored(
    form: form("xTea"),
    mode: form_modal.Create,
    error: "boom",
  ))
}

pub fn set_form_keeps_the_errored_banner_while_editing_test() {
  let errored =
    form_modal.Errored(
      form: form("Tea"),
      mode: form_modal.Edit(id(1)),
      error: "boom",
    )
  errored
  |> form_modal.set_form(fn(f) { f })
  |> should.equal(form_modal.Errored(
    form: form("Tea"),
    mode: form_modal.Edit(id(1)),
    error: "boom",
  ))
}

pub fn set_form_is_a_no_op_when_hidden_or_submitting_test() {
  let update = fn(f: Form) { form(prefixed(f.name)) }

  form_modal.hidden()
  |> form_modal.set_form(update)
  |> should.equal(form_modal.Hidden)

  let submitting =
    form_modal.Submitting(form: form("Tea"), mode: form_modal.Create)
  submitting
  |> form_modal.set_form(update)
  |> should.equal(form_modal.Submitting(
    form: form("Tea"),
    mode: form_modal.Create,
  ))
}

// ── submit ────────────────────────────────────────────────────────────────────

/// A validate that succeeds when the name is non-blank, returning the trimmed
/// name as payload and the (unchanged) form.
fn valid_validate(form: Form) -> Result(#(String, Form), Form) {
  let name = form.name |> string.trim
  case name {
    "" -> Error(form)
    _ -> Ok(#(name, form))
  }
}

pub fn submit_from_create_issues_a_post_request_test() {
  let #(modal, request) =
    form_modal.submit(form_modal.create(form("Tea")), valid_validate)

  modal
  |> should.equal(form_modal.Submitting(
    form: form("Tea"),
    mode: form_modal.Create,
  ))
  request |> should.equal(Some(form_modal.Post("Tea")))
}

pub fn submit_from_edit_issues_a_put_request_test() {
  let id = id(1)
  let #(modal, request) =
    form_modal.submit(form_modal.edit(id, form("Tea")), valid_validate)

  modal
  |> should.equal(form_modal.Submitting(
    form: form("Tea"),
    mode: form_modal.Edit(id),
  ))
  request |> should.equal(Some(form_modal.Put(id, "Tea")))
}

pub fn submit_retry_from_errored_moves_to_submitting_test() {
  let errored =
    form_modal.Errored(
      form: form("Tea"),
      mode: form_modal.Create,
      error: "boom",
    )
  let #(modal, request) = form_modal.submit(errored, valid_validate)

  modal
  |> should.equal(form_modal.Submitting(
    form: form("Tea"),
    mode: form_modal.Create,
  ))
  request |> should.equal(Some(form_modal.Post("Tea")))
}

pub fn submit_validation_failure_keeps_the_modal_open_with_errors_test() {
  let #(modal, request) =
    form_modal.submit(form_modal.create(form("  ")), valid_validate)

  modal
  |> should.equal(form_modal.Active(form: form("  "), mode: form_modal.Create))
  request |> should.equal(None)
}

pub fn submit_validation_failure_from_errored_drops_the_banner_test() {
  let errored =
    form_modal.Errored(form: form("  "), mode: form_modal.Create, error: "boom")
  let #(modal, request) = form_modal.submit(errored, valid_validate)

  modal
  |> should.equal(form_modal.Active(form: form("  "), mode: form_modal.Create))
  request |> should.equal(None)
}

pub fn submit_is_a_no_op_when_hidden_test() {
  let #(modal, request) = form_modal.submit(form_modal.hidden(), valid_validate)

  modal |> should.equal(form_modal.Hidden)
  request |> should.equal(None)
}

pub fn submit_is_a_no_op_while_submitting_test() {
  let submitting =
    form_modal.Submitting(form: form("Tea"), mode: form_modal.Create)
  let #(modal, request) = form_modal.submit(submitting, valid_validate)

  modal
  |> should.equal(form_modal.Submitting(
    form: form("Tea"),
    mode: form_modal.Create,
  ))
  request |> should.equal(None)
}

// ── succeeded ─────────────────────────────────────────────────────────────────

pub fn succeeded_create_closes_and_reports_created_test() {
  let submitting =
    form_modal.Submitting(form: form("Tea"), mode: form_modal.Create)
  let #(modal, outcome) = form_modal.succeeded(submitting, "Tea")

  modal |> should.equal(form_modal.Hidden)
  outcome |> should.equal(form_modal.Created("Tea"))
}

pub fn succeeded_edit_closes_and_reports_updated_test() {
  let id = id(1)
  let submitting =
    form_modal.Submitting(form: form("Tea"), mode: form_modal.Edit(id))
  let #(modal, outcome) = form_modal.succeeded(submitting, "Tea")

  modal |> should.equal(form_modal.Hidden)
  outcome |> should.equal(form_modal.Updated("Tea"))
}

pub fn succeeded_is_a_no_op_outside_submitting_test() {
  let active = form_modal.create(form("Tea"))
  let #(modal, outcome) = form_modal.succeeded(active, "Tea")

  modal |> should.equal(active)
  outcome |> should.equal(form_modal.NoChange)
}

// ── failed ────────────────────────────────────────────────────────────────────

pub fn failed_moves_submitting_to_errored_with_details_test() {
  let submitting =
    form_modal.Submitting(form: form("Tea"), mode: form_modal.Create)

  form_modal.failed(submitting, api_error("boom"))
  |> should.equal(form_modal.Errored(
    form: form("Tea"),
    mode: form_modal.Create,
    error: "boom",
  ))
}

pub fn failed_is_a_no_op_outside_submitting_test() {
  let active = form_modal.create(form("Tea"))
  form_modal.failed(active, api_error("boom")) |> should.equal(active)

  let hidden: form_modal.Modal(Form) = form_modal.hidden()
  form_modal.failed(hidden, api_error("boom")) |> should.equal(hidden)
}

// ── cancel / dismissed ────────────────────────────────────────────────────────

pub fn cancel_closes_active_and_errored_and_asks_to_close_the_dialog_test() {
  let #(modal, close) = form_modal.cancel(form_modal.create(form("Tea")))
  modal |> should.equal(form_modal.Hidden)
  close |> should.be_true

  let errored =
    form_modal.Errored(
      form: form("Tea"),
      mode: form_modal.Create,
      error: "boom",
    )
  let #(modal, close) = form_modal.cancel(errored)
  modal |> should.equal(form_modal.Hidden)
  close |> should.be_true
}

pub fn cancel_is_a_no_op_when_hidden_or_submitting_test() {
  let #(modal, close) = form_modal.cancel(form_modal.hidden())
  modal |> should.equal(form_modal.Hidden)
  close |> should.be_false

  let submitting =
    form_modal.Submitting(form: form("Tea"), mode: form_modal.Create)
  let #(modal, close) = form_modal.cancel(submitting)
  modal |> should.equal(submitting)
  close |> should.be_false
}

pub fn dismissed_hides_without_asking_to_close_the_dialog_test() {
  // The browser already closed the dialog (Esc / backdrop), so no
  // CloseDialog effect is needed.
  form_modal.dismissed(form_modal.create(form("Tea")))
  |> should.equal(form_modal.Hidden)

  let errored =
    form_modal.Errored(
      form: form("Tea"),
      mode: form_modal.Create,
      error: "boom",
    )
  form_modal.dismissed(errored) |> should.equal(form_modal.Hidden)
}

pub fn dismissed_is_a_no_op_when_hidden_or_submitting_test() {
  form_modal.hidden() |> form_modal.dismissed |> should.equal(form_modal.Hidden)

  let submitting =
    form_modal.Submitting(form: form("Tea"), mode: form_modal.Create)
  form_modal.dismissed(submitting) |> should.equal(submitting)
}
