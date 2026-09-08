import budgeteur/shared/api_error.{type ApiError, ApiError}
import budgeteur/shared/field
import budgeteur/shared/form_modal.{
  Active, CloseDialog, Create, Created, Edit, Errored, Hidden, NoChange, Post,
  Put, Submitting, Updated,
}
import budgeteur/tagging_page/tag/tag.{type Tag, Tag}
import budgeteur/tagging_page/tag/tag_form.{
  type Modal, CancelRequested, ColorChosen, CreateRequested, DialogDismissed,
  Duplicate, EditRequested, Form, NameChanged, NameRequired, SaveCompleted,
  SaveRequested, TooLong,
}
import budgeteur/tagging_page/tag_write_request.{TagWriteRequest}
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should
import youid/uuid.{type Uuid}

fn make_tag(name: String) -> Tag {
  Tag(id: uuid.v7(), name:, color: tag_form.default_color)
}

fn make_create_modal() -> Modal {
  let state = tag_form.hidden()
  let #(state, _, _) = tag_form.update(state, CreateRequested, [])
  state
}

fn make_edit_modal(tag: Tag) -> Modal {
  let state = tag_form.hidden()
  let #(state, _, _) = tag_form.update(state, EditRequested(tag), [])
  state
}

fn modal_with_tag_name(state: Modal, tag_name: String) -> Modal {
  let #(state, _, _) = tag_form.update(state, NameChanged(tag_name), [])

  state
}

fn try_validate(state: Modal, tags: List(Tag)) -> Modal {
  let #(state, _, _) = tag_form.update(state, SaveRequested, tags)
  state
}

pub fn validate_rejects_duplicate_name_test() {
  let tag = make_tag("Coffee")
  let modal = make_create_modal() |> modal_with_tag_name(tag.name)

  let error_state = try_validate(modal, [tag])

  let assert Active(
    form: Form(name: field.Invalid(error: Duplicate, ..), ..),
    ..,
  ) = error_state
    as "Expected the name to be marked as duplicate"
}

pub fn validate_does_not_count_self_as_duplicate_test() {
  // The page builds `other_tag_names` excluding the tag being edited, so the
  // form sees no duplicate when renaming keeps the same name.
  let existing_tag = make_tag("Coffee")
  let modal =
    make_edit_modal(existing_tag) |> modal_with_tag_name(existing_tag.name)

  let modal = try_validate(modal, [existing_tag])

  let assert Submitting(form: Form(name: field.Valid(value: name, ..), ..), ..) =
    modal

  name |> should.equal(existing_tag.name)
}

pub fn validate_trims_the_request_name_but_not_the_field_test() {
  let modal = make_create_modal() |> modal_with_tag_name("  Coffee  ")

  // The field keeps showing exactly what the user typed (trimming the field
  // on submit would make the shown value jump around); the request carries
  // the trimmed name.
  let assert #(submitting, [request], NoChange) =
    tag_form.update(modal, SaveRequested, [])
  request
  |> should.equal(Post(TagWriteRequest("Coffee", tag_form.default_color)))

  let assert Submitting(
    form: Form(name: field.Valid(value: _, input:), color:),
    ..,
  ) = submitting
  input |> should.equal("  Coffee  ")
  color |> should.equal(tag_form.default_color)
}

pub fn validate_reports_required_error_for_blank_name_test() {
  let modal = make_create_modal()

  let error_state = try_validate(modal, [])

  let assert Active(
    form: Form(name: field.Invalid(error: NameRequired, ..), ..),
    ..,
  ) = error_state
    as "Expected the name to be marked as missing (name required)"
}

pub fn set_name_records_too_long_error_test() {
  let modal =
    make_create_modal()
    |> modal_with_tag_name(string.repeat("a", tag_form.max_name_length + 1))

  let assert Active(form: Form(name: field.Invalid(error: TooLong, ..), ..), ..) =
    modal
    as "Expected the name to be marked as too long"
}

pub fn typing_keeps_the_space_the_user_just_typed_test() {
  // The field is re-rendered from this stored value on every keystroke, so a
  // trailing space must survive NameChanged: trimming it here would eat the
  // space while typing "Food & Drink" from scratch. Trim happens on save.
  let #(state, _, _) =
    tag_form.update(make_create_modal(), NameChanged("Food & "), [])

  let assert Active(form: Form(name: field.Valid(value: _, input:), ..), ..) =
    state
  input |> should.equal("Food & ")

  let #(typed, _, _) = tag_form.update(state, NameChanged("Food & Drink"), [])
  let assert Active(form: Form(name: field.Valid(value: _, input:), ..), ..) =
    typed
  input |> should.equal("Food & Drink")
}

