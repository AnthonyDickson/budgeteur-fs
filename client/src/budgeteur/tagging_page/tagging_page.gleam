import budgeteur/shared/api_error.{type ApiError}
import budgeteur/shared/api_route
import budgeteur/shared/delete_modal
import budgeteur/shared/effect.{type Effect}
import budgeteur/shared/form_modal
import budgeteur/shared/out_msg.{type OutMsg}
import budgeteur/shared/response
import budgeteur/tagging_page/rule/rule.{type Rule}
import budgeteur/tagging_page/rule/rule_delete_modal
import budgeteur/tagging_page/rule/rule_modal
import budgeteur/tagging_page/rule/rule_view
import budgeteur/tagging_page/rule_write_request
import budgeteur/tag.{type Tag}
import budgeteur/tagging_page/tag/tag_delete_modal
import budgeteur/tagging_page/tag/tag_modal
import budgeteur/tagging_page/tag/tag_view
import budgeteur/tagging_page/tag_write_request
import budgeteur/tagging_page/tagging_page_data.{
  type TaggingPageData, TaggingPageData,
}
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import youid/uuid.{type Uuid}

pub type Model {
  Model(
    tags: List(Tag),
    rules: List(Rule),
    selected_tag: Option(Uuid),
    tag_modal: tag_modal.Modal,
    tag_delete_modal: tag_delete_modal.DeleteModalState,
    rule_modal: rule_modal.Modal,
    rule_delete_modal: rule_delete_modal.DeleteModalState,
  )
}

pub type Msg {
  ClientRestoredData(Option(TaggingPageData))
  // API responses
  ClientFetchedData(Result(TaggingPageData, ApiError))

  // Tag modal messages
  UserRequestedTagCreation
  UserRequestedTagEdit(Uuid)
  TagModalMsg(tag_modal.Msg)
  // Tag delete modal messages
  UserRequestedTagDelete(Tag)
  UserConfirmedTagDelete
  UserCancelledTagDelete
  // Server response to a tag delete request. 404 is folded into Ok by the
  // page (the end state matches the user's intent), so this only carries
  // genuine failures.
  ServerDeletedTag(tag: Tag, result: Result(Nil, ApiError))
  // Selection
  UserSelectedTag(Uuid)
  // Rule modal messages
  UserRequestedRuleCreation
  UserRequestedRuleEdit(Uuid)
  RuleModalMsg(rule_modal.Msg)
  // Rule delete modal messages
  UserRequestedRuleDelete(Rule, String)
  UserConfirmedRuleDelete
  UserCancelledRuleDelete
  // Server response to a rule delete request (see ServerDeletedTag).
  ServerDeletedRule(rule: Rule, result: Result(Nil, ApiError))
}

fn persist_data(model: Model) -> Effect(Msg) {
  effect.SaveToStore(
    tagging_page_data.storage_key,
    tagging_page_data.data_to_string(TaggingPageData(
      tags: model.tags,
      rules: model.rules,
    )),
  )
}

fn restore_data_from_store() -> Effect(Msg) {
  effect.LoadFromStore(
    key: tagging_page_data.storage_key,
    callback: fn(store_result) {
      case store_result {
        Ok(value) -> {
          case json.parse(value, using: tagging_page_data.data_decoder()) {
            Ok(data) -> ClientRestoredData(Some(data))
            Error(_) -> ClientRestoredData(None)
          }
        }
        Error(_) -> ClientRestoredData(None)
      }
    },
  )
}

// TODO: See if there's a common pattern among the API request effect helpers and refactor
fn fetch_page_data() -> Effect(Msg) {
  effect.get(api_route.GetTaggingData |> api_route.to_string, fn(result) {
    case result {
      Ok(body) ->
        ClientFetchedData(response.decode_success(
          body,
          tagging_page_data.data_decoder(),
        ))
      Error(http_error) ->
        ClientFetchedData(Error(response.http_error_to_api_error(http_error)))
    }
  })
}

pub fn init() -> #(Model, Effect(Msg)) {
  #(
    Model(
      tags: [],
      rules: [],
      selected_tag: None,
      tag_modal: tag_modal.hidden(),
      tag_delete_modal: tag_delete_modal.empty(),
      rule_modal: rule_modal.hidden(),
      rule_delete_modal: rule_delete_modal.empty(),
    ),
    effect.batch([restore_data_from_store(), fetch_page_data()]),
  )
}

