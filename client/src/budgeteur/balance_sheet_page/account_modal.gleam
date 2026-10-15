//// The account form: name, number, and term. A new account also takes an
//// optional opening balance; an existing account's balance is recorded with
//// the balance form instead. See decision 13 in docs/csv-import.md.

import budgeteur/balance_sheet_page/account.{type Account}
import budgeteur/balance_sheet_page/account_write_request.{
  type AccountWriteRequest, AccountWriteRequest,
}
import budgeteur/balance_sheet_page/balance_form
import budgeteur/shared/api_error.{type ApiError}
import budgeteur/shared/field
import budgeteur/shared/form_modal
import budgeteur/shared/term.{type Term, Current, NonCurrent}
import budgeteur/shared/ui/dialog
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

pub type Form {
  Form(
    name: field.Field(String, NameError),
    // The raw number; blank means no number. The server checks its format.
    number: String,
    term: Term,
    // The opening balance of a new account; None when editing.
    opening_balance: Option(balance_form.Form),
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
  // The as-of date of the opening balance starts at the client's today, when
  // known.
  CreateRequested(today: Option(Date))
  EditRequested(account: Account)
  NameChanged(value: String)
  NumberChanged(value: String)
  TermChanged(value: String)
  BalanceMsg(balance_form.Msg)
  SaveRequested
  // Response to the in-flight create or update. Transport timeouts surface
  // here as `Error(NetworkError(...))`.
  SaveCompleted(result: Result(Account, ApiError))
  // Cancel button, or the browser dismissed the dialog (Esc / outside click)
  CancelRequested
  // Delete button of the edit dialog. The dialog closes, and the page opens
  // the delete confirmation in its place.
  DeleteRequested
}

pub fn update(state: Modal, msg: Msg) -> #(Modal, Option(Request), Outcome) {
  case msg {
    CreateRequested(today:) ->
      case state {
        form_modal.Submitting(..) -> #(state, None, form_modal.NoChange)
        _ -> #(form_modal.create(empty_form(today)), None, form_modal.NoChange)
      }
    EditRequested(account:) ->
      case state {
        form_modal.Submitting(..) -> #(state, None, form_modal.NoChange)
        _ -> #(
          form_modal.edit(account.id, from_account(account)),
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
    BalanceMsg(balance_msg) -> #(
      form_modal.set_form(state, fn(form) {
        Form(
          ..form,
          opening_balance: option.map(form.opening_balance, balance_form.update(
            _,
            balance_msg,
          )),
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
    CancelRequested | DeleteRequested -> #(
      form_modal.cancel(state),
      None,
      form_modal.NoChange,
    )
  }
}

/// An empty form for a new account. Its balance is blank: an account may be
/// created before its balance is known.
fn empty_form(today: Option(Date)) -> Form {
  Form(
    name: field.Empty(""),
    number: "",
    term: Current,
    opening_balance: Some(balance_form.empty(today)),
  )
}

/// A form pre-filled with an existing account's details.
fn from_account(account: Account) -> Form {
  Form(
    name: field.Valid(value: account.name, input: account.name),
    number: option.unwrap(account.number, ""),
    term: account.term,
    opening_balance: None,
  )
}

// Validation

/// Finalize the form after a submit attempt and build the write request when
/// every field is valid. The opening balance is optional.
fn validate_form(form: Form) -> Result(#(AccountWriteRequest, Form), Form) {
  let name = field.finalize(form.name, fn() { NameRequired })

  let #(opening, opening_balance) = case form.opening_balance {
    None -> #(Ok(None), None)
    Some(balance) ->
      case balance_form.validate(balance, optional: True) {
        Ok(#(entry, balance)) -> #(Ok(entry), Some(balance))
        Error(balance) -> #(Error(Nil), Some(balance))
      }
  }
  let form = Form(..form, name:, opening_balance:)

  let number = case string.trim(form.number) {
    "" -> None
    number -> Some(number)
  }

  case field.value(name), opening {
    Some(name), Ok(opening_balance) ->
      Ok(#(
        AccountWriteRequest(name:, number:, term: form.term, opening_balance:),
        form,
      ))
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

// View

/// Renders nothing while `Hidden`, otherwise the open dialog. The dialog is
/// locked while a request is in flight so it cannot be dismissed mid-request.
pub fn view(state: Modal) -> Element(Msg) {
  let open = fn(children, submitting) {
    dialog.dialog(
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
  let Form(name:, number:, term:, opening_balance:) = form

  let #(title, submit_label, submitting_label) = case mode {
    form_modal.Create -> #("Add account", "Add account", "Adding account...")
    form_modal.Edit(_) -> #("Edit account", "Save", "Saving...")
  }

  let has_error =
    field.has_error(name)
    || case opening_balance {
      Some(balance) -> balance_form.has_error(balance)
      None -> False
    }

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
            dialog.error_banner(
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
              #(dialog.error_border_style, field.has_error(name)),
            ]),
            attribute.autofocus(True),
            attribute.value(field.input(name)),
            attribute.disabled(submitting),
            event.on_input(NameChanged),
          ]),
          case field.error(name) {
            Some(NameRequired) ->
              dialog.form_error_message("Name cannot be empty")
            Some(TooLong) ->
              dialog.form_error_message(
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
        dialog.radio_group(
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
        case opening_balance {
          Some(balance) ->
            balance_form.view(
              balance,
              submitting:,
              note: "Leave blank if you do not know it yet. The account is left out of the totals until it has a balance.",
            )
            |> element.map(BalanceMsg)
          None -> element.none()
        },
        dialog.form_footer(
          leading: case mode {
            form_modal.Create -> None
            form_modal.Edit(_) ->
              Some(dialog.delete_request_button(
                testid: "account-delete-button",
                disabled: submitting,
                on_click: DeleteRequested,
              ))
          },
          cancel: dialog.cancel_button(
            testid: "account-cancel-button",
            disabled: submitting,
            on_click: CancelRequested,
          ),
          submit: dialog.submit_button(
            testid: "account-submit-button",
            idle_label: submit_label,
            busy_label: submitting_label,
            busy: submitting,
            disabled: has_error,
          ),
        ),
      ],
    ),
  ]
}
