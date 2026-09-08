import budgeteur/shared/api_error.{type ApiError, ApiError}
import budgeteur/shared/field
import budgeteur/shared/form_modal.{
  Active, CloseDialog, Create, Created, Edit, Errored, Hidden, NoChange, Post,
  Put, ShowDialog, Submitting, Updated,
}
import budgeteur/tagging_page/rule/rule.{type Rule, Rule}
import budgeteur/tagging_page/rule/rule_form.{
  type Modal, CancelRequested, CreateRequested, DialogDismissed, Duplicate,
  EditRequested, Form, InvalidTag, PatternChanged, PatternRequired,
  SaveCompleted, SaveRequested, TagChanged, TooLong, ValidTag,
}
import budgeteur/tagging_page/rule_write_request.{RuleWriteRequest}
import gleam/int
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should
import youid/uuid.{type Uuid}

fn make_id(n: Int) -> Uuid {
  let assert Ok(id) =
    uuid.from_string("00000000-0000-0000-0000-00000000000" <> int.to_string(n))
  id
}

fn make_rule(id: Uuid, pattern: String, tag_id: Uuid) -> Rule {
  Rule(id:, pattern:, tag_id:)
}

fn make_create_modal() -> Modal {
  let state = rule_form.hidden()
  let #(state, _, _) = rule_form.update(state, CreateRequested(make_id(1)), [])
  state
}

fn make_edit_modal(rule: Rule) -> Modal {
  let state = rule_form.hidden()
  let #(state, _, _) = rule_form.update(state, EditRequested(rule), [])
  state
}

fn modal_with_pattern(state: Modal, pattern: String) -> Modal {
  let #(state, _, _) = rule_form.update(state, PatternChanged(pattern), [])
  state
}

fn api_error(message: String) -> ApiError {
  ApiError(
    error: "Conflict",
    details: message,
    status_code: Some(409),
    request_id: None,
  )
}

pub fn opening_create_seeds_empty_pattern_and_selected_tag_test() {
  let #(state, requests, outcome) =
    rule_form.update(rule_form.hidden(), CreateRequested(make_id(1)), [])
  state
  |> should.equal(Active(
    form: Form(pattern: field.Empty(""), tag_id: ValidTag(make_id(1))),
    mode: Create,
  ))
  requests |> should.equal([ShowDialog])
  outcome |> should.equal(NoChange)
}

pub fn opening_edit_prefills_pattern_and_tag_test() {
  let existing = make_rule(make_id(3), "STARBUCKS", make_id(1))
  let #(state, requests, _) =
    rule_form.update(rule_form.hidden(), EditRequested(existing), [])
  state
  |> should.equal(Active(
    form: Form(
      pattern: field.Valid(value: "STARBUCKS", input: "STARBUCKS"),
      tag_id: ValidTag(make_id(1)),
    ),
    mode: Edit(existing.id),
  ))
  requests |> should.equal([ShowDialog])
}

pub fn typing_keeps_the_space_the_user_just_typed_test() {
  // The field is re-rendered from this stored value on every keystroke, so a
  // trailing space must survive PatternChanged: trimming it here would eat the
  // space while typing a pattern with a space from scratch. Trim happens on
  // save.
  let #(state, _, _) =
    rule_form.update(make_create_modal(), PatternChanged("Food & "), [])

  let assert Active(form: Form(pattern: field.Valid(value: _, input:), ..), ..) =
    state
  input |> should.equal("Food & ")

  let #(typed, _, _) =
    rule_form.update(state, PatternChanged("Food & Drink"), [])
  let assert Active(form: Form(pattern: field.Valid(value: _, input:), ..), ..) =
    typed
  input |> should.equal("Food & Drink")
}

pub fn validate_trims_the_request_pattern_but_not_the_field_test() {
  let modal = make_create_modal() |> modal_with_pattern("  STARBUCKS  ")

  // The field keeps showing exactly what the user typed (trimming the field
  // on submit would make the shown value jump around); the request carries
  // the trimmed pattern.
  let assert #(submitting, [request], NoChange) =
    rule_form.update(modal, SaveRequested, [])
  request |> should.equal(Post(RuleWriteRequest("STARBUCKS", make_id(1))))

  let assert Submitting(
    form: Form(pattern: field.Valid(value: _, input:), tag_id:),
    ..,
  ) = submitting
  input |> should.equal("  STARBUCKS  ")
  tag_id |> should.equal(ValidTag(make_id(1)))
}

