import budgeteur/effect.{type Effect}
import budgeteur/guard
import budgeteur/out_msg.{type OutMsg}
import budgeteur/tags/rule/rule.{type Rule, Rule}
import budgeteur/tags/rule/rule_delete_modal
import budgeteur/tags/rule/rule_form
import budgeteur/tags/tag/tag.{type Tag, Tag}
import budgeteur/tags/tag/tag_delete_modal
import budgeteur/tags/tag/tag_form
import budgeteur/tags/tags_page_data.{type TagsPageData, TagsPageData}
import budgeteur/toast
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import youid/uuid.{type Uuid}

pub type Model {
  Model(
    tags: List(Tag),
    rules: List(Rule),
    selected_tag: Option(Uuid),
    tag_modal: tag_form.ModalState,
    tag_delete_modal: tag_delete_modal.DeleteModalState,
    rule_modal: rule_form.ModalState,
    rule_delete_modal: rule_delete_modal.DeleteModalState,
  )
}

pub type Msg {
  ClientRestoredData(Option(TagsPageData))
  // Tag modal messages
  UserRequestedTagCreation
  UserRequestedTagEdit(Uuid)
  UserUpdatedTagName(String)
  UserUpdatedTagColor(String)
  UserSubmittedTagForm
  UserCancelledTagForm
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
    tags_page_data.storage_key,
    tags_page_data.data_to_string(TagsPageData(
      tags: model.tags,
      rules: model.rules,
    )),
  )
}

fn restore_data_from_store() -> Effect(Msg) {
  effect.LoadFromStore(
    key: tags_page_data.storage_key,
    callback: fn(store_result) {
      case store_result {
        Ok(value) -> {
          case json.parse(value, using: tags_page_data.data_decoder()) {
            Ok(data) -> ClientRestoredData(Some(data))
            Error(_) -> ClientRestoredData(None)
          }
        }
        Error(_) -> ClientRestoredData(None)
      }
    },
  )
}

pub fn init() -> #(Model, Effect(Msg)) {
  #(
    Model(
      tags: [],
      rules: [],
      selected_tag: None,
      tag_modal: tag_form.empty_modal(),
      tag_delete_modal: tag_delete_modal.empty(),
      rule_modal: rule_form.create_modal(uuid.nil),
      rule_delete_modal: rule_delete_modal.empty(),
    ),
    restore_data_from_store(),
  )
}

fn sort_tags(tags: List(Tag)) -> List(Tag) {
  list.sort(tags, by: fn(a, b) { string.compare(a.name, b.name) })
}

fn rules_for_tag(tag_id: Uuid, rules: List(Rule)) -> List(Rule) {
  list.filter(rules, fn(rule) { rule.tag_id == tag_id })
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

    UserRequestedTagCreation -> #(
      Model(..model, tag_modal: tag_form.empty_modal()),
      effect.ShowDialog(selector: tag_form.dom_id_selector),
      None,
    )

    UserRequestedTagEdit(id) -> {
      case list.find(model.tags, fn(tag) { tag.id == id }) {
        Ok(tag) -> #(
          Model(..model, tag_modal: tag_form.edit_modal(tag)),
          effect.ShowDialog(selector: tag_form.dom_id_selector),
          None,
        )
        Error(Nil) -> #(model, effect.none(), None)
      }
    }

    UserUpdatedTagName(name) -> {
      let tag_modal = tag_form.set_name(model.tag_modal, name)
      #(Model(..model, tag_modal:), effect.none(), None)
    }

    UserUpdatedTagColor(color) -> {
      let tag_modal = tag_form.set_color(model.tag_modal, color)
      #(Model(..model, tag_modal:), effect.none(), None)
    }

    UserSubmittedTagForm -> {
      let other_tag_names =
        model.tags
        |> list.filter(fn(tag) {
          case model.tag_modal.mode {
            tag_form.Edit(id) if tag.id == id -> False
            _ -> True
          }
        })
        |> list.map(fn(tag) { tag.name })

      case tag_form.validate(model.tag_modal, other_tag_names) {
        Ok(#(name, color)) -> {
          case model.tag_modal.mode {
            tag_form.Create -> {
              let new_tag = Tag(id: uuid.v7(), name:, color:)
              let tags = sort_tags([new_tag, ..model.tags])
              #(
                Model(
                  ..model,
                  tags:,
                  selected_tag: Some(new_tag.id),
                  tag_modal: tag_form.empty_modal(),
                ),
                effect.CloseDialog(selector: tag_form.dom_id_selector),
                Some(out_msg.PageRequestedToast(
                  title: "Success",
                  body: "Created tag " <> name,
                  level: toast.Success,
                  dismiss_after_ms: Some(5000),
                )),
              )
            }
            tag_form.Edit(id) -> {
              let tags =
                model.tags
                |> list.map(fn(tag) {
                  case tag.id == id {
                    True -> Tag(..tag, name:, color:)
                    False -> tag
                  }
                })
                |> sort_tags
              #(
                Model(..model, tags:, tag_modal: tag_form.empty_modal()),
                effect.CloseDialog(selector: tag_form.dom_id_selector),
                Some(out_msg.PageRequestedToast(
                  title: "Success",
                  body: "Updated tag " <> name,
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
            tag_modal: tag_form.ModalState(..model.tag_modal, form: form),
          ),
          effect.none(),
          None,
        )
      }
    }

    UserCancelledTagForm -> #(
      model,
      effect.CloseDialog(selector: tag_form.dom_id_selector),
      None,
    )

    UserRequestedTagDelete(tag) -> {
      let rule_count = rules_for_tag(tag.id, model.rules) |> list.length
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

pub fn view(model: Model) -> Element(Msg) {
  html.div([attribute.class("mx-auto max-w-6xl px-4 py-8 sm:px-6")], [
    html.h1([attribute.class("mb-6 text-2xl font-semibold text-gray-900")], [
      html.text("Tags & Rules"),
    ]),
    case list.is_empty(model.tags) {
      True -> no_tags_empty_state()
      False -> master_detail(model)
    },
    tag_form.view(
      model.tag_modal,
      on_name_input: UserUpdatedTagName,
      on_color_click: UserUpdatedTagColor,
      on_submit: UserSubmittedTagForm,
      on_cancel: UserCancelledTagForm,
    ),
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
        tags_panel(model),
        rules_panel(model),
      ]),
    ],
  )
}

