//// Auto-tagging runs from the tagging page: the two actions, the run's
//// progress, the result counts, and the re-tag confirmation dialog.

import budgeteur/shared/modal_ui
import budgeteur/shared/number
import gleam/dynamic/decode
import gleam/json
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html

/// How long a run may stay in flight before the transport aborts it. A run
/// rewrites assignments for every transaction, so it gets longer than a save.
pub const run_timeout_ms = 30_000

pub type Action {
  /// Apply rules to untagged transactions only.
  TagUntagged
  /// Recompute every transaction without a manual tag, so rule tags may change
  /// or be cleared. Confirmed first.
  Retag
}

pub type Run {
  Idle
  /// The re-tag confirmation dialog is open.
  ConfirmingRetag
  /// A run is in flight; both buttons are disabled.
  Running(Action)
}

/// How many transactions a run changed.
pub type Counts {
  Counts(
    // Untagged transactions that got a rule tag.
    tagged: Int,
    // Rule tags changed to another rule's tag.
    changed: Int,
    // Rule tags removed because no rule matches any more.
    cleared: Int,
  )
}

pub fn to_json(action: Action) -> json.Json {
  json.object([
    #(
      "action",
      json.string(case action {
        TagUntagged -> "TagUntagged"
        Retag -> "Retag"
      }),
    ),
  ])
}

pub fn counts_decoder() -> decode.Decoder(Counts) {
  use tagged <- decode.field("tagged", decode.int)
  use changed <- decode.field("changed", decode.int)
  use cleared <- decode.field("cleared", decode.int)
  decode.success(Counts(tagged:, changed:, cleared:))
}

/// The result toast's body. Tag untagged never changes or clears a tag, so it
/// reports the tagged count only.
pub fn summary(action: Action, counts: Counts) -> String {
  case action {
    TagUntagged ->
      "Tagged "
      <> number.format_int(counts.tagged)
      <> case counts.tagged {
        1 -> " untagged transaction"
        _ -> " untagged transactions"
      }
    Retag ->
      "Tagged "
      <> number.format_int(counts.tagged)
      <> ", changed "
      <> number.format_int(counts.changed)
      <> ", and cleared "
      <> number.format_int(counts.cleared)
      <> " transactions"
  }
}

/// The re-tag confirmation dialog, rendered while confirming. Confirming
/// closes it; the run's progress shows on the page's buttons.
pub fn view_retag_confirmation(
  run: Run,
  on_cancel on_cancel: msg,
  on_confirm on_confirm: msg,
) -> Element(msg) {
  case run {
    ConfirmingRetag ->
      modal_ui.dialog(
        testid: "retag-modal",
        busy: False,
        on_dismiss: on_cancel,
        children: [
          html.h2(
            [attribute.class("mb-4 text-lg font-semibold text-gray-900")],
            [
              html.text("Re-tag all transactions"),
            ],
          ),
          html.p([attribute.class("mb-4 text-sm text-gray-700")], [
            html.text(
              "Tags set by rules may change or be cleared to match the current "
              <> "rules. Tags you set are kept. This cannot be undone.",
            ),
          ]),
          html.div([attribute.class("flex justify-end gap-3 pt-2")], [
            modal_ui.cancel_button(
              testid: "retag-cancel-button",
              disabled: False,
              on_click: on_cancel,
            ),
            modal_ui.confirm_button(
              testid: "retag-confirm-button",
              label: "Re-tag",
              on_click: on_confirm,
            ),
          ]),
        ],
      )
    Idle | Running(_) -> element.none()
  }
}
