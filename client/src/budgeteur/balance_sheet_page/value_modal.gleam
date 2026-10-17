//// The value form: records an item's value as of a date, which the server adds
//// to the item's observations. It opens on the current value, dated today. See
//// decision 2 in docs/reports.md.
////
//// It runs on `form_modal` in edit mode, since a value is always recorded for
//// an existing item: the `Put` it returns names the item, and the page sends
//// it as a record-value request.

import budgeteur/balance_sheet_page/balance_sheet_item.{type BalanceSheetItem}
import budgeteur/balance_sheet_page/item_write_request.{type ValueEntry}
import budgeteur/balance_sheet_page/value_form
import budgeteur/shared/api_error.{type ApiError}
import budgeteur/shared/date
import budgeteur/shared/form_modal
import budgeteur/shared/money
import budgeteur/shared/side
import budgeteur/shared/ui/banner
import budgeteur/shared/ui/dialog
import gleam/option.{type Option, None, Some}
import gleam/time/calendar.{type Date}
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

pub type Form {
  Form(item: BalanceSheetItem, value: value_form.Form)
}

pub type Modal =
  form_modal.Modal(Form)

pub type Request =
  form_modal.Request(ValueEntry)

pub type Outcome =
  form_modal.Outcome(BalanceSheetItem)

pub fn hidden() -> Modal {
  form_modal.hidden()
}

// Update

pub type Msg {
  // The as-of date starts at the client's today, when known.
  OpenRequested(item: BalanceSheetItem, today: Option(Date))
  ValueMsg(value_form.Msg)
  SaveRequested
  // Response to the in-flight request. Transport timeouts surface here as
  // `Error(NetworkError(...))`.
  SaveCompleted(result: Result(BalanceSheetItem, ApiError))
  // Cancel button, or the browser dismissed the dialog (Esc / outside click)
  CancelRequested
}

pub fn update(state: Modal, msg: Msg) -> #(Modal, Option(Request), Outcome) {
  case msg {
    OpenRequested(item:, today:) ->
      case state {
        form_modal.Submitting(..) -> #(state, None, form_modal.NoChange)
        _ -> #(
          form_modal.edit(
            item.id,
            Form(item:, value: value_form.prefilled(item.value, today)),
          ),
          None,
          form_modal.NoChange,
        )
      }
    ValueMsg(value_msg) -> #(
      form_modal.set_form(state, fn(form) {
        Form(..form, value: value_form.update(form.value, value_msg))
      }),
      None,
      form_modal.NoChange,
    )
    SaveRequested -> {
      let #(modal, request) =
        form_modal.submit(state, fn(form) {
          case value_form.validate(form.value) {
            Ok(#(entry, value)) -> Ok(#(entry, Form(..form, value:)))
            Error(value) -> Error(Form(..form, value:))
          }
        })
      #(modal, request, form_modal.NoChange)
    }
    SaveCompleted(result: Ok(item)) -> {
      let #(modal, outcome) = form_modal.succeeded(state, item)
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

// View

/// Renders nothing while `Hidden`, otherwise the open dialog. The dialog is
/// locked while a request is in flight so it cannot be dismissed mid-request.
pub fn view(state: Modal) -> Element(Msg) {
  let open = fn(children, submitting) {
    dialog.dialog(
      testid: "value-modal",
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
  let item = form.item

  [
    html.h2([attribute.class("text-lg font-semibold text-fg")], [
      html.text("Record value"),
    ]),
    html.p(
      [
        attribute.class("mb-4 text-sm text-fg-muted"),
        attribute.attribute("data-testid", "value-current"),
      ],
      [
        html.text(
          item.name
          <> ": "
          <> money.format(item.value)
          <> " "
          <> case item.side {
            side.Asset -> "asset"
            side.Liability -> "liability"
          }
          <> " as of "
          <> date.format(item.as_of),
        ),
      ],
    ),
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
              [attribute.attribute("data-testid", "value-api-error")],
              [html.text("Could not record value: " <> message)],
            )
          None -> element.none()
        },
        value_form.view(
          form.value,
          side: item.side,
          submitting:,
          autofocus: True,
          note: "To correct the current value, keep its date: a value on a date that already has one replaces it.",
        )
          |> element.map(ValueMsg),
        dialog.form_footer(
          leading: None,
          cancel: dialog.cancel_button(
            testid: "value-cancel-button",
            disabled: submitting,
            on_click: CancelRequested,
          ),
          submit: dialog.submit_button(
            testid: "value-submit-button",
            idle_label: "Record value",
            busy_label: "Recording...",
            busy: submitting,
            disabled: value_form.has_error(form.value),
          ),
        ),
      ],
    ),
  ]
}
