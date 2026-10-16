//// The close form: records the date a line was sold, repaid, or closed. It is
//// apart from the line's edit form because closing is an event in the line's
//// life, not one of its details. Reopening needs no form. See decision 4 in
//// docs/reports.md.
////
//// It runs on `form_modal` in edit mode, since a line is always closed after
//// it exists: the `Put` it returns names the line, and the page sends it as a
//// close request.

import budgeteur/shared/api_error.{type ApiError}
import budgeteur/shared/date
import budgeteur/shared/field
import budgeteur/shared/form_modal
import budgeteur/shared/ui/banner
import budgeteur/shared/ui/dialog
import budgeteur/shared/ui/input
import budgeteur/shared/ui/popover
import gleam/option.{type Option, None, Some}
import gleam/string
import gleam/time/calendar.{type Date}
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import youid/uuid.{type Uuid}

/// What is being closed, which words the form.
pub type Kind {
  Item
  Account
}

pub type CloseDateError {
  Required
  NotADate
}

pub type Form {
  Form(
    kind: Kind,
    name: String,
    // Whether the line is closed already, so its close date changes.
    changing: Bool,
    closed_on: field.Field(Date, CloseDateError),
  )
}

pub type Modal =
  form_modal.Modal(Form)

/// The close date to send.
pub type Request =
  form_modal.Request(Date)

pub type Outcome =
  form_modal.Outcome(Nil)

pub fn hidden() -> Modal {
  form_modal.hidden()
}

// Update

pub type Msg {
  // `starts_on` is the date the form starts on: today for an open line. A
  // closed line is `changing` its close date.
  OpenRequested(
    id: Uuid,
    kind: Kind,
    name: String,
    starts_on: Option(Date),
    changing: Bool,
  )
  ClosedOnChanged(value: String)
  SaveRequested
  // Response to the in-flight request. Transport timeouts surface here as
  // `Error(NetworkError(...))`.
  SaveCompleted(result: Result(Nil, ApiError))
  // Cancel button, or the browser dismissed the dialog (Esc / outside click)
  CancelRequested
}

pub fn update(state: Modal, msg: Msg) -> #(Modal, Option(Request), Outcome) {
  case msg {
    OpenRequested(id:, kind:, name:, starts_on:, changing:) ->
      case state {
        form_modal.Submitting(..) -> #(state, None, form_modal.NoChange)
        _ -> #(
          form_modal.edit(
            id,
            Form(kind:, name:, changing:, closed_on: case starts_on {
              Some(starts_on) ->
                field.Valid(value: starts_on, input: date.format(starts_on))
              None -> field.Empty("")
            }),
          ),
          None,
          form_modal.NoChange,
        )
      }
    ClosedOnChanged(value:) -> #(
      form_modal.set_form(state, fn(form) {
        Form(
          ..form,
          closed_on: field.validate(value, parse, fn(error) {
            error == Required
          }),
        )
      }),
      None,
      form_modal.NoChange,
    )
    SaveRequested -> {
      let #(modal, request) =
        form_modal.submit(state, fn(form) {
          let closed_on = field.finalize(form.closed_on, fn() { Required })
          let form = Form(..form, closed_on:)
          case closed_on {
            field.Valid(value:, ..) -> Ok(#(value, form))
            field.Empty(..) | field.Invalid(..) -> Error(form)
          }
        })
      #(modal, request, form_modal.NoChange)
    }
    SaveCompleted(result: Ok(Nil)) -> {
      let #(modal, outcome) = form_modal.succeeded(state, Nil)
      #(modal, None, outcome)
    }
    SaveCompleted(result: Error(error)) -> #(
      form_modal.failed(state, error),
      None,
      form_modal.NoChange,
    )
    CancelRequested -> #(form_modal.cancel(state), None, form_modal.NoChange)
  }
}

fn parse(input: String) -> Result(Date, CloseDateError) {
  case string.trim(input) {
    "" -> Error(Required)
    trimmed ->
      case date.parse(trimmed) {
        Ok(closed_on) -> Ok(closed_on)
        Error(Nil) -> Error(NotADate)
      }
  }
}

// View

/// Renders nothing while `Hidden`, otherwise the open dialog. The dialog is
/// locked while a request is in flight so it cannot be dismissed mid-request.
pub fn view(state: Modal) -> Element(Msg) {
  let open = fn(children, submitting) {
    dialog.dialog(
      testid: "close-modal",
      busy: submitting,
      on_dismiss: CancelRequested,
      children:,
    )
  }

  case state {
    form_modal.Hidden -> element.none()
    form_modal.Active(form:, ..) ->
      open(view_form(form, api_error: None, submitting: False), False)
    form_modal.Submitting(form:, ..) ->
      open(view_form(form, api_error: None, submitting: True), True)
    form_modal.Errored(form:, error:, ..) ->
      open(view_form(form, api_error: Some(error), submitting: False), False)
  }
}

fn view_form(
  form: Form,
  api_error api_error: Option(String),
  submitting submitting: Bool,
) -> List(Element(Msg)) {
  let title = case form.changing {
    True -> "Change the close date of " <> form.name
    False -> "Close " <> form.name
  }
  let #(label, help) = case form.kind {
    Item -> #(
      "Sold or repaid on",
      "Balance sheets from this date leave the item out, and earlier ones keep it. Reopen it from this page if you still have it.",
    )
    Account -> #(
      "Closed on",
      "Balance sheets from this date leave the account out, and earlier ones keep it. Its transactions and balances stay. Reopen it from this page if it is still open.",
    )
  }

  [
    html.h2([attribute.class("mb-4 text-lg font-semibold text-fg")], [
      html.text(title),
    ]),
    html.form(
      [
        event.on_submit(fn(_) { SaveRequested }),
        attribute.class("space-y-4"),
      ],
      [
        case api_error {
          Some(message) ->
            banner.view(
              banner.Error,
              [attribute.attribute("data-testid", "close-api-error")],
              [html.text("Could not close: " <> message)],
            )
          None -> element.none()
        },
        html.div([], [
          input.label_with_help(
            label,
            for: "close-date-input",
            help: popover.help(id: "close-date-help", about: label, paragraphs: [
              help,
            ]),
          ),
          input.text([
            attribute.id("close-date-input"),
            attribute.type_("date"),
            attribute.attribute("data-testid", "close-date-input"),
            attribute.aria_describedby("close-date-help"),
            attribute.value(field.input(form.closed_on)),
            attribute.disabled(submitting),
            event.on_input(ClosedOnChanged),
            input.invalid(field.has_error(form.closed_on)),
          ]),
          case field.error(form.closed_on) {
            Some(Required) -> input.error_message("Date cannot be empty")
            Some(NotADate) -> input.error_message("Not a valid date")
            None -> element.none()
          },
        ]),
        dialog.form_footer(
          leading: None,
          cancel: dialog.cancel_button(
            testid: "close-cancel-button",
            disabled: submitting,
            on_click: CancelRequested,
          ),
          submit: dialog.submit_button(
            testid: "close-submit-button",
            idle_label: case form.changing {
              True -> "Save"
              False -> "Close"
            },
            busy_label: "Saving...",
            busy: submitting,
            disabled: field.has_error(form.closed_on),
          ),
        ),
      ],
    ),
  ]
}
