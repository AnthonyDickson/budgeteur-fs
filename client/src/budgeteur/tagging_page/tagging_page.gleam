import budgeteur/shared/api_error.{type ApiError}
import budgeteur/shared/api_route
import budgeteur/shared/delete_modal
import budgeteur/shared/effect.{type Effect}
import budgeteur/shared/form_modal
import budgeteur/shared/out_msg.{type OutMsg}
import budgeteur/shared/remote.{type Remote, Failed, Loaded, Loading}
import budgeteur/shared/response
import budgeteur/tag.{type Tag}
import budgeteur/tagging_page/rule.{type Rule}
import budgeteur/tagging_page/rule_delete_modal
import budgeteur/tagging_page/rule_modal
import budgeteur/tagging_page/rule_view
import budgeteur/tagging_page/rule_write_request
import budgeteur/tagging_page/tag_delete_modal
import budgeteur/tagging_page/tag_modal
import budgeteur/tagging_page/tag_view
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
import lustre/event
import youid/uuid.{type Uuid}

pub type Model {
  Model(
    data: Remote(TaggingPageData),
    selected_tag: Option(Uuid),
    tag_modal: tag_modal.Modal,
    tag_delete_modal: tag_delete_modal.DeleteModalState,
    rule_modal: rule_modal.Modal,
    rule_delete_modal: rule_delete_modal.DeleteModalState,
  )
}

pub type Msg {
  // API responses
  ClientFetchedData(Result(TaggingPageData, ApiError))
  // Retry after a failed first load.
  UserRequestedReload

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
      data: Loading,
      selected_tag: None,
      tag_modal: tag_modal.hidden(),
      tag_delete_modal: tag_delete_modal.empty(),
      rule_modal: rule_modal.hidden(),
      rule_delete_modal: rule_delete_modal.empty(),
    ),
    fetch_page_data(),
  )
}

fn sort_tags(tags: List(Tag)) -> List(Tag) {
  list.sort(tags, by: fn(a, b) { string.compare(a.name, b.name) })
}

/// The loaded tags and rules; empty while loading or after a failed load.
fn loaded(model: Model) -> TaggingPageData {
  remote.unwrap(model.data, or: TaggingPageData(tags: [], rules: []))
}

/// Apply `f` to the loaded tags and rules. No-op unless loaded.
fn map_data(model: Model, f: fn(TaggingPageData) -> TaggingPageData) -> Model {
  Model(..model, data: remote.map(model.data, f))
}

fn first_tag_id(tags: List(Tag)) -> Option(Uuid) {
  list.first(tags)
  |> result.map(fn(tag) { tag.id })
  |> option.from_result
}

