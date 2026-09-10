import budgeteur/shared/api_error.{type ApiError}
import budgeteur/shared/date
import budgeteur/shared/field
import budgeteur/shared/form_modal
import budgeteur/shared/modal_ui
import budgeteur/shared/money
import budgeteur/transaction/create_transaction_request.{
  type CreateTransactionRequest,
}
import budgeteur/transaction/transaction.{type Transaction, Transaction}
import gleam/dynamic/decode
import gleam/float
import gleam/int
import gleam/option.{type Option, None, Some}
import gleam/string
import gleam/time/calendar.{type Date}
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

pub const max_description_length = 256

const dom_id = "transaction_modal"

/// The CSS selector for the modal dialog element. The `#` hash prefix is
/// composed here so callers (e.g. the show/close dialog effects) never have to
/// remember it.
pub const dom_id_selector = "#" <> dom_id

pub type TransactionType {
  Debit
  Credit
}

pub type AmountError {
  NotANumber
  NotPositive
  AmountRequired
}

pub type DescriptionError {
  DescriptionRequired
  TooLong
}

pub type DateError {
  NotADate
  DateRequired
}

pub type AmountField =
  field.Field(Float, AmountError)

pub type DescriptionField =
  field.Field(String, DescriptionError)

pub type DateField =
  field.Field(Date, DateError)

pub type Form {
  Form(
    amount: AmountField,
    type_: TransactionType,
    is_transfer: Bool,
    description: DescriptionField,
    date: DateField,
  )
}

pub type Modal =
  form_modal.Modal(Form)

pub type Request =
  form_modal.Request(CreateTransactionRequest)

pub type Outcome =
  form_modal.Outcome(Transaction)

pub fn hidden() -> Modal {
  form_modal.hidden()
}

// Update

pub type Msg {
  // "Record Transaction" clicked; the modal opens with an empty form.
  CreateRequested
  // Row "Edit" clicked; the page looks the transaction up first.
  EditRequested(transaction: Transaction)
  AmountChanged(value: String)
  TypeChanged(type_: TransactionType)
  IsTransferChanged(is_transfer: Bool)
  DescriptionChanged(value: String)
  DateChanged(value: String)
  SaveRequested
  // Response to the in-flight create or update; the `Created`/`Updated`
  // outcome variant is chosen from the `mode` in the `Submitting` state.
  // Transport timeouts surface here as `Error(NetworkError(...))`.
  SaveCompleted(result: Result(Transaction, ApiError))
  // Cancel button (dialog stays open until page closes it)
  CancelRequested
  // browser dismissed the dialog (Esc / backdrop click)
  DialogDismissed
}

pub fn update(state: Modal, msg: Msg) -> #(Modal, List(Request), Outcome) {
  case msg {
    CreateRequested ->
      case state {
        form_modal.Submitting(..) -> #(state, [], form_modal.NoChange)
        _ -> #(create_modal(), [form_modal.ShowDialog], form_modal.NoChange)
      }
    EditRequested(transaction:) ->
      case state {
        form_modal.Submitting(..) -> #(state, [], form_modal.NoChange)
        _ -> #(
          edit_modal(transaction),
          [form_modal.ShowDialog],
          form_modal.NoChange,
        )
      }
    AmountChanged(value:) -> #(
      set_amount(state, value),
      [],
      form_modal.NoChange,
    )
    TypeChanged(type_:) -> #(set_type(state, type_), [], form_modal.NoChange)
    IsTransferChanged(is_transfer:) -> #(
      set_is_transfer(state, is_transfer),
      [],
      form_modal.NoChange,
    )
    DescriptionChanged(value:) -> #(
      set_description(state, value),
      [],
      form_modal.NoChange,
    )
    DateChanged(value:) -> #(set_date(state, value), [], form_modal.NoChange)
    SaveRequested -> save(state)
    SaveCompleted(result: Ok(transaction)) ->
      on_save_succeeded(state, transaction)
    SaveCompleted(result: Error(error)) -> #(
      form_modal.failed(state, error),
      [],
      form_modal.NoChange,
    )
    CancelRequested -> cancel(state)
    DialogDismissed -> #(form_modal.dismissed(state), [], form_modal.NoChange)
  }
}

/// An empty modal for recording a new transaction.
fn create_modal() -> Modal {
  form_modal.create(empty_form())
}

/// A modal pre-filled with an existing transaction, ready for editing.
fn edit_modal(transaction: Transaction) -> Modal {
  let Transaction(id:, ..) = transaction
  form_modal.edit(id, from_transaction(transaction))
}

/// An empty form. The modal always opens fresh (D2), so no values are
/// retained across open/close.
fn empty_form() -> Form {
  Form(
    amount: field.Empty(""),
    type_: Debit,
    is_transfer: False,
    description: field.Empty(""),
    date: field.Empty(""),
  )
}

