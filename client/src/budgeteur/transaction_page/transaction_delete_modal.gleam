import budgeteur/shared/delete_modal
import budgeteur/shared/money
import budgeteur/transaction_page/transaction.{type Transaction}
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html

pub type DeleteModalState =
  delete_modal.State(Transaction, Nil)

pub fn empty() -> DeleteModalState {
  delete_modal.empty()
}

/// Open the dialog pre-targeted at an existing transaction.
pub fn open(transaction: Transaction) -> DeleteModalState {
  delete_modal.open(transaction, Nil)
}

pub fn view(
  state: DeleteModalState,
  on_cancel on_cancel: msg,
  on_confirm on_confirm: msg,
) -> Element(msg) {
  delete_modal.view(
    state,
    delete_modal.Options(
      title: "Delete Transaction",
      modal_testid: "delete-transaction-modal",
      error_testid: "transaction-delete-error",
      error_prefix: "Could not delete transaction",
      cancel_testid: "delete-cancel-button",
      confirm_testid: "delete-confirm-button",
      body: fn(transaction: Transaction, _context: Nil) {
        let formatted_amount = transaction.amount |> money.format

        html.p([attribute.class("mb-4 text-sm text-gray-700")], [
          html.text(
            "Are you sure you want to delete "
            <> transaction.description
            <> " ("
            <> formatted_amount
            <> ")? This action cannot be undone.",
          ),
        ])
      },
    ),
    on_cancel:,
    on_confirm:,
  )
}
