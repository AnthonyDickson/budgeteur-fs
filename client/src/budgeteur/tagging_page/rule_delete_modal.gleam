import budgeteur/shared/delete_modal
import budgeteur/tagging_page/rule.{type Rule, TagTarget, TransferTarget}
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html

pub type DeleteModalState =
  delete_modal.State(Rule, String)

pub fn empty() -> DeleteModalState {
  delete_modal.empty()
}

/// Open the dialog pre-targeted at an existing rule. `target_name` is the name
/// of the tag the rule points at, or "Transfer", shown in the confirmation copy.
pub fn open(rule: Rule, target_name: String) -> DeleteModalState {
  delete_modal.open(rule, target_name)
}

pub fn view(
  state: DeleteModalState,
  on_cancel on_cancel: msg,
  on_confirm on_confirm: msg,
) -> Element(msg) {
  delete_modal.view(
    state,
    delete_modal.Options(
      title: "Delete Rule",
      modal_testid: "delete-rule-modal",
      error_testid: "rule-delete-error",
      error_prefix: "Could not delete rule",
      cancel_testid: "rule-delete-cancel-button",
      confirm_testid: "rule-delete-confirm-button",
      body: fn(rule: Rule, target_name: String) {
        html.div([], [
          html.p([attribute.class("mb-4 text-sm text-fg-muted")], [
            html.text(
              "Delete rule '" <> rule.pattern <> "' > " <> target_name <> "?",
            ),
          ]),
          html.p([attribute.class("mb-4 text-sm text-fg-muted")], [
            html.text(
              case rule.target {
                TagTarget(..) ->
                  "Transactions matching this pattern will no longer be auto-tagged. "
                TransferTarget ->
                  "Transactions matching this pattern will no longer be suggested as transfers. "
              }
              <> "This action cannot be undone.",
            ),
          ]),
        ])
      },
    ),
    on_cancel:,
    on_confirm:,
  )
}
