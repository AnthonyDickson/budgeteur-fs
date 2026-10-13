import budgeteur/balance_sheet_page/balance_sheet_item.{type BalanceSheetItem}
import budgeteur/balance_sheet_page/item_kind.{type ItemKind, Asset, Liability}
import budgeteur/balance_sheet_page/item_write_request.{
  type ItemWriteRequest, ItemWriteRequest,
}
import budgeteur/balance_sheet_page/term.{type Term, Current, NonCurrent}
import budgeteur/shared/api_error.{type ApiError}
import budgeteur/shared/date
import budgeteur/shared/field
import budgeteur/shared/form_modal
import budgeteur/shared/modal_ui
import budgeteur/shared/money
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import gleam/time/calendar.{type Date}
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

/// Max length of an item name. Mirrors the server's `ItemName.MaxLength`.
pub const max_name_length = 128

const input_class = "block w-full rounded-md border border-gray-300 px-3 py-2 text-sm text-gray-900 shadow-sm "
  <> "focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500 "
  <> "disabled:cursor-not-allowed disabled:bg-gray-100 disabled:text-gray-400"

pub type NameError {
  NameRequired
  TooLong
  Duplicate
}

pub type BalanceError {
  BalanceRequired
  NotANumber
  Negative
}

pub type AsOfError {
  AsOfRequired
  NotADate
}

pub type NameField =
  field.Field(String, NameError)

pub type BalanceField =
  field.Field(Float, BalanceError)

pub type AsOfField =
  field.Field(Date, AsOfError)

pub type Form {
  Form(
    name: NameField,
    kind: ItemKind,
    term: Term,
    balance: BalanceField,
    as_of: AsOfField,
  )
}

pub type Modal =
  form_modal.Modal(Form)

pub type Request =
  form_modal.Request(ItemWriteRequest)

pub type Outcome =
  form_modal.Outcome(BalanceSheetItem)

pub fn hidden() -> Modal {
  form_modal.hidden()
}

// Update

pub type Msg {
  // The kind is fixed by the entry point that opened the form; it is never a
  // field, so an item can't be created on the wrong side of the sheet. The
  // as-of date starts at the client's today, when it is known.
  CreateRequested(kind: ItemKind, today: Option(Date))
  EditRequested(item: BalanceSheetItem)
  NameChanged(value: String)
  TermChanged(value: String)
  BalanceChanged(value: String)
  AsOfChanged(value: String)
  SaveRequested
  // Response to the in-flight create or update; the `Created`/`Updated`
  // outcome variant is chosen from the `mode` in the `Submitting` state.
  // Transport timeouts surface here as `Error(NetworkError(...))`.
  SaveCompleted(result: Result(BalanceSheetItem, ApiError))
  // Cancel button, or the browser dismissed the dialog (Esc / outside click)
  CancelRequested
  // Delete button of the edit dialog. The dialog closes, and the page opens
  // the delete confirmation in its place.
  DeleteRequested
}

