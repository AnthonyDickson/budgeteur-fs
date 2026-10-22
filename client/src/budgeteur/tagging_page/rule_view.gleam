import budgeteur/shared/guard
import budgeteur/shared/tag.{type Tag}
import budgeteur/shared/ui/button
import budgeteur/shared/ui/row
import budgeteur/shared/ui/swatch
import budgeteur/tagging_page/rule.{
  type Rule, type Target, TagTarget, TransferTarget,
}
import gleam/list
import gleam/option.{type Option}
import gleam/result
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import youid/uuid.{type Uuid}

/// The rules panel for the current selection: the selected tag's name and swatch,
/// or "Transfers" with a note that transfer rules only suggest, a "New rule"
/// button, and the rule rows, which open the rule's form. When nothing is
/// selected, or the selected tag no longer exists, a prompt is shown instead.
pub fn panel(
  tags: List(Tag),
  rules: List(Rule),
  selected: Option(Target),
  on_create_rule on_create_rule: msg,
  on_edit_rule on_edit_rule: fn(Uuid) -> msg,
) -> Element(msg) {
  use target <- guard.some_lazy(selected, else_return: rules_prompt)
  use selection <- guard.ok_lazy(
    case target {
      TagTarget(tag_id:) ->
        list.find(tags, fn(tag) { tag.id == tag_id })
        |> result.map(SelectedTag)
      TransferTarget -> Ok(SelectedTransfers)
    },
    else_return: fn(_) { rules_prompt() },
  )

  let rules = rules_for(target, rules)

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
            ..selection_heading(selection)
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
      case selection {
        SelectedTransfers -> transfers_note()
        SelectedTag(_) -> element.none()
      },
      ..case list.is_empty(rules) {
        True -> [rules_empty_state(selection)]
        False -> [
          column_headers(),
          rules_list(rules, on_edit: on_edit_rule),
        ]
      }
    ],
  )
}

/// The rules with the target: a tag's rules, or the transfer rules.
pub fn rules_for(target: Target, rules: List(Rule)) -> List(Rule) {
  list.filter(rules, fn(rule) { rule.target == target })
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

fn rules_empty_state(selection: Selection) -> Element(msg) {
  let #(title, body) = case selection {
    SelectedTag(tag) -> #(
      "No rules for \"" <> tag.name <> "\" yet",
      "Rules auto-tag transactions whose description contains a pattern, "
        <> "e.g. \"STARBUCKS\" > Coffee.",
    )
    SelectedTransfers -> #(
      "No transfer rules yet",
      "Transfer rules find transfers between your accounts by a pattern in "
        <> "the description, e.g. \"TRANSFER TO SAVINGS\".",
    )
  }
  html.div(
    [
      attribute.class(
        "flex flex-1 flex-col items-center justify-center px-6 py-10 text-center",
      ),
    ],
    [
      html.h3([attribute.class("text-sm font-medium text-fg")], [
        html.text(title),
      ]),
      html.p([attribute.class("mt-1 max-w-sm text-sm text-fg-muted")], [
        html.text(body),
      ]),
    ],
  )
}

/// The selection, once its tag is found.
type Selection {
  SelectedTag(Tag)
  SelectedTransfers
}

fn selection_heading(selection: Selection) -> List(Element(msg)) {
  let heading = fn(text) {
    html.h2([attribute.class("text-sm font-semibold text-fg")], [
      html.text(text),
    ])
  }
  case selection {
    SelectedTag(tag) -> [swatch.view(tag.color), heading(tag.name)]
    SelectedTransfers -> [heading("Transfers")]
  }
}

/// Transfer rules do not mark transfers: a wrong one would hide money from the
/// income statement and the queue. See decision 3 in docs/transfer-rules.md.
fn transfers_note() -> Element(msg) {
  html.p(
    [
      attribute.class("border-b border-border px-4 py-2 text-xs text-fg-muted"),
      attribute.attribute("data-testid", "transfer-rules-note"),
    ],
    [
      html.text(
        "Transfer rules suggest matching transactions as transfers in quick "
        <> "tagging. They do not mark them until you approve.",
      ),
    ],
  )
}
