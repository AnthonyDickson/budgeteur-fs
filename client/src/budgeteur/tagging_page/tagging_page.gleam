import budgeteur/shared/api_error.{type ApiError}
import budgeteur/shared/api_route
import budgeteur/shared/delete_modal
import budgeteur/shared/effect.{type Effect}
import budgeteur/shared/form_modal
import budgeteur/shared/out_msg.{type OutMsg}
import budgeteur/shared/remote.{type Remote, Failed, Loaded, Loading}
import budgeteur/shared/response
import budgeteur/shared/tag.{type Tag}
import budgeteur/shared/ui/button
import budgeteur/tagging_page/auto_tag
import budgeteur/tagging_page/rule.{type Rule}
import budgeteur/tagging_page/rule_delete_modal
import budgeteur/tagging_page/rule_matches
import budgeteur/tagging_page/rule_modal
import budgeteur/tagging_page/rule_view
import budgeteur/tagging_page/rule_write_request
import budgeteur/tagging_page/tag_delete_modal
import budgeteur/tagging_page/tag_modal
import budgeteur/tagging_page/tag_view
import budgeteur/tagging_page/tag_write_request
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import youid/uuid.{type Uuid}

pub type Model {
  Model(
    /// Sorted by name.
    tags: Remote(List(Tag)),
    /// In evaluation order.
    rules: Remote(List(Rule)),
    selected_tag: Option(Uuid),
    tag_modal: tag_modal.Modal,
    tag_delete_modal: tag_delete_modal.DeleteModalState,
    rule_modal: rule_modal.Modal,
    rule_delete_modal: rule_delete_modal.DeleteModalState,
    auto_tag: auto_tag.Run,
  )
}

pub type Msg {
  // API responses
  ClientFetchedTags(Result(List(Tag), ApiError))
  ClientFetchedRules(Result(List(Rule), ApiError))
  // Retry after a failed first load.
  UserRequestedReload

  // Tag modal messages
  UserRequestedTagCreation
  UserRequestedTagEdit(Uuid)
  TagModalMsg(tag_modal.Msg)
  // Tag delete modal messages. The tag modal's `DeleteRequested` opens it.
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
  // Rule delete modal messages. The rule modal's `DeleteRequested` opens it.
  UserConfirmedRuleDelete
  UserCancelledRuleDelete
  // Server response to a rule delete request (see ServerDeletedTag).
  ServerDeletedRule(rule: Rule, result: Result(Nil, ApiError))
  // Auto-tagging messages
  UserRequestedTagUntagged
  UserRequestedRetag
  UserConfirmedRetag
  UserCancelledRetag
  ServerRanAutoTag(
    action: auto_tag.Action,
    result: Result(auto_tag.Counts, ApiError),
  )
}

// TODO: See if there's a common pattern among the API request effect helpers and refactor
fn fetch_tags() -> Effect(Msg) {
  effect.get(api_route.GetAllTags |> api_route.to_string, fn(result) {
    case result {
      Ok(body) ->
        ClientFetchedTags(response.decode_success(
          body,
          decode.list(tag.tag_decoder()),
        ))
      Error(http_error) ->
        ClientFetchedTags(Error(response.http_error_to_api_error(http_error)))
    }
  })
}

fn fetch_rules() -> Effect(Msg) {
  effect.get(api_route.GetAllRules |> api_route.to_string, fn(result) {
    case result {
      Ok(body) ->
        ClientFetchedRules(response.decode_success(
          body,
          decode.list(rule.rule_decoder()),
        ))
      Error(http_error) ->
        ClientFetchedRules(Error(response.http_error_to_api_error(http_error)))
    }
  })
}

pub fn init() -> #(Model, Effect(Msg)) {
  #(
    Model(
      tags: Loading,
      rules: Loading,
      selected_tag: None,
      tag_modal: tag_modal.hidden(),
      tag_delete_modal: tag_delete_modal.empty(),
      rule_modal: rule_modal.hidden(),
      rule_delete_modal: rule_delete_modal.empty(),
      auto_tag: auto_tag.Idle,
    ),
    effect.batch([fetch_tags(), fetch_rules()]),
  )
}

fn sort_tags(tags: List(Tag)) -> List(Tag) {
  list.sort(tags, by: fn(a, b) { string.compare(a.name, b.name) })
}

/// The loaded tags; empty while loading or after a failed load.
fn loaded_tags(model: Model) -> List(Tag) {
  remote.unwrap(model.tags, or: [])
}

/// The loaded rules; empty while loading or after a failed load.
fn loaded_rules(model: Model) -> List(Rule) {
  remote.unwrap(model.rules, or: [])
}

