import budgeteur/shared/api_error.{type ApiError}
import budgeteur/shared/api_route
import budgeteur/shared/effect.{type Effect}
import budgeteur/shared/out_msg.{type OutMsg}
import budgeteur/shared/response
import budgeteur/shared/toast
import budgeteur/tags_and_rules/rule/rule.{type Rule, Rule}
import budgeteur/tags_and_rules/rule/rule_delete_modal
import budgeteur/tags_and_rules/rule/rule_form
import budgeteur/tags_and_rules/rule/rule_view
import budgeteur/tags_and_rules/tag/tag.{type Tag}
import budgeteur/tags_and_rules/tag/tag_delete_modal
import budgeteur/tags_and_rules/tag/tag_form
import budgeteur/tags_and_rules/tag/tag_view
import budgeteur/tags_and_rules/tag_write_request
import budgeteur/tags_and_rules/tags_and_rules_page_data.{
  type TagsAndRulesPageData, TagsAndRulesPageData,
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
    tag_modal: tag_form.Modal,
    tag_delete_modal: tag_delete_modal.DeleteModalState,
    rule_modal: rule_form.ModalState,
    rule_delete_modal: rule_delete_modal.DeleteModalState,
  )
}

pub type Msg {
  ClientRestoredData(Option(TagsAndRulesPageData))
  // API responses
  ClientFetchedData(Result(TagsAndRulesPageData, ApiError))

  // Tag modal messages
  UserRequestedTagCreation
  UserRequestedTagEdit(Uuid)
  TagFormMsg(tag_form.Msg)
  // Tag delete modal messages
  UserRequestedTagDelete(Tag)
  UserConfirmedTagDelete
  UserCancelledTagDelete
  // Selection
  UserSelectedTag(Uuid)
  // Rule modal messages
  UserRequestedRuleCreation
  UserRequestedRuleEdit(Uuid)
  UserUpdatedRulePattern(String)
  UserUpdatedRuleTag(String)
  UserSubmittedRuleForm
  UserCancelledRuleForm
  // Rule delete modal messages
  UserRequestedRuleDelete(Rule, String)
  UserConfirmedRuleDelete
  UserCancelledRuleDelete
}

fn persist_data(model: Model) -> Effect(Msg) {
  effect.SaveToStore(
    tags_and_rules_page_data.storage_key,
    tags_and_rules_page_data.data_to_string(TagsAndRulesPageData(
      tags: model.tags,
      rules: model.rules,
    )),
  )
}

