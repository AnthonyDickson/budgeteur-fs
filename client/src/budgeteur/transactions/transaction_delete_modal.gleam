import budgeteur/money
import budgeteur/transactions/transaction.{type Transaction}
import gleam/option.{None, Some}
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

const dom_id = "transaction_delete_modal"

/// The CSS selector for the modal dialog element. The `#` hash prefix is
/// composed here so callers (e.g. the show/close dialog effects) never have to
/// remember it.
pub const dom_id_selector = "#" <> dom_id

/// State of the transaction delete confirmation dialog.
///
/// The dialog element is always rendered by `view` so the show/close dialog
/// effects can find it; visibility is driven by effects rather than by adding
/// or removing the element from the DOM (which would reset its state).
///
/// The lifecycle is encoded in the variants so illegal states (e.g. "deleting"
/// without a target transaction) are unrepresentable.
///
/// Deliberate tradeoff: the DOM dialog can be dismissed without a Msg (Escape
/// key, or `closedby="any"` outside-click), so the state here can drift out of
/// sync with what is on screen. We accept this because any stale state is
/// benign: `open` overwrites the state on the next Delete click, and the
/// caller only ever re-shows the dialog by going through `open`. We do not
/// listen for the dialog's `cancel`/`close` events to keep the state in sync,
/// as that would add machinery to fix a state that self-heals.
pub type DeleteModalState {
  /// Dialog is closed. The dialog element is still rendered, just inert.
  Hidden
  /// Dialog is open, awaiting the user's confirmation.
  Confirming(transaction: Transaction)
  /// A delete request is in flight; the buttons are disabled.
  Deleting(transaction: Transaction)
}

pub fn empty() -> DeleteModalState {
  Hidden
}

/// Open the dialog pre-targeted at an existing transaction.
pub fn open(transaction: Transaction) -> DeleteModalState {
  Confirming(transaction)
}

pub fn view(
  state: DeleteModalState,
  on_cancel on_cancel: msg,
  on_confirm on_confirm: msg,
) -> Element(msg) {
  let #(transaction, deleting) = case state {
    Hidden -> #(None, False)
    Confirming(transaction) -> #(Some(transaction), False)
    Deleting(transaction) -> #(Some(transaction), True)
  }

  html.dialog(
    [
      attribute.id(dom_id),
      attribute.attribute("data-testid", "delete-transaction-modal"),
      attribute.class(
        "mx-auto my-auto w-full max-w-md rounded-lg border border-gray-200 bg-white p-6 shadow-xl backdrop:bg-gray-900/50",
      ),
      // "closedby" = "any" is needed to allow the dialog to be closed by
      // clicking outside the dialog.
      attribute.attribute("closedby", "any"),
    ],
    case transaction {
      None -> []
      Some(transaction) -> {
        let formatted_amount = transaction.amount |> money.format

        [
          html.h2(
            [attribute.class("mb-4 text-lg font-semibold text-gray-900")],
            [
              html.text("Delete Transaction"),
            ],
          ),
          html.p([attribute.class("mb-4 text-sm text-gray-700")], [
            html.text(
              "Are you sure you want to delete "
              <> transaction.description
              <> " ("
              <> formatted_amount
              <> ")? This action cannot be undone.",
            ),
          ]),
          html.div([attribute.class("flex justify-end gap-3 pt-2")], [
            html.button(
              [
                attribute.type_("button"),
                attribute.attribute("data-testid", "delete-cancel-button"),
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
                attribute.attribute("data-testid", "delete-confirm-button"),
                attribute.class(
                  "inline-flex items-center justify-center gap-2 rounded-md bg-red-600 px-4 py-2 text-sm font-medium "
                  <> "text-white hover:bg-red-500 focus:outline-none focus:ring-2 focus:ring-red-500 "
                  <> "focus:ring-offset-2 disabled:cursor-not-allowed disabled:bg-gray-400 disabled:hover:bg-gray-400",
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
      }
    },
  )
}
