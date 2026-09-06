import budgeteur/shared/api_error.{ApiError}
import budgeteur/shared/api_route
import budgeteur/shared/effect
import budgeteur/shared/http_effect
import budgeteur/shared/out_msg.{type OutMsg}
import budgeteur/shared/toast
import budgeteur/tagging_page/rule/rule
import budgeteur/tagging_page/rule/rule_delete_modal
import budgeteur/tagging_page/rule/rule_form
import budgeteur/tagging_page/tag/tag
import budgeteur/tagging_page/tag/tag_delete_modal
import budgeteur/tagging_page/tag/tag_form
import budgeteur/tagging_page/tagging_page
import budgeteur/tagging_page/tagging_page_data.{TaggingPageData}
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

fn empty_model() -> tagging_page.Model {
  tagging_page.Model(
    tags: [],
    rules: [],
    selected_tag: None,
    tag_modal: tag_form.hidden(),
    tag_delete_modal: tag_delete_modal.empty(),
    rule_modal: rule_form.hidden(),
    rule_delete_modal: rule_delete_modal.empty(),
  )
}

fn model_with(tags: List(tag.Tag)) -> tagging_page.Model {
  let selected_tag = case tags {
    [first, ..] -> Some(first.id)
    _ -> None
  }
  tagging_page.Model(..empty_model(), tags:, selected_tag:)
}

/// Apply a page message, keeping only the resulting model.
fn run(model: tagging_page.Model, msg: tagging_page.Msg) -> tagging_page.Model {
  let #(model, _, _) = tagging_page.update(model, msg)
  model
}

pub fn restored_data_sorts_and_selects_first_tag_test() {
  let data =
    TaggingPageData(
      tags: [tag_named(tag_id(2), "Rent"), tag_named(tag_id(1), "Coffee")],
      rules: [],
    )
  let #(new_model, _, _) =
    tagging_page.update(
      empty_model(),
      tagging_page.ClientRestoredData(Some(data)),
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
  let #(_, effect) = tagging_page.init()

  let assert effect.Batch([
    effect.LoadFromStore(key: key, ..),
    effect.HttpRequest(method: method, url: url, ..),
  ]) = effect
  key |> should.equal("budgeteur.tags")
  method |> should.equal(http_effect.Get)
  url |> should.equal(api_route.to_string(api_route.GetTaggingData))
}

pub fn fetched_data_sorts_and_selects_first_tag_test() {
  let data =
    TaggingPageData(
      tags: [tag_named(tag_id(2), "Rent"), tag_named(tag_id(1), "Coffee")],
      rules: [make_rule_for(tag_id(1))],
    )
  let #(new_model, effect, out_msg) =
    tagging_page.update(empty_model(), tagging_page.ClientFetchedData(Ok(data)))

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
    effect.NoEffect,
    effect.SaveToStore(key: key, value: value),
  ]) = effect
  key |> should.equal("budgeteur.tags")
  let assert Ok(round_tripped) =
    json.parse(value, using: tagging_page_data.data_decoder())
  round_tripped
  |> should.equal(TaggingPageData(
    tags: [tag_named(tag_id(1), "Coffee"), tag_named(tag_id(2), "Rent")],
    rules: data.rules,
  ))
}

