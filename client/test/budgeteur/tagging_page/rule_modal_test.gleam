import budgeteur/shared/api_error.{type ApiError, ApiError}
import budgeteur/shared/field
import budgeteur/shared/form_modal.{
  Active, Create, Created, Edit, Errored, Hidden, NoChange, Post, Put,
  Submitting, Updated,
}
import budgeteur/tagging_page/rule.{type Rule, Rule, TagTarget, TransferTarget}
import budgeteur/tagging_page/rule_matches.{RuleMatches}
import budgeteur/tagging_page/rule_modal.{
  type Modal, CancelRequested, CountFailed, CountMatches, Counted, Counting,
  CreateRequested, Duplicate, EditRequested, Form, InvalidTag, MatchesCounted,
  NotCounted, PatternChanged, PatternRequired, PatternSettled, Save,
  SaveCompleted, SaveRequested, TagChanged, TooLong, ValidTag,
}
import budgeteur/tagging_page/rule_write_request.{RuleWriteRequest}
import gleam/int
import gleam/json
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
  Rule(id:, pattern:, target: TagTarget(tag_id))
}

fn make_create_modal() -> Modal {
  let state = rule_modal.hidden()
  let #(state, _, _) = rule_modal.update(state, CreateRequested(make_id(1)), [])
  state
}

fn make_edit_modal(rule: Rule) -> Modal {
  let state = rule_modal.hidden()
  let #(state, _, _) = rule_modal.update(state, EditRequested(rule), [])
  state
}

fn modal_with_pattern(state: Modal, pattern: String) -> Modal {
  let #(state, _, _) = rule_modal.update(state, PatternChanged(pattern), [])
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
  let #(state, request, outcome) =
    rule_modal.update(rule_modal.hidden(), CreateRequested(make_id(1)), [])
  state
  |> should.equal(Active(
    form: Form(
      pattern: field.Empty(""),
      tag_id: ValidTag(make_id(1)),
      match_count: NotCounted,
    ),
    mode: Create,
  ))
  request |> should.equal(None)
  outcome |> should.equal(NoChange)
}

pub fn opening_edit_prefills_pattern_and_tag_and_counts_matches_test() {
  let existing = make_rule(make_id(3), "STARBUCKS", make_id(1))
  let #(state, request, _) =
    rule_modal.update(rule_modal.hidden(), EditRequested(existing), [])
  state
  |> should.equal(Active(
    form: Form(
      pattern: field.Valid(value: "STARBUCKS", input: "STARBUCKS"),
      tag_id: ValidTag(make_id(1)),
      match_count: Counting("STARBUCKS"),
    ),
    mode: Edit(existing.id),
  ))
  request |> should.equal(Some(CountMatches("STARBUCKS")))
}

pub fn typing_keeps_the_space_the_user_just_typed_test() {
  // The field is re-rendered from this stored value on every keystroke, so a
  // trailing space must survive PatternChanged: trimming it here would eat the
  // space while typing a pattern with a space from scratch. Trim happens on
  // save.
  let #(state, _, _) =
    rule_modal.update(make_create_modal(), PatternChanged("Food & "), [])

  let assert Active(form: Form(pattern: field.Valid(value: _, input:), ..), ..) =
    state
  input |> should.equal("Food & ")

  let #(typed, _, _) =
    rule_modal.update(state, PatternChanged("Food & Drink"), [])
  let assert Active(form: Form(pattern: field.Valid(value: _, input:), ..), ..) =
    typed
  input |> should.equal("Food & Drink")
}

pub fn validate_trims_the_request_pattern_but_not_the_field_test() {
  let modal = make_create_modal() |> modal_with_pattern("  STARBUCKS  ")

  // The field keeps showing exactly what the user typed (trimming the field
  // on submit would make the shown value jump around); the request carries
  // the trimmed pattern.
  let assert #(submitting, Some(request), NoChange) =
    rule_modal.update(modal, SaveRequested, [])
  request
  |> should.equal(
    Save(Post(RuleWriteRequest("STARBUCKS", TagTarget(make_id(1))))),
  )

  let assert Submitting(
    form: Form(pattern: field.Valid(value: _, input:), tag_id:, ..),
    ..,
  ) = submitting
  input |> should.equal("  STARBUCKS  ")
  tag_id |> should.equal(ValidTag(make_id(1)))
}

pub fn submitting_a_blank_pattern_marks_it_required_test() {
  let assert #(state, request, NoChange) =
    rule_modal.update(make_create_modal(), SaveRequested, [])
  request |> should.equal(None)
  let assert Active(
    form: Form(pattern: field.Invalid(error: PatternRequired, ..), ..),
    ..,
  ) = state
    as "Expected the pattern to be marked as missing (pattern required)"
}

