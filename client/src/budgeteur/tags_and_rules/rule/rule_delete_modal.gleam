import budgeteur/tags_and_rules/rule/rule.{type Rule}
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

const dom_id = "rule_delete_modal"

/// The CSS selector for the modal dialog element. The `#` hash prefix is
/// composed here so callers (e.g. the show/close dialog effects) never have to
/// remember it.
pub const dom_id_selector = "#" <> dom_id

/// State of the rule delete confirmation dialog.
///
/// The dialog element is always rendered by `view` so the show/close dialog
/// effects can find it; visibility is driven by effects rather than by adding
/// or removing the element from the DOM (which would reset its state).
pub type DeleteModalState {
  /// Dialog is closed. The dialog element is still rendered, just inert.
  Hidden
  /// Dialog is open, awaiting the user's confirmation.
  Confirming(rule: Rule, tag_name: String)
}

pub fn empty() -> DeleteModalState {
  Hidden
}

/// Open the dialog pre-targeted at an existing rule.
pub fn open(rule: Rule, tag_name: String) -> DeleteModalState {
  Confirming(rule:, tag_name:)
}

pub fn view(
  state: DeleteModalState,
  on_cancel on_cancel: msg,
  on_confirm on_confirm: msg,
) -> Element(msg) {
  html.dialog(
    [
      attribute.id(dom_id),
      attribute.attribute("data-testid", "delete-rule-modal"),
      attribute.class(
        "mx-auto my-auto w-full max-w-md rounded-lg border border-gray-200 bg-white p-6 shadow-xl backdrop:bg-gray-900/50",
      ),
      // "closedby" = "any" is needed to allow the dialog to be closed by
      // clicking outside the dialog.
      attribute.attribute("closedby", "any"),
    ],
    case state {
      Hidden -> []
      Confirming(rule:, tag_name:) -> [
        html.h2([attribute.class("mb-4 text-lg font-semibold text-gray-900")], [
          html.text("Delete Rule"),
        ]),
        html.p([attribute.class("mb-4 text-sm text-gray-700")], [
          html.text(
            "Delete rule '" <> rule.pattern <> "'" <> " > " <> tag_name <> "?",
          ),
        ]),
        html.p([attribute.class("mb-4 text-sm text-gray-700")], [
          html.text(
            "Transactions matching this pattern will no longer be auto-tagged. "
            <> "This action cannot be undone.",
          ),
        ]),
        html.div([attribute.class("flex justify-end gap-3 pt-2")], [
          html.button(
            [
              attribute.type_("button"),
              attribute.attribute("data-testid", "rule-delete-cancel-button"),
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
              attribute.attribute("data-testid", "rule-delete-confirm-button"),
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
