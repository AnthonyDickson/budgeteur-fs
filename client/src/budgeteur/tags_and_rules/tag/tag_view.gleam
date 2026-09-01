import budgeteur/tags_and_rules/tag/tag.{type Tag}
import budgeteur/tags_and_rules/ui
import gleam/list
import gleam/option.{type Option, Some}
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import youid/uuid.{type Uuid}

/// The tag sidebar: a selectable list of tags with edit/delete actions for the
/// selected tag, plus a "New tag" button.
pub fn panel(
  tags: List(Tag),
  selected_tag: Option(Uuid),
  on_select on_select: fn(Uuid) -> msg,
  on_edit on_edit: fn(Uuid) -> msg,
  on_delete on_delete: fn(Tag) -> msg,
  on_create on_create: msg,
) -> Element(msg) {
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
        list.map(tags, fn(tag) {
          let is_selected = selected_tag == Some(tag.id)
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
                event.on_click(on_select(tag.id)),
              ],
              [
                ui.color_swatch(tag.color),
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
                            event.on_click(on_edit(tag.id))
                              |> event.stop_propagation,
                          ],
                          [ui.pencil_icon()],
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
                            event.on_click(on_delete(tag))
                              |> event.stop_propagation,
                          ],
                          [ui.trash_icon()],
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
          event.on_click(on_create),
        ],
        [html.text("Create your first tag")],
      ),
    ],
  )
}
