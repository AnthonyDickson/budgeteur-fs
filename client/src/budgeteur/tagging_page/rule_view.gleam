import budgeteur/shared/guard
import budgeteur/shared/tag.{type Tag}
import budgeteur/shared/ui/button
import budgeteur/shared/ui/row
import budgeteur/shared/ui/swatch
import budgeteur/tagging_page/rule.{type Rule}
import gleam/list
import gleam/option.{type Option}
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import youid/uuid.{type Uuid}

/// The rules panel for the currently selected tag: its name and swatch, a
/// "New rule" button, and the rule rows, which open the rule's form. When no tag
/// is selected, or the selected tag no longer exists, a prompt is shown
/// instead.
pub fn panel(
  tags: List(Tag),
  rules: List(Rule),
  selected_tag: Option(Uuid),
  on_create_rule on_create_rule: msg,
  on_edit_rule on_edit_rule: fn(Uuid) -> msg,
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
            "flex h-12 items-center justify-between gap-4 border-b border-border px-4",
          ),
        ],
        [
          html.div([attribute.class("flex items-center gap-2")], [
            html.span(
              [
                attribute.class(
                  "text-xs font-semibold uppercase tracking-wide text-fg-muted",
                ),
              ],
              [html.text("Rules")],
            ),
            swatch.view(selected_tag.color),
            html.h2([attribute.class("text-sm font-semibold text-fg")], [
              html.text(selected_tag.name),
            ]),
          ]),
          button.view(
            button.Primary,
            button.Small,
            [
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
          rules_list(rules, on_edit: on_edit_rule),
        ]
      }
    ],
  )
}

/// The rules belonging to a tag.
pub fn rules_for_tag(tag_id: Uuid, rules: List(Rule)) -> List(Rule) {
  list.filter(rules, rule.targets_tag(_, tag_id))
}

fn column_headers() -> Element(msg) {
  html.div(
    [
      attribute.class(
        "flex items-center gap-3 border-b border-border bg-surface-hover px-4 py-2",
      ),
    ],
    [
      html.span(
        [
          attribute.class(
            "text-xs font-medium uppercase tracking-wide text-fg-muted",
          ),
        ],
        [html.text("Pattern")],
      ),
    ],
  )
}

fn rules_list(
  rules: List(Rule),
  on_edit on_edit: fn(Uuid) -> msg,
) -> Element(msg) {
  html.ul(
    [attribute.class("flex-1 divide-y divide-border overflow-y-auto")],
    list.map(rules, fn(rule) {
      html.li(
        [
          attribute.class(
            "group relative flex h-11 items-center gap-3 px-4 hover:bg-surface-hover",
          ),
          attribute.attribute("data-testid", "rule-row"),
        ],
        [
          html.div([attribute.class("min-w-0 flex-1")], [
            row.open_button(
              testid: "edit-rule-" <> uuid.to_string(rule.id),
              on_click: on_edit(rule.id),
              class: "block max-w-full truncate",
              children: [
                html.code(
                  [
                    attribute.class(
                      "rounded bg-surface-hover px-1.5 py-0.5 text-xs font-medium text-fg",
                    ),
                  ],
                  [html.text(rule.pattern)],
                ),
              ],
            ),
          ]),
          row.chevron(class: ""),
        ],
      )
    }),
  )
}

fn rules_prompt() -> Element(msg) {
  html.div([attribute.class("flex flex-1 flex-col")], [
    html.div([attribute.class("h-12 border-b border-border")], []),
    html.div(
      [
        attribute.class(
          "flex flex-1 items-center justify-center p-8 text-center",
        ),
      ],
      [
        html.p([attribute.class("text-sm text-fg-muted")], [
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
      html.h3([attribute.class("text-sm font-medium text-fg")], [
        html.text("No rules for \"" <> tag.name <> "\" yet"),
      ]),
      html.p([attribute.class("mt-1 max-w-sm text-sm text-fg-muted")], [
        html.text(
          "Rules auto-tag transactions whose description contains a pattern, "
          <> "e.g. \"STARBUCKS\" > Coffee.",
        ),
      ]),
    ],
  )
}
