import budgeteur/shared/delete_modal
import budgeteur/tag.{type Tag}
import gleam/int
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html

pub type DeleteModalState =
  delete_modal.State(Tag, Int)

pub fn empty() -> DeleteModalState {
  delete_modal.empty()
}

/// Open the dialog pre-targeted at an existing tag. `rule_count` is the number
/// of rules that belong to the tag and will be deleted with it.
pub fn open(tag: Tag, rule_count: Int) -> DeleteModalState {
  delete_modal.open(tag, rule_count)
}

pub fn view(
  state: DeleteModalState,
  on_cancel on_cancel: msg,
  on_confirm on_confirm: msg,
) -> Element(msg) {
  delete_modal.view(
    state,
    delete_modal.Options(
      title: "Delete Tag",
      modal_testid: "delete-tag-modal",
      error_testid: "tag-delete-error",
      error_prefix: "Could not delete tag",
      cancel_testid: "tag-delete-cancel-button",
      confirm_testid: "tag-delete-confirm-button",
      body: fn(tag: Tag, rule_count: Int) {
        html.div([], [
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
        ])
      },
    ),
    on_cancel:,
    on_confirm:,
  )
}
