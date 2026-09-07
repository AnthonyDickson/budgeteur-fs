import budgeteur/tagging_page/rule/rule.{type Rule}
import gleam/option.{None, Some}
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

const dom_id = "rule_delete_modal"

/// The CSS selector for the modal dialog element. The `#` hash prefix is
/// composed here so callers (e.g. the show/close dialog effects) never have to
/// remember it.
pub const dom_id_selector = "#" <> dom_id

/// How long a delete request may stay in flight before the transport aborts
/// it. This should be applied by the page via `effect.with_timeout`.
pub const delete_timeout_ms = 10_000

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
  /// A delete request is in flight. The dialog cannot be dismissed and both
  /// buttons are disabled.
  Deleting(rule: Rule, tag_name: String)
  /// The delete request failed. The dialog stays open so the user can retry
  /// in place; the error is shown inline.
  Errored(rule: Rule, tag_name: String, error: String)
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
  let #(rule, tag_name, deleting, error) = case state {
    Hidden -> #(None, "", False, None)
    Confirming(rule:, tag_name:) -> #(Some(rule), tag_name, False, None)
    Deleting(rule:, tag_name:) -> #(Some(rule), tag_name, True, None)
    Errored(rule:, tag_name:, error:) -> #(
      Some(rule),
      tag_name,
      False,
      Some(error),
    )
  }

  // "closedby" = "any" is needed to allow the dialog to be closed by
  // clicking outside the dialog. While a delete is in flight it is "none"
  // so the dialog cannot be dismissed mid-request.
  let closedby_mode = case deleting {
    True -> "none"
    False -> "any"
  }

  html.dialog(
    [
      attribute.id(dom_id),
      attribute.attribute("data-testid", "delete-rule-modal"),
      attribute.class(
        "mx-auto my-auto w-full max-w-md rounded-lg border border-gray-200 bg-white p-6 shadow-xl backdrop:bg-gray-900/50",
      ),
      attribute.attribute("closedby", closedby_mode),
    ],
    case rule {
      None -> []
      Some(rule) -> [
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
        case error {
          Some(message) ->
            html.p(
              [
                attribute.attribute("role", "alert"),
                attribute.attribute("data-testid", "rule-delete-error"),
                attribute.class(
                  "mb-4 rounded-md border border-red-200 bg-red-50 px-3 py-2 text-sm text-red-700",
                ),
              ],
              [html.text("Could not delete rule: " <> message)],
            )
          None -> element.none()
        },
        html.div([attribute.class("flex justify-end gap-3 pt-2")], [
          html.button(
            [
              attribute.type_("button"),
              attribute.attribute("data-testid", "rule-delete-cancel-button"),
              attribute.class(
                "rounded-md border border-gray-300 bg-white px-4 py-2 text-sm font-medium text-gray-700 "
                <> "hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-gray-500 focus:ring-offset-2 "
                <> "disabled:cursor-not-allowed disabled:bg-gray-100 disabled:text-gray-400 disabled:hover:bg-gray-100",
              ),
              attribute.disabled(deleting),
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
                <> "focus:ring-red-500 focus:ring-offset-2 "
                <> "disabled:cursor-not-allowed disabled:bg-gray-400 disabled:hover:bg-gray-400",
              ),
              attribute.disabled(deleting),
              event.on_click(on_confirm),
            ],
            case deleting {
              True -> [
                html.span(
                  [
                    attribute.attribute("aria-hidden", "true"),
                    attribute.class(
                      "h-4 w-4 animate-spin rounded-full border-2 border-white/40 border-t-white",
                    ),
                  ],
                  [],
                ),
                html.text("Deleting..."),
              ]
              False -> [html.text("Delete")]
            },
          ),
        ]),
      ]
    },
  )
}
