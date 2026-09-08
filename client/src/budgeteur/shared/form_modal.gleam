//// A generic create/update form modal state machine shared by the tag, rule,
//// and transaction forms.
////
//// A form modal has one of four states: `Hidden`, `Active` (user editing, may
//// hold inline validation errors), `Submitting` (request in flight, dialog
//// locked), or `Errored` (the request failed; the dialog stays open with an
//// inline banner so the user can retry in place). The `form` type parameter is
//// the feature's own field record; `Mode` records whether the dialog creates
//// or edits an entity, and which id when editing.
////
//// The module is a pure reducer: transitions take the current `Modal` and
//// return the next one plus whatever the caller must act on (`submit` returns
//// the request to send, `cancel` says whether the dialog should be closed by
//// the parent). Request/outcome types are shared so the feature modules can
//// alias them (`pub type Request = form_modal.Request(TagWriteRequest)`) and
//// the pages can interpret them uniformly.
////
//// `submit` and the other transitions are deliberately no-ops on states they
//// do not apply to, so a stale message (a `SaveCompleted` after a cancel, a
//// second `SaveRequested` while already `Submitting`) can never corrupt a
//// newer modal session. The double-submit guard falls out of `submit` being a
//// no-op while `Submitting`.
////
//// The dialog element itself is always rendered by the feature's `view`, so
//// the show/close dialog effects can find it. While a request is in flight the
//// dialog is locked (`closedby="none"`), so a response can never race a newer
//// modal session.

import budgeteur/shared/api_error.{type ApiError}
import gleam/option.{type Option, None, Some}
import youid/uuid.{type Uuid}

/// How long a create or update request may stay in flight before the
/// transport aborts it. This should be applied by the page via
/// `effect.with_timeout`.
pub const submit_timeout_ms = 10_000

/// Whether the modal creates a new entity or edits an existing one.
pub type Mode {
  /// Open an empty form.
  Create
  /// Pre-fill the form with an existing entity.
  Edit(id: Uuid)
}

/// The state of a form modal: the feature's form fields plus the mode.
pub type Modal(form) {
  /// The modal is not visible.
  Hidden
  /// The user is editing the form; it may hold client-side validation errors.
  Active(form: form, mode: Mode)
  /// The API request is in flight; the dialog is locked.
  Submitting(form: form, mode: Mode)
  /// The API request failed; the dialog stays open so the user can retry.
  Errored(form: form, mode: Mode, error: String)
}

/// An effect a form's `update` asks its page to perform, plus the create or
/// update request to send. `ShowDialog`/`CloseDialog` carry no payload; the
/// create (`Post`) and update (`Put`) requests carry the write request the
/// page serialises.
pub type Request(payload) {
  ShowDialog
  CloseDialog
  /// POST the payload to the collection endpoint.
  Post(payload)
  /// PUT the payload to the item endpoint.
  Put(id: Uuid, payload: payload)
}

/// The result of a completed save, reported back to the page so it can mutate
/// its lists and toast.
pub type Outcome(entity) {
  NoChange
  Created(entity: entity)
  Updated(entity: entity)
}

/// An empty (closed) modal.
pub fn hidden() -> Modal(a) {
  Hidden
}

/// An `Active` modal for creating a new entity.
pub fn create(form: a) -> Modal(a) {
  Active(form:, mode: Create)
}

/// An `Active` modal pre-filled with an existing entity, ready for editing.
pub fn edit(id: Uuid, form: a) -> Modal(a) {
  Active(form:, mode: Edit(id))
}

/// Apply `update` to the modal's form. No-op when `Hidden` or `Submitting`.
/// `Errored` keeps its error banner while the user edits.
pub fn set_form(modal: Modal(a), update: fn(a) -> a) -> Modal(a) {
  case modal {
    Active(form:, mode:) -> Active(form: update(form), mode:)
    Errored(form:, mode:, error:) -> Errored(form: update(form), mode:, error:)
    Hidden | Submitting(..) -> modal
  }
}

/// The modal's mode when it is open; `None` when `Hidden` or `Submitting`.
pub fn mode(modal: Modal(a)) -> Option(Mode) {
  case modal {
    Hidden | Submitting(..) -> None
    Active(mode:, ..) -> Some(mode)
    Errored(mode:, ..) -> Some(mode)
  }
}

/// Validate and submit. `Active` and `Errored` modals run `validate`, which
/// returns the payload and corrected form on success (e.g. trimmed values) or
/// the form with inline errors on failure. A submit attempt on an `Errored`
/// modal clears its banner first: the retry supersedes the stale server
/// message, so a validation failure shows only the fresh field errors. On
/// success the modal moves to `Submitting` and the returned request is `Post`
/// or `Put` according to the mode; on failure the modal returns to `Active`
/// with the corrected form. No-op when `Hidden` or `Submitting`, which also
/// guards against double submits.
pub fn submit(
  modal: Modal(a),
  validate: fn(a) -> Result(#(payload, a), a),
) -> #(Modal(a), Option(Request(payload))) {
  case modal {
    Active(form:, mode:) | Errored(form:, mode:, ..) -> {
      case validate(form) {
        Ok(#(payload, corrected)) -> {
          let request = case mode {
            Create -> Post(payload)
            Edit(id) -> Put(id, payload)
          }
          #(Submitting(corrected, mode), Some(request))
        }
        Error(corrected) -> #(Active(corrected, mode), None)
      }
    }
    Hidden | Submitting(..) -> #(modal, None)
  }
}

/// A completed save. `Submitting` modals close (`Hidden`) and report
/// `Created` or `Updated` from the mode. Every other state is returned
/// unchanged with `NoChange`, so a stale completion cannot corrupt a newer
/// modal session.
pub fn succeeded(modal: Modal(a), entity: e) -> #(Modal(a), Outcome(e)) {
  case modal {
    Submitting(mode:, ..) ->
      case mode {
        Create -> #(Hidden, Created(entity))
        Edit(_) -> #(Hidden, Updated(entity))
      }
    other -> #(other, NoChange)
  }
}

/// A failed save. `Submitting` modals move to `Errored` with the API error
/// details so the dialog can show an inline banner and the user can retry in
/// place. Every other state is returned unchanged (a stale failure cannot
/// corrupt a newer modal session).
pub fn failed(modal: Modal(a), error: ApiError) -> Modal(a) {
  case modal {
    Submitting(form:, mode:) -> Errored(form:, mode:, error: error.details)
    other -> other
  }
}

/// The Cancel button was clicked. `Active` and `Errored` modals close; the
/// `Bool` tells the caller whether to emit a `CloseDialog` effect. No-op while
/// `Hidden`/`Submitting`.
pub fn cancel(modal: Modal(a)) -> #(Modal(a), Bool) {
  case modal {
    Active(..) | Errored(..) -> #(Hidden, True)
    Hidden | Submitting(..) -> #(modal, False)
  }
}

/// The browser dismissed the dialog (Esc / backdrop click), so it is already
/// closed on screen and no `CloseDialog` effect is needed. No-op while
/// `Hidden`/`Submitting`.
pub fn dismissed(modal: Modal(a)) -> Modal(a) {
  case modal {
    Active(..) | Errored(..) -> Hidden
    Hidden | Submitting(..) -> modal
  }
}
