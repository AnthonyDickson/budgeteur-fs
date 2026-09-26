import budgeteur/balance_sheet_page/balance_sheet_item.{type BalanceSheetItem}
import budgeteur/balance_sheet_page/item_kind.{type ItemKind, Asset, Liability}
import budgeteur/balance_sheet_page/term.{type Term, Current, NonCurrent}
import budgeteur/balance_sheet_page/write_item_request.{
  type WriteBalanceSheetItemRequest, WriteBalanceSheetItemRequest,
}
import budgeteur/shared/api_error.{type ApiError}
import budgeteur/shared/field
import budgeteur/shared/form_modal
import budgeteur/shared/modal_ui
import budgeteur/shared/money
import gleam/dynamic/decode
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

/// Max length of an item name. Mirrors the server's `ItemName.MaxLength`.
pub const max_name_length = 128

const dom_id = "balance_sheet_item_modal"

/// The CSS selector for the modal dialog element. The `#` hash prefix is
/// composed here so callers (e.g. the show/close dialog effects) never have to
/// remember it.
pub const dom_id_selector = "#" <> dom_id

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

pub type NameField =
  field.Field(String, NameError)

pub type BalanceField =
  field.Field(Float, BalanceError)

pub type Form {
  Form(name: NameField, kind: ItemKind, term: Term, balance: BalanceField)
}

pub type Modal =
  form_modal.Modal(Form)

pub type Request =
  form_modal.Request(WriteBalanceSheetItemRequest)

pub type Outcome =
  form_modal.Outcome(BalanceSheetItem)

pub fn hidden() -> Modal {
  form_modal.hidden()
}

// Update

pub type Msg {
  // The kind is fixed by the entry point that opened the form; it is never a
  // field, so an item can't be created on the wrong side of the sheet.
  CreateRequested(kind: ItemKind)
  EditRequested(item: BalanceSheetItem)
  NameChanged(value: String)
  TermChanged(value: String)
  BalanceChanged(value: String)
  SaveRequested
  // Response to the in-flight create or update; the `Created`/`Updated`
  // outcome variant is chosen from the `mode` in the `Submitting` state.
  // Transport timeouts surface here as `Error(NetworkError(...))`.
  SaveCompleted(result: Result(BalanceSheetItem, ApiError))
  // Cancel button (dialog stays open until page closes it)
  CancelRequested
  // browser dismissed the dialog (Esc / backdrop click)
  DialogDismissed
}

pub fn update(
  state: Modal,
  msg: Msg,
  items: List(BalanceSheetItem),
) -> #(Modal, List(Request), Outcome) {
  case msg {
    CreateRequested(kind:) ->
      case state {
        form_modal.Submitting(..) -> #(state, [], form_modal.NoChange)
        _ -> #(create_modal(kind), [form_modal.ShowDialog], form_modal.NoChange)
      }
    EditRequested(item:) ->
      case state {
        form_modal.Submitting(..) -> #(state, [], form_modal.NoChange)
        _ -> #(edit_modal(item), [form_modal.ShowDialog], form_modal.NoChange)
      }
    NameChanged(value:) -> #(set_name(state, value), [], form_modal.NoChange)
    TermChanged(value:) -> #(set_term(state, value), [], form_modal.NoChange)
    BalanceChanged(value:) -> #(
      set_balance(state, value),
      [],
      form_modal.NoChange,
    )
    SaveRequested -> save(state, items)
    SaveCompleted(result: Ok(item)) -> on_save_succeeded(state, item)
    SaveCompleted(result: Error(error)) -> #(
      form_modal.failed(state, error),
      [],
      form_modal.NoChange,
    )
    CancelRequested -> cancel(state)
    DialogDismissed -> #(form_modal.dismissed(state), [], form_modal.NoChange)
  }
}

/// An empty modal for creating a new item of the given kind.
fn create_modal(kind: ItemKind) -> Modal {
  form_modal.create(Form(
    name: field.Empty(""),
    kind:,
    term: Current,
    balance: field.Empty(""),
  ))
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

fn save(
  state: Modal,
  items: List(BalanceSheetItem),
) -> #(Modal, List(Request), Outcome) {
  case form_modal.mode(state) {
    None -> #(state, [], form_modal.NoChange)
    Some(mode) -> {
      let other_items = case mode {
        form_modal.Create -> items
        form_modal.Edit(id:) -> list.filter(items, fn(item) { item.id != id })
      }

      case
        form_modal.submit(state, fn(form) { validate_form(form, other_items) })
      {
        #(modal, Some(request)) -> #(modal, [request], form_modal.NoChange)
        #(modal, None) -> #(modal, [], form_modal.NoChange)
      }
    }
  }
}

fn on_save_succeeded(
  state: Modal,
  item: BalanceSheetItem,
) -> #(Modal, List(Request), Outcome) {
  case form_modal.succeeded(state, item) {
    #(modal, outcome) ->
      case outcome {
        form_modal.NoChange -> #(modal, [], form_modal.NoChange)
        form_modal.Created(_) | form_modal.Updated(_) -> #(
          modal,
          [form_modal.CloseDialog],
          outcome,
        )
      }
  }
}

