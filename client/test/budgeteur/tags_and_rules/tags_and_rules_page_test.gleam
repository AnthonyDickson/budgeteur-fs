import budgeteur/shared/api_error.{ApiError}
import budgeteur/shared/effect
import budgeteur/shared/http_effect
import budgeteur/shared/out_msg.{type OutMsg}
import budgeteur/shared/toast
import budgeteur/tags_and_rules/rule/rule
import budgeteur/tags_and_rules/rule/rule_delete_modal
import budgeteur/tags_and_rules/rule/rule_form
import budgeteur/tags_and_rules/tag/tag
import budgeteur/tags_and_rules/tag/tag_delete_modal
import budgeteur/tags_and_rules/tag/tag_form
import budgeteur/tags_and_rules/tags_and_rules_page
import budgeteur/tags_and_rules/tags_and_rules_page_data.{TagsAndRulesPageData}
import gleam/int
import gleam/json
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

fn empty_model() -> tags_and_rules_page.Model {
  tags_and_rules_page.Model(
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
    TagsAndRulesPageData(
      tags: [tag_named(tag_id(2), "Rent"), tag_named(tag_id(1), "Coffee")],
      rules: [],
    )
  let #(new_model, _, _) =
    tags_and_rules_page.update(
      empty_model(),
      tags_and_rules_page.ClientRestoredData(Some(data)),
    )

  new_model.tags
  |> should.equal([
    tag_named(tag_id(1), "Coffee"),
    tag_named(tag_id(2), "Rent"),
  ])
  new_model.selected_tag |> should.equal(Some(tag_id(1)))
}

// ── Server sync ────────────────────────────────────────────────────────────────

pub fn init_batches_store_restore_and_fetch_test() {
  let #(_, effect) = tags_and_rules_page.init()

  let assert effect.Batch([
    effect.LoadFromStore(key: key, ..),
    effect.HttpRequest(method: method, url: url, ..),
  ]) = effect
  key |> should.equal("budgeteur.tags")
  method |> should.equal(http_effect.Get)
  url |> should.equal("/api/tags-and-rules")
}

pub fn fetched_data_sorts_and_selects_first_tag_test() {
  let data =
    TagsAndRulesPageData(
      tags: [tag_named(tag_id(2), "Rent"), tag_named(tag_id(1), "Coffee")],
      rules: [make_rule_for(tag_id(1))],
    )
  let #(new_model, effect, out_msg) =
    tags_and_rules_page.update(
      empty_model(),
      tags_and_rules_page.ClientFetchedData(Ok(data)),
    )

  new_model.tags
  |> should.equal([
    tag_named(tag_id(1), "Coffee"),
    tag_named(tag_id(2), "Rent"),
  ])
  new_model.rules |> should.equal(data.rules)
  new_model.selected_tag |> should.equal(Some(tag_id(1)))
  out_msg |> should.equal(None)

  // Fetched data replaces the store so the next reload starts from it.
  let assert effect.Batch([
    effect.None,
    effect.SaveToStore(key: key, value: value),
  ]) = effect
  key |> should.equal("budgeteur.tags")
  let assert Ok(round_tripped) =
    json.parse(value, using: tags_and_rules_page_data.data_decoder())
  round_tripped
  |> should.equal(TagsAndRulesPageData(
    tags: [tag_named(tag_id(1), "Coffee"), tag_named(tag_id(2), "Rent")],
    rules: data.rules,
  ))
}

pub fn fetched_data_error_keeps_local_data_and_toasts_test() {
  let coffee = tag_named(tag_id(1), "Coffee")
  let model =
    tags_and_rules_page.Model(
      ..empty_model(),
      tags: [coffee],
      selected_tag: Some(coffee.id),
    )

  let #(new_model, effect, out_msg) =
    tags_and_rules_page.update(
      model,
      tags_and_rules_page.ClientFetchedData(
        Error(ApiError(
          error: "boom",
          details: "boom",
          status_code: Some(500),
          request_id: None,
        )),
      ),
    )

  new_model |> should.equal(model)
  let assert effect.LogError(_) = effect
  let assert Some(out_msg.PageRequestedToast(level: level, ..)) = out_msg
  level |> should.equal(toast.Error)
}

pub fn deleting_tag_cascades_rules_and_reselects_test() {
  let coffee = tag_named(tag_id(1), "Coffee")
  let rent = tag_named(tag_id(2), "Rent")
  let model =
    tags_and_rules_page.Model(
      ..empty_model(),
      tags: [coffee, rent],
      rules: [make_rule_for(coffee.id)],
      selected_tag: Some(coffee.id),
    )

  let #(new_model, _, _) =
    tags_and_rules_page.update(
      model,
      tags_and_rules_page.UserRequestedTagDelete(coffee),
    )
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
    tags_and_rules_page.Model(
      ..empty_model(),
      tags: [coffee],
      rules: [existing],
      selected_tag: Some(coffee.id),
    )

  let #(opened, _, _) =
    tags_and_rules_page.update(
      model,
      tags_and_rules_page.UserRequestedRuleCreation,
    )
  let #(after_pattern, _, _) =
    tags_and_rules_page.update(
      opened,
      tags_and_rules_page.UserUpdatedRulePattern("STARBUCKS"),
    )
  let #(new_model, _, _) =
    tags_and_rules_page.update(
      after_pattern,
      tags_and_rules_page.UserSubmittedRuleForm,
    )

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
    tags_and_rules_page.Model(
      ..empty_model(),
      tags: [coffee, rent],
      rules: [starbucks],
      selected_tag: Some(coffee.id),
    )

  let #(opened, _, _) =
    tags_and_rules_page.update(
      model,
      tags_and_rules_page.UserRequestedRuleEdit(starbucks.id),
    )
  let #(after_tag, _, _) =
    tags_and_rules_page.update(
      opened,
      tags_and_rules_page.UserUpdatedRuleTag(uuid.to_string(rent.id)),
    )
  let #(new_model, _, _) =
    tags_and_rules_page.update(
      after_tag,
      tags_and_rules_page.UserSubmittedRuleForm,
    )

  let assert [moved] = new_model.rules
  moved.tag_id |> should.equal(rent.id)
}

fn then_confirm(
  result: #(
    tags_and_rules_page.Model,
    effect.Effect(tags_and_rules_page.Msg),
    Option(OutMsg),
  ),
) -> #(
  tags_and_rules_page.Model,
  effect.Effect(tags_and_rules_page.Msg),
  Option(OutMsg),
) {
  let #(model, _, _) = result
  tags_and_rules_page.update(model, tags_and_rules_page.UserConfirmedTagDelete)
}