/// Build a form pre-filled with an existing transaction's values. The stored
/// amount is signed (debit = negative); the form expresses the sign via the
/// type toggle, so the amount is converted to its absolute value.
fn from_transaction(transaction: Transaction) -> Form {
  let Transaction(
    id: _,
    amount:,
    description:,
    date:,
    is_transfer:,
    account_id: _,
    tag_id: _,
  ) = transaction

  let type_ = case amount <. 0.0 {
    True -> Debit
    False -> Credit
  }

  let amount = amount |> float.absolute_value

  Form(
    amount: field.Valid(value: amount, input: money.to_string(amount)),
    type_:,
    is_transfer:,
    description: field.Valid(value: description, input: description),
    date: field.Valid(value: date, input: date.format(date)),
  )
}

/// Note: only clips valid numbers such as "1.234".
/// Invalid numbers such as "12.." and "12.34.56" pass through for the validation
/// layer to catch the issue.
pub fn clip_amount_to_two_dp(amount: String) -> String {
  case string.split(amount, ".") {
    [whole, fraction] ->
      whole <> "." <> string.slice(from: fraction, at_index: 0, length: 2)
    _ -> amount
  }
}

/// Validate and set the amount field. No op for Hidden and Submitting states.
fn set_amount(state: Modal, amount: String) -> Modal {
  form_modal.set_form(state, fn(form) {
    let amount = clip_amount_to_two_dp(amount)
    Form(
      ..form,
      amount: field.validate(amount, validate_amount, is_amount_required),
    )
  })
}

/// The amount has no "blank while typing" demotion beyond a truly empty
/// input; a blank amount is only flagged at submit time by `finalize`.
fn is_amount_required(error: AmountError) -> Bool {
  case error {
    AmountRequired -> True
    NotANumber | NotPositive -> False
  }
}

/// Validate and set the type field. No op for Hidden and Submitting states.
fn set_type(state: Modal, type_: TransactionType) -> Modal {
  form_modal.set_form(state, fn(form) { Form(..form, type_:) })
}

/// Validate and set the transfer flag. No op for Hidden and Submitting
/// states.
fn set_is_transfer(state: Modal, is_transfer: Bool) -> Modal {
  form_modal.set_form(state, fn(form) { Form(..form, is_transfer:) })
}

/// Validate and set the description field. No op for Hidden and Submitting
/// states.
fn set_description(state: Modal, description: String) -> Modal {
  form_modal.set_form(state, fn(form) {
    Form(
      ..form,
      description: field.validate(
        description,
        validate_description,
        is_description_required,
      ),
    )
  })
}

/// A whitespace-only description parses to the required error and is demoted
/// to a blank `Empty` field (no inline error while typing).
fn is_description_required(error: DescriptionError) -> Bool {
  case error {
    DescriptionRequired -> True
    TooLong -> False
  }
}

/// Validate and set the date field. No op for Hidden and Submitting states.
fn set_date(state: Modal, date: String) -> Modal {
  form_modal.set_form(state, fn(form) {
    Form(..form, date: field.validate(date, validate_date, is_date_required))
  })
}

/// A whitespace-only date parses to the required error and is demoted to a
/// blank `Empty` field (no inline error while typing).
fn is_date_required(error: DateError) -> Bool {
  case error {
    DateRequired -> True
    NotADate -> False
  }
}

fn validate_amount(amount_string: String) -> Result(Float, AmountError) {
  case float.parse(amount_string) {
    Ok(amount) ->
      case amount <. 0.0 {
        True -> Error(NotPositive)
        False -> Ok(amount)
      }

    Error(Nil) ->
      case int.parse(amount_string) {
        Ok(amount) -> {
          let amount = int.to_float(amount)

          case amount <. 0.0 {
            True -> Error(NotPositive)
            False -> Ok(amount)
          }
        }

        Error(Nil) -> Error(NotANumber)
      }
  }
}

fn validate_description(
  description: String,
) -> Result(String, DescriptionError) {
  let trimmed = string.trim(description)

  case string.is_empty(trimmed) {
    True -> Error(DescriptionRequired)
    False ->
      case string.length(trimmed) > max_description_length {
        True -> Error(TooLong)
        False -> Ok(trimmed)
      }
  }
}

fn validate_date(date_string: String) -> Result(Date, DateError) {
  let trimmed = string.trim(date_string)

  case string.is_empty(trimmed) {
    True -> Error(DateRequired)
    False ->
      case date.parse(trimmed) {
        Ok(date) -> Ok(date)
        Error(Nil) -> Error(NotADate)
      }
  }
}