fn sort_tags(tags: List(Tag)) -> List(Tag) {
  list.sort(tags, by: fn(a, b) { string.compare(a.name, b.name) })
}

pub fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg), Option(OutMsg)) {
  let #(new_model, effect, out_msg) = update_inner(model, msg)

  case msg {
    // Restored data came from the store, so don't write it straight back.
    ClientRestoredData(_) -> #(new_model, effect, out_msg)
    _ ->
      case new_model.tags == model.tags && new_model.rules == model.rules {
        True -> #(new_model, effect, out_msg)
        False -> #(
          new_model,
          effect.batch([effect, persist_data(new_model)]),
          out_msg,
        )
      }
  }
}

fn update_inner(
  model: Model,
  msg: Msg,
) -> #(Model, Effect(Msg), Option(OutMsg)) {
  case msg {
    ClientRestoredData(Some(data)) -> {
      let tags = sort_tags(data.tags)
      let selected_tag = case list.first(tags) {
        Ok(tag) -> Some(tag.id)
        Error(Nil) -> None
      }
      #(
        Model(..model, tags:, rules: data.rules, selected_tag:),
        effect.none(),
        None,
      )
    }

    ClientRestoredData(None) -> #(model, effect.none(), None)

    ClientFetchedData(Ok(data)) -> {
      let tags = sort_tags(data.tags)
      let selected_tag =
        list.first(tags)
        |> result.map(fn(tag) { tag.id })
        |> option.from_result

      let model = Model(..model, tags:, rules: data.rules, selected_tag:)
      #(model, effect.none(), None)
    }

    ClientFetchedData(Error(error)) -> #(
      model,
      effect.LogError(api_error.describe(error)),
      Some(out_msg.error_toast(
        "Could not sync tags and rules",
        "Falling back to local data",
      )),
    )

    UserRequestedTagCreation -> run_tag_modal(model, tag_modal.CreateRequested)

    UserRequestedTagEdit(id) -> {
      case list.find(model.tags, fn(tag) { tag.id == id }) {
        Ok(tag) -> run_tag_modal(model, tag_modal.EditRequested(tag))

        Error(Nil) -> #(model, effect.none(), None)
      }
    }

    TagModalMsg(inner_msg) -> run_tag_modal(model, inner_msg)

    UserRequestedTagDelete(tag) -> {
      let rule_count =
        rule_view.rules_for_tag(tag.id, model.rules) |> list.length
      #(
        Model(..model, tag_delete_modal: tag_delete_modal.open(tag, rule_count)),
        effect.ShowDialog(selector: tag_delete_modal.dom_id_selector),
        None,
      )
    }

    UserConfirmedTagDelete -> confirm_tag_delete(model)

    ServerDeletedTag(tag, result) -> {
      case result {
        Ok(_) -> on_tag_delete_succeeded(model, tag)
        Error(error) ->
          case api_error.is_not_found(error) {
            True -> on_tag_delete_succeeded(model, tag)
            False -> on_tag_delete_failed(model, error)
          }
      }
    }

    UserCancelledTagDelete -> #(
      Model(..model, tag_delete_modal: tag_delete_modal.empty()),
      effect.CloseDialog(selector: tag_delete_modal.dom_id_selector),
      None,
    )

    UserSelectedTag(id) -> #(
      Model(..model, selected_tag: Some(id)),
      effect.none(),
      None,
    )

    UserRequestedRuleCreation -> {
      case model.selected_tag {
        Some(tag_id) ->
          run_rule_modal(model, rule_modal.CreateRequested(tag_id))
        None -> #(model, effect.none(), None)
      }
    }

    UserRequestedRuleEdit(id) -> {
      case list.find(model.rules, fn(rule) { rule.id == id }) {
        Ok(rule) -> run_rule_modal(model, rule_modal.EditRequested(rule))
        Error(Nil) -> #(model, effect.none(), None)
      }
    }

    RuleModalMsg(msg) -> run_rule_modal(model, msg)

    UserRequestedRuleDelete(rule, tag_name) -> #(
      Model(..model, rule_delete_modal: rule_delete_modal.open(rule, tag_name)),
      effect.ShowDialog(selector: rule_delete_modal.dom_id_selector),
      None,
    )

    UserConfirmedRuleDelete -> confirm_rule_delete(model)

    ServerDeletedRule(rule, result) -> {
      case result {
        Ok(_) -> on_rule_delete_succeeded(model, rule)
        Error(error) ->
          case api_error.is_not_found(error) {
            True -> on_rule_delete_succeeded(model, rule)
            False -> on_rule_delete_failed(model, error)
          }
      }
    }

    UserCancelledRuleDelete -> #(
      Model(..model, rule_delete_modal: rule_delete_modal.empty()),
      effect.CloseDialog(selector: rule_delete_modal.dom_id_selector),
      None,
    )
  }
}

