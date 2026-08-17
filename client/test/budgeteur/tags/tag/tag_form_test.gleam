import budgeteur/tags/tag/tag
import budgeteur/tags/tag/tag_form.{Duplicate, NameRequired, TooLong}
import gleam/string
import gleeunit/should
import youid/uuid

pub fn validate_rejects_duplicate_name_test() {
  let state = tag_form.empty_modal() |> tag_form.set_name("Coffee")
  let error_form = tag_form.validate(state, ["Coffee"]) |> should.be_error
  let assert tag_form.InvalidName(error: Duplicate, ..) = error_form.name
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
  let state = tag_form.empty_modal() |> tag_form.set_name("  Coffee  ")
  let assert Ok(#(name, color)) = tag_form.validate(state, [])
  name |> should.equal("Coffee")
  color |> should.equal(tag_form.default_color)
}

pub fn validate_reports_required_error_for_blank_name_test() {
  let state = tag_form.empty_modal()
  let error_form = tag_form.validate(state, []) |> should.be_error
  let assert tag_form.InvalidName(error: NameRequired, ..) = error_form.name
}

pub fn set_name_records_too_long_error_test() {
  let state =
    tag_form.empty_modal()
    |> tag_form.set_name(string.repeat("a", tag_form.max_name_length + 1))
  let assert tag_form.InvalidName(input: _, error: TooLong) = state.form.name
}
