//// Generic delete-confirmation dialog shared by the transactions, tags, and
//// rules features.
////
//// The dialog element is always rendered by `view` so the show/close dialog
//// effects can find it; visibility is driven by effects rather than by adding
//// or removing the element from the DOM (which would reset its state). The
//// feature-specific bits (title, test ids, body copy) are handed in through
//// `Options`.
////
//// Deliberate tradeoff: the DOM dialog can be dismissed without a Msg (Escape
//// key, or `closedby="any"` outside-click), so the state here can drift out of
//// sync with what is on screen while a dialog is open. We accept this because
//// any stale state is benign: `open` overwrites the state on the next Delete
//// click, and the caller only ever re-shows the dialog by going through
//// `open`. We do not listen for the dialog's `cancel`/`close` events to keep
//// the state in sync, as that would add machinery to fix a state that
//// self-heals. While a request is in flight the dialog is locked
//// (`closedby="none"`), so a response can never race a newer modal session.

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
  /// Dialog is closed. The dialog element is still rendered, just inert.
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
    dialog_id: String,
    title: String,
    modal_testid: String,
    error_testid: String,
    error_prefix: String,
    cancel_testid: String,
    confirm_testid: String,
    body: fn(target, context) -> Element(msg),
  )
}

/// Always renders the `<dialog>` element (so the show/close effects can find
/// it); its children are empty while `Hidden`. `closedby` is "none" while
/// `Deleting`, locking the dialog so it cannot be dismissed mid-request. The
/// buttons emit `on_cancel`/`on_confirm` and are disabled while a delete is in
/// flight, with a spinner in the confirm button.
pub fn view(
  state: State(target, context),
  options: Options(target, context, msg),
  on_cancel on_cancel: msg,
  on_confirm on_confirm: msg,
) -> Element(msg) {
  let deleting = case state {
    Deleting(..) -> True
    _ -> False
  }

  html.dialog(
    modal_ui.dialog_attributes(
      options.dialog_id,
      options.modal_testid,
      deleting,
    ),
    content(state, options, on_cancel:, on_confirm:),
  )
}

fn content(
  state: State(target, context),
  options: Options(target, context, msg),
  on_cancel on_cancel: msg,
  on_confirm on_confirm: msg,
) -> List(Element(msg)) {
  case state {
    Hidden -> []
    Confirming(target:, context:) ->
      dialog_content(
        options,
        target,
        context,
        error: None,
        deleting: False,
        on_cancel:,
        on_confirm:,
      )
    Deleting(target:, context:) ->
      dialog_content(
        options,
        target,
        context,
        error: None,
        deleting: True,
        on_cancel:,
        on_confirm:,
      )
    Errored(target:, context:, error:) ->
      dialog_content(
        options,
        target,
        context,
        error: Some(error),
        deleting: False,
        on_cancel:,
        on_confirm:,
      )
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