fn confirm_tag_delete(model: Model) -> #(Model, Effect(Msg), Option(OutMsg)) {
  case delete_modal.confirm(model.tag_delete_modal) {
    Ok(#(state, tag)) -> #(
      Model(..model, tag_delete_modal: state),
      delete_tag(tag),
      None,
    )
    Error(Nil) -> #(model, effect.none(), None)
  }
}

fn delete_tag(tag: Tag) -> Effect(Msg) {
  effect.delete(api_route.DeleteTag(tag.id) |> api_route.to_string, fn(result) {
    case result {
      // A successful delete returns 204 with no body, so there is nothing
      // to decode.
      Ok(_) -> ServerDeletedTag(tag, Ok(Nil))
      Error(http_error) ->
        ServerDeletedTag(
          tag,
          Error(response.http_error_to_api_error(http_error)),
        )
    }
  })
  |> effect.with_timeout(delete_modal.delete_timeout_ms)
}

fn on_tag_delete_succeeded(
  model: Model,
  tag: Tag,
) -> #(Model, Effect(Msg), Option(OutMsg)) {
  let tags = list.filter(model.tags, fn(t) { t.id != tag.id })
  let rules = list.filter(model.rules, fn(r) { r.tag_id != tag.id })
  let selected_tag = case model.selected_tag {
    Some(id) if id == tag.id ->
      case list.first(tags) {
        Ok(t) -> Some(t.id)
        Error(Nil) -> None
      }
    other -> other
  }
  #(
    Model(
      ..model,
      tags:,
      rules:,
      selected_tag:,
      tag_delete_modal: tag_delete_modal.empty(),
    ),
    effect.CloseDialog(selector: tag_delete_modal.dom_id_selector),
    Some(out_msg.success_toast("Deleted tag " <> tag.name)),
  )
}

fn on_tag_delete_failed(
  model: Model,
  error: ApiError,
) -> #(Model, Effect(Msg), Option(OutMsg)) {
  // A response can only arrive while the modal is `Deleting` (the dialog is
  // locked while the request is in flight), so `fail` normally moves it to
  // `Errored` for an inline retry. The unchanged-state check covers a stale
  // response (the modal was reset, e.g. closed and re-opened for another
  // tag), which must not touch the newer session.
  let updated = delete_modal.fail(model.tag_delete_modal, error)
  case updated == model.tag_delete_modal {
    True -> #(model, effect.none(), None)
    False -> #(
      Model(..model, tag_delete_modal: updated),
      effect.LogError(api_error.describe(error)),
      None,
    )
  }
}

fn confirm_rule_delete(model: Model) -> #(Model, Effect(Msg), Option(OutMsg)) {
  case delete_modal.confirm(model.rule_delete_modal) {
    Ok(#(state, rule)) -> #(
      Model(..model, rule_delete_modal: state),
      delete_rule(rule),
      None,
    )
    Error(Nil) -> #(model, effect.none(), None)
  }
}

fn delete_rule(rule: Rule) -> Effect(Msg) {
  effect.delete(
    api_route.DeleteRule(rule.id) |> api_route.to_string,
    fn(result) {
      case result {
        // A successful delete returns 204 with no body, so there is nothing
        // to decode.
        Ok(_) -> ServerDeletedRule(rule, Ok(Nil))
        Error(http_error) ->
          ServerDeletedRule(
            rule,
            Error(response.http_error_to_api_error(http_error)),
          )
      }
    },
  )
  |> effect.with_timeout(delete_modal.delete_timeout_ms)
}

fn on_rule_delete_succeeded(
  model: Model,
  rule: Rule,
) -> #(Model, Effect(Msg), Option(OutMsg)) {
  let rules = list.filter(model.rules, fn(r) { r.id != rule.id })
  #(
    Model(..model, rules:, rule_delete_modal: rule_delete_modal.empty()),
    effect.CloseDialog(selector: rule_delete_modal.dom_id_selector),
    Some(out_msg.success_toast("Deleted rule " <> rule.pattern)),
  )
}