fn cancel(state: Modal) -> #(Modal, List(Request), Outcome) {
  case form_modal.cancel(state) {
    #(modal, True) -> #(modal, [form_modal.CloseDialog], form_modal.NoChange)
    #(modal, False) -> #(modal, [], form_modal.NoChange)
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
) -> Result(#(WriteBalanceSheetItemRequest, Form), Form) {
  let form = finalize(form, other_items)

  case field.value(form.name), field.value(form.balance) {
    Some(name), Some(balance) ->
      Ok(#(
        WriteBalanceSheetItemRequest(
          name:,
          kind: form.kind,
          term: form.term,
          balance:,
        ),
        form,
      ))
    _, _ -> Error(form)
  }
}

/// Finalize the form after a submit attempt: blank fields become errors, and
/// the name is checked against the other items with the same kind and term.
/// The duplicate check mirrors the server's `UNIQUE(UserId, Name, Kind, Term)`
/// constraint so a duplicate is caught inline before the round trip; the server
/// check remains authoritative when the client's list is stale.
fn finalize(form: Form, other_items: List(BalanceSheetItem)) -> Form {
  let Form(name:, kind:, term:, balance:) = form
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
  Form(name:, kind:, term:, balance:)
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

// View

/// Always renders the `<dialog>` element so the show/close dialog effects can
/// find it. The dialog is `closedby="none"` while a request is in flight,
/// locking it so it cannot be dismissed mid-request. The `on("close")` handler
/// covers browser-initiated dismissals (Esc / backdrop click) while open.
pub fn view(state: Modal) -> Element(Msg) {
  let submitting = case state {
    form_modal.Submitting(..) -> True
    _ -> False
  }

  html.dialog(
    [
      event.on("close", decode.success(DialogDismissed)),
      ..modal_ui.dialog_attributes(
        dom_id,
        "balance-sheet-item-modal",
        submitting,
      )
    ],
    case state {
      form_modal.Hidden -> []
      form_modal.Active(form:, mode:) ->
        view_form(form, mode, api_error: None, submitting: False)
      form_modal.Submitting(form:, mode:) ->
        view_form(form, mode, api_error: None, submitting: True)
      form_modal.Errored(form:, mode:, error:) ->
        view_form(form, mode, api_error: Some(error), submitting: False)
    },
  )
}

fn view_form(
  form: Form,
  mode: form_modal.Mode,
  api_error api_error: Option(String),
  submitting submitting: Bool,
) -> List(Element(Msg)) {
  let Form(name:, kind:, term:, balance:) = form

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
        html.div([attribute.class("flex justify-end gap-3 pt-2")], [
          modal_ui.cancel_button(
            testid: "item-cancel-button",
            disabled: submitting,
            on_click: CancelRequested,
          ),
          modal_ui.submit_button(
            testid: "item-submit-button",
            idle_label: submit_label,
            busy_label: submitting_label,
            busy: submitting,
            disabled: field.has_error(name) || balance_invalid,
          ),
        ]),
      ],
    ),
  ]
}

fn term_field(kind: ItemKind, term: Term, submitting: Bool) -> Element(Msg) {
  let #(current_label, non_current_label) = term_labels(kind)

  radio_group(
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

/// A radio group for a closed set of two options. Kept local to this modal;
/// promote it to `modal_ui` when a second form needs one.
fn radio_group(
  legend legend: String,
  testid testid: String,
  disabled disabled: Bool,
  options options: List(#(String, String, Bool, fn(String) -> Msg)),
) -> Element(Msg) {
  html.fieldset([attribute.class("block")], [
    html.legend(
      [attribute.class("mb-1 block text-sm font-medium text-gray-700")],
      [html.text(legend)],
    ),
    html.div(
      [attribute.class("grid grid-cols-2 gap-2")],
      list.map(options, fn(option) {
        let #(value, label, selected, on_change) = option

        let option_class = case selected {
          True -> "border-indigo-600 bg-indigo-50 font-medium text-indigo-700"
          False -> "border-gray-300 bg-white text-gray-700 hover:bg-gray-50"
        }

        let option_class = case disabled {
          True -> option_class <> " cursor-not-allowed opacity-60"
          False -> option_class
        }

        html.label(
          [
            attribute.class(
              "flex cursor-pointer items-center gap-2 rounded-md border px-3 py-2 text-sm "
              <> option_class,
            ),
          ],
          [
            html.input([
              attribute.type_("radio"),
              attribute.name(testid),
              attribute.value(value),
              attribute.checked(selected),
              attribute.attribute("data-testid", testid <> "-" <> value),
              attribute.class(
                "h-4 w-4 border-gray-300 text-indigo-600 focus:ring-indigo-500 disabled:cursor-not-allowed",
              ),
              attribute.disabled(disabled),
              event.on_change(on_change),
            ]),
            html.text(label),
          ],
        )
      }),
    ),
  ])
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