fn restore_data_from_store() -> Effect(Msg) {
  effect.LoadFromStore(
    key: tags_and_rules_page_data.storage_key,
    callback: fn(store_result) {
      case store_result {
        Ok(value) -> {
          case
            json.parse(value, using: tags_and_rules_page_data.data_decoder())
          {
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
  effect.get(api_route.GetTagsAndRules |> api_route.to_string, fn(result) {
    case result {
      Ok(body) ->
        ClientFetchedData(response.decode_success(
          body,
          tags_and_rules_page_data.data_decoder(),
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
      tag_modal: tag_form.hidden(),
      tag_delete_modal: tag_delete_modal.empty(),
      rule_modal: rule_form.create_modal(uuid.nil),
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
      Some(out_msg.PageRequestedToast(
        title: "Could not sync tags and rules",
        body: "Falling back to local data",
        level: toast.Error,
        dismiss_after_ms: Some(5000),
      )),
    )

    UserRequestedTagCreation -> run_tag_form(model, tag_form.CreateRequested)

    UserRequestedTagEdit(id) -> {
      case list.find(model.tags, fn(tag) { tag.id == id }) {
        Ok(tag) -> run_tag_form(model, tag_form.EditRequested(tag))

        Error(Nil) -> #(model, effect.none(), None)
      }
    }

    TagFormMsg(inner_msg) -> run_tag_form(model, inner_msg)

    UserRequestedTagDelete(tag) -> {
      let rule_count =
        rule_view.rules_for_tag(tag.id, model.rules) |> list.length
      #(
        Model(..model, tag_delete_modal: tag_delete_modal.open(tag, rule_count)),
        effect.ShowDialog(selector: tag_delete_modal.dom_id_selector),
        None,
      )
    }

    UserConfirmedTagDelete -> {
      case model.tag_delete_modal {
        tag_delete_modal.Confirming(tag:, ..) -> {
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
            Some(out_msg.PageRequestedToast(
              title: "Success",
              body: "Deleted tag " <> tag.name,
              level: toast.Success,
              dismiss_after_ms: Some(5000),
            )),
          )
        }
        _ -> #(model, effect.none(), None)
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
        Some(tag_id) -> #(
          Model(..model, rule_modal: rule_form.create_modal(tag_id)),
          effect.ShowDialog(selector: rule_form.dom_id_selector),
          None,
        )
        None -> #(model, effect.none(), None)
      }
    }

    UserRequestedRuleEdit(id) -> {
      case list.find(model.rules, fn(rule) { rule.id == id }) {
        Ok(rule) -> #(
          Model(..model, rule_modal: rule_form.edit_modal(rule)),
          effect.ShowDialog(selector: rule_form.dom_id_selector),
          None,
        )
        Error(Nil) -> #(model, effect.none(), None)
      }
    }

    UserUpdatedRulePattern(pattern) -> {
      let rule_modal = rule_form.set_pattern(model.rule_modal, pattern)
      #(Model(..model, rule_modal:), effect.none(), None)
    }

    UserUpdatedRuleTag(tag_id) -> {
      let rule_modal = rule_form.set_tag(model.rule_modal, tag_id)
      #(Model(..model, rule_modal:), effect.none(), None)
    }

    UserSubmittedRuleForm -> {
      let other_patterns =
        model.rules
        |> list.filter(fn(rule) {
          case model.rule_modal.mode {
            rule_form.Edit(id) if rule.id == id -> False
            _ -> True
          }
        })
        |> list.map(fn(rule) { rule.pattern })

      case rule_form.validate(model.rule_modal, other_patterns) {
        Ok(#(pattern, tag_id)) -> {
          case model.rule_modal.mode {
            rule_form.Create -> {
              let new_rule = Rule(id: uuid.v7(), pattern:, tag_id:)
              #(
                Model(
                  ..model,
                  rules: list.append(model.rules, [new_rule]),
                  rule_modal: rule_form.create_modal(tag_id),
                ),
                effect.CloseDialog(selector: rule_form.dom_id_selector),
                Some(out_msg.PageRequestedToast(
                  title: "Success",
                  body: "Created rule " <> pattern,
                  level: toast.Success,
                  dismiss_after_ms: Some(5000),
                )),
              )
            }
            rule_form.Edit(id) -> {
              let rules =
                list.map(model.rules, fn(rule) {
                  case rule.id == id {
                    True -> Rule(..rule, pattern:, tag_id:)
                    False -> rule
                  }
                })
              #(
                Model(
                  ..model,
                  rules:,
                  rule_modal: rule_form.create_modal(tag_id),
                ),
                effect.CloseDialog(selector: rule_form.dom_id_selector),
                Some(out_msg.PageRequestedToast(
                  title: "Success",
                  body: "Updated rule " <> pattern,
                  level: toast.Success,
                  dismiss_after_ms: Some(5000),
                )),
              )
            }
          }
        }
        Error(form) -> #(
          Model(
            ..model,
            rule_modal: rule_form.ModalState(..model.rule_modal, form: form),
          ),
          effect.none(),
          None,
        )
      }
    }

    UserCancelledRuleForm -> #(
      model,
      effect.CloseDialog(selector: rule_form.dom_id_selector),
      None,
    )

    UserRequestedRuleDelete(rule, tag_name) -> #(
      Model(..model, rule_delete_modal: rule_delete_modal.open(rule, tag_name)),
      effect.ShowDialog(selector: rule_delete_modal.dom_id_selector),
      None,
    )

    UserConfirmedRuleDelete -> {
      case model.rule_delete_modal {
        rule_delete_modal.Confirming(rule, _tag_name) -> {
          let rules = list.filter(model.rules, fn(r) { r.id != rule.id })
          #(
            Model(..model, rules:, rule_delete_modal: rule_delete_modal.empty()),
            effect.CloseDialog(selector: rule_delete_modal.dom_id_selector),
            Some(out_msg.PageRequestedToast(
              title: "Success",
              body: "Deleted rule " <> rule.pattern,
              level: toast.Success,
              dismiss_after_ms: Some(5000),
            )),
          )
        }
        _ -> #(model, effect.none(), None)
      }
    }

    UserCancelledRuleDelete -> #(
      Model(..model, rule_delete_modal: rule_delete_modal.empty()),
      effect.CloseDialog(selector: rule_delete_modal.dom_id_selector),
      None,
    )
  }
}