// ── Reducer transitions ───────────────────────────────────────────────────────

fn make_id() -> Uuid {
  let assert Ok(id) = uuid.from_string("00000000-0000-0000-0000-000000000001")
  id
}

fn tag_named(id: Uuid, name: String) -> tag.Tag {
  Tag(id:, name:, color: tag_form.default_color)
}

fn api_error(message: String) -> ApiError {
  ApiError(
    error: "Conflict",
    details: message,
    status_code: Some(409),
    request_id: None,
  )
}

pub fn create_tag_workflow_test() {
  let id = make_id()
  let modal = make_create_modal()

  let assert #(named, _, NoChange) =
    tag_form.update(modal, NameChanged("Coffee"), [])
  let assert #(colored, _, NoChange) =
    tag_form.update(named, ColorChosen("#EF4444"), [])

  let assert #(submitting, [request], NoChange) =
    tag_form.update(colored, SaveRequested, [])
  let assert Submitting(mode: Create, ..) = submitting
  request |> should.equal(Post(TagWriteRequest("Coffee", "#EF4444")))

  let new_tag = tag_named(id, "Coffee")
  let #(final_state, requests, outcome) =
    tag_form.update(submitting, SaveCompleted(Ok(new_tag)), [])
  final_state |> should.equal(Hidden)
  requests |> should.equal([CloseDialog])
  outcome |> should.equal(Created(new_tag))
}

pub fn edit_tag_workflow_keeps_own_name_test() {
  let id = make_id()
  let existing = tag_named(id, "Coffee")
  let modal = make_edit_modal(existing)

  let assert #(submitting, [request], NoChange) =
    tag_form.update(modal, SaveRequested, [
      existing,
    ])
  let assert Submitting(mode: Edit(id), ..) = submitting
  id |> should.equal(existing.id)
  request |> should.equal(Put(id, TagWriteRequest("Coffee", "#6366F1")))

  let saved = tag_named(make_id(), "Coffee & Drink")
  let #(final_state, requests, outcome) =
    tag_form.update(submitting, SaveCompleted(Ok(saved)), [existing])
  final_state |> should.equal(Hidden)
  requests |> should.equal([CloseDialog])
  outcome |> should.equal(Updated(saved))
}

pub fn submit_duplicate_name_marks_invalid_and_emits_no_request_test() {
  let existing = tag_named(make_id(), "Coffee")
  let #(named, _, _) =
    tag_form.update(make_create_modal(), NameChanged("Coffee"), [])

  let assert #(new_state, requests, NoChange) =
    tag_form.update(named, SaveRequested, [existing])
  requests |> should.equal([])
  let assert Active(
    form: Form(name: field.Invalid(error: Duplicate, ..), ..),
    ..,
  ) = new_state
}

pub fn save_failure_then_fix_then_retry_test() {
  let #(named, _, _) =
    tag_form.update(make_create_modal(), NameChanged("Coffee"), [])
  let assert #(submitting, [Post(_)], NoChange) =
    tag_form.update(named, SaveRequested, [])

  // The failure surfaces the API error as the banner message.
  let assert #(errored, requests, NoChange) =
    tag_form.update(
      submitting,
      tag_form.SaveCompleted(
        Error(api_error("A tag named Coffee already exists")),
      ),
      [],
    )
  requests |> should.equal([])
  let assert Errored(mode: Create, error:, ..) = errored
  error |> should.equal("A tag named Coffee already exists")

  // Editing keeps the banner; the next submit attempt clears it.
  let assert #(still_errored, _, NoChange) =
    tag_form.update(errored, NameChanged("Tea"), [])
  let assert Errored(form:, error:, ..) = still_errored
  form.name |> should.equal(field.Valid(value: "Tea", input: "Tea"))
  error |> should.equal("A tag named Coffee already exists")

  // Retry is legal from the errored state.
  let assert #(submitting_again, [Post(_)], NoChange) =
    tag_form.update(still_errored, SaveRequested, [])
  let assert Submitting(..) = submitting_again
}

pub fn cancel_requests_dialog_close_but_dismiss_does_not_test() {
  let assert #(state, requests, NoChange) =
    tag_form.update(make_create_modal(), CancelRequested, [])
  state |> should.equal(Hidden)
  requests |> should.equal([CloseDialog])

  let assert #(state, requests, NoChange) =
    tag_form.update(make_create_modal(), DialogDismissed, [])
  state |> should.equal(Hidden)
  requests |> should.equal([])
}
