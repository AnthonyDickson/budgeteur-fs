import budgeteur/guard
import budgeteur/tags_and_rules/rule/rule.{type Rule}
import budgeteur/tags_and_rules/tag/tag.{type Tag}
import budgeteur/tags_and_rules/ui
import gleam/list
import gleam/option.{type Option}
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import youid/uuid.{type Uuid}

/// The rules panel for the currently selected tag: its name and swatch, a
/// "New rule" button, and the rule rows with edit/delete actions. When no tag
/// is selected, or the selected tag no longer exists, a prompt is shown
/// instead.
pub fn panel(
  tags: List(Tag),
  rules: List(Rule),
  selected_tag: Option(Uuid),
  on_create_rule on_create_rule: msg,
  on_edit_rule on_edit_rule: fn(Uuid) -> msg,
  on_delete_rule on_delete_rule: fn(Rule, String) -> msg,
) -> Element(msg) {
  use id <- guard.some_lazy(selected_tag, else_return: rules_prompt)
  use selected_tag <- guard.ok_lazy(
    list.find(tags, fn(tag) { tag.id == id }),
    else_return: fn(_) { rules_prompt() },
  )

  let rules = rules_for_tag(id, rules)

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
            ui.color_swatch(selected_tag.color),
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
              event.on_click(on_create_rule),
            ],
            [html.text("New rule")],
          ),
        ],
      ),
      ..case list.is_empty(rules) {
        True -> [rules_empty_state(selected_tag)]
        False -> [
          column_headers(),
          rules_list(rules, selected_tag.name, on_edit_rule, on_delete_rule),
        ]
      }
    ],
  )
}

/// The rules belonging to a tag.
pub fn rules_for_tag(tag_id: Uuid, rules: List(Rule)) -> List(Rule) {
  list.filter(rules, fn(rule) { rule.tag_id == tag_id })
}

fn column_headers() -> Element(msg) {
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

fn rules_list(
  rules: List(Rule),
  tag_name: String,
  on_edit on_edit: fn(Uuid) -> msg,
  on_delete on_delete: fn(Rule, String) -> msg,
) -> Element(msg) {
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
                event.on_click(on_edit(rule.id)),
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
                event.on_click(on_delete(rule, tag_name)),
              ],
              [html.text("Delete")],
            ),
          ]),
        ],
      )
    }),
  )
}

fn rules_prompt() -> Element(msg) {
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

fn rules_empty_state(tag: Tag) -> Element(msg) {
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