fn save(state: Modal) -> #(Modal, List(Request), Outcome) {
  case form_modal.submit(state, validate_form) {
    #(modal, Some(request)) -> #(modal, [request], form_modal.NoChange)
    #(modal, None) -> #(modal, [], form_modal.NoChange)
  }
}

fn on_save_succeeded(
  state: Modal,
  transaction: Transaction,
) -> #(Modal, List(Request), Outcome) {
  case form_modal.succeeded(state, transaction) {
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

/// Finalize the form after a submit attempt so the blank fields show their
/// required errors, then build the write request if every field is valid.
/// Debit amounts are negated in the request; the form keeps the unsigned
/// amount (the type toggle expresses the sign).
fn validate_form(
  form: Form,
) -> Result(#(CreateTransactionRequest, Form), Form) {
  let form = finalize(form)

  let Form(amount:, type_:, is_transfer:, description:, date:) = form

  case field.value(amount), field.value(description), field.value(date) {
    Some(amount_value), Some(description), Some(date) -> {
      let amount = case type_ {
        Debit -> -1.0 *. amount_value
        Credit -> amount_value
      }

      Ok(#(
        create_transaction_request.CreateTransactionRequest(
          amount:,
          description:,
          date:,
          is_transfer:,
        ),
        form,
      ))
    }

    _, _, _ -> Error(form)
  }
}

/// Promote the blank fields to their required errors so the inline messages
/// appear after a submit attempt. Fields already `Valid` or `Invalid` are
/// left untouched.
fn finalize(form: Form) -> Form {
  let Form(amount:, description:, date:, ..) = form
  Form(
    ..form,
    amount: field.finalize(amount, fn() { AmountRequired }),
    description: field.finalize(description, fn() { DescriptionRequired }),
    date: field.finalize(date, fn() { DateRequired }),
  )
}

// View

