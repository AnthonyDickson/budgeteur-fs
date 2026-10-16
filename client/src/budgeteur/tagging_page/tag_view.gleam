import budgeteur/shared/tag.{type Tag}
import budgeteur/shared/ui/button
import budgeteur/shared/ui/card
import budgeteur/shared/ui/swatch
import budgeteur/tagging_page/icon
import gleam/list
import gleam/option.{type Option, Some}
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import youid/uuid.{type Uuid}

/// The tag sidebar: a selectable list of tags with an edit button on each row,
/// plus a "New tag" button. Clicking a row selects its tag, so unlike other
/// lists the row cannot also open the form; deleting starts from the form.
pub fn panel(
  tags: List(Tag),
  selected_tag: Option(Uuid),
  on_select on_select: fn(Uuid) -> msg,
  on_edit on_edit: fn(Uuid) -> msg,
  on_create on_create: msg,
) -> Element(msg) {
  html.div(
    [
      attribute.class(
        "flex shrink-0 flex-col border-b border-border md:w-72 md:border-r md:border-b-0",
      ),
      attribute.attribute("data-testid", "tags-panel"),
    ],
    [
      html.h2(
        [
          attribute.class(
            "flex h-12 items-center border-b border-border px-4 text-xs font-semibold uppercase tracking-wide text-fg-muted",
          ),
        ],
        [html.text("Tags")],
      ),
      html.ul(
        [attribute.class("flex-1 divide-y divide-border overflow-y-auto")],
        list.map(tags, fn(tag) {
          let is_selected = selected_tag == Some(tag.id)
          html.li([attribute.class("group relative")], [
            html.button(
              [
                attribute.class(
                  "flex h-11 w-full cursor-pointer items-center gap-3 px-4 text-left "
                  <> "focus:outline-none focus:ring-2 focus:ring-inset "
                  <> "focus:ring-primary "
                  <> case is_selected {
                    True -> "border-l-2 border-primary bg-primary-tint"
                    False ->
                      "border-l-2 border-transparent hover:bg-surface-hover"
                  },
                ),
                attribute.attribute(
                  "data-testid",
                  "tag-row-" <> uuid.to_string(tag.id),
                ),
                attribute.attribute("aria-current", case is_selected {
                  True -> "true"
                  False -> "false"
                }),
                event.on_click(on_select(tag.id)),
              ],
              [
                swatch.view(tag.color),
                html.span(
                  [
                    attribute.class(
                      "flex-1 truncate pr-12 text-sm "
                      <> case is_selected {
                        True -> "font-medium text-fg"
                        False -> "text-fg-muted"
                      },
                    ),
                  ],
                  [html.text(tag.name)],
                ),
              ],
            ),
            html.div(
              [
                attribute.class(
                  "absolute inset-y-0 right-0 flex items-center pr-2 "
                  <> "transition-opacity "
                  <> case is_selected {
                    True -> "opacity-100"
                    False ->
                      "opacity-0 focus-within:opacity-100 group-hover:opacity-100"
                  },
                ),
              ],
              [
                html.button(
                  [
                    attribute.class(
                      "flex h-9 w-9 shrink-0 items-center justify-center "
                      <> "rounded-md text-primary hover:bg-primary-tint "
                      <> "focus:outline-none focus:ring-2 focus:ring-inset "
                      <> "focus:ring-primary",
                    ),
                    attribute.attribute(
                      "data-testid",
                      "edit-tag-" <> uuid.to_string(tag.id),
                    ),
                    attribute.aria_label("Edit tag " <> tag.name),
                    event.on_click(on_edit(tag.id))
                      |> event.stop_propagation,
                  ],
                  [icon.pencil()],
                ),
              ],
            ),
          ])
        }),
      ),
      html.div([attribute.class("mt-auto border-t border-border p-3")], [
        html.button(
          [
            attribute.class(
              "w-full rounded-md border border-dashed border-border-input px-3 py-2 "
              <> "text-sm font-medium text-fg-muted hover:border-primary "
              <> "hover:text-primary-hover focus:outline-none focus:ring-2 "
              <> "focus:ring-primary focus:ring-offset-2 focus:ring-offset-surface",
            ),
            attribute.attribute("data-testid", "new-tag-button"),
            event.on_click(on_create),
          ],
          [html.text("+ New tag")],
        ),
      ]),
    ],
  )
}

/// Shown in place of the whole page content when there are no tags yet,
/// prompting the user to create the first one.
pub fn no_tags_empty_state(on_create on_create: msg) -> Element(msg) {
  card.empty_state(
    [
      attribute.class("mx-auto max-w-md"),
      attribute.attribute("data-testid", "no-tags-empty-state"),
    ],
    [
      html.h2([attribute.class("text-base font-semibold text-fg")], [
        html.text("No tags yet"),
      ]),
      html.p([attribute.class("mt-1 text-sm text-fg-muted")], [
        html.text(
          "Tags help you categorise transactions and power auto-tagging rules.",
        ),
      ]),
      button.view(
        button.Primary,
        button.Regular,
        [
          attribute.class("mt-4"),
          attribute.attribute("data-testid", "create-first-tag-button"),
          event.on_click(on_create),
        ],
        [html.text("Create your first tag")],
      ),
    ],
  )
}
