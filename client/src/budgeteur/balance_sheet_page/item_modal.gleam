//// The item form: creates an item with its first value, or edits an item's
//// name and term. An item's side is fixed at creation, and its later values
//// are recorded with the value form. See decision 2 in docs/reports.md.

import budgeteur/balance_sheet_page/balance_sheet_item.{type BalanceSheetItem}
import budgeteur/balance_sheet_page/item_write_request.{
  type ItemWriteRequest, CreateItem, UpdateItem,
}
import budgeteur/balance_sheet_page/value_form
import budgeteur/shared/api_error.{type ApiError}
import budgeteur/shared/field
import budgeteur/shared/form_modal
import budgeteur/shared/side.{type Side, Asset, Liability}
import budgeteur/shared/term.{type Term, Current, NonCurrent}
import budgeteur/shared/ui/dialog
import budgeteur/shared/ui/input
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

pub type NameError {
  NameRequired
  TooLong
  Duplicate
}

pub type NameField =
  field.Field(String, NameError)

pub type Form {
  Form(
    name: NameField,
    side: Side,
    term: Term,
    // The first value of a new item; None when editing.
    opening_value: Option(value_form.Form),
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
  // The side is fixed by the entry point that opened the form; it is never a
  // field, so an item can't be created on the wrong side of the sheet. The
  // as-of date of the first value starts at the client's today, when it is
  // known.
  CreateRequested(side: Side, today: Option(Date))
  EditRequested(item: BalanceSheetItem)
  NameChanged(value: String)
  TermChanged(value: String)
  ValueMsg(value_form.Msg)
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
    CreateRequested(side:, today:) ->
      case state {
        form_modal.Submitting(..) -> #(state, None, form_modal.NoChange)
        _ -> #(create_modal(side, today), None, form_modal.NoChange)
      }
    EditRequested(item:) ->
      case state {
        form_modal.Submitting(..) -> #(state, None, form_modal.NoChange)
        _ -> #(edit_modal(item), None, form_modal.NoChange)
      }
    NameChanged(value:) -> #(set_name(state, value), None, form_modal.NoChange)
    TermChanged(value:) -> #(set_term(state, value), None, form_modal.NoChange)
    ValueMsg(value_msg) -> #(
      form_modal.set_form(state, fn(form) {
        Form(
          ..form,
          opening_value: option.map(form.opening_value, value_form.update(
            _,
            value_msg,
          )),
        )
      }),
      None,
      form_modal.NoChange,
    )
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

/// An empty modal for creating a new item on the given side, with its first
/// value dated today when today is known.
fn create_modal(side: Side, today: Option(Date)) -> Modal {
  form_modal.create(Form(
    name: field.Empty(""),
    side:,
    term: Current,
    opening_value: Some(value_form.empty(today)),
  ))
}

/// A modal pre-filled with an existing item's details, ready for editing.
fn edit_modal(item: BalanceSheetItem) -> Modal {
  form_modal.edit(
    item.id,
    Form(
      name: field.Valid(value: item.name, input: item.name),
      side: item.side,
      term: item.term,
      opening_value: None,
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
/// being edited, if any. A form with a first value creates an item; one
/// without updates it.
fn validate_form(
  form: Form,
  other_items: List(BalanceSheetItem),
) -> Result(#(ItemWriteRequest, Form), Form) {
  let name = finalize_name(form, other_items)
  let opening = option.map(form.opening_value, value_form.validate)
  let form =
    Form(
      ..form,
      name:,
      opening_value: option.map(opening, fn(result) {
        case result {
          Ok(#(_, value)) | Error(value) -> value
        }
      }),
    )

  case field.value(name), opening {
    Some(name), Some(Ok(#(first, _))) ->
      Ok(#(CreateItem(name:, side: form.side, term: form.term, first:), form))
    Some(name), None -> Ok(#(UpdateItem(name:, term: form.term), form))
    _, _ -> Error(form)
  }
}

/// Finalize the name after a submit attempt: a blank name is an error, and it
/// is checked against the other items with the same side and term. The
/// duplicate check mirrors the server's `UNIQUE(UserId, Name, Side, Term)`
/// constraint so a duplicate is caught inline before the round trip; the server
/// check remains authoritative when the client's list is stale.
fn finalize_name(form: Form, other_items: List(BalanceSheetItem)) -> NameField {
  let name = field.finalize(form.name, fn() { NameRequired })
  case name {
    field.Valid(value:, ..) ->
      case is_duplicate(other_items, value, form.side, form.term) {
        True -> field.mark_invalid(name, Duplicate)
        False -> name
      }
    field.Empty(..) | field.Invalid(..) -> name
  }
}

fn is_duplicate(
  items: List(BalanceSheetItem),
  name: String,
  side: Side,
  term: Term,
) -> Bool {
  list.any(items, fn(item) {
    item.name == name && item.side == side && item.term == term
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

/// A parse error is demoted to a blank `Empty` field (no inline error while
/// typing) only when it is the required error, e.g. a whitespace-only name.
fn is_name_required(error: NameError) -> Bool {
  case error {
    NameRequired -> True
    TooLong | Duplicate -> False
  }
}

// View

/// Renders nothing while `Hidden`, otherwise the open dialog. The dialog is
/// locked while a request is in flight so it cannot be dismissed mid-request.
pub fn view(state: Modal) -> Element(Msg) {
  let open = fn(children, submitting) {
    dialog.dialog(
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
  let Form(name:, side:, term:, opening_value:) = form

  let #(title, submit_label, submitting_label) = case mode {
    form_modal.Create ->
      case side {
        Asset -> #("Add asset", "Add asset", "Adding asset...")
        Liability -> #("Add liability", "Add liability", "Adding liability...")
      }
    form_modal.Edit(_) ->
      case side {
        Asset -> #("Edit asset", "Save", "Saving...")
        Liability -> #("Edit liability", "Save", "Saving...")
      }
  }

  let value_invalid = case opening_value {
    Some(value) -> value_form.has_error(value)
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
              testid: "balance-sheet-item-api-error",
              message: "Could not save item: " <> message,
              extra_class: "",
            )
          None -> element.none()
        },
        html.label([attribute.class("block")], [
          input.label("Name"),
          input.text([
            attribute.type_("text"),
            attribute.attribute("data-testid", "item-name-input"),
            attribute.placeholder("e.g. House"),
            attribute.autofocus(True),
            attribute.value(field.input(name)),
            attribute.disabled(submitting),
            event.on_input(NameChanged),
            input.invalid(field.has_error(name)),
          ]),
          view_name_error(field.error(name)),
        ]),
        term_field(side, term, submitting),
        html.p([attribute.class("text-xs text-gray-500")], [
          html.text(term_help(side)),
        ]),
        case opening_value {
          Some(value) ->
            value_form.view(
              value,
              side:,
              submitting:,
              note: "Later values are recorded from the item's line.",
            )
            |> element.map(ValueMsg)
          None -> element.none()
        },
        dialog.form_footer(
          leading: case mode {
            form_modal.Create -> None
            form_modal.Edit(_) ->
              Some(dialog.delete_request_button(
                testid: "item-delete-button",
                disabled: submitting,
                on_click: DeleteRequested,
              ))
          },
          cancel: dialog.cancel_button(
            testid: "item-cancel-button",
            disabled: submitting,
            on_click: CancelRequested,
          ),
          submit: dialog.submit_button(
            testid: "item-submit-button",
            idle_label: submit_label,
            busy_label: submitting_label,
            busy: submitting,
            disabled: field.has_error(name) || value_invalid,
          ),
        ),
      ],
    ),
  ]
}

fn term_field(side: Side, term: Term, submitting: Bool) -> Element(Msg) {
  let current_label = term.label(Current, side)
  let non_current_label = term.label(NonCurrent, side)

  input.radio_group(
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

fn term_help(side: Side) -> String {
  case side {
    Asset ->
      "A liquid asset is cash, or can be turned into cash quickly without losing value. Everything else is fixed."
    Liability ->
      "A short-term liability is due within about 12 months. Everything else is long-term."
  }
}

fn view_name_error(name_error: Option(NameError)) -> Element(Msg) {
  case name_error {
    Some(NameRequired) -> input.error_message("Name cannot be empty")
    Some(TooLong) ->
      input.error_message(
        "Name cannot be longer than "
        <> int.to_string(max_name_length)
        <> " characters",
      )
    Some(Duplicate) ->
      input.error_message(
        "An identical item already exists for this side and term",
      )
    None -> element.none()
  }
}