fn tags_panel(model: Model) -> Element(Msg) {
  html.div(
    [
      attribute.class("flex w-72 shrink-0 flex-col border-r border-gray-200"),
      attribute.attribute("data-testid", "tags-panel"),
    ],
    [
      html.h2(
        [
          attribute.class(
            "flex h-12 items-center border-b border-gray-200 px-4 text-xs font-semibold uppercase tracking-wide text-gray-500",
          ),
        ],
        [html.text("Tags")],
      ),
      html.ul(
        [attribute.class("flex-1 divide-y divide-gray-100 overflow-y-auto")],
        list.map(model.tags, fn(tag) {
          let is_selected = model.selected_tag == Some(tag.id)
          html.li([], [
            html.div(
              [
                attribute.class(
                  "relative flex h-11 cursor-pointer items-center gap-3 px-4 "
                  <> case is_selected {
                    True -> "border-l-2 border-indigo-600 bg-indigo-50"
                    False -> "border-l-2 border-transparent hover:bg-gray-50"
                  },
                ),
                attribute.attribute(
                  "data-testid",
                  "tag-row-" <> uuid.to_string(tag.id),
                ),
                event.on_click(UserSelectedTag(tag.id)),
              ],
              [
                color_swatch(tag.color),
                html.span(
                  [
                    attribute.class(
                      "flex-1 truncate text-sm "
                      <> case is_selected {
                        True -> "pr-24 font-medium text-gray-900"
                        False -> "text-gray-700"
                      },
                    ),
                  ],
                  [html.text(tag.name)],
                ),
                case is_selected {
                  True ->
                    html.div(
                      [
                        attribute.class(
                          "absolute inset-y-0 right-0 flex items-center gap-1 pr-2",
                        ),
                      ],
                      [
                        html.button(
                          [
                            attribute.class(
                              "flex h-9 w-9 shrink-0 items-center justify-center "
                              <> "rounded-md text-indigo-600 hover:bg-indigo-100 "
                              <> "focus:outline-none focus:ring-2 focus:ring-inset "
                              <> "focus:ring-indigo-500",
                            ),
                            attribute.attribute(
                              "data-testid",
                              "edit-tag-" <> uuid.to_string(tag.id),
                            ),
                            attribute.aria_label("Edit tag " <> tag.name),
                            event.on_click(UserRequestedTagEdit(tag.id))
                              |> event.stop_propagation,
                          ],
                          [pencil_icon()],
                        ),
                        html.button(
                          [
                            attribute.class(
                              "flex h-9 w-9 shrink-0 items-center justify-center "
                              <> "rounded-md text-red-600 hover:bg-red-100 "
                              <> "focus:outline-none focus:ring-2 focus:ring-inset "
                              <> "focus:ring-red-500",
                            ),
                            attribute.attribute(
                              "data-testid",
                              "delete-tag-" <> uuid.to_string(tag.id),
                            ),
                            attribute.aria_label("Delete tag " <> tag.name),
                            event.on_click(UserRequestedTagDelete(tag))
                              |> event.stop_propagation,
                          ],
                          [trash_icon()],
                        ),
                      ],
                    )
                  False -> element.none()
                },
              ],
            ),
          ])
        }),
      ),
      html.div([attribute.class("mt-auto border-t border-gray-200 p-3")], [
        html.button(
          [
            attribute.class(
              "w-full rounded-md border border-dashed border-gray-300 px-3 py-2 "
              <> "text-sm font-medium text-gray-600 hover:border-indigo-400 "
              <> "hover:text-indigo-600 focus:outline-none focus:ring-2 "
              <> "focus:ring-indigo-500 focus:ring-offset-2",
            ),
            attribute.attribute("data-testid", "new-tag-button"),
            event.on_click(UserRequestedTagCreation),
          ],
          [html.text("+ New tag")],
        ),
      ]),
    ],
  )
}