pub fn update(
  state: Modal,
  msg: Msg,
  items: List(BalanceSheetItem),
) -> #(Modal, Option(Request), Outcome) {
  case msg {
    CreateRequested(kind:, today:) ->
      case state {
        form_modal.Submitting(..) -> #(state, None, form_modal.NoChange)
        _ -> #(create_modal(kind, today), None, form_modal.NoChange)
      }
    EditRequested(item:) ->
      case state {
        form_modal.Submitting(..) -> #(state, None, form_modal.NoChange)
        _ -> #(edit_modal(item), None, form_modal.NoChange)
      }
    NameChanged(value:) -> #(set_name(state, value), None, form_modal.NoChange)
    TermChanged(value:) -> #(set_term(state, value), None, form_modal.NoChange)
    BalanceChanged(value:) -> #(
      set_balance(state, value),
      None,
      form_modal.NoChange,
    )
    AsOfChanged(value:) -> #(set_as_of(state, value), None, form_modal.NoChange)
    SaveRequested -> save(state, items)
    SaveCompleted(result: Ok(item)) -> {
      let #(modal, outcome) = form_modal.succeeded(state, item)
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

/// An empty modal for creating a new item of the given kind, dated today when
/// today is known.
fn create_modal(kind: ItemKind, today: Option(Date)) -> Modal {
  form_modal.create(
    Form(
      name: field.Empty(""),
      kind:,
      term: Current,
      balance: field.Empty(""),
      as_of: case today {
        Some(today) -> field.Valid(value: today, input: date.format(today))
        None -> field.Empty("")
      },
    ),
  )
}

/// A modal pre-filled with an existing item, ready for editing.
fn edit_modal(item: BalanceSheetItem) -> Modal {
  form_modal.edit(
    item.id,
    Form(
      name: field.Valid(value: item.name, input: item.name),
      kind: item.kind,
      term: item.term,
      balance: field.Valid(
        value: item.balance,
        input: money.to_string(item.balance),
      ),
      as_of: field.Valid(value: item.as_of, input: date.format(item.as_of)),
    ),
  )
}

/// Validate and set the name field. No op for Hidden and Submitting states.
fn set_name(state: Modal, name: String) -> Modal {
  form_modal.set_form(state, fn(form) {
    Form(..form, name: field.validate(name, validate_name, is_name_required))
  })
}

/// Set the term field. An unrecognised value is ignored.
fn set_term(state: Modal, value: String) -> Modal {
  case term.parse(value) {
    Ok(term) -> form_modal.set_form(state, fn(form) { Form(..form, term:) })
    Error(Nil) -> state
  }
}

/// Validate and set the balance field. No op for Hidden and Submitting states.
fn set_balance(state: Modal, value: String) -> Modal {
  form_modal.set_form(state, fn(form) {
    let value = money.clip_to_two_dp(value)
    Form(
      ..form,
      balance: field.validate(value, validate_balance, is_balance_required),
    )
  })
}

/// Validate and set the as-of date. No op for Hidden and Submitting states.
fn set_as_of(state: Modal, value: String) -> Modal {
  form_modal.set_form(state, fn(form) {
    Form(
      ..form,
      as_of: field.validate(value, validate_as_of, is_as_of_required),
    )
  })
}

fn save(
  state: Modal,
  items: List(BalanceSheetItem),
) -> #(Modal, Option(Request), Outcome) {
  case form_modal.mode(state) {
    None -> #(state, None, form_modal.NoChange)
    Some(mode) -> {
      let other_items = case mode {
        form_modal.Create -> items
        form_modal.Edit(id:) -> list.filter(items, fn(item) { item.id != id })
      }

      let #(modal, request) =
        form_modal.submit(state, fn(form) { validate_form(form, other_items) })
      #(modal, request, form_modal.NoChange)
    }
  }
}

// Validation

/// Validate the form against the other items. On success returns the write
/// request and the (finalized) form to keep while submitting; on failure
/// returns the form with inline errors set. `other_items` excludes the item
/// being edited, if any.
fn validate_form(
  form: Form,
  other_items: List(BalanceSheetItem),
) -> Result(#(ItemWriteRequest, Form), Form) {
  let form = finalize(form, other_items)

  case
    field.value(form.name),
    field.value(form.balance),
    field.value(form.as_of)
  {
    Some(name), Some(balance), Some(as_of) ->
      Ok(#(
        ItemWriteRequest(
          name:,
          kind: form.kind,
          term: form.term,
          balance:,
          as_of:,
        ),
        form,
      ))
    _, _, _ -> Error(form)
  }
}

/// Finalize the form after a submit attempt: blank fields become errors, and
/// the name is checked against the other items with the same kind and term.
/// The duplicate check mirrors the server's `UNIQUE(UserId, Name, Kind, Term)`
/// constraint so a duplicate is caught inline before the round trip; the server
/// check remains authoritative when the client's list is stale.
fn finalize(form: Form, other_items: List(BalanceSheetItem)) -> Form {
  let Form(name:, kind:, term:, balance:, as_of:) = form
  let name = field.finalize(name, fn() { NameRequired })
  let name = case name {
    field.Valid(value:, ..) ->
      case is_duplicate(other_items, value, kind, term) {
        True -> field.mark_invalid(name, Duplicate)
        False -> name
      }
    field.Empty(..) | field.Invalid(..) -> name
  }
  let balance = field.finalize(balance, fn() { BalanceRequired })
  let as_of = field.finalize(as_of, fn() { AsOfRequired })
  Form(name:, kind:, term:, balance:, as_of:)
}

