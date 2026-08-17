import budgeteur/effect
import budgeteur/out_msg.{type OutMsg}
import budgeteur/tags/rule/rule
import budgeteur/tags/rule/rule_delete_modal
import budgeteur/tags/rule/rule_form
import budgeteur/tags/tag/tag
import budgeteur/tags/tag/tag_delete_modal
import budgeteur/tags/tag/tag_form
import budgeteur/tags/tags_page
import budgeteur/tags/tags_page_data.{TagsPageData}
import gleam/int
import gleam/option.{type Option, None, Some}
import gleeunit/should
import youid/uuid

fn tag_id(n: Int) -> uuid.Uuid {
  let assert Ok(id) =
    uuid.from_string("00000000-0000-0000-0000-00000000000" <> int.to_string(n))
  id
}

fn tag_named(id: uuid.Uuid, name: String) -> tag.Tag {
  tag.Tag(id:, name:, color: "#6366F1")
}

fn make_rule_for(for_tag: uuid.Uuid) -> rule.Rule {
  rule.Rule(id: tag_id(9), pattern: "STARBUCKS", tag_id: for_tag)
}

fn empty_model() -> tags_page.Model {
  tags_page.Model(
    tags: [],
    rules: [],
    selected_tag: None,
    tag_modal: tag_form.empty_modal(),
    tag_delete_modal: tag_delete_modal.empty(),
    rule_modal: rule_form.create_modal(uuid.nil),
    rule_delete_modal: rule_delete_modal.empty(),
  )
}

pub fn restored_data_sorts_and_selects_first_tag_test() {
  let data =
    TagsPageData(
      tags: [tag_named(tag_id(2), "Rent"), tag_named(tag_id(1), "Coffee")],
      rules: [],
    )
  let #(new_model, _, _) =
    tags_page.update(empty_model(), tags_page.ClientRestoredData(Some(data)))

  new_model.tags
  |> should.equal([
    tag_named(tag_id(1), "Coffee"),
    tag_named(tag_id(2), "Rent"),
  ])
  new_model.selected_tag |> should.equal(Some(tag_id(1)))
}

pub fn deleting_tag_cascades_rules_and_reselects_test() {
  let coffee = tag_named(tag_id(1), "Coffee")
  let rent = tag_named(tag_id(2), "Rent")
  let model =
    tags_page.Model(
      ..empty_model(),
      tags: [coffee, rent],
      rules: [make_rule_for(coffee.id)],
      selected_tag: Some(coffee.id),
    )

  let #(new_model, _, _) =
    tags_page.update(model, tags_page.UserRequestedTagDelete(coffee))
    |> then_confirm

  new_model.tags |> should.equal([rent])
  new_model.rules |> should.equal([])
  new_model.selected_tag |> should.equal(Some(rent.id))
}

pub fn creating_rule_appends_to_existing_rules_test() {
  let coffee = tag_named(tag_id(1), "Coffee")
  let existing =
    rule.Rule(..make_rule_for(coffee.id), id: tag_id(7), pattern: "7-ELEVEN")
  let model =
    tags_page.Model(
      ..empty_model(),
      tags: [coffee],
      rules: [existing],
      selected_tag: Some(coffee.id),
    )

  let #(opened, _, _) =
    tags_page.update(model, tags_page.UserRequestedRuleCreation)
  let #(after_pattern, _, _) =
    tags_page.update(opened, tags_page.UserUpdatedRulePattern("STARBUCKS"))
  let #(new_model, _, _) =
    tags_page.update(after_pattern, tags_page.UserSubmittedRuleForm)

  // New rules append so insertion order equals rule evaluation order.
  let assert [existing_kept, created] = new_model.rules
  existing_kept |> should.equal(existing)
  created.pattern |> should.equal("STARBUCKS")
  created.tag_id |> should.equal(coffee.id)
}

pub fn editing_rule_can_move_it_to_another_tag_test() {
  let coffee = tag_named(tag_id(1), "Coffee")
  let rent = tag_named(tag_id(2), "Rent")
  let starbucks = make_rule_for(coffee.id)
  let model =
    tags_page.Model(
      ..empty_model(),
      tags: [coffee, rent],
      rules: [starbucks],
      selected_tag: Some(coffee.id),
    )

  let #(opened, _, _) =
    tags_page.update(model, tags_page.UserRequestedRuleEdit(starbucks.id))
  let #(after_tag, _, _) =
    tags_page.update(
      opened,
      tags_page.UserUpdatedRuleTag(uuid.to_string(rent.id)),
    )
  let #(new_model, _, _) =
    tags_page.update(after_tag, tags_page.UserSubmittedRuleForm)

  let assert [moved] = new_model.rules
  moved.tag_id |> should.equal(rent.id)
}

fn then_confirm(
  result: #(tags_page.Model, effect.Effect(tags_page.Msg), Option(OutMsg)),
) -> #(tags_page.Model, effect.Effect(tags_page.Msg), Option(OutMsg)) {
  let #(model, _, _) = result
  tags_page.update(model, tags_page.UserConfirmedTagDelete)
}