fn rules_panel(model: Model) -> Element(Msg) {
  use id <- guard.some_lazy(model.selected_tag, else_return: rules_prompt)
  use selected_tag <- guard.ok_lazy(
    list.find(model.tags, fn(tag) { tag.id == id }),
    else_return: fn(_) { rules_prompt() },
  )

  let rules = rules_for_tag(id, model.rules)

  html.div(
    [
      attribute.class("flex flex-1 flex-col"),
      attribute.attribute("data-testid", "rules-panel"),
    ],
    [
      html.div(
        [
          attribute.class(
            "flex h-12 items-center justify-between gap-4 border-b border-gray-200 px-4",
          ),
        ],
        [
          html.div([attribute.class("flex items-center gap-2")], [
            html.span(
              [
                attribute.class(
                  "text-xs font-semibold uppercase tracking-wide text-gray-500",
                ),
              ],
              [html.text("Rules")],
            ),
            color_swatch(selected_tag.color),
            html.h2([attribute.class("text-sm font-semibold text-gray-900")], [
              html.text(selected_tag.name),
            ]),
          ]),
          html.button(
            [
              attribute.class(
                "rounded-md bg-indigo-600 px-3 py-1.5 text-sm font-medium "
                <> "text-white hover:bg-indigo-500 focus:outline-none "
                <> "focus:ring-2 focus:ring-indigo-500 focus:ring-offset-2",
              ),
              attribute.attribute("data-testid", "new-rule-button"),
              event.on_click(UserRequestedRuleCreation),
            ],
            [html.text("New rule")],
          ),
        ],
      ),
      ..case list.is_empty(rules) {
        True -> [rules_empty_state(selected_tag)]
        False -> [
          column_headers(),
          rules_list(rules, selected_tag.name),
        ]
      }
    ],
  )
}

fn column_headers() -> Element(Msg) {
  html.div(
    [
      attribute.class(
        "flex items-center gap-3 border-b border-gray-200 bg-gray-50 px-4 py-2",
      ),
    ],
    [
      html.span(
        [
          attribute.class(
            "text-xs font-medium uppercase tracking-wide text-gray-500",
          ),
        ],
        [html.text("Pattern")],
      ),
      html.span(
        [
          attribute.class(
            "ml-auto text-xs font-medium uppercase tracking-wide text-gray-500",
          ),
        ],
        [html.text("Actions")],
      ),
    ],
  )
}

fn rules_list(rules: List(Rule), tag_name: String) -> Element(Msg) {
  html.ul(
    [attribute.class("flex-1 divide-y divide-gray-100 overflow-y-auto")],
    list.map(rules, fn(rule) {
      html.li(
        [
          attribute.class("flex h-11 items-center gap-3 px-4 hover:bg-gray-50"),
          attribute.attribute("data-testid", "rule-row"),
        ],
        [
          html.code(
            [
              attribute.class(
                "rounded bg-gray-100 px-1.5 py-0.5 text-xs font-medium text-gray-800",
              ),
            ],
            [html.text(rule.pattern)],
          ),
          html.div([attribute.class("ml-auto flex items-center gap-2")], [
            html.button(
              [
                attribute.class(
                  "rounded-md px-3 py-1 text-sm font-medium text-indigo-600 "
                  <> "hover:bg-indigo-50 hover:text-indigo-700 "
                  <> "focus:outline-none focus:ring-2 focus:ring-indigo-500 "
                  <> "focus:ring-offset-2",
                ),
                attribute.attribute(
                  "data-testid",
                  "edit-rule-" <> uuid.to_string(rule.id),
                ),
                event.on_click(UserRequestedRuleEdit(rule.id)),
              ],
              [html.text("Edit")],
            ),
            html.button(
              [
                attribute.class(
                  "rounded-md px-3 py-1 text-sm font-medium text-red-600 "
                  <> "hover:bg-red-50 hover:text-red-700 "
                  <> "focus:outline-none focus:ring-2 focus:ring-red-500 "
                  <> "focus:ring-offset-2",
                ),
                attribute.attribute(
                  "data-testid",
                  "delete-rule-" <> uuid.to_string(rule.id),
                ),
                event.on_click(UserRequestedRuleDelete(rule, tag_name)),
              ],
              [html.text("Delete")],
            ),
          ]),
        ],
      )
    }),
  )
}