/// Apply `f` to the loaded tags. No-op unless loaded.
fn map_tags(model: Model, f: fn(List(Tag)) -> List(Tag)) -> Model {
  Model(..model, tags: remote.map(model.tags, f))
}

/// Apply `f` to the loaded rules. No-op unless loaded.
fn map_rules(model: Model, f: fn(List(Rule)) -> List(Rule)) -> Model {
  Model(..model, rules: remote.map(model.rules, f))
}

/// A failed fetch of one list. A refetch (e.g. on returning to the page) keeps
/// the loaded list, still the latest the page has seen, and toasts; a failed
/// first load marks the list `Failed` so the page offers a retry.
fn fetch_failed(
  fetched: Remote(a),
  error: ApiError,
  noun: String,
) -> #(Remote(a), Effect(Msg), Option(OutMsg)) {
  let log = effect.LogError(api_error.describe(error))
  case fetched {
    Loaded(_) -> #(
      fetched,
      log,
      Some(out_msg.error_toast(
        "Could not refresh " <> noun,
        "Showing the " <> noun <> " loaded earlier",
      )),
    )
    Loading | Failed -> #(Failed, log, None)
  }
}

fn first_tag_id(tags: List(Tag)) -> Option(Uuid) {
  list.first(tags)
  |> result.map(fn(tag) { tag.id })
  |> option.from_result
}

pub fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg), Option(OutMsg)) {
  case msg {
    ClientFetchedTags(Ok(tags)) -> {
      let tags = sort_tags(tags)
      let model =
        Model(..model, tags: Loaded(tags), selected_tag: first_tag_id(tags))
      #(model, effect.none(), None)
    }

    ClientFetchedTags(Error(error)) -> {
      let #(tags, effect, out_msg) = fetch_failed(model.tags, error, "tags")
      #(Model(..model, tags:), effect, out_msg)
    }

    ClientFetchedRules(Ok(rules)) -> #(
      Model(..model, rules: Loaded(rules)),
      effect.none(),
      None,
    )

    ClientFetchedRules(Error(error)) -> {
      let #(rules, effect, out_msg) = fetch_failed(model.rules, error, "rules")
      #(Model(..model, rules:), effect, out_msg)
    }

    UserRequestedReload -> #(
      Model(..model, tags: Loading, rules: Loading),
      effect.batch([fetch_tags(), fetch_rules()]),
      None,
    )

    UserRequestedTagCreation -> run_tag_modal(model, tag_modal.CreateRequested)

    UserRequestedTagEdit(id) -> {
      case list.find(loaded_tags(model), fn(tag) { tag.id == id }) {
        Ok(tag) -> run_tag_modal(model, tag_modal.EditRequested(tag))

        Error(Nil) -> #(model, effect.none(), None)
      }
    }

    TagModalMsg(tag_modal.DeleteRequested as inner_msg) ->
      open_tag_delete(model) |> run_tag_modal(inner_msg)

    TagModalMsg(inner_msg) -> run_tag_modal(model, inner_msg)

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
      effect.none(),
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
      case list.find(loaded_rules(model), fn(rule) { rule.id == id }) {
        Ok(rule) -> run_rule_modal(model, rule_modal.EditRequested(rule))
        Error(Nil) -> #(model, effect.none(), None)
      }
    }

    RuleModalMsg(rule_modal.DeleteRequested as msg) ->
      open_rule_delete(model) |> run_rule_modal(msg)

    RuleModalMsg(msg) -> run_rule_modal(model, msg)

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
      effect.none(),
      None,
    )

    UserRequestedTagUntagged ->
      case model.auto_tag {
        auto_tag.Idle -> start_auto_tag(model, auto_tag.TagUntagged)
        auto_tag.ConfirmingRetag | auto_tag.Running(_) -> #(
          model,
          effect.none(),
          None,
        )
      }

    UserRequestedRetag ->
      case model.auto_tag {
        auto_tag.Idle -> #(
          Model(..model, auto_tag: auto_tag.ConfirmingRetag),
          effect.none(),
          None,
        )
        auto_tag.ConfirmingRetag | auto_tag.Running(_) -> #(
          model,
          effect.none(),
          None,
        )
      }

    UserConfirmedRetag ->
      case model.auto_tag {
        auto_tag.ConfirmingRetag -> start_auto_tag(model, auto_tag.Retag)
        auto_tag.Idle | auto_tag.Running(_) -> #(model, effect.none(), None)
      }

    UserCancelledRetag ->
      case model.auto_tag {
        auto_tag.ConfirmingRetag -> #(
          Model(..model, auto_tag: auto_tag.Idle),
          effect.none(),
          None,
        )
        auto_tag.Idle | auto_tag.Running(_) -> #(model, effect.none(), None)
      }

    ServerRanAutoTag(action:, result:) -> {
      // The run happened whatever the page shows now, so its result is always
      // toasted. Only the run it belongs to ends; a response that arrives
      // after the page was re-entered must not close a newer confirmation.
      let model = case model.auto_tag == auto_tag.Running(action) {
        True -> Model(..model, auto_tag: auto_tag.Idle)
        False -> model
      }
      case result {
        Ok(counts) -> #(
          model,
          effect.none(),
          Some(out_msg.success_toast(auto_tag.summary(action, counts))),
        )
        Error(error) -> #(
          model,
          effect.LogError(api_error.describe(error)),
          Some(out_msg.error_toast(
            case action {
              auto_tag.TagUntagged -> "Could not tag untagged transactions"
              auto_tag.Retag -> "Could not re-tag transactions"
            },
            error.details,
          )),
        )
      }
    }
  }
}