pub fn pattern_records_too_long_error_test() {
  let modal =
    make_create_modal()
    |> modal_with_pattern(string.repeat("a", rule_modal.max_pattern_length + 1))

  let assert Active(
    form: Form(pattern: field.Invalid(error: TooLong, ..), ..),
    ..,
  ) = modal
    as "Expected the pattern to be marked as too long"
}

pub fn changing_tag_select_updates_the_rule_target_test() {
  let #(state, _, _) =
    rule_modal.update(
      make_create_modal(),
      TagChanged(uuid.to_string(make_id(2))),
      [],
    )
  let assert Active(form: Form(tag_id: ValidTag(id), ..), ..) = state
  id |> should.equal(make_id(2))
}

pub fn selecting_an_invalid_tag_blocks_save_test() {
  let modal = make_create_modal() |> modal_with_pattern("STARBUCKS")
  let #(changed, _, _) = rule_modal.update(modal, TagChanged("not-a-uuid"), [])
  let assert Active(form: Form(tag_id: InvalidTag, ..), ..) = changed

  let assert #(state, request, NoChange) =
    rule_modal.update(changed, SaveRequested, [])
  request |> should.equal(None)
  let assert Active(form: Form(tag_id: InvalidTag, ..), ..) = state
}

// ── Reducer transitions ───────────────────────────────────────────────────────

pub fn create_rule_workflow_test() {
  let modal = make_create_modal() |> modal_with_pattern("STARBUCKS")

  let assert #(submitting, Some(request), NoChange) =
    rule_modal.update(modal, SaveRequested, [])
  let assert Submitting(mode: Create, ..) = submitting
  request
  |> should.equal(
    Save(Post(RuleWriteRequest("STARBUCKS", TagTarget(make_id(1))))),
  )

  let saved = make_rule(make_id(3), "STARBUCKS", make_id(1))
  let #(final_state, request, outcome) =
    rule_modal.update(submitting, SaveCompleted(Ok(saved)), [])
  final_state |> should.equal(Hidden)
  request |> should.equal(None)
  outcome |> should.equal(Created(saved))
}

pub fn edit_rule_workflow_keeps_own_pattern_test() {
  let existing = make_rule(make_id(3), "STARBUCKS", make_id(1))
  let modal = make_edit_modal(existing)

  // Editing without changing the pattern is not a duplicate: the rule being
  // edited is excluded from the other-patterns check.
  let assert #(submitting, Some(request), NoChange) =
    rule_modal.update(modal, SaveRequested, [existing])
  let assert Submitting(mode: Edit(id), ..) = submitting
  id |> should.equal(existing.id)
  request
  |> should.equal(
    Save(Put(existing.id, RuleWriteRequest("STARBUCKS", TagTarget(make_id(1))))),
  )

  let saved = make_rule(make_id(3), "7-ELEVEN", make_id(2))
  let #(final_state, request, outcome) =
    rule_modal.update(submitting, SaveCompleted(Ok(saved)), [existing])
  final_state |> should.equal(Hidden)
  request |> should.equal(None)
  outcome |> should.equal(Updated(saved))
}

pub fn duplicate_pattern_under_any_tag_marks_form_and_emits_no_request_test() {
  // Patterns are unique per user, ignoring case, whatever their tag: a
  // lowercase "starbucks" under one tag collides with "STARBUCKS" under
  // another, since both would match the same transactions.
  let existing = make_rule(make_id(4), "STARBUCKS", make_id(2))
  let modal = make_create_modal() |> modal_with_pattern("starbucks")

  let assert #(state, request, NoChange) =
    rule_modal.update(modal, SaveRequested, [existing])
  request |> should.equal(None)
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
    rule_modal.update(modal, TagChanged(uuid.to_string(make_id(2))), [])

  let assert #(submitting, Some(request), NoChange) =
    rule_modal.update(moved, SaveRequested, [in_destination, starbucks])
  let assert Submitting(mode: Edit(id), ..) = submitting
  id |> should.equal(starbucks.id)
  request
  |> should.equal(
    Save(Put(starbucks.id, RuleWriteRequest("STARBUCKS", TagTarget(make_id(2))))),
  )
}