fn on_rule_delete_failed(
  model: Model,
  error: ApiError,
) -> #(Model, Effect(Msg), Option(OutMsg)) {
  // See `on_tag_delete_failed`; the same reasoning applies to rules.
  let updated = delete_modal.fail(model.rule_delete_modal, error)
  case updated == model.rule_delete_modal {
    True -> #(model, effect.none(), None)
    False -> #(
      Model(..model, rule_delete_modal: updated),
      effect.LogError(api_error.describe(error)),
      None,
    )
  }
}

fn run_tag_modal(
  model: Model,
  msg: tag_modal.Msg,
) -> #(Model, Effect(Msg), Option(OutMsg)) {
  let #(tag_modal, requests, outcome) =
    tag_modal.update(model.tag_modal, msg, model.tags)
  let model = Model(..model, tag_modal:)
  let error_effect = case msg {
    tag_modal.SaveCompleted(result: Error(error)) ->
      Some(effect.LogError(api_error.describe(error)))
    _ -> None
  }
  fold_form(
    model,
    requests,
    outcome,
    error_effect,
    apply_tag_outcome,
    interpret_tag_modal_request,
  )
}

fn apply_tag_outcome(
  model: Model,
  outcome: tag_modal.Outcome,
) -> #(Model, Option(OutMsg)) {
  case outcome {
    form_modal.NoChange -> #(model, None)
    form_modal.Created(entity: tag) -> {
      let tags = [tag, ..model.tags] |> sort_tags
      let model = Model(..model, tags:, selected_tag: Some(tag.id))
      #(model, Some(out_msg.success_toast("Created tag '" <> tag.name <> "'")))
    }
    form_modal.Updated(entity: tag) -> {
      let tags =
        list.map(model.tags, fn(t) {
          case t.id == tag.id {
            True -> tag
            False -> t
          }
        })
        |> sort_tags
      let model = Model(..model, tags:)
      #(model, Some(out_msg.success_toast("Updated tag '" <> tag.name <> "'")))
    }
  }
}

fn interpret_tag_modal_request(request: tag_modal.Request) -> Effect(Msg) {
  case request {
    form_modal.ShowDialog ->
      effect.ShowDialog(selector: tag_modal.dom_id_selector)
    form_modal.CloseDialog ->
      effect.CloseDialog(selector: tag_modal.dom_id_selector)
    form_modal.Post(payload) ->
      effect.post(
        api_route.CreateTag |> api_route.to_string,
        tag_write_request.to_json(payload)
          |> json.to_string,
        handle_tag_response,
      )
      |> effect.with_timeout(form_modal.submit_timeout_ms)
      |> effect.map(TagModalMsg)
    form_modal.Put(id:, payload:) ->
      effect.put(
        api_route.UpdateTag(id) |> api_route.to_string,
        tag_write_request.to_json(payload)
          |> json.to_string,
        handle_tag_response,
      )
      |> effect.with_timeout(form_modal.submit_timeout_ms)
      |> effect.map(TagModalMsg)
  }
}

fn handle_tag_response(result) {
  case result {
    Ok(body) ->
      response.decode_success(body, tag.tag_decoder())
      |> tag_modal.SaveCompleted
    Error(http_error) ->
      tag_modal.SaveCompleted(
        Error(response.http_error_to_api_error(http_error)),
      )
  }
}

fn run_rule_modal(
  model: Model,
  msg: rule_modal.Msg,
) -> #(Model, Effect(Msg), Option(OutMsg)) {
  let #(rule_modal, requests, outcome) =
    rule_modal.update(model.rule_modal, msg, model.rules)
  let model = Model(..model, rule_modal:)
  let error_effect = case msg {
    rule_modal.SaveCompleted(result: Error(error)) ->
      Some(effect.LogError(api_error.describe(error)))
    _ -> None
  }
  fold_form(
    model,
    requests,
    outcome,
    error_effect,
    apply_rule_outcome,
    interpret_rule_modal_request,
  )
}

fn apply_rule_outcome(
  model: Model,
  outcome: rule_modal.Outcome,
) -> #(Model, Option(OutMsg)) {
  case outcome {
    form_modal.NoChange -> #(model, None)
    form_modal.Created(entity: rule) -> {
      // New rules append so insertion order equals rule evaluation order.
      let model = Model(..model, rules: list.append(model.rules, [rule]))
      #(model, Some(out_msg.success_toast("Created rule " <> rule.pattern)))
    }
    form_modal.Updated(entity: rule) -> {
      let rules =
        list.map(model.rules, fn(r) {
          case r.id == rule.id {
            True -> rule
            False -> r
          }
        })
      let model = Model(..model, rules:)
      #(model, Some(out_msg.success_toast("Updated rule " <> rule.pattern)))
    }
  }
}