fn run_tag_form(
  model: Model,
  msg: tag_form.Msg,
) -> #(Model, Effect(Msg), Option(OutMsg)) {
  let #(tag_modal, requests, outcome) =
    tag_form.update(model.tag_modal, msg, model.tags)
  let model = Model(..model, tag_modal:)
  apply_tag_form(model, requests, outcome, msg)
}

fn apply_tag_form(
  model: Model,
  requests: List(tag_form.Request),
  outcome: tag_form.Outcome,
  msg: tag_form.Msg,
) -> #(Model, Effect(Msg), Option(OutMsg)) {
  let model = case outcome {
    tag_form.NoChange -> model
    tag_form.Created(tag:) -> {
      let tags = [tag, ..model.tags] |> sort_tags
      Model(..model, tags:, selected_tag: Some(tag.id))
    }
    tag_form.Updated(tag:) -> {
      let tags =
        list.map(model.tags, fn(t) {
          case t.id == tag.id {
            True -> tag
            False -> t
          }
        })
        |> sort_tags
      Model(..model, tags:)
    }
  }

  let effects = interpret_tag_form_requests(requests)
  let effects = case msg {
    tag_form.SaveCompleted(result: Error(error)) -> [
      effect.LogError(api_error.describe(error)),
      ..effects
    ]
    _ -> effects
  }

  let out_msg = case outcome {
    tag_form.NoChange -> None
    tag_form.Created(tag:) ->
      Some(out_msg.PageRequestedToast(
        title: "Success",
        body: "Created tag '" <> tag.name <> "'",
        level: toast.Success,
        dismiss_after_ms: Some(5000),
      ))
    tag_form.Updated(tag:) ->
      Some(out_msg.PageRequestedToast(
        title: "Success",
        body: "Updated tag '" <> tag.name <> "'",
        level: toast.Success,
        dismiss_after_ms: Some(5000),
      ))
  }

  #(model, effect.batch(effects), out_msg)
}

fn interpret_tag_form_requests(requests: List(tag_form.Request)) {
  case requests {
    [] -> []
    [request, ..others] -> [
      interpret_tag_form_request(request),
      ..interpret_tag_form_requests(others)
    ]
  }
}

fn interpret_tag_form_request(request: tag_form.Request) -> Effect(Msg) {
  case request {
    tag_form.ShowDialog -> effect.ShowDialog(tag_form.dom_id_selector)
    tag_form.CloseDialog -> effect.CloseDialog(tag_form.dom_id_selector)
    tag_form.CreateTag(request:) -> {
      effect.post(
        api_route.CreateTag |> api_route.to_string,
        tag_write_request.to_json(request)
          |> json.to_string,
        handle_tag_response,
      )
      |> effect.with_timeout(tag_form.submit_timeout_ms)
      |> effect.map(TagFormMsg)
    }
    tag_form.PutTag(id:, request:) ->
      effect.put(
        api_route.UpdateTag(id) |> api_route.to_string,
        tag_write_request.to_json(request)
          |> json.to_string,
        handle_tag_response,
      )
      |> effect.with_timeout(tag_form.submit_timeout_ms)
      |> effect.map(TagFormMsg)
  }
}

fn handle_tag_response(result) {
  case result {
    Ok(body) ->
      response.decode_success(body, tag.tag_decoder())
      |> tag_form.SaveCompleted
    Error(http_error) ->
      tag_form.SaveCompleted(
        Error(response.http_error_to_api_error(http_error)),
      )
  }
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
    tag_form.view(model.tag_modal)
      |> element.map(TagFormMsg),
    tag_delete_modal.view(
      model.tag_delete_modal,
      on_cancel: UserCancelledTagDelete,
      on_confirm: UserConfirmedTagDelete,
    ),
    rule_form.view(
      model.rule_modal,
      model.tags,
      on_pattern_input: UserUpdatedRulePattern,
      on_tag_change: UserUpdatedRuleTag,
      on_submit: UserSubmittedRuleForm,
      on_cancel: UserCancelledRuleForm,
    ),
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