pub fn save_failure_then_fix_then_retry_test() {
  let modal = make_create_modal() |> modal_with_pattern("STARBUCKS")
  let assert #(submitting, Some(Save(Post(_))), NoChange) =
    rule_modal.update(modal, SaveRequested, [])

  // The failure surfaces the API error as the banner message.
  let message = "A rule with the pattern 'STARBUCKS' already exists"
  let assert #(errored, request, NoChange) =
    rule_modal.update(submitting, SaveCompleted(Error(api_error(message))), [])
  request |> should.equal(None)
  let assert Errored(mode: Create, error:, ..) = errored
  error |> should.equal(message)

  // Editing keeps the banner; the next submit attempt clears it.
  let assert #(still_errored, _, NoChange) =
    rule_modal.update(errored, PatternChanged("7-ELEVEN"), [])
  let assert Errored(form:, error:, ..) = still_errored
  form.pattern
  |> should.equal(field.Valid(value: "7-ELEVEN", input: "7-ELEVEN"))
  error |> should.equal(message)

  // Retry is legal from the errored state.
  let assert #(submitting_again, Some(Save(Post(_))), NoChange) =
    rule_modal.update(still_errored, SaveRequested, [])
  let assert Submitting(..) = submitting_again
}

pub fn cancel_hides_the_modal_test() {
  let assert #(state, request, NoChange) =
    rule_modal.update(make_create_modal(), CancelRequested, [])
  state |> should.equal(Hidden)
  request |> should.equal(None)
}

fn send(state: Modal, msg: rule_modal.Msg) -> Modal {
  let #(state, _, _) = rule_modal.update(state, msg, [])
  state
}

fn match_count_of(state: Modal) -> rule_modal.MatchCount {
  let assert Active(form:, ..) = state
  form.match_count
}

pub fn a_settled_pattern_counts_matches_test() {
  let modal = make_create_modal() |> modal_with_pattern("  COUNTDOWN ")

  let assert #(counting, Some(CountMatches("COUNTDOWN")), NoChange) =
    rule_modal.update(modal, PatternSettled("  COUNTDOWN "), [])
  match_count_of(counting) |> should.equal(Counting("COUNTDOWN"))
}

pub fn a_settled_blank_pattern_clears_the_count_test() {
  let modal =
    make_edit_modal(make_rule(make_id(3), "STARBUCKS", make_id(1)))
    |> modal_with_pattern("  ")

  let assert #(cleared, None, NoChange) =
    rule_modal.update(modal, PatternSettled("  "), [])
  match_count_of(cleared) |> should.equal(NotCounted)
}

pub fn the_count_for_the_current_pattern_is_shown_test() {
  let modal = make_edit_modal(make_rule(make_id(3), "STARBUCKS", make_id(1)))
  let matches =
    RuleMatches(count: 2, total: 10, samples: ["Starbucks Ponsonby"])

  modal
  |> send(MatchesCounted("STARBUCKS", Ok(matches)))
  |> match_count_of
  |> should.equal(Counted(pattern: "STARBUCKS", matches:))

  modal
  |> send(MatchesCounted("STARBUCKS", Error(api_error("boom"))))
  |> match_count_of
  |> should.equal(CountFailed("STARBUCKS"))
}

pub fn an_outdated_count_is_ignored_test() {
  let matches = RuleMatches(count: 9, total: 10, samples: [])
  let counting =
    make_create_modal()
    |> modal_with_pattern("COUNT")
    |> send(PatternSettled("COUNT"))
    |> modal_with_pattern("COUNTDOWN")
    |> send(PatternSettled("COUNTDOWN"))

  // A newer count was requested.
  counting
  |> send(MatchesCounted("COUNT", Ok(matches)))
  |> match_count_of
  |> should.equal(Counting("COUNTDOWN"))

  // The pattern changed again before the count arrived.
  counting
  |> modal_with_pattern("COUNTDOWN FUEL")
  |> send(MatchesCounted("COUNTDOWN", Ok(matches)))
  |> match_count_of
  |> should.equal(Counting("COUNTDOWN"))
}

pub fn choosing_transfer_sends_the_transfer_target_without_a_tag_test() {
  let modal = make_create_modal() |> modal_with_pattern("TO SAVINGS")
  let #(modal, _, _) = rule_modal.update(modal, TagChanged("transfer"), [])

  let assert #(_, Some(Save(Post(request))), NoChange) =
    rule_modal.update(modal, SaveRequested, [])
  request |> should.equal(RuleWriteRequest("TO SAVINGS", TransferTarget))
  rule_write_request.to_json(request)
  |> json.to_string
  |> should.equal("{\"pattern\":\"TO SAVINGS\",\"target\":\"Transfer\"}")
}

pub fn editing_a_transfer_rule_keeps_its_target_test() {
  let transfer =
    Rule(id: make_id(5), pattern: "TO SAVINGS", target: TransferTarget)
  let #(modal, _, _) =
    rule_modal.update(rule_modal.hidden(), EditRequested(transfer), [])

  let assert #(_, Some(Save(Put(_, request))), NoChange) =
    rule_modal.update(modal, SaveRequested, [transfer])
  request |> should.equal(RuleWriteRequest("TO SAVINGS", TransferTarget))
}
