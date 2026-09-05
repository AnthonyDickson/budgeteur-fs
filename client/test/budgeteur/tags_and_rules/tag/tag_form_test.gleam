import budgeteur/shared/api_error.{type ApiError, ApiError}
import budgeteur/tags_and_rules/tag/tag
import budgeteur/tags_and_rules/tag/tag_form.{Duplicate, NameRequired, TooLong}
import budgeteur/tags_and_rules/tag_write_request
import gleam/int
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should
import youid/uuid

pub fn validate_rejects_duplicate_name_test() {
  let state = tag_form.create_modal() |> tag_form.set_name("Coffee")
  let error_state = tag_form.validate(state, ["Coffee"]) |> should.be_error
  let assert Some(tag_form.InvalidName(error: Duplicate, ..)) =
    tag_form.get_name(error_state)
    as "Expected the name to be marked as duplicate"
}

pub fn validate_does_not_count_self_as_duplicate_test() {
  // The page builds `other_tag_names` excluding the tag being edited, so the
  // form sees no duplicate when renaming keeps the same name.
  let assert Ok(id) = uuid.from_string("00000000-0000-0000-0000-000000000001")
  let existing = tag.Tag(id:, name: "Coffee", color: "#6366F1")
  let state = tag_form.edit_modal(existing)
  let assert Ok(#(name, _)) = tag_form.validate(state, [])
  name |> should.equal("Coffee")
}

pub fn validate_trims_name_and_returns_color_test() {
  let state = tag_form.create_modal() |> tag_form.set_name("  Coffee  ")
  let assert Ok(#(name, color)) = tag_form.validate(state, [])
    as "Expected the form to have a valid name and color"
  name |> should.equal("Coffee")
  color |> should.equal(tag_form.default_color)
}

pub fn validate_reports_required_error_for_blank_name_test() {
  let state = tag_form.create_modal()
  let error_state = tag_form.validate(state, []) |> should.be_error
  let assert Some(tag_form.InvalidName(error: NameRequired, ..)) =
    tag_form.get_name(error_state)
    as "Expected the name to be marked as missing (name required)"
}

pub fn set_name_records_too_long_error_test() {
  let state =
    tag_form.create_modal()
    |> tag_form.set_name(string.repeat("a", tag_form.max_name_length + 1))
  let assert Some(tag_form.InvalidName(error: TooLong, ..)) =
    tag_form.get_name(state)
    as "Expected the name to be marked as too long"
}

// ── Reducer transitions ───────────────────────────────────────────────────────

fn tag_id(n: Int) -> uuid.Uuid {
  let assert Ok(id) =
    uuid.from_string("00000000-0000-0000-0000-00000000000" <> int.to_string(n))
  id
}

fn tag_named(id: uuid.Uuid, name: String) -> tag.Tag {
  tag.Tag(id:, name:, color: "#6366F1")
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
  let assert #(named, _, tag_form.NoChange) =
    tag_form.update(tag_form.create_modal(), tag_form.NameChanged("Coffee"), [])
  let assert #(colored, _, tag_form.NoChange) =
    tag_form.update(named, tag_form.ColorChosen("#EF4444"), [])

  let assert #(submitting, [request], tag_form.NoChange) =
    tag_form.update(colored, tag_form.SaveRequested, [])
  let assert tag_form.Submitting(mode: tag_form.Create, ..) = submitting
  request
  |> should.equal(
    tag_form.CreateTag(tag_write_request.TagWriteRequest("Coffee", "#EF4444")),
  )

  let new_tag = tag_named(tag_id(1), "Coffee")
  let #(final_state, requests, outcome) =
    tag_form.update(submitting, tag_form.SaveCompleted(Ok(new_tag)), [])
  final_state |> should.equal(tag_form.Hidden)
  requests |> should.equal([tag_form.CloseDialog])
  outcome |> should.equal(tag_form.Created(new_tag))
}

pub fn edit_tag_workflow_keeps_own_name_test() {
  let existing = tag_named(tag_id(1), "Coffee")

  let assert #(submitting, [request], tag_form.NoChange) =
    tag_form.update(tag_form.edit_modal(existing), tag_form.SaveRequested, [
      existing,
    ])
  let assert tag_form.Submitting(mode: tag_form.Edit(id), ..) = submitting
  id |> should.equal(tag_id(1))
  request
  |> should.equal(tag_form.PutTag(
    tag_id(1),
    tag_write_request.TagWriteRequest("Coffee", "#6366F1"),
  ))

  let saved = tag_named(tag_id(1), "Coffee & Drink")
  let #(final_state, requests, outcome) =
    tag_form.update(submitting, tag_form.SaveCompleted(Ok(saved)), [existing])
  final_state |> should.equal(tag_form.Hidden)
  requests |> should.equal([tag_form.CloseDialog])
  outcome |> should.equal(tag_form.Updated(saved))
}

pub fn submit_duplicate_name_marks_invalid_and_emits_no_request_test() {
  let existing = tag_named(tag_id(1), "Coffee")
  let #(named, _, _) =
    tag_form.update(tag_form.create_modal(), tag_form.NameChanged("Coffee"), [])

  let assert #(new_state, requests, tag_form.NoChange) =
    tag_form.update(named, tag_form.SaveRequested, [existing])
  requests |> should.equal([])
  let assert Some(tag_form.InvalidName(error: Duplicate, ..)) =
    tag_form.get_name(new_state)
}

pub fn save_failure_then_fix_then_retry_test() {
  let #(named, _, _) =
    tag_form.update(tag_form.create_modal(), tag_form.NameChanged("Coffee"), [])
  let assert #(submitting, [tag_form.CreateTag(_)], tag_form.NoChange) =
    tag_form.update(named, tag_form.SaveRequested, [])

  // The failure surfaces the API error as the banner message.
  let assert #(errored, requests, tag_form.NoChange) =
    tag_form.update(
      submitting,
      tag_form.SaveCompleted(
        Error(api_error("A tag named Coffee already exists")),
      ),
      [],
    )
  requests |> should.equal([])
  let assert tag_form.Errored(mode: tag_form.Create, error:, ..) = errored
  error |> should.equal("A tag named Coffee already exists")

  // Editing the name keeps the banner until the next successful submit.
  let assert #(still_errored, _, tag_form.NoChange) =
    tag_form.update(errored, tag_form.NameChanged("Tea"), [])
  let assert tag_form.Errored(form:, error:, ..) = still_errored
  form.name |> should.equal(tag_form.ValidName(input: "Tea"))
  error |> should.equal("A tag named Coffee already exists")

  // Retry is legal from the errored state.
  let assert #(submitting_again, [tag_form.CreateTag(_)], tag_form.NoChange) =
    tag_form.update(still_errored, tag_form.SaveRequested, [])
  let assert tag_form.Submitting(..) = submitting_again
}

pub fn cancel_requests_dialog_close_but_dismiss_does_not_test() {
  let assert #(state, requests, tag_form.NoChange) =
    tag_form.update(tag_form.create_modal(), tag_form.CancelRequested, [])
  state |> should.equal(tag_form.Hidden)
  requests |> should.equal([tag_form.CloseDialog])

  let assert #(state, requests, tag_form.NoChange) =
    tag_form.update(tag_form.create_modal(), tag_form.DialogDismissed, [])
  state |> should.equal(tag_form.Hidden)
  requests |> should.equal([])
}
