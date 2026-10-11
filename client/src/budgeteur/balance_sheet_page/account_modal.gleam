//// The account form: name, number, term, and a new balance, entered as held
//// or owed and a magnitude, with its as-of date. Saving a balance records an
//// observation on the server; leaving it blank keeps the balance history as
//// it is. See decision 13 in docs/csv-import.md.

import budgeteur/balance_sheet_page/account.{type Account}
import budgeteur/balance_sheet_page/account_write_request.{
  type AccountWriteRequest, AccountWriteRequest, BalanceEntry,
}
import budgeteur/balance_sheet_page/term.{type Term, Current, NonCurrent}
import budgeteur/shared/api_error.{type ApiError}
import budgeteur/shared/date
import budgeteur/shared/field
import budgeteur/shared/form_modal
import budgeteur/shared/modal_ui
import budgeteur/shared/money
import gleam/int
import gleam/option.{type Option, None, Some}
import gleam/string
import gleam/time/calendar.{type Date}
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

/// Max length of an account name. Mirrors the server's `AccountName.MaxLength`.
pub const max_name_length = 128

const input_class = "block w-full rounded-md border border-gray-300 px-3 py-2 text-sm text-gray-900 shadow-sm "
  <> "focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500 "
  <> "disabled:cursor-not-allowed disabled:bg-gray-100 disabled:text-gray-400"

pub type NameError {
  NameRequired
  TooLong
}

pub type BalanceError {
  NotANumber
  Negative
}

pub type AsOfError {
  AsOfRequired
  NotADate
}

/// Which side of the sheet the balance is on. The form takes a magnitude, so
/// the user never types a sign.
pub type Side {
  Held
  Owed
}

pub type Form {
  Form(
    name: field.Field(String, NameError),
    // The raw number; blank means no number. The server checks its format.
    number: String,
    term: Term,
    side: Side,
    // Blank means no new balance.
    balance: field.Field(Float, BalanceError),
    as_of: field.Field(Date, AsOfError),
  )
}

pub type Modal =
  form_modal.Modal(Form)

pub type Request =
  form_modal.Request(AccountWriteRequest)

pub type Outcome =
  form_modal.Outcome(Account)

pub fn hidden() -> Modal {
  form_modal.hidden()
}

// Update

pub type Msg {
  // The as-of date of a new balance starts at the client's today, when known.
  CreateRequested(today: Option(Date))
  EditRequested(account: Account, today: Option(Date))
  NameChanged(value: String)
  NumberChanged(value: String)
  TermChanged(value: String)
  SideChanged(side: Side)
  BalanceChanged(value: String)
  AsOfChanged(value: String)
  SaveRequested
  // Response to the in-flight create or update. Transport timeouts surface
  // here as `Error(NetworkError(...))`.
  SaveCompleted(result: Result(Account, ApiError))
  // Cancel button, or the browser dismissed the dialog (Esc / outside click)
  CancelRequested
}