fn is_duplicate(
  items: List(BalanceSheetItem),
  name: String,
  kind: ItemKind,
  term: Term,
) -> Bool {
  list.any(items, fn(item) {
    item.name == name && item.kind == kind && item.term == term
  })
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
  let trimmed = string.trim(balance)

  case string.is_empty(trimmed) {
    True -> Error(BalanceRequired)
    False ->
      case money.parse_decimal(trimmed) {
        Error(Nil) -> Error(NotANumber)
        Ok(amount) ->
          case amount <. 0.0 {
            True -> Error(Negative)
            False -> Ok(amount)
          }
      }
  }
}

/// A parse error is demoted to a blank `Empty` field (no inline error while
/// typing) only when it is the required error, e.g. a whitespace-only name.
fn is_name_required(error: NameError) -> Bool {
  case error {
    NameRequired -> True
    TooLong | Duplicate -> False
  }
}

fn is_balance_required(error: BalanceError) -> Bool {
  case error {
    BalanceRequired -> True
    NotANumber | Negative -> False
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

fn is_as_of_required(error: AsOfError) -> Bool {
  case error {
    AsOfRequired -> True
    NotADate -> False
  }
}

// View

/// Renders nothing while `Hidden`, otherwise the open dialog. The dialog is
/// locked while a request is in flight so it cannot be dismissed mid-request.
pub fn view(state: Modal) -> Element(Msg) {
  let open = fn(children, submitting) {
    modal_ui.dialog(
      testid: "balance-sheet-item-modal",
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
  let Form(name:, kind:, term:, balance:, as_of:) = form

  let #(title, submit_label, submitting_label) = case mode {
    form_modal.Create ->
      case kind {
        Asset -> #("Add asset", "Add asset", "Adding asset...")
        Liability -> #("Add liability", "Add liability", "Adding liability...")
      }
    form_modal.Edit(_) ->
      case kind {
        Asset -> #("Edit asset", "Save", "Saving...")
        Liability -> #("Edit liability", "Save", "Saving...")
      }
  }

  let balance_invalid = field.has_error(balance)
  let as_of_invalid = field.has_error(as_of)

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
              testid: "balance-sheet-item-api-error",
              message: "Could not save item: " <> message,
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
            attribute.attribute("data-testid", "item-name-input"),
            attribute.placeholder("e.g. Chequing account"),
            attribute.class(input_class),
            attribute.classes([
              #(modal_ui.error_border_style, field.has_error(name)),
            ]),
            attribute.autofocus(True),
            attribute.value(field.input(name)),
            attribute.disabled(submitting),
            event.on_input(NameChanged),
          ]),
          view_name_error(field.error(name)),
        ]),
        term_field(kind, term, submitting),
        html.p([attribute.class("text-xs text-gray-500")], [
          html.text(term_help(kind)),
        ]),
        html.label([attribute.class("block")], [
          html.span(
            [attribute.class("mb-1 block text-sm font-medium text-gray-700")],
            [html.text("Balance")],
          ),
          html.input([
            attribute.type_("text"),
            attribute.attribute("data-testid", "item-balance-input"),
            attribute.inputmode("decimal"),
            attribute.step("0.01"),
            attribute.placeholder("0.00"),
            attribute.min("0"),
            attribute.class(input_class),
            attribute.classes([#(modal_ui.error_border_style, balance_invalid)]),
            attribute.value(field.input(balance)),
            attribute.disabled(submitting),
            event.on_input(BalanceChanged),
          ]),
          view_balance_error(field.error(balance)),
          html.p([attribute.class("mt-1 text-xs text-gray-500")], [
            html.text(balance_help(kind)),
          ]),
        ]),
        html.label([attribute.class("block")], [
          html.span(
            [attribute.class("mb-1 block text-sm font-medium text-gray-700")],
            [html.text("As of")],
          ),
          html.input([
            attribute.type_("date"),
            attribute.attribute("data-testid", "item-as-of-input"),
            attribute.class(input_class),
            attribute.classes([#(modal_ui.error_border_style, as_of_invalid)]),
            attribute.value(field.input(as_of)),
            attribute.disabled(submitting),
            event.on_input(AsOfChanged),
          ]),
          view_as_of_error(field.error(as_of)),
          html.p([attribute.class("mt-1 text-xs text-gray-500")], [
            html.text("The date the balance is accurate as of."),
          ]),
        ]),
        modal_ui.form_footer(
          leading: case mode {
            form_modal.Create -> None
            form_modal.Edit(_) ->
              Some(modal_ui.delete_request_button(
                testid: "item-delete-button",
                disabled: submitting,
                on_click: DeleteRequested,
              ))
          },
          cancel: modal_ui.cancel_button(
            testid: "item-cancel-button",
            disabled: submitting,
            on_click: CancelRequested,
          ),
          submit: modal_ui.submit_button(
            testid: "item-submit-button",
            idle_label: submit_label,
            busy_label: submitting_label,
            busy: submitting,
            disabled: field.has_error(name) || balance_invalid || as_of_invalid,
          ),
        ),
      ],
    ),
  ]
}

