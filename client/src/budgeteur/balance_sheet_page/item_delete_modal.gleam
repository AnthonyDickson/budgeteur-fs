import budgeteur/balance_sheet_page/balance_sheet_item.{type BalanceSheetItem}
import budgeteur/shared/delete_modal
import budgeteur/shared/money
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html

const dom_id = "balance_sheet_item_delete_modal"

/// The CSS selector for the modal dialog element. The `#` hash prefix is
/// composed here so callers (e.g. the show/close dialog effects) never have to
/// remember it.
pub const dom_id_selector = "#" <> dom_id

pub type DeleteModalState =
  delete_modal.State(BalanceSheetItem, Nil)

pub fn empty() -> DeleteModalState {
  delete_modal.empty()
}

/// Open the dialog pre-targeted at an existing item.
pub fn open(item: BalanceSheetItem) -> DeleteModalState {
  delete_modal.open(item, Nil)
}

pub fn view(
  state: DeleteModalState,
  on_cancel on_cancel: msg,
  on_confirm on_confirm: msg,
) -> Element(msg) {
  delete_modal.view(
    state,
    delete_modal.Options(
      dialog_id: dom_id,
      title: "Delete Item",
      modal_testid: "delete-balance-sheet-item-modal",
      error_testid: "balance-sheet-item-delete-error",
      error_prefix: "Could not delete item",
      cancel_testid: "balance-sheet-item-delete-cancel-button",
      confirm_testid: "balance-sheet-item-delete-confirm-button",
      body: fn(item: BalanceSheetItem, _context: Nil) {
        html.p([attribute.class("mb-4 text-sm text-gray-700")], [
          html.text(
            "Are you sure you want to delete "
            <> item.name
            <> " ("
            <> money.format(item.balance)
            <> ")? This cannot be undone.",
          ),
        ])
      },
    ),
    on_cancel:,
    on_confirm:,
  )
}