pub fn update(state: Modal, msg: Msg) -> #(Modal, Option(Request), Outcome) {
  case msg {
    CreateRequested(today:) ->
      case state {
        form_modal.Submitting(..) -> #(state, None, form_modal.NoChange)
        _ -> #(form_modal.create(empty_form(today)), None, form_modal.NoChange)
      }
    EditRequested(account:, today:) ->
      case state {
        form_modal.Submitting(..) -> #(state, None, form_modal.NoChange)
        _ -> #(
          form_modal.edit(account.id, from_account(account, today)),
          None,
          form_modal.NoChange,
        )
      }
    NameChanged(value:) -> #(
      form_modal.set_form(state, fn(form) {
        Form(
          ..form,
          name: field.validate(value, validate_name, fn(error) {
            error == NameRequired
          }),
        )
      }),
      None,
      form_modal.NoChange,
    )
    NumberChanged(value:) -> #(
      form_modal.set_form(state, fn(form) { Form(..form, number: value) }),
      None,
      form_modal.NoChange,
    )
    TermChanged(value:) ->
      case term.parse(value) {
        Ok(term) -> #(
          form_modal.set_form(state, fn(form) { Form(..form, term:) }),
          None,
          form_modal.NoChange,
        )
        Error(Nil) -> #(state, None, form_modal.NoChange)
      }
    SideChanged(side:) -> #(
      form_modal.set_form(state, fn(form) { Form(..form, side:) }),
      None,
      form_modal.NoChange,
    )
    BalanceChanged(value:) -> #(
      form_modal.set_form(state, fn(form) {
        Form(
          ..form,
          balance: field.validate(
            money.clip_to_two_dp(value),
            validate_balance,
            fn(_) { False },
          ),
        )
      }),
      None,
      form_modal.NoChange,
    )
    AsOfChanged(value:) -> #(
      form_modal.set_form(state, fn(form) {
        Form(
          ..form,
          as_of: field.validate(value, validate_as_of, fn(error) {
            error == AsOfRequired
          }),
        )
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

fn today_field(today: Option(Date)) -> field.Field(Date, AsOfError) {
  case today {
    Some(today) -> field.Valid(value: today, input: date.format(today))
    None -> field.Empty("")
  }
}

/// An empty form for a new account. Its balance is blank: an account may be
/// created before its balance is known.
fn empty_form(today: Option(Date)) -> Form {
  Form(
    name: field.Empty(""),
    number: "",
    term: Current,
    side: Held,
    balance: field.Empty(""),
    as_of: today_field(today),
  )
}

/// A form pre-filled with an existing account. The balance starts blank, so
/// saving a rename does not record a balance as of today.
fn from_account(account: Account, today: Option(Date)) -> Form {
  Form(
    name: field.Valid(value: account.name, input: account.name),
    number: option.unwrap(account.number, ""),
    term: account.term,
    side: Held,
    balance: field.Empty(""),
    as_of: today_field(today),
  )
}

// Validation

/// The signed balance for a magnitude on a side: owed is negative.
pub fn signed_balance(side: Side, magnitude: Float) -> Float {
  case side {
    Held -> magnitude
    Owed -> 0.0 -. magnitude
  }
}

/// Finalize the form after a submit attempt and build the write request when
/// every field is valid. The as-of date is only required with a balance.
fn validate_form(form: Form) -> Result(#(AccountWriteRequest, Form), Form) {
  let name = field.finalize(form.name, fn() { NameRequired })
  let as_of = case form.balance {
    field.Empty(..) -> form.as_of
    field.Valid(..) | field.Invalid(..) ->
      field.finalize(form.as_of, fn() { AsOfRequired })
  }
  let form = Form(..form, name:, as_of:)

  let number = case string.trim(form.number) {
    "" -> None
    number -> Some(number)
  }

  let balance = case form.balance, form.as_of {
    field.Empty(..), _ -> Ok(None)
    field.Valid(value: magnitude, ..), field.Valid(value: as_of, ..) ->
      Ok(
        Some(BalanceEntry(balance: signed_balance(form.side, magnitude), as_of:)),
      )
    _, _ -> Error(Nil)
  }

  case field.value(form.name), balance {
    Some(name), Ok(balance) ->
      Ok(#(AccountWriteRequest(name:, number:, term: form.term, balance:), form))
    _, _ -> Error(form)
  }
}

fn validate_name(name: String) -> Result(String, NameError) {
  let trimmed = string.trim(name)

  case string.is_empty(trimmed) {
    True -> Error(NameRequired)
    False ->
      case string.length(trimmed) > max_name_length {
        True -> Error(TooLong)
        False -> Ok(trimmed)
      }
  }
}

fn validate_balance(balance: String) -> Result(Float, BalanceError) {
  case money.parse_decimal(string.trim(balance)) {
    Error(Nil) -> Error(NotANumber)
    Ok(amount) ->
      case amount <. 0.0 {
        True -> Error(Negative)
        False -> Ok(amount)
      }
  }
}

fn validate_as_of(as_of: String) -> Result(Date, AsOfError) {
  case string.trim(as_of) {
    "" -> Error(AsOfRequired)
    trimmed ->
      case date.parse(trimmed) {
        Ok(as_of) -> Ok(as_of)
        Error(Nil) -> Error(NotADate)
      }
  }
}

// View

/// Renders nothing while `Hidden`, otherwise the open dialog. The dialog is
/// locked while a request is in flight so it cannot be dismissed mid-request.
pub fn view(state: Modal) -> Element(Msg) {
  let open = fn(children, submitting) {
    modal_ui.dialog(
      testid: "account-modal",
      busy: submitting,
      on_dismiss: CancelRequested,
      children:,
    )
  }

  case state {
    form_modal.Hidden -> element.none()
    form_modal.Active(form:, mode:) ->
      open(view_form(form, mode, api_error: None, submitting: False), False)
    form_modal.Submitting(form:, mode:) ->
      open(view_form(form, mode, api_error: None, submitting: True), True)
    form_modal.Errored(form:, mode:, error:) ->
      open(
        view_form(form, mode, api_error: Some(error), submitting: False),
        False,
      )
  }
}

fn view_form(
  form: Form,
  mode: form_modal.Mode,
  api_error api_error: Option(String),
  submitting submitting: Bool,
) -> List(Element(Msg)) {
  let Form(name:, number:, term:, side:, balance:, as_of:) = form

  let #(title, submit_label, submitting_label, balance_help) = case mode {
    form_modal.Create -> #(
      "Add account",
      "Add account",
      "Adding account...",
      "Leave blank if you do not know it yet. The account is left out of the totals until it has a balance.",
    )
    form_modal.Edit(_) -> #(
      "Edit account",
      "Save",
      "Saving...",
      "Leave blank to keep the current balance. A balance on a date that already has one replaces it.",
    )
  }

  let has_error =
    field.has_error(name) || field.has_error(balance) || field.has_error(as_of)

  [
    html.h2([attribute.class("mb-4 text-lg font-semibold text-gray-900")], [
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
            modal_ui.error_banner(
              testid: "account-api-error",
              message: "Could not save account: " <> message,
              extra_class: "",
            )
          None -> element.none()
        },
        html.label([attribute.class("block")], [
          html.span(
            [attribute.class("mb-1 block text-sm font-medium text-gray-700")],
            [html.text("Name")],
          ),
          html.input([
            attribute.type_("text"),
            attribute.attribute("data-testid", "account-name-input"),
            attribute.placeholder("e.g. Everyday"),
            attribute.class(input_class),
            attribute.classes([
              #(modal_ui.error_border_style, field.has_error(name)),
            ]),
            attribute.autofocus(True),
            attribute.value(field.input(name)),
            attribute.disabled(submitting),
            event.on_input(NameChanged),
          ]),
          case field.error(name) {
            Some(NameRequired) ->
              modal_ui.form_error_message("Name cannot be empty")
            Some(TooLong) ->
              modal_ui.form_error_message(
                "Name cannot be longer than "
                <> int.to_string(max_name_length)
                <> " characters",
              )
            None -> element.none()
          },
        ]),
        html.label([attribute.class("block")], [
          html.span(
            [attribute.class("mb-1 block text-sm font-medium text-gray-700")],
            [html.text("Account number (optional)")],
          ),
          html.input([
            attribute.type_("text"),
            attribute.attribute("data-testid", "account-number-input"),
            attribute.placeholder("e.g. 12-3456-0789012-00"),
            attribute.class(input_class),
            attribute.value(number),
            attribute.disabled(submitting),
            event.on_input(NumberChanged),
          ]),
          html.p([attribute.class("mt-1 text-xs text-gray-500")], [
            html.text(
              "Imports find the account by its number. Set it before the first import so the statement does not create a second account.",
            ),
          ]),
        ]),
        modal_ui.radio_group(
          legend: "Term",
          testid: "account-term",
          disabled: submitting,
          options: [
            #(term.to_string(Current), "Current", term == Current, TermChanged),
            #(
              term.to_string(NonCurrent),
              "Non-current",
              term == NonCurrent,
              TermChanged,
            ),
          ],
        ),
        html.p([attribute.class("text-xs text-gray-500")], [
          html.text(
            "Current for everyday, savings, and credit card accounts. The side of the balance sheet follows the balance.",
          ),
        ]),
        html.div([attribute.class("space-y-2")], [
          modal_ui.radio_group(
            legend: "New balance",
            testid: "account-side",
            disabled: submitting,
            options: [
              #("Held", "Held", side == Held, fn(_) { SideChanged(Held) }),
              #("Owed", "Owed", side == Owed, fn(_) { SideChanged(Owed) }),
            ],
          ),
          html.input([
            attribute.type_("text"),
            attribute.attribute("data-testid", "account-balance-input"),
            attribute.inputmode("decimal"),
            attribute.placeholder("0.00"),
            attribute.class(input_class),
            attribute.classes([
              #(modal_ui.error_border_style, field.has_error(balance)),
            ]),
            attribute.value(field.input(balance)),
            attribute.disabled(submitting),
            event.on_input(BalanceChanged),
          ]),
          case field.error(balance) {
            Some(NotANumber) ->
              modal_ui.form_error_message("Not a valid number")
            Some(Negative) ->
              modal_ui.form_error_message(
                "Enter the amount without a sign. Choose held or owed instead.",
              )
            None -> element.none()
          },
          html.p([attribute.class("text-xs text-gray-500")], [
            html.text(balance_help),
          ]),
        ]),
        html.label([attribute.class("block")], [
          html.span(
            [attribute.class("mb-1 block text-sm font-medium text-gray-700")],
            [html.text("Balance as of")],
          ),
          html.input([
            attribute.type_("date"),
            attribute.attribute("data-testid", "account-as-of-input"),
            attribute.class(input_class),
            attribute.classes([
              #(modal_ui.error_border_style, field.has_error(as_of)),
            ]),
            attribute.value(field.input(as_of)),
            attribute.disabled(submitting),
            event.on_input(AsOfChanged),
          ]),
          case field.error(as_of) {
            Some(AsOfRequired) ->
              modal_ui.form_error_message("Date cannot be empty")
            Some(NotADate) -> modal_ui.form_error_message("Not a valid date")
            None -> element.none()
          },
        ]),
        html.div([attribute.class("flex justify-end gap-3 pt-2")], [
          modal_ui.cancel_button(
            testid: "account-cancel-button",
            disabled: submitting,
            on_click: CancelRequested,
          ),
          modal_ui.submit_button(
            testid: "account-submit-button",
            idle_label: submit_label,
            busy_label: submitting_label,
            busy: submitting,
            disabled: has_error,
          ),
        ]),
      ],
    ),
  ]
}