pub fn fetched_data_error_keeps_local_data_and_toasts_test() {
  let coffee = tag_named(tag_id(1), "Coffee")
  let model =
    tagging_page.Model(
      ..empty_model(),
      tags: [coffee],
      selected_tag: Some(coffee.id),
    )

  let #(new_model, effect, out_msg) =
    tagging_page.update(
      model,
      tagging_page.ClientFetchedData(
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
    tagging_page.Model(
      ..empty_model(),
      tags: [coffee, rent],
      rules: [make_rule_for(coffee.id)],
      selected_tag: Some(coffee.id),
    )

  let #(new_model, _, _) =
    tagging_page.update(model, tagging_page.UserRequestedTagDelete(coffee))
    |> then_confirm

  new_model.tags |> should.equal([rent])
  new_model.rules |> should.equal([])
  new_model.selected_tag |> should.equal(Some(rent.id))
}

pub fn creating_rule_posts_and_appends_to_existing_rules_test() {
  let coffee = tag_named(tag_id(1), "Coffee")
  let existing =
    rule.Rule(..make_rule_for(coffee.id), id: tag_id(7), pattern: "7-ELEVEN")
  let model =
    tagging_page.Model(
      ..empty_model(),
      tags: [coffee],
      rules: [existing],
      selected_tag: Some(coffee.id),
    )

  // Opening the create form seeds the tag select with the selected tag.
  let opened =
    model
    |> run(tagging_page.UserRequestedRuleCreation)
    |> run(tagging_page.RuleFormMsg(rule_form.PatternChanged("STARBUCKS")))
  let #(submitting, submit_effect, _) =
    tagging_page.update(
      opened,
      tagging_page.RuleFormMsg(rule_form.SaveRequested),
    )
  let assert effect.Batch([
    effect.HttpRequest(method: method, timeout: timeout, ..),
  ]) = submit_effect
  method |> should.equal(http_effect.Post)
  timeout |> should.equal(Some(rule_form.submit_timeout_ms))

  let created =
    rule.Rule(id: tag_id(5), pattern: "STARBUCKS", tag_id: coffee.id)
  let #(new_model, _, out_msg) =
    tagging_page.update(
      submitting,
      tagging_page.RuleFormMsg(rule_form.SaveCompleted(Ok(created))),
    )

  // New rules append so insertion order equals rule evaluation order.
  new_model.rules |> should.equal([existing, created])
  new_model.selected_tag |> should.equal(Some(coffee.id))
  new_model.rule_modal |> should.equal(rule_form.hidden())
  let assert Some(out_msg.PageRequestedToast(level: toast.Success, ..)) =
    out_msg
}

pub fn editing_rule_can_move_it_to_another_tag_test() {
  let coffee = tag_named(tag_id(1), "Coffee")
  let rent = tag_named(tag_id(2), "Rent")
  let starbucks = make_rule_for(coffee.id)
  let model =
    tagging_page.Model(
      ..empty_model(),
      tags: [coffee, rent],
      rules: [starbucks],
      selected_tag: Some(coffee.id),
    )

  let opened =
    run(model, tagging_page.UserRequestedRuleEdit(starbucks.id))
    |> run(
      tagging_page.RuleFormMsg(rule_form.TagChanged(uuid.to_string(rent.id))),
    )
  let #(submitting, submit_effect, _) =
    tagging_page.update(
      opened,
      tagging_page.RuleFormMsg(rule_form.SaveRequested),
    )
  let assert effect.Batch([
    effect.HttpRequest(method: method, timeout: timeout, ..),
  ]) = submit_effect
  method |> should.equal(http_effect.Put)
  timeout |> should.equal(Some(rule_form.submit_timeout_ms))

  let moved = rule.Rule(..starbucks, tag_id: rent.id)
  let #(new_model, _, out_msg) =
    tagging_page.update(
      submitting,
      tagging_page.RuleFormMsg(rule_form.SaveCompleted(Ok(moved))),
    )

  new_model.rules |> should.equal([moved])
  new_model.rule_modal |> should.equal(rule_form.hidden())
  let assert Some(out_msg.PageRequestedToast(level: toast.Success, ..)) =
    out_msg
}

pub fn failed_rule_save_logs_error_and_keeps_the_form_open_test() {
  let coffee = tag_named(tag_id(1), "Coffee")
  let starbucks = make_rule_for(coffee.id)
  let model =
    tagging_page.Model(
      ..empty_model(),
      tags: [coffee],
      rules: [starbucks],
      selected_tag: Some(coffee.id),
    )
  let opened = run(model, tagging_page.UserRequestedRuleEdit(starbucks.id))
  let #(submitting, _, _) =
    tagging_page.update(
      opened,
      tagging_page.RuleFormMsg(rule_form.SaveRequested),
    )

  let error =
    ApiError(
      error: "Conflict",
      details: "boom",
      status_code: Some(409),
      request_id: None,
    )
  let #(failed, fail_effect, out_msg) =
    tagging_page.update(
      submitting,
      tagging_page.RuleFormMsg(rule_form.SaveCompleted(Error(error))),
    )

  let assert rule_form.Errored(..) = failed.rule_modal
  failed.rules |> should.equal(model.rules)
  out_msg |> should.equal(None)
  let assert effect.Batch([effect.LogError(_)]) = fail_effect
}

pub fn cancelling_the_rule_form_closes_it_without_changes_test() {
  let coffee = tag_named(tag_id(1), "Coffee")
  let model =
    tagging_page.Model(
      ..empty_model(),
      tags: [coffee],
      selected_tag: Some(coffee.id),
    )
  let opened = run(model, tagging_page.UserRequestedRuleCreation)
  let #(closed, close_effect, _) =
    tagging_page.update(
      opened,
      tagging_page.RuleFormMsg(rule_form.CancelRequested),
    )

  closed.rule_modal |> should.equal(rule_form.hidden())
  closed.rules |> should.equal(model.rules)
  let assert effect.Batch([effect.CloseDialog(_)]) = close_effect
}

pub fn editing_an_unknown_rule_is_a_noop_test() {
  let model = model_with([tag_named(tag_id(1), "Coffee")])

  let #(new_model, noop_effect, _) =
    tagging_page.update(model, tagging_page.UserRequestedRuleEdit(tag_id(9)))

  new_model |> should.equal(model)
  let assert effect.NoEffect = noop_effect
}

// ── Tag form ──────────────────────────────────────────────────────────────────

pub fn creating_tag_inserts_sorts_and_selects_it_test() {
  let coffee = tag_named(tag_id(1), "Coffee")
  let rent = tag_named(tag_id(2), "Rent")

  let named =
    model_with([coffee, rent])
    |> run(tagging_page.UserRequestedTagCreation)
    |> run(tagging_page.TagFormMsg(tag_form.NameChanged("NewTag")))
  let #(submitting, submit_effect, _) =
    tagging_page.update(named, tagging_page.TagFormMsg(tag_form.SaveRequested))
  let assert effect.Batch([
    effect.HttpRequest(method: method, timeout: timeout, ..),
  ]) = submit_effect
  method |> should.equal(http_effect.Post)
  timeout |> should.equal(Some(tag_form.submit_timeout_ms))

  let created = tag_named(tag_id(3), "NewTag")
  let #(new_model, _, out_msg) =
    tagging_page.update(
      submitting,
      tagging_page.TagFormMsg(tag_form.SaveCompleted(Ok(created))),
    )

  new_model.tags |> should.equal([coffee, created, rent])
  new_model.selected_tag |> should.equal(Some(created.id))
  new_model.tag_modal |> should.equal(tag_form.hidden())
  let assert Some(out_msg.PageRequestedToast(level: toast.Success, ..)) =
    out_msg
}

pub fn creating_duplicate_name_surfaces_server_error_inline_test() {
  // The name is new to the client, so validation passes and the POST goes
  // out; the server still rejects it (stale list or lost response retry).
  let model = model_with([tag_named(tag_id(1), "Coffee")])
  let named =
    model
    |> run(tagging_page.UserRequestedTagCreation)
    |> run(tagging_page.TagFormMsg(tag_form.NameChanged("Tea")))
  let #(submitting, submit_effect, _) =
    tagging_page.update(named, tagging_page.TagFormMsg(tag_form.SaveRequested))
  let assert effect.Batch([effect.HttpRequest(method: http_effect.Post, ..)]) =
    submit_effect

  let error =
    ApiError(
      error: "Conflict",
      details: "A tag with the name 'Tea' already exists",
      status_code: Some(409),
      request_id: None,
    )
  let #(failed, fail_effect, out_msg) =
    tagging_page.update(
      submitting,
      tagging_page.TagFormMsg(tag_form.SaveCompleted(Error(error))),
    )

  let assert tag_form.Errored(mode: tag_form.Create, error: details, ..) =
    failed.tag_modal
  details |> should.equal("A tag with the name 'Tea' already exists")
  failed.tags |> should.equal(model.tags)
  out_msg |> should.equal(None)
  let assert effect.Batch([effect.LogError(_)]) = fail_effect
}

pub fn editing_tag_replaces_and_resorts_it_test() {
  let coffee = tag_named(tag_id(1), "Coffee")
  let rent = tag_named(tag_id(2), "Rent")

  // The pre-filled name is valid, so submitting arms PUT with the timeout.
  let opened =
    model_with([coffee, rent])
    |> run(tagging_page.UserRequestedTagEdit(tag_id(2)))
  let #(submitting, submit_effect, _) =
    tagging_page.update(opened, tagging_page.TagFormMsg(tag_form.SaveRequested))
  let assert effect.Batch([
    effect.HttpRequest(method: method, timeout: timeout, ..),
  ]) = submit_effect
  method |> should.equal(http_effect.Put)
  timeout |> should.equal(Some(tag_form.submit_timeout_ms))

  let updated = tag_named(tag_id(2), "AAA")
  let #(new_model, _, out_msg) =
    tagging_page.update(
      submitting,
      tagging_page.TagFormMsg(tag_form.SaveCompleted(Ok(updated))),
    )

  new_model.tags |> should.equal([updated, coffee])
  new_model.selected_tag |> should.equal(Some(coffee.id))
  let assert Some(out_msg.PageRequestedToast(level: toast.Success, ..)) =
    out_msg
}

pub fn failed_save_logs_error_and_keeps_the_form_open_test() {
  let coffee = tag_named(tag_id(1), "Coffee")
  let model = model_with([coffee])
  let opened = run(model, tagging_page.UserRequestedTagEdit(coffee.id))
  let #(submitting, _, _) =
    tagging_page.update(opened, tagging_page.TagFormMsg(tag_form.SaveRequested))

  let error =
    ApiError(
      error: "Conflict",
      details: "boom",
      status_code: Some(409),
      request_id: None,
    )
  let #(failed, fail_effect, out_msg) =
    tagging_page.update(
      submitting,
      tagging_page.TagFormMsg(tag_form.SaveCompleted(Error(error))),
    )

  let assert tag_form.Errored(..) = failed.tag_modal
  failed.tags |> should.equal(model.tags)
  out_msg |> should.equal(None)
  let assert effect.Batch([effect.LogError(_)]) = fail_effect
}

pub fn editing_an_unknown_tag_is_a_noop_test() {
  let model = model_with([tag_named(tag_id(1), "Coffee")])

  let #(new_model, noop_effect, _) =
    tagging_page.update(model, tagging_page.UserRequestedTagEdit(tag_id(9)))

  new_model |> should.equal(model)
  let assert effect.NoEffect = noop_effect
}

pub fn cancelling_the_tag_form_closes_it_without_changes_test() {
  let model = model_with([tag_named(tag_id(1), "Coffee")])
  let opened = run(model, tagging_page.UserRequestedTagCreation)
  let #(closed, close_effect, _) =
    tagging_page.update(
      opened,
      tagging_page.TagFormMsg(tag_form.CancelRequested),
    )

  closed.tag_modal |> should.equal(tag_form.hidden())
  closed.tags |> should.equal(model.tags)
  let assert effect.Batch([effect.CloseDialog(_)]) = close_effect
}

fn then_confirm(
  result: #(tagging_page.Model, effect.Effect(tagging_page.Msg), Option(OutMsg)),
) -> #(tagging_page.Model, effect.Effect(tagging_page.Msg), Option(OutMsg)) {
  let #(model, _, _) = result
  tagging_page.update(model, tagging_page.UserConfirmedTagDelete)
}
