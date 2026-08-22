import budgeteur/tags/rule/rule
import budgeteur/tags/rule/rule_form
import gleeunit/should
import youid/uuid

pub fn create_modal_defaults_to_given_tag_test() {
  let assert Ok(tag_id) =
    uuid.from_string("00000000-0000-0000-0000-000000000001")
  let state = rule_form.create_modal(tag_id)
  let assert rule_form.ValidTag(id) = state.form.tag_id
  id |> should.equal(tag_id)
}

pub fn validate_rejects_duplicate_pattern_case_insensitively_test() {
  let assert Ok(tag_id) =
    uuid.from_string("00000000-0000-0000-0000-000000000001")
  let state =
    rule_form.create_modal(tag_id) |> rule_form.set_pattern("STARBUCKS")
  let error_form = rule_form.validate(state, ["starbucks"]) |> should.be_error
  let assert rule_form.InvalidPattern(error: rule_form.Duplicate, ..) =
    error_form.pattern
}

pub fn validate_does_not_count_self_as_duplicate_test() {
  // The page builds `other_patterns` excluding the rule being edited, so the
  // form sees no duplicate when editing keeps the same pattern.
  let assert Ok(id) = uuid.from_string("00000000-0000-0000-0000-000000000001")
  let assert Ok(tag_id) =
    uuid.from_string("00000000-0000-0000-0000-000000000002")
  let existing = rule.Rule(id:, pattern: "STARBUCKS", tag_id:)
  let state = rule_form.edit_modal(existing)
  let assert Ok(#(pattern, _)) = rule_form.validate(state, [])
  pattern |> should.equal("STARBUCKS")
}

pub fn validate_trims_pattern_and_returns_tag_test() {
  let assert Ok(tag_id) =
    uuid.from_string("00000000-0000-0000-0000-000000000001")
  let state =
    rule_form.create_modal(tag_id) |> rule_form.set_pattern("  STARBUCKS  ")
  let assert Ok(#(pattern, id)) = rule_form.validate(state, [])
  pattern |> should.equal("STARBUCKS")
  id |> should.equal(tag_id)
}

pub fn set_tag_with_invalid_value_marks_invalid_test() {
  let assert Ok(tag_id) =
    uuid.from_string("00000000-0000-0000-0000-000000000001")
  let state = rule_form.create_modal(tag_id) |> rule_form.set_tag("not-a-uuid")
  let assert rule_form.InvalidTag = state.form.tag_id
}