pub fn submitting_a_blank_pattern_marks_it_required_test() {
  let assert #(state, requests, NoChange) =
    rule_form.update(make_create_modal(), SaveRequested, [])
  requests |> should.equal([])
  let assert Active(
    form: Form(pattern: field.Invalid(error: PatternRequired, ..), ..),
    ..,
  ) = state
    as "Expected the pattern to be marked as missing (pattern required)"
}

pub fn pattern_records_too_long_error_test() {
  let modal =
    make_create_modal()
    |> modal_with_pattern(string.repeat("a", rule_form.max_pattern_length + 1))

  let assert Active(
    form: Form(pattern: field.Invalid(error: TooLong, ..), ..),
    ..,
  ) = modal
    as "Expected the pattern to be marked as too long"
}

pub fn changing_tag_select_updates_the_rule_target_test() {
  let #(state, _, _) =
    rule_form.update(
      make_create_modal(),
      TagChanged(uuid.to_string(make_id(2))),
      [],
    )
  let assert Active(form: Form(tag_id: ValidTag(id), ..), ..) = state
  id |> should.equal(make_id(2))
}

pub fn selecting_an_invalid_tag_blocks_save_test() {
  let modal = make_create_modal() |> modal_with_pattern("STARBUCKS")
  let #(changed, _, _) = rule_form.update(modal, TagChanged("not-a-uuid"), [])
  let assert Active(form: Form(tag_id: InvalidTag, ..), ..) = changed

  let assert #(state, requests, NoChange) =
    rule_form.update(changed, SaveRequested, [])
  requests |> should.equal([])
  let assert Active(form: Form(tag_id: InvalidTag, ..), ..) = state
}

// ── Reducer transitions ───────────────────────────────────────────────────────

pub fn create_rule_workflow_test() {
  let modal = make_create_modal() |> modal_with_pattern("STARBUCKS")

  let assert #(submitting, [request], NoChange) =
    rule_form.update(modal, SaveRequested, [])
  let assert Submitting(mode: Create, ..) = submitting
  request |> should.equal(Post(RuleWriteRequest("STARBUCKS", make_id(1))))

  let saved = make_rule(make_id(3), "STARBUCKS", make_id(1))
  let #(final_state, requests, outcome) =
    rule_form.update(submitting, SaveCompleted(Ok(saved)), [])
  final_state |> should.equal(Hidden)
  requests |> should.equal([CloseDialog])
  outcome |> should.equal(Created(saved))
}

pub fn edit_rule_workflow_keeps_own_pattern_test() {
  let existing = make_rule(make_id(3), "STARBUCKS", make_id(1))
  let modal = make_edit_modal(existing)

  // Editing without changing the pattern is not a duplicate: the rule being
  // edited is excluded from the other-patterns check.
  let assert #(submitting, [request], NoChange) =
    rule_form.update(modal, SaveRequested, [existing])
  let assert Submitting(mode: Edit(id), ..) = submitting
  id |> should.equal(existing.id)
  request
  |> should.equal(Put(existing.id, RuleWriteRequest("STARBUCKS", make_id(1))))

  let saved = make_rule(make_id(3), "7-ELEVEN", make_id(2))
  let #(final_state, requests, outcome) =
    rule_form.update(submitting, SaveCompleted(Ok(saved)), [existing])
  final_state |> should.equal(Hidden)
  requests |> should.equal([CloseDialog])
  outcome |> should.equal(Updated(saved))
}

pub fn duplicate_pattern_in_same_tag_marks_form_and_emits_no_request_test() {
  // The duplicate check is case-insensitive within the selected tag, so a
  // lowercase "starbucks" collides with an existing "STARBUCKS" under the same
  // tag: rules differing only in case would match the same transactions.
  let existing = make_rule(make_id(4), "STARBUCKS", make_id(1))
  let modal = make_create_modal() |> modal_with_pattern("starbucks")

  let assert #(state, requests, NoChange) =
    rule_form.update(modal, SaveRequested, [existing])
  requests |> should.equal([])
  let assert Active(
    form: Form(pattern: field.Invalid(error: Duplicate, ..), ..),
    ..,
  ) = state
}