fn interpret_rule_modal_request(request: rule_modal.Request) -> Effect(Msg) {
  case request {
    form_modal.ShowDialog ->
      effect.ShowDialog(selector: rule_modal.dom_id_selector)
    form_modal.CloseDialog ->
      effect.CloseDialog(selector: rule_modal.dom_id_selector)
    form_modal.Post(payload) ->
      effect.post(
        api_route.CreateRule |> api_route.to_string,
        rule_write_request.to_json(payload)
          |> json.to_string,
        handle_rule_response,
      )
      |> effect.with_timeout(form_modal.submit_timeout_ms)
      |> effect.map(RuleModalMsg)
    form_modal.Put(id:, payload:) ->
      effect.put(
        api_route.UpdateRule(id) |> api_route.to_string,
        rule_write_request.to_json(payload)
          |> json.to_string,
        handle_rule_response,
      )
      |> effect.with_timeout(form_modal.submit_timeout_ms)
      |> effect.map(RuleModalMsg)
  }
}

fn handle_rule_response(result) {
  case result {
    Ok(body) ->
      response.decode_success(body, rule.rule_decoder())
      |> rule_modal.SaveCompleted
    Error(http_error) ->
      rule_modal.SaveCompleted(
        Error(response.http_error_to_api_error(http_error)),
      )
  }
}

/// Fold a form's `#(modal, requests, outcome)` triple into page state: store
/// the modal, apply the outcome to the lists (with a toast), turn the requests
/// into effects, and log the API error when the triggering message was a save
/// failure. Shared by the tag and rule slices; the differences are passed in.
fn fold_form(
  model: Model,
  requests: List(request),
  outcome: outcome,
  error_effect: Option(Effect(Msg)),
  apply_outcome: fn(Model, outcome) -> #(Model, Option(OutMsg)),
  interpret: fn(request) -> Effect(Msg),
) -> #(Model, Effect(Msg), Option(OutMsg)) {
  let #(model, out_msg) = apply_outcome(model, outcome)
  let effects = list.map(requests, interpret)
  let effects = case error_effect {
    Some(error_effect) -> [error_effect, ..effects]
    None -> effects
  }
  // A single effect stays unwrapped so the caller's persist batching does not
  // nest one-element batches; several effects are batched.
  let effect = case effects {
    [] -> effect.none()
    [effect] -> effect
    _ -> effect.batch(effects)
  }
  #(model, effect, out_msg)
}

pub fn view(model: Model) -> Element(Msg) {
  html.div([attribute.class("mx-auto max-w-6xl px-4 py-8 sm:px-6")], [
    html.h1([attribute.class("mb-6 text-2xl font-semibold text-gray-900")], [
      html.text("Tags & Rules"),
    ]),
    case list.is_empty(model.tags) {
      True -> tag_view.no_tags_empty_state(on_create: UserRequestedTagCreation)
      False -> master_detail(model)
    },
    tag_modal.view(model.tag_modal)
      |> element.map(TagModalMsg),
    tag_delete_modal.view(
      model.tag_delete_modal,
      on_cancel: UserCancelledTagDelete,
      on_confirm: UserConfirmedTagDelete,
    ),
    rule_modal.view(model.rule_modal, model.tags)
      |> element.map(RuleModalMsg),
    rule_delete_modal.view(
      model.rule_delete_modal,
      on_cancel: UserCancelledRuleDelete,
      on_confirm: UserConfirmedRuleDelete,
    ),
  ])
}

fn master_detail(model: Model) -> Element(Msg) {
  html.div(
    [
      attribute.class(
        "h-[30rem] overflow-hidden rounded-lg border border-gray-200 bg-white shadow-sm",
      ),
    ],
    [
      html.div([attribute.class("flex h-full")], [
        tag_view.panel(
          model.tags,
          model.selected_tag,
          on_select: UserSelectedTag,
          on_edit: UserRequestedTagEdit,
          on_delete: UserRequestedTagDelete,
          on_create: UserRequestedTagCreation,
        ),
        rule_view.panel(
          model.tags,
          model.rules,
          model.selected_tag,
          on_create_rule: UserRequestedRuleCreation,
          on_edit_rule: UserRequestedRuleEdit,
          on_delete_rule: UserRequestedRuleDelete,
        ),
      ]),
    ],
  )
}