pub fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg), Option(OutMsg)) {
  case msg {
    ClientFetchedData(Ok(data)) -> {
      let tags = sort_tags(data.tags)
      let model =
        Model(
          ..model,
          data: Loaded(TaggingPageData(tags:, rules: data.rules)),
          selected_tag: first_tag_id(tags),
        )
      #(model, effect.none(), None)
    }

    ClientFetchedData(Error(error)) ->
      case model.data {
        // A refetch failed (e.g. on returning to the page); the loaded data is
        // still the latest the page has seen.
        Loaded(_) -> #(
          model,
          effect.LogError(api_error.describe(error)),
          Some(out_msg.error_toast(
            "Could not refresh tags and rules",
            "Showing the tags and rules loaded earlier",
          )),
        )
        Loading | Failed -> #(
          Model(..model, data: Failed),
          effect.LogError(api_error.describe(error)),
          None,
        )
      }

    UserRequestedReload -> #(
      Model(..model, data: Loading),
      fetch_page_data(),
      None,
    )

    UserRequestedTagCreation -> run_tag_modal(model, tag_modal.CreateRequested)

    UserRequestedTagEdit(id) -> {
      case list.find(loaded(model).tags, fn(tag) { tag.id == id }) {
        Ok(tag) -> run_tag_modal(model, tag_modal.EditRequested(tag))

        Error(Nil) -> #(model, effect.none(), None)
      }
    }

    TagModalMsg(inner_msg) -> run_tag_modal(model, inner_msg)

    UserRequestedTagDelete(tag) -> {
      let rule_count =
        rule_view.rules_for_tag(tag.id, loaded(model).rules) |> list.length
      #(
        Model(..model, tag_delete_modal: tag_delete_modal.open(tag, rule_count)),
        effect.none(),
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
      case list.find(loaded(model).rules, fn(rule) { rule.id == id }) {
        Ok(rule) -> run_rule_modal(model, rule_modal.EditRequested(rule))
        Error(Nil) -> #(model, effect.none(), None)
      }
    }

    RuleModalMsg(msg) -> run_rule_modal(model, msg)

    UserRequestedRuleDelete(rule, tag_name) -> #(
      Model(..model, rule_delete_modal: rule_delete_modal.open(rule, tag_name)),
      effect.none(),
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
      effect.none(),
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
  let model =
    map_data(model, fn(data) {
      TaggingPageData(
        tags: list.filter(data.tags, fn(t) { t.id != tag.id }),
        rules: list.filter(data.rules, fn(r) { r.tag_id != tag.id }),
      )
    })
  let selected_tag = case model.selected_tag {
    Some(id) if id == tag.id -> first_tag_id(loaded(model).tags)
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
  let model =
    map_data(model, fn(data) {
      TaggingPageData(
        ..data,
        rules: list.filter(data.rules, fn(r) { r.id != rule.id }),
      )
    })
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
    tag_modal.update(model.tag_modal, msg, loaded(model).tags)
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
      let model =
        map_data(model, fn(data) {
          TaggingPageData(..data, tags: [tag, ..data.tags] |> sort_tags)
        })
      let model = Model(..model, selected_tag: Some(tag.id))
      #(model, Some(out_msg.success_toast("Created tag '" <> tag.name <> "'")))
    }
    form_modal.Updated(entity: tag) -> {
      let model =
        map_data(model, fn(data) {
          let tags =
            list.map(data.tags, fn(t) {
              case t.id == tag.id {
                True -> tag
                False -> t
              }
            })
            |> sort_tags
          TaggingPageData(..data, tags:)
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
    rule_modal.update(model.rule_modal, msg, loaded(model).rules)
  let model = Model(..model, rule_modal:)
  let error_effect = case msg {
    rule_modal.SaveCompleted(result: Error(error)) ->
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
      let model =
        map_data(model, fn(data) {
          TaggingPageData(..data, rules: list.append(data.rules, [rule]))
        })
      #(model, Some(out_msg.success_toast("Created rule " <> rule.pattern)))
    }
    form_modal.Updated(entity: rule) -> {
      let model =
        map_data(model, fn(data) {
          let rules =
            list.map(data.rules, fn(r) {
              case r.id == rule.id {
                True -> rule
                False -> r
              }
            })
          TaggingPageData(..data, rules:)
        })
      #(model, Some(out_msg.success_toast("Updated rule " <> rule.pattern)))
    }
  }
}

fn interpret_rule_modal_request(request: rule_modal.Request) -> Effect(Msg) {
  case request {
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
    html.h1([attribute.class("mb-6 text-2xl font-semibold text-gray-900")], [
      html.text("Tags & Rules"),
    ]),
    case model.data {
      Loading -> loading_state()
      Failed -> failed_state()
      Loaded(data) ->
        case list.is_empty(data.tags) {
          True ->
            tag_view.no_tags_empty_state(on_create: UserRequestedTagCreation)
          False -> master_detail(data, model.selected_tag)
        }
    },
    tag_modal.view(model.tag_modal)
      |> element.map(TagModalMsg),
    tag_delete_modal.view(
      model.tag_delete_modal,
      on_cancel: UserCancelledTagDelete,
      on_confirm: UserConfirmedTagDelete,
    ),
    rule_modal.view(model.rule_modal, loaded(model).tags)
      |> element.map(RuleModalMsg),
    rule_delete_modal.view(
      model.rule_delete_modal,
      on_cancel: UserCancelledRuleDelete,
      on_confirm: UserConfirmedRuleDelete,
    ),
  ])
}

fn master_detail(
  data: TaggingPageData,
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
          data.tags,
          selected_tag,
          on_select: UserSelectedTag,
          on_edit: UserRequestedTagEdit,
          on_delete: UserRequestedTagDelete,
          on_create: UserRequestedTagCreation,
        ),
        rule_view.panel(
          data.tags,
          data.rules,
          selected_tag,
          on_create_rule: UserRequestedRuleCreation,
          on_edit_rule: UserRequestedRuleEdit,
          on_delete_rule: UserRequestedRuleDelete,
        ),
      ]),
    ],
  )
}

const primary_button_class = "rounded-md bg-indigo-600 px-4 py-2 text-sm font-medium text-white "
  <> "hover:bg-indigo-500 focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:ring-offset-2"

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
      html.button(
        [
          attribute.class("mt-4 " <> primary_button_class),
          attribute.attribute("data-testid", "tagging-retry"),
          event.on_click(UserRequestedReload),
        ],
        [html.text("Retry")],
      ),
    ],
  )
}
