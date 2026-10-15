//// The balance form: records an account's balance as of a date, which the
//// server adds to the account's balance history. It opens on the current
//// balance's side and amount, dated today. See decision 13 in
//// docs/csv-import.md.
////
//// It runs on `form_modal` in edit mode, since a balance is always recorded
//// for an existing account: the `Put` it returns names the account, and the
//// page sends it as a record-balance request.

import budgeteur/balance_sheet_page/account.{type Account}
import budgeteur/balance_sheet_page/account_write_request.{type BalanceEntry}
import budgeteur/balance_sheet_page/balance_form
import budgeteur/shared/api_error.{type ApiError}
import budgeteur/shared/date
import budgeteur/shared/form_modal
import budgeteur/shared/money
import budgeteur/shared/side.{type Side}
import budgeteur/shared/ui/banner
import budgeteur/shared/ui/dialog
import gleam/option.{type Option, None, Some}
import gleam/time/calendar.{type Date}
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

/// An account's current balance, as its balance sheet line shows it.
pub type CurrentBalance {
  CurrentBalance(side: Side, amount: Float, as_of: Date)
}

pub type Form {
  Form(
    account: Account,
    // None when the balance is unknown.
    current: Option(CurrentBalance),
    balance: balance_form.Form,
  )
}

pub type Modal =
  form_modal.Modal(Form)

pub type Request =
  form_modal.Request(BalanceEntry)

pub type Outcome =
  form_modal.Outcome(Account)

pub fn hidden() -> Modal {
  form_modal.hidden()
}

// Update

pub type Msg {
  // The as-of date starts at the client's today, when known.
  OpenRequested(
    account: Account,
    current: Option(CurrentBalance),
    today: Option(Date),
  )
  BalanceMsg(balance_form.Msg)
  SaveRequested
  // Response to the in-flight request. Transport timeouts surface here as
  // `Error(NetworkError(...))`.
  SaveCompleted(result: Result(Account, ApiError))
  // Cancel button, or the browser dismissed the dialog (Esc / outside click)
  CancelRequested
}

pub fn update(state: Modal, msg: Msg) -> #(Modal, Option(Request), Outcome) {
  case msg {
    OpenRequested(account:, current:, today:) ->
      case state {
        form_modal.Submitting(..) -> #(state, None, form_modal.NoChange)
        _ -> {
          let balance = case current {
            Some(current) ->
              balance_form.prefilled(current.side, current.amount, today)
            None -> balance_form.empty(today)
          }
          #(
            form_modal.edit(account.id, Form(account:, current:, balance:)),
            None,
            form_modal.NoChange,
          )
        }
      }
    BalanceMsg(balance_msg) -> #(
      form_modal.set_form(state, fn(form) {
        Form(..form, balance: balance_form.update(form.balance, balance_msg))
      }),
      None,
      form_modal.NoChange,
    )
    SaveRequested -> {
      let #(modal, request) = form_modal.submit(state, validate_form)
      #(modal, request, form_modal.NoChange)
    }
    SaveCompleted(result: Ok(account)) -> {
      let #(modal, outcome) = form_modal.succeeded(state, account)
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

/// The amount is required: recording nothing is not a balance.
fn validate_form(form: Form) -> Result(#(BalanceEntry, Form), Form) {
  case balance_form.validate(form.balance, optional: False) {
    Ok(#(Some(entry), balance)) -> Ok(#(entry, Form(..form, balance:)))
    Ok(#(None, balance)) | Error(balance) -> Error(Form(..form, balance:))
  }
}

// View

/// Renders nothing while `Hidden`, otherwise the open dialog. The dialog is
/// locked while a request is in flight so it cannot be dismissed mid-request.
pub fn view(state: Modal) -> Element(Msg) {
  let open = fn(children, submitting) {
    dialog.dialog(
      testid: "balance-modal",
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
  [
    html.h2([attribute.class("text-lg font-semibold text-fg")], [
      html.text("Record balance"),
    ]),
    html.p(
      [
        attribute.class("mb-4 text-sm text-fg-muted"),
        attribute.attribute("data-testid", "balance-current"),
      ],
      [html.text(form.account.name <> ": " <> describe_current(form.current))],
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
              [attribute.attribute("data-testid", "balance-api-error")],
              [html.text("Could not record balance: " <> message)],
            )
          None -> element.none()
        },
        balance_form.view(
          form.balance,
          submitting:,
          note: "To correct the current balance, keep its date: a balance on a date that already has one replaces it.",
        )
          |> element.map(BalanceMsg),
        dialog.form_footer(
          leading: None,
          cancel: dialog.cancel_button(
            testid: "balance-cancel-button",
            disabled: submitting,
            on_click: CancelRequested,
          ),
          submit: dialog.submit_button(
            testid: "balance-submit-button",
            idle_label: "Record balance",
            busy_label: "Recording...",
            busy: submitting,
            disabled: balance_form.has_error(form.balance),
          ),
        ),
      ],
    ),
  ]
}

fn describe_current(current: Option(CurrentBalance)) -> String {
  case current {
    Some(CurrentBalance(side:, amount:, as_of:)) ->
      money.format(amount)
      <> " "
      <> case side {
        side.Asset -> "asset"
        side.Liability -> "liability"
      }
      <> " as of "
      <> date.format(as_of)
    None -> "no balance yet"
  }
}
