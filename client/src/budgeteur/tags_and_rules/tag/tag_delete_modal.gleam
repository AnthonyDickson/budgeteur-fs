import budgeteur/tags_and_rules/tag/tag.{type Tag}
import gleam/int
import gleam/option.{None, Some}
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

const dom_id = "tag_delete_modal"

/// The CSS selector for the modal dialog element. The `#` hash prefix is
/// composed here so callers (e.g. the show/close dialog effects) never have to
/// remember it.
pub const dom_id_selector = "#" <> dom_id

/// State of the tag delete confirmation dialog.
///
/// The dialog element is always rendered by `view` so the show/close dialog
/// effects can find it; visibility is driven by effects rather than by adding
/// or removing the element from the DOM (which would reset its state).
pub type DeleteModalState {
  /// Dialog is closed. The dialog element is still rendered, just inert.
  Hidden
  /// Dialog is open, awaiting the user's confirmation. `rule_count` is the
  /// number of rules that belong to the tag and will be deleted with it.
  Confirming(tag: Tag, rule_count: Int)
}

pub fn empty() -> DeleteModalState {
  Hidden
}

/// Open the dialog pre-targeted at an existing tag.
pub fn open(tag: Tag, rule_count: Int) -> DeleteModalState {
  Confirming(tag, rule_count)
}

pub fn view(
  state: DeleteModalState,
  on_cancel on_cancel: msg,
  on_confirm on_confirm: msg,
) -> Element(msg) {
  let #(tag, rule_count) = case state {
    Hidden -> #(None, 0)
    Confirming(tag:, rule_count:) -> #(Some(tag), rule_count)
  }

  html.dialog(
    [
      attribute.id(dom_id),
      attribute.attribute("data-testid", "delete-tag-modal"),
      attribute.class(
        "mx-auto my-auto w-full max-w-md rounded-lg border border-gray-200 bg-white p-6 shadow-xl backdrop:bg-gray-900/50",
      ),
      // "closedby" = "any" is needed to allow the dialog to be closed by
      // clicking outside the dialog.
      attribute.attribute("closedby", "any"),
    ],
    case tag {
      None -> []
      Some(tag) -> [
        html.h2([attribute.class("mb-4 text-lg font-semibold text-gray-900")], [
          html.text("Delete Tag"),
        ]),
        html.p([attribute.class("mb-4 text-sm text-gray-700")], [
          html.text(
            "Are you sure you want to delete "
            <> tag.name
            <> "? This cannot be undone.",
          ),
        ]),
        html.ul(
          [
            attribute.class(
              "mb-4 list-disc space-y-1 pl-5 text-sm text-gray-700",
            ),
          ],
          [
            html.li([], [
              html.text("Transactions tagged with it lose their tag"),
            ]),
            html.li([], [
              html.text(
                "Its "
                <> int.to_string(rule_count)
                <> case rule_count {
                  1 -> " matching rule is"
                  _ -> " matching rules are"
                }
                <> " deleted too",
              ),
            ]),
          ],
        ),
        html.div([attribute.class("flex justify-end gap-3 pt-2")], [
          html.button(
            [
              attribute.type_("button"),
              attribute.attribute("data-testid", "tag-delete-cancel-button"),
              attribute.class(
                "rounded-md border border-gray-300 bg-white px-4 py-2 text-sm font-medium text-gray-700 "
                <> "hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-gray-500 focus:ring-offset-2",
              ),
              event.on_click(on_cancel),
            ],
            [html.text("Cancel")],
          ),
          html.button(
            [
              attribute.type_("button"),
              attribute.attribute("data-testid", "tag-delete-confirm-button"),
              attribute.class(
                "rounded-md bg-red-600 px-4 py-2 text-sm font-medium text-white "
                <> "hover:bg-red-500 focus:outline-none focus:ring-2 "
                <> "focus:ring-red-500 focus:ring-offset-2",
              ),
              event.on_click(on_confirm),
            ],
            [html.text("Delete")],
          ),
        ]),
      ]
    },
  )
}
