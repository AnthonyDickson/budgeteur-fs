//// Generic delete-confirmation dialog shared by the transactions, tags, and
//// rules features.
////
//// `view` renders the dialog (`modal_ui.dialog`) for every state except
//// `Hidden`, so the dialog is open exactly while the state says so. The
//// feature-specific bits (title, test ids, body copy) are handed in through
//// `Options`. The browser dismissing the dialog (Escape or an outside click)
//// sends the same `on_cancel` message as the Cancel button. While a request is
//// in flight the dialog is locked (`closedby="none"`), so a response can never
//// race a newer modal session.

import budgeteur/shared/api_error.{type ApiError}
import budgeteur/shared/modal_ui
import gleam/option.{type Option, None, Some}
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html

/// How long a delete request may stay in flight before the transport aborts
/// it. This should be applied by the page via `effect.with_timeout`.
pub const delete_timeout_ms = 10_000

pub type State(target, context) {
  /// Dialog is closed and not rendered.
  Hidden
  /// Dialog is open, awaiting the user's confirmation.
  Confirming(target: target, context: context)
  /// A delete request is in flight; the dialog cannot be dismissed and both
  /// buttons are disabled.
  Deleting(target: target, context: context)
  /// The delete request failed. The dialog stays open so the user can retry
  /// in place; the error is shown inline.
  Errored(target: target, context: context, error: String)
}

pub fn empty() -> State(target, context) {
  Hidden
}

/// Open the dialog pre-targeted at an existing entity. `context` carries any
/// extra data the body renderer needs (e.g. a rule count).
pub fn open(target: target, context: context) -> State(target, context) {
  Confirming(target:, context:)
}

/// `Confirming` or `Errored` -> `Deleting`, returning the new state plus the
/// target needed to build the DELETE effect. No-op when `Hidden` or already
/// `Deleting`.
pub fn confirm(
  state: State(target, context),
) -> Result(#(State(target, context), target), Nil) {
  case state {
    Confirming(target:, context:) -> Ok(#(Deleting(target:, context:), target))
    Errored(target:, context:, ..) -> Ok(#(Deleting(target:, context:), target))
    Hidden | Deleting(..) -> Error(Nil)
  }
}

/// `Deleting` -> `Errored` with the API error details. Any other state is
/// returned unchanged, so a late failure cannot disturb a newer modal session.
pub fn fail(
  state: State(target, context),
  error: ApiError,
) -> State(target, context) {
  case state {
    Deleting(target:, context:) ->
      Errored(target:, context:, error: error.details)
    other -> other
  }
}

pub type Options(target, context, msg) {
  Options(
    title: String,
    modal_testid: String,
    error_testid: String,
    error_prefix: String,
    cancel_testid: String,
    confirm_testid: String,
    body: fn(target, context) -> Element(msg),
  )
}

/// Renders nothing while `Hidden`, otherwise the open dialog. `closedby` is
/// "none" while `Deleting`, locking the dialog so it cannot be dismissed
/// mid-request. The buttons emit `on_cancel`/`on_confirm` and are disabled
/// while a delete is in flight, with a spinner in the confirm button.
pub fn view(
  state: State(target, context),
  options: Options(target, context, msg),
  on_cancel on_cancel: msg,
  on_confirm on_confirm: msg,
) -> Element(msg) {
  let open = fn(target, context, error, deleting) {
    modal_ui.dialog(
      testid: options.modal_testid,
      busy: deleting,
      on_dismiss: on_cancel,
      children: dialog_content(
        options,
        target,
        context,
        error:,
        deleting:,
        on_cancel:,
        on_confirm:,
      ),
    )
  }

  case state {
    Hidden -> element.none()
    Confirming(target:, context:) -> open(target, context, None, False)
    Deleting(target:, context:) -> open(target, context, None, True)
    Errored(target:, context:, error:) ->
      open(target, context, Some(error), False)
  }
}

fn dialog_content(
  options: Options(target, context, msg),
  target: target,
  context: context,
  error error: Option(String),
  deleting deleting: Bool,
  on_cancel on_cancel: msg,
  on_confirm on_confirm: msg,
) -> List(Element(msg)) {
  [
    html.h2([attribute.class("mb-4 text-lg font-semibold text-gray-900")], [
      html.text(options.title),
    ]),
    options.body(target, context),
    case error {
      Some(message) ->
        modal_ui.error_banner(
          testid: options.error_testid,
          message: options.error_prefix <> ": " <> message,
          extra_class: "mb-4",
        )
      None -> element.none()
    },
    html.div([attribute.class("flex justify-end gap-3 pt-2")], [
      modal_ui.cancel_button(
        testid: options.cancel_testid,
        disabled: deleting,
        on_click: on_cancel,
      ),
      modal_ui.delete_button(
        testid: options.confirm_testid,
        busy: deleting,
        on_click: on_confirm,
      ),
    ]),
  ]
}
