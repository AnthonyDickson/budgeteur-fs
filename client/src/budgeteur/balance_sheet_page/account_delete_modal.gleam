import budgeteur/balance_sheet_page/account.{type Account}
import budgeteur/shared/delete_modal
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html

pub type DeleteModalState =
  delete_modal.State(Account, Nil)

pub fn empty() -> DeleteModalState {
  delete_modal.empty()
}

/// Open the dialog pre-targeted at an existing account.
pub fn open(account: Account) -> DeleteModalState {
  delete_modal.open(account, Nil)
}

pub fn view(
  state: DeleteModalState,
  on_cancel on_cancel: msg,
  on_confirm on_confirm: msg,
) -> Element(msg) {
  delete_modal.view(
    state,
    delete_modal.Options(
      title: "Delete Account",
      modal_testid: "delete-account-modal",
      error_testid: "account-delete-error",
      error_prefix: "Could not delete account",
      cancel_testid: "account-delete-cancel-button",
      confirm_testid: "account-delete-confirm-button",
      body: fn(account: Account, _context: Nil) {
        html.div([attribute.class("mb-4 space-y-2 text-sm text-fg-muted")], [
          html.p([], [
            html.text("Are you sure you want to delete " <> account.name <> "?"),
          ]),
          html.p([attribute.class("font-medium text-danger")], [
            html.text(
              "Its transactions and balance history are deleted with it. This cannot be undone.",
            ),
          ]),
        ])
      },
    ),
    on_cancel:,
    on_confirm:,
  )
}