pub fn same_pattern_under_another_tag_is_allowed_test() {
  // Uniqueness is per tag, not per user (mirroring the server's
  // UNIQUE(UserId, Pattern, TagId) constraint): the same pattern may exist
  // under a different tag.
  let other = make_rule(make_id(4), "STARBUCKS", make_id(2))
  let modal = make_create_modal() |> modal_with_pattern("STARBUCKS")

  let assert #(submitting, [request], NoChange) =
    rule_form.update(modal, SaveRequested, [other])
  let assert Submitting(mode: Create, ..) = submitting
  request |> should.equal(Post(RuleWriteRequest("STARBUCKS", make_id(1))))
}

pub fn moving_a_rule_to_a_tag_with_the_same_pattern_is_rejected_test() {
  // Changing the tag select moves the rule, so the duplicate check runs
  // against the destination tag's rules. Moving onto a tag that already has a
  // matching pattern (case-insensitively) is rejected; the rule itself is
  // excluded from the check.
  let starbucks = make_rule(make_id(3), "STARBUCKS", make_id(1))
  let in_destination = make_rule(make_id(4), "starbucks", make_id(2))
  let modal = make_edit_modal(starbucks)
  let #(moved, _, _) =
    rule_form.update(modal, TagChanged(uuid.to_string(make_id(2))), [])

  let assert #(state, requests, NoChange) =
    rule_form.update(moved, SaveRequested, [starbucks, in_destination])
  requests |> should.equal([])
  let assert Active(
    form: Form(pattern: field.Invalid(error: Duplicate, ..), ..),
    ..,
  ) = state
}

pub fn moving_a_rule_to_a_tag_without_the_pattern_is_allowed_test() {
  let starbucks = make_rule(make_id(3), "STARBUCKS", make_id(1))
  let in_destination = make_rule(make_id(4), "7-ELEVEN", make_id(2))
  let modal = make_edit_modal(starbucks)
  let #(moved, _, _) =
    rule_form.update(modal, TagChanged(uuid.to_string(make_id(2))), [])

  let assert #(submitting, [request], NoChange) =
    rule_form.update(moved, SaveRequested, [in_destination, starbucks])
  let assert Submitting(mode: Edit(id), ..) = submitting
  id |> should.equal(starbucks.id)
  request
  |> should.equal(Put(starbucks.id, RuleWriteRequest("STARBUCKS", make_id(2))))
}

pub fn save_failure_then_fix_then_retry_test() {
  let modal = make_create_modal() |> modal_with_pattern("STARBUCKS")
  let assert #(submitting, [Post(_)], NoChange) =
    rule_form.update(modal, SaveRequested, [])

  // The failure surfaces the API error as the banner message.
  let message = "The rule pattern 'STARBUCKS' for tag 2 already exists"
  let assert #(errored, requests, NoChange) =
    rule_form.update(submitting, SaveCompleted(Error(api_error(message))), [])
  requests |> should.equal([])
  let assert Errored(mode: Create, error:, ..) = errored
  error |> should.equal(message)

  // Editing keeps the banner; the next submit attempt clears it.
  let assert #(still_errored, _, NoChange) =
    rule_form.update(errored, PatternChanged("7-ELEVEN"), [])
  let assert Errored(form:, error:, ..) = still_errored
  form.pattern
  |> should.equal(field.Valid(value: "7-ELEVEN", input: "7-ELEVEN"))
  error |> should.equal(message)

  // Retry is legal from the errored state.
  let assert #(submitting_again, [Post(_)], NoChange) =
    rule_form.update(still_errored, SaveRequested, [])
  let assert Submitting(..) = submitting_again
}

pub fn cancel_requests_dialog_close_but_dismiss_does_not_test() {
  let assert #(state, requests, NoChange) =
    rule_form.update(make_create_modal(), CancelRequested, [])
  state |> should.equal(Hidden)
  requests |> should.equal([CloseDialog])

  let assert #(state, requests, NoChange) =
    rule_form.update(make_create_modal(), DialogDismissed, [])
  state |> should.equal(Hidden)
  requests |> should.equal([])
}