fn start_auto_tag(
  model: Model,
  action: auto_tag.Action,
) -> #(Model, Effect(Msg), Option(OutMsg)) {
  #(
    Model(..model, auto_tag: auto_tag.Running(action)),
    run_auto_tag(action),
    None,
  )
}

fn run_auto_tag(action: auto_tag.Action) -> Effect(Msg) {
  effect.post(
    api_route.RunAutoTag |> api_route.to_string,
    auto_tag.to_json(action) |> json.to_string,
    fn(result) {
      case result {
        Ok(body) ->
          ServerRanAutoTag(
            action,
            response.decode_success(body, auto_tag.counts_decoder()),
          )
        Error(http_error) ->
          ServerRanAutoTag(
            action,
            Error(response.http_error_to_api_error(http_error)),
          )
      }
    },
  )
  |> effect.with_timeout(auto_tag.run_timeout_ms)
}

/// The id of the entity an edit dialog is open for, if any.
fn editing_id(modal: form_modal.Modal(form)) -> Result(Uuid, Nil) {
  case form_modal.mode(modal) {
    Some(form_modal.Edit(id:)) -> Ok(id)
    Some(form_modal.Create) | None -> Error(Nil)
  }
}

/// Open the delete confirmation for the tag being edited, with the number of
/// rules deleted with it. The tag modal closes itself on the same message.
fn open_tag_delete(model: Model) -> Model {
  let tag = {
    use id <- result.try(editing_id(model.tag_modal))
    list.find(loaded_tags(model), fn(tag) { tag.id == id })
  }
  case tag {
    Ok(tag) -> {
      let rule_count =
        rule_view.rules_for_tag(tag.id, loaded_rules(model)) |> list.length
      Model(..model, tag_delete_modal: tag_delete_modal.open(tag, rule_count))
    }
    Error(Nil) -> model
  }
}