fn rules_prompt() -> Element(Msg) {
  html.div([attribute.class("flex flex-1 flex-col")], [
    html.div([attribute.class("h-12 border-b border-gray-200")], []),
    html.div(
      [
        attribute.class(
          "flex flex-1 items-center justify-center p-8 text-center",
        ),
      ],
      [
        html.p([attribute.class("text-sm text-gray-500")], [
          html.text("Select a tag to see its rules"),
        ]),
      ],
    ),
  ])
}

fn rules_empty_state(tag: Tag) -> Element(Msg) {
  html.div(
    [
      attribute.class(
        "flex flex-1 flex-col items-center justify-center px-6 py-10 text-center",
      ),
    ],
    [
      html.h3([attribute.class("text-sm font-medium text-gray-900")], [
        html.text("No rules for \"" <> tag.name <> "\" yet"),
      ]),
      html.p([attribute.class("mt-1 max-w-sm text-sm text-gray-500")], [
        html.text(
          "Rules auto-tag transactions whose description contains a pattern, "
          <> "e.g. \"STARBUCKS\" > Coffee.",
        ),
      ]),
    ],
  )
}

fn no_tags_empty_state() -> Element(Msg) {
  html.div(
    [
      attribute.class(
        "mx-auto max-w-md rounded-lg border border-gray-200 bg-white px-6 py-12 text-center shadow-sm",
      ),
      attribute.attribute("data-testid", "no-tags-empty-state"),
    ],
    [
      html.h2([attribute.class("text-base font-semibold text-gray-900")], [
        html.text("No tags yet"),
      ]),
      html.p([attribute.class("mt-1 text-sm text-gray-500")], [
        html.text(
          "Tags help you categorise transactions and power auto-tagging rules.",
        ),
      ]),
      html.button(
        [
          attribute.class(
            "mt-4 rounded-md bg-indigo-600 px-4 py-2 text-sm font-medium text-white "
            <> "hover:bg-indigo-500 focus:outline-none focus:ring-2 "
            <> "focus:ring-indigo-500 focus:ring-offset-2",
          ),
          attribute.attribute("data-testid", "create-first-tag-button"),
          event.on_click(UserRequestedTagCreation),
        ],
        [html.text("Create your first tag")],
      ),
    ],
  )
}

fn color_swatch(color: String) -> Element(Msg) {
  html.span(
    [
      attribute.class("inline-block h-3 w-3 shrink-0 rounded-full"),
      attribute.style("background-color", color),
      attribute.attribute("aria-hidden", "true"),
    ],
    [],
  )
}

fn svg_icon(path_d: String) -> Element(msg) {
  html.svg(
    [
      attribute.attribute("fill", "none"),
      attribute.attribute("viewBox", "0 0 24 24"),
      attribute.attribute("stroke-width", "1.5"),
      attribute.attribute("stroke", "currentColor"),
      attribute.class("h-4 w-4"),
      attribute.attribute("aria-hidden", "true"),
    ],
    [
      element.namespaced(
        "http://www.w3.org/2000/svg",
        "path",
        [
          attribute.attribute("stroke-linecap", "round"),
          attribute.attribute("stroke-linejoin", "round"),
          attribute.attribute("d", path_d),
        ],
        [],
      ),
    ],
  )
}

fn pencil_icon() -> Element(Msg) {
  svg_icon(
    "m16.862 4.487 1.687-1.688a1.875 1.875 0 1 1 2.652 2.652L10.582 16.07a4.5 4.5 0 0 1-1.897 1.13L6 18l.8-2.685a4.5 4.5 0 0 1 1.13-1.897l8.932-8.931Zm0 0L19.5 7.125M18 14v4.75A2.25 2.25 0 0 1 15.75 21H5.25A2.25 2.25 0 0 1 3 18.75V8.25A2.25 2.25 0 0 1 5.25 6H10",
  )
}

fn trash_icon() -> Element(Msg) {
  svg_icon(
    "m14.74 9-.346 9m-4.788 0L9.26 9m9.968-3.21c.342.052.682.107 1.022.166m-1.022-.165L18.16 19.673a2.25 2.25 0 0 1-2.244 2.077H8.084a2.25 2.25 0 0 1-2.244-2.077L4.772 5.79m14.456 0a48.108 48.108 0 0 0-3.478-.397m-12 .562c.34-.059.68-.114 1.022-.165m0 0a48.11 48.11 0 0 1 3.478-.397m7.5 0v-.916c0-1.18-.91-2.164-2.09-2.201a51.964 51.964 0 0 0-3.32 0c-1.18.037-2.09 1.022-2.09 2.201v.916m7.5 0a48.667 48.667 0 0 0-7.5 0",
  )
}
