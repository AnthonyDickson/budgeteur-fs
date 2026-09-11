import budgeteur/shared/delete_modal
import budgeteur/tagging_page/rule.{type Rule}
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html

const dom_id = "rule_delete_modal"

/// The CSS selector for the modal dialog element. The `#` hash prefix is
/// composed here so callers (e.g. the show/close dialog effects) never have to
/// remember it.
pub const dom_id_selector = "#" <> dom_id

pub type DeleteModalState =
  delete_modal.State(Rule, String)

pub fn empty() -> DeleteModalState {
  delete_modal.empty()
}

/// Open the dialog pre-targeted at an existing rule. `tag_name` is the name of
/// the tag the rule points at, shown in the confirmation copy.
pub fn open(rule: Rule, tag_name: String) -> DeleteModalState {
  delete_modal.open(rule, tag_name)
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
      title: "Delete Rule",
      modal_testid: "delete-rule-modal",
      error_testid: "rule-delete-error",
      error_prefix: "Could not delete rule",
      cancel_testid: "rule-delete-cancel-button",
      confirm_testid: "rule-delete-confirm-button",
      body: fn(rule: Rule, tag_name: String) {
        html.div([], [
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
        ])
      },
    ),
    on_cancel:,
    on_confirm:,
  )
}