fn term_field(kind: ItemKind, term: Term, submitting: Bool) -> Element(Msg) {
  let #(current_label, non_current_label) = term_labels(kind)

  modal_ui.radio_group(
    legend: "Term",
    testid: "item-term",
    disabled: submitting,
    options: [
      #(term.to_string(Current), current_label, term == Current, TermChanged),
      #(
        term.to_string(NonCurrent),
        non_current_label,
        term == NonCurrent,
        TermChanged,
      ),
    ],
  )
}

/// The term labels that read best for the selected kind: assets are liquid or
/// fixed, liabilities are short-term or long-term. The model always stores
/// `Current` or `NonCurrent`.
fn term_labels(kind: ItemKind) -> #(String, String) {
  case kind {
    Asset -> #("Liquid", "Fixed")
    Liability -> #("Short-term", "Long-term")
  }
}

fn term_help(kind: ItemKind) -> String {
  case kind {
    Asset ->
      "A liquid asset is cash, or can be turned into cash quickly without losing value. Everything else is fixed."
    Liability ->
      "A short-term liability is due within about 12 months. Everything else is long-term."
  }
}

fn balance_help(kind: ItemKind) -> String {
  case kind {
    Asset -> "Enter what it is worth. Use zero if it is worth nothing."
    Liability -> "Enter how much is owed. Use zero if nothing is outstanding."
  }
}

fn view_name_error(name_error: Option(NameError)) -> Element(Msg) {
  case name_error {
    Some(NameRequired) -> modal_ui.form_error_message("Name cannot be empty")
    Some(TooLong) ->
      modal_ui.form_error_message(
        "Name cannot be longer than "
        <> int.to_string(max_name_length)
        <> " characters",
      )
    Some(Duplicate) ->
      modal_ui.form_error_message(
        "An identical item already exists for this kind and term",
      )
    None -> element.none()
  }
}

fn view_balance_error(balance_error: Option(BalanceError)) -> Element(Msg) {
  case balance_error {
    Some(BalanceRequired) ->
      modal_ui.form_error_message("Balance cannot be empty")
    Some(NotANumber) -> modal_ui.form_error_message("Not a valid number")
    Some(Negative) ->
      modal_ui.form_error_message(
        "Balance cannot be negative. Use the kind to record what is owed.",
      )
    None -> element.none()
  }
}

fn view_as_of_error(as_of_error: Option(AsOfError)) -> Element(Msg) {
  case as_of_error {
    Some(AsOfRequired) -> modal_ui.form_error_message("Date cannot be empty")
    Some(NotADate) -> modal_ui.form_error_message("Not a valid date")
    None -> element.none()
  }
}