/// As for tags, for the rule being edited, named with its tag.
fn open_rule_delete(model: Model) -> Model {
  let target = {
    use id <- result.try(editing_id(model.rule_modal))
    use rule <- result.try(
      list.find(loaded_rules(model), fn(rule) { rule.id == id }),
    )
    use tag <- result.map(
      list.find(loaded_tags(model), fn(tag) { tag.id == rule.tag_id }),
    )
    #(rule, tag.name)
  }
  case target {
    Ok(#(rule, tag_name)) ->
      Model(..model, rule_delete_modal: rule_delete_modal.open(rule, tag_name))
    Error(Nil) -> model
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
  let model =
    model
    |> map_tags(list.filter(_, fn(t) { t.id != tag.id }))
    |> map_rules(list.filter(_, fn(r) { r.tag_id != tag.id }))
  let selected_tag = case model.selected_tag {
    Some(id) if id == tag.id -> first_tag_id(loaded_tags(model))
    other -> other
  }
  #(
    Model(..model, selected_tag:, tag_delete_modal: tag_delete_modal.empty()),
    effect.none(),
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
  let model = map_rules(model, list.filter(_, fn(r) { r.id != rule.id }))
  #(
    Model(..model, rule_delete_modal: rule_delete_modal.empty()),
    effect.none(),
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
  let #(tag_modal, request, outcome) =
    tag_modal.update(model.tag_modal, msg, loaded_tags(model))
  let model = Model(..model, tag_modal:)
  let error_effect = case msg {
    tag_modal.SaveCompleted(result: Error(error)) ->
      Some(effect.LogError(api_error.describe(error)))
    _ -> None
  }
  fold_form(
    model,
    request,
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
      let model = map_tags(model, fn(tags) { [tag, ..tags] |> sort_tags })
      let model = Model(..model, selected_tag: Some(tag.id))
      #(model, Some(out_msg.success_toast("Created tag '" <> tag.name <> "'")))
    }
    form_modal.Updated(entity: tag) -> {
      let model =
        map_tags(model, fn(tags) {
          list.map(tags, fn(t) {
            case t.id == tag.id {
              True -> tag
              False -> t
            }
          })
          |> sort_tags
        })
      #(model, Some(out_msg.success_toast("Updated tag '" <> tag.name <> "'")))
    }
  }
}

fn interpret_tag_modal_request(request: tag_modal.Request) -> Effect(Msg) {
  case request {
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
  let #(rule_modal, request, outcome) =
    rule_modal.update(model.rule_modal, msg, loaded_rules(model))
  let model = Model(..model, rule_modal:)
  let error_effect = case msg {
    rule_modal.SaveCompleted(result: Error(error))
    | rule_modal.MatchesCounted(result: Error(error), ..) ->
      Some(effect.LogError(api_error.describe(error)))
    _ -> None
  }
  fold_form(
    model,
    request,
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
      let model = map_rules(model, list.append(_, [rule]))
      #(model, Some(out_msg.success_toast("Created rule " <> rule.pattern)))
    }
    form_modal.Updated(entity: rule) -> {
      let model =
        map_rules(model, fn(rules) {
          list.map(rules, fn(r) {
            case r.id == rule.id {
              True -> rule
              False -> r
            }
          })
        })
      #(model, Some(out_msg.success_toast("Updated rule " <> rule.pattern)))
    }
  }
}

fn interpret_rule_modal_request(request: rule_modal.Request) -> Effect(Msg) {
  case request {
    rule_modal.Save(form_modal.Post(payload)) ->
      effect.post(
        api_route.CreateRule |> api_route.to_string,
        rule_write_request.to_json(payload)
          |> json.to_string,
        handle_rule_response,
      )
      |> effect.with_timeout(form_modal.submit_timeout_ms)
      |> effect.map(RuleModalMsg)
    rule_modal.Save(form_modal.Put(id:, payload:)) ->
      effect.put(
        api_route.UpdateRule(id) |> api_route.to_string,
        rule_write_request.to_json(payload)
          |> json.to_string,
        handle_rule_response,
      )
      |> effect.with_timeout(form_modal.submit_timeout_ms)
      |> effect.map(RuleModalMsg)
    rule_modal.CountMatches(pattern:) ->
      effect.get(
        api_route.GetRuleMatches(pattern) |> api_route.to_string,
        handle_matches_response(pattern, _),
      )
      |> effect.map(RuleModalMsg)
  }
}

fn handle_matches_response(pattern, result) {
  case result {
    Ok(body) ->
      response.decode_success(body, rule_matches.rule_matches_decoder())
      |> rule_modal.MatchesCounted(pattern, _)
    Error(http_error) ->
      rule_modal.MatchesCounted(
        pattern,
        Error(response.http_error_to_api_error(http_error)),
      )
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

/// Fold a form's `#(modal, request, outcome)` triple into page state: store
/// the modal, apply the outcome to the lists (with a toast), turn the request
/// into an effect, and log the API error when the triggering message was a save
/// failure. Shared by the tag and rule slices; the differences are passed in.
fn fold_form(
  model: Model,
  request: Option(request),
  outcome: outcome,
  error_effect: Option(Effect(Msg)),
  apply_outcome: fn(Model, outcome) -> #(Model, Option(OutMsg)),
  interpret: fn(request) -> Effect(Msg),
) -> #(Model, Effect(Msg), Option(OutMsg)) {
  let #(model, out_msg) = apply_outcome(model, outcome)
  let effects = case request {
    Some(request) -> [interpret(request)]
    None -> []
  }
  let effects = case error_effect {
    Some(error_effect) -> [error_effect, ..effects]
    None -> effects
  }
  // A single effect stays unwrapped rather than becoming a one-element batch;
  // several effects are batched.
  let effect = case effects {
    [] -> effect.none()
    [effect] -> effect
    _ -> effect.batch(effects)
  }
  #(model, effect, out_msg)
}

pub fn view(model: Model) -> Element(Msg) {
  html.div([attribute.class("mx-auto max-w-6xl px-4 py-8 sm:px-6")], [
    html.div(
      [
        attribute.class(
          "mb-6 flex flex-wrap items-center justify-between gap-4",
        ),
      ],
      [
        html.h1([attribute.class("text-2xl font-semibold text-gray-900")], [
          html.text("Tags & Rules"),
        ]),
        // Runs apply every rule, not the selected tag's, so the buttons sit
        // in the page header rather than the rules panel. Without tags there is
        // nothing to tag with.
        case remote.both(model.tags, model.rules) {
          Loaded(#([_, ..], _)) -> auto_tag_buttons(model.auto_tag)
          Loaded(_) | Loading | Failed -> element.none()
        },
      ],
    ),
    case remote.both(model.tags, model.rules) {
      Loading -> loading_state()
      Failed -> failed_state()
      Loaded(#(tags, rules)) ->
        case list.is_empty(tags) {
          True ->
            tag_view.no_tags_empty_state(on_create: UserRequestedTagCreation)
          False -> master_detail(tags, rules, model.selected_tag)
        }
    },
    tag_modal.view(model.tag_modal)
      |> element.map(TagModalMsg),
    tag_delete_modal.view(
      model.tag_delete_modal,
      on_cancel: UserCancelledTagDelete,
      on_confirm: UserConfirmedTagDelete,
    ),
    rule_modal.view(model.rule_modal, loaded_tags(model))
      |> element.map(RuleModalMsg),
    rule_delete_modal.view(
      model.rule_delete_modal,
      on_cancel: UserCancelledRuleDelete,
      on_confirm: UserConfirmedRuleDelete,
    ),
    auto_tag.view_retag_confirmation(
      model.auto_tag,
      on_cancel: UserCancelledRetag,
      on_confirm: UserConfirmedRetag,
    ),
  ])
}

/// "Tag untagged" and "Re-tag all", both disabled while a run is in progress.
fn auto_tag_buttons(run: auto_tag.Run) -> Element(Msg) {
  let auto_tag_button = fn(testid, label, busy_label, action, on_click) {
    button.view(
      button.Secondary,
      button.Small,
      [
        attribute.attribute("data-testid", testid),
        attribute.disabled(run != auto_tag.Idle),
        event.on_click(on_click),
      ],
      [
        html.text(case run == auto_tag.Running(action) {
          True -> busy_label
          False -> label
        }),
      ],
    )
  }

  html.div([attribute.class("flex gap-2")], [
    auto_tag_button(
      "tag-untagged-button",
      "Tag untagged",
      "Tagging...",
      auto_tag.TagUntagged,
      UserRequestedTagUntagged,
    ),
    auto_tag_button(
      "retag-all-button",
      "Re-tag all",
      "Re-tagging...",
      auto_tag.Retag,
      UserRequestedRetag,
    ),
  ])
}

fn master_detail(
  tags: List(Tag),
  rules: List(Rule),
  selected_tag: Option(Uuid),
) -> Element(Msg) {
  html.div(
    [
      attribute.class(
        "h-[30rem] overflow-hidden rounded-lg border border-gray-200 bg-white shadow-sm",
      ),
    ],
    [
      html.div([attribute.class("flex h-full")], [
        tag_view.panel(
          tags,
          selected_tag,
          on_select: UserSelectedTag,
          on_edit: UserRequestedTagEdit,
          on_create: UserRequestedTagCreation,
        ),
        rule_view.panel(
          tags,
          rules,
          selected_tag,
          on_create_rule: UserRequestedRuleCreation,
          on_edit_rule: UserRequestedRuleEdit,
        ),
      ]),
    ],
  )
}

fn loading_state() -> Element(Msg) {
  html.div(
    [
      attribute.class(
        "rounded-lg border border-gray-200 bg-white px-6 py-12 text-center shadow-sm",
      ),
      attribute.attribute("data-testid", "tagging-loading-state"),
    ],
    [
      html.p([attribute.class("text-sm text-gray-500")], [
        html.text("Loading tags and rules..."),
      ]),
    ],
  )
}

/// The first load failed; the page offers a retry rather than an indefinite
/// loading state.
fn failed_state() -> Element(Msg) {
  html.div(
    [
      attribute.class(
        "rounded-lg border border-gray-200 bg-white px-6 py-12 text-center shadow-sm",
      ),
      attribute.attribute("data-testid", "tagging-load-error"),
    ],
    [
      html.h2([attribute.class("text-base font-semibold text-gray-900")], [
        html.text("Could not load tags and rules"),
      ]),
      html.p([attribute.class("mt-1 text-sm text-gray-500")], [
        html.text("Check your connection and try again."),
      ]),
      button.view(
        button.Primary,
        button.Regular,
        [
          attribute.class("mt-4"),
          attribute.attribute("data-testid", "tagging-retry"),
          event.on_click(UserRequestedReload),
        ],
        [html.text("Retry")],
      ),
    ],
  )
}