pub fn view(state: Modal) -> Element(Msg) {
  let submitting = case state {
    form_modal.Submitting(..) -> True
    _ -> False
  }

  html.dialog(
    [
      event.on("close", decode.success(DialogDismissed)),
      ..modal_ui.dialog_attributes(dom_id, "transaction-modal", submitting)
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
  let #(title, submit_label, submitting_label) = case mode {
    form_modal.Create -> #(
      "Create Transaction",
      "Save Transaction",
      "Saving...",
    )
    form_modal.Edit(_) -> #(
      "Edit Transaction",
      "Update Transaction",
      "Updating...",
    )
  }

  let Form(amount:, type_:, is_transfer:, description:, date:) = form

  let amount_error = field.error(amount)
  let description_error = field.error(description)
  let date_error = field.error(date)

  let has_error =
    field.has_error(amount)
    || field.has_error(description)
    || field.has_error(date)

  [
    html.h2([attribute.class("mb-4 text-lg font-semibold text-gray-900")], [
      html.text(title),
    ]),
    case api_error {
      Some(message) ->
        modal_ui.error_banner(
          testid: "transaction-api-error",
          message: "Could not save transaction: " <> message,
          extra_class: "",
        )
      None -> element.none()
    },
    html.form(
      [
        event.on_submit(fn(_) { SaveRequested }),
        attribute.class("space-y-4"),
      ],
      [
        html.label([attribute.class("block")], [
          html.span(
            [attribute.class("mb-1 block text-sm font-medium text-gray-700")],
            [html.text("Amount")],
          ),
          html.input([
            attribute.type_("text"),
            attribute.attribute("data-testid", "transaction-amount-input"),
            attribute.inputmode("decimal"),
            attribute.step("0.01"),
            attribute.placeholder("0.00"),
            attribute.min("0"),
            attribute.value(field.input(amount)),
            attribute.class(
              "block w-full rounded-md border border-gray-300 px-3 py-2 text-sm text-gray-900 shadow-sm "
              <> "focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500 "
              <> "disabled:cursor-not-allowed disabled:bg-gray-100 disabled:text-gray-400",
            ),
            attribute.classes([
              #(modal_ui.error_border_style, field.has_error(amount)),
            ]),
            attribute.disabled(submitting),
            event.on_input(AmountChanged),
          ]),
          case amount_error {
            Some(NotANumber) ->
              modal_ui.form_error_message("Not a valid number")
            Some(NotPositive) ->
              modal_ui.form_error_message("Amount must be positive")
            Some(AmountRequired) ->
              modal_ui.form_error_message("Amount cannot be empty")
            None -> element.none()
          },
        ]),
        html.fieldset([attribute.class("block")], [
          html.legend(
            [attribute.class("mb-1 block text-sm font-medium text-gray-700")],
            [html.text("Type")],
          ),
          html.div([attribute.class("grid grid-cols-2 gap-3")], [
            html.label(
              [
                attribute.class(
                  "flex cursor-pointer items-center justify-center gap-2 rounded-md border border-gray-300 bg-white "
                  <> "px-4 py-2 text-sm font-medium text-gray-700 shadow-sm hover:bg-gray-50 "
                  <> "has-checked:border-indigo-600 has-checked:bg-indigo-50 has-checked:text-indigo-700",
                ),
              ],
              [
                html.input([
                  attribute.type_("radio"),
                  attribute.attribute("data-testid", "transaction-type-debit"),
                  attribute.name("transaction_type"),
                  attribute.checked(type_ == Debit),
                  attribute.class(
                    "h-4 w-4 border-gray-300 text-indigo-600 focus:ring-indigo-500",
                  ),
                  attribute.disabled(submitting),
                  event.on_click(TypeChanged(Debit)),
                ]),
                html.text("Debit"),
              ],
            ),
            html.label(
              [
                attribute.class(
                  "flex cursor-pointer items-center justify-center gap-2 rounded-md border border-gray-300 bg-white "
                  <> "px-4 py-2 text-sm font-medium text-gray-700 shadow-sm hover:bg-gray-50 "
                  <> "has-checked:border-indigo-600 has-checked:bg-indigo-50 has-checked:text-indigo-700",
                ),
              ],
              [
                html.input([
                  attribute.type_("radio"),
                  attribute.attribute("data-testid", "transaction-type-credit"),
                  attribute.name("transaction_type"),
                  attribute.checked(type_ == Credit),
                  attribute.class(
                    "h-4 w-4 border-gray-300 text-indigo-600 focus:ring-indigo-500",
                  ),
                  attribute.disabled(submitting),
                  event.on_click(TypeChanged(Credit)),
                ]),
                html.text("Credit"),
              ],
            ),
          ]),
        ]),
        html.label([attribute.class("flex items-center gap-2")], [
          html.input([
            attribute.type_("checkbox"),
            attribute.attribute("data-testid", "transaction-is-transfer-input"),
            attribute.name("is_transfer"),
            attribute.checked(is_transfer),
            attribute.class(
              "h-4 w-4 rounded border-gray-300 text-indigo-600 focus:ring-indigo-500",
            ),
            attribute.disabled(submitting),
            event.on_check(IsTransferChanged),
          ]),
          html.span([attribute.class("text-sm font-medium text-gray-700")], [
            html.text("Transfer between my own accounts"),
          ]),
        ]),
        html.label([attribute.class("block")], [
          html.span(
            [attribute.class("mb-1 block text-sm font-medium text-gray-700")],
            [html.text("Description")],
          ),
          html.input([
            attribute.type_("text"),
            attribute.attribute("data-testid", "transaction-description-input"),
            attribute.placeholder("What was this for?"),
            attribute.class(
              "block w-full rounded-md border border-gray-300 px-3 py-2 text-sm text-gray-900 shadow-sm "
              <> "focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500 "
              <> "disabled:cursor-not-allowed disabled:bg-gray-100 disabled:text-gray-400",
            ),
            attribute.classes([
              #(modal_ui.error_border_style, field.has_error(description)),
            ]),
            attribute.minlength(1),
            attribute.value(field.input(description)),
            attribute.disabled(submitting),
            event.on_input(DescriptionChanged),
          ]),
          case description_error {
            Some(DescriptionRequired) ->
              modal_ui.form_error_message("Description cannot be empty")
            Some(TooLong) ->
              modal_ui.form_error_message(
                "Description cannot be longer than "
                <> int.to_string(max_description_length)
                <> " characters",
              )
            None -> element.none()
          },
        ]),
        html.label([attribute.class("block")], [
          html.span(
            [attribute.class("mb-1 block text-sm font-medium text-gray-700")],
            [html.text("Date")],
          ),
          html.input([
            attribute.type_("date"),
            attribute.attribute("data-testid", "transaction-date-input"),
            attribute.class(
              "block w-full rounded-md border border-gray-300 px-3 py-2 text-sm text-gray-900 shadow-sm "
              <> "focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500 "
              <> "disabled:cursor-not-allowed disabled:bg-gray-100 disabled:text-gray-400",
            ),
            attribute.classes([
              #(modal_ui.error_border_style, field.has_error(date)),
            ]),
            attribute.value(field.input(date)),
            attribute.disabled(submitting),
            event.on_input(DateChanged),
          ]),
          case date_error {
            Some(NotADate) -> modal_ui.form_error_message("Not a valid date")
            Some(DateRequired) ->
              modal_ui.form_error_message("Date cannot be empty")
            None -> element.none()
          },
        ]),
        html.div([attribute.class("flex justify-end gap-3 pt-2")], [
          modal_ui.cancel_button(
            testid: "transaction-cancel-button",
            disabled: submitting,
            on_click: CancelRequested,
          ),
          modal_ui.submit_button(
            testid: "transaction-submit-button",
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
