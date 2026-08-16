import budgeteur/date
import budgeteur/money
import budgeteur/transactions/create_transaction_request.{
  type CreateTransactionRequest,
}
import budgeteur/transactions/transaction.{type Transaction, Transaction}
import gleam/float
import gleam/int
import gleam/option.{type Option, None, Some}
import gleam/string
import gleam/time/calendar.{type Date}
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import youid/uuid.{type Uuid}

pub const max_description_length = 256

const dom_id = "transaction_modal"

/// The CSS selector for the modal dialog element. The `#` hash prefix is
/// composed here so callers (e.g. the show/close dialog effects) never have to
/// remember it.
pub const dom_id_selector = "#" <> dom_id

const error_border_style = "border-red-400 focus:border-red-500 focus:outline-none focus:ring-1 focus:ring-red-500"

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

pub type AmountField {
  EmptyAmount(input: String)
  ValidAmount(value: Float, input: String)
  InvalidAmount(input: String, error: AmountError)
}

pub type DescriptionField {
  EmptyDescription(input: String)
  ValidDescription(input: String)
  InvalidDescription(input: String, error: DescriptionError)
}

pub type DateField {
  EmptyDate(input: String)
  ValidDate(value: Date, input: String)
  InvalidDate(input: String, error: DateError)
}

pub type Form {
  Form(
    amount: AmountField,
    type_: TransactionType,
    is_transfer: Bool,
    description: DescriptionField,
    date: DateField,
  )
}

/// The mode the transaction form modal is in.
pub type FormMode {
  /// Open an empty form
  Create
  /// Pre-fill the form with an existing transaction
  Edit(id: Uuid)
}

/// State of the transaction form modal: the form fields, the mode, and whether
/// a create/update request is in flight (the submit button is disabled while
/// submitting).
pub type ModalState {
  ModalState(form: Form, mode: FormMode, submitting: Bool)
}

pub fn empty() -> Form {
  Form(
    amount: EmptyAmount(""),
    type_: Debit,
    is_transfer: False,
    description: EmptyDescription(""),
    date: EmptyDate(""),
  )
}

pub fn empty_modal() -> ModalState {
  ModalState(form: empty(), mode: Create, submitting: False)
}

/// A modal pre-filled with an existing transaction, ready for editing.
pub fn edit_modal(transaction: Transaction) -> ModalState {
  let Transaction(id:, ..) = transaction
  ModalState(
    form: from_transaction(transaction),
    mode: Edit(id),
    submitting: False,
  )
}

/// Build a form pre-filled with an existing transaction's values. The stored
/// amount is signed (debit = negative); the form expresses the sign via the
/// type toggle, so the amount is converted to its absolute value.
pub fn from_transaction(transaction: Transaction) -> Form {
  let Transaction(
    id: _,
    amount:,
    description:,
    date:,
    is_transfer:,
    account_id: _,
    category_id: _,
  ) = transaction

  let type_ = case amount <. 0.0 {
    True -> Debit
    False -> Credit
  }

  let amount = amount |> float.absolute_value

  Form(
    amount: ValidAmount(value: amount, input: money.to_string(amount)),
    type_:,
    is_transfer:,
    description: ValidDescription(input: description),
    date: ValidDate(value: date, input: date.format(date)),
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

pub fn set_amount(state: ModalState, amount: String) -> ModalState {
  let ModalState(form:, ..) = state
  ModalState(..state, form: set_form_amount(form, amount))
}

fn set_form_amount(form: Form, amount: String) -> Form {
  let amount = clip_amount_to_two_dp(amount)
  let amount = case string.is_empty(amount) {
    True -> EmptyAmount(amount)
    False ->
      case validate_amount(amount) {
        Ok(value) -> ValidAmount(value: value, input: amount)
        Error(error) -> InvalidAmount(input: amount, error:)
      }
  }
  Form(..form, amount:)
}

pub fn set_type_(state: ModalState, type_: TransactionType) -> ModalState {
  let ModalState(form:, ..) = state
  ModalState(..state, form: Form(..form, type_:))
}

pub fn set_is_transfer(state: ModalState, is_transfer: Bool) -> ModalState {
  let ModalState(form:, ..) = state
  ModalState(..state, form: Form(..form, is_transfer:))
}

pub fn set_description(state: ModalState, description: String) -> ModalState {
  let ModalState(form:, ..) = state
  ModalState(..state, form: set_form_description(form, description))
}

fn set_form_description(form: Form, description: String) -> Form {
  let description = case validate_description(description) {
    Ok(_) -> ValidDescription(input: description)
    Error(DescriptionRequired) -> EmptyDescription(description)
    Error(TooLong) -> InvalidDescription(input: description, error: TooLong)
  }
  Form(..form, description:)
}

pub fn set_date(state: ModalState, date: String) -> ModalState {
  let ModalState(form:, ..) = state
  ModalState(..state, form: set_form_date(form, date))
}

fn set_form_date(form: Form, date: String) -> Form {
  let date = case validate_date(date) {
    Ok(value) -> ValidDate(value:, input: date)
    Error(DateRequired) -> EmptyDate(date)
    Error(NotADate) -> InvalidDate(input: date, error: NotADate)
  }
  Form(..form, date:)
}

fn finalize(form: Form) -> Form {
  let Form(amount:, description:, date:, ..) = form
  Form(
    ..form,
    amount: case amount {
      EmptyAmount(input) -> InvalidAmount(input:, error: AmountRequired)
      other -> other
    },
    description: case description {
      EmptyDescription(input) ->
        InvalidDescription(input:, error: DescriptionRequired)
      other -> other
    },
    date: case date {
      EmptyDate(input) -> InvalidDate(input:, error: DateRequired)
      other -> other
    },
  )
}

pub fn validate(state: ModalState) -> Result(CreateTransactionRequest, Form) {
  let ModalState(form:, ..) = state
  let form = finalize(form)

  case form {
    Form(
      amount: ValidAmount(value: amount_value, ..),
      type_:,
      is_transfer:,
      description: ValidDescription(input: description),
      date: ValidDate(value: date, ..),
    ) -> {
      let amount = case type_ {
        Debit -> -1.0 *. amount_value
        Credit -> amount_value
      }

      create_transaction_request.CreateTransactionRequest(
        amount:,
        description: string.trim(description),
        date:,
        is_transfer:,
      )
      |> Ok
    }

    _ -> Error(form)
  }
}

fn field_amount_input(field: AmountField) -> String {
  case field {
    EmptyAmount(input) -> input
    ValidAmount(input:, ..) -> input
    InvalidAmount(input:, ..) -> input
  }
}

fn field_description_input(field: DescriptionField) -> String {
  case field {
    EmptyDescription(input) -> input
    ValidDescription(input) -> input
    InvalidDescription(input:, ..) -> input
  }
}

fn field_date_input(field: DateField) -> String {
  case field {
    EmptyDate(input) -> input
    ValidDate(input:, ..) -> input
    InvalidDate(input:, ..) -> input
  }
}

fn field_amount_error(field: AmountField) -> Option(AmountError) {
  case field {
    InvalidAmount(error:, ..) -> Some(error)
    _ -> None
  }
}

fn field_description_error(
  field: DescriptionField,
) -> Option(DescriptionError) {
  case field {
    InvalidDescription(error:, ..) -> Some(error)
    _ -> None
  }
}

fn field_date_error(field: DateField) -> Option(DateError) {
  case field {
    InvalidDate(error:, ..) -> Some(error)
    _ -> None
  }
}

pub fn view(
  state: ModalState,
  on_amount_input on_amount_input: fn(String) -> msg,
  on_type_click on_type_click: fn(TransactionType) -> msg,
  on_is_transfer_input on_is_transfer_input: fn(Bool) -> msg,
  on_description_input on_description_input: fn(String) -> msg,
  on_date_input on_date_input: fn(String) -> msg,
  on_submit on_submit: msg,
  on_cancel on_cancel: msg,
) -> Element(msg) {
  let ModalState(form:, mode:, submitting:) = state

  let #(title, submit_label) = case mode {
    Create -> #("Create Transaction", "Save Transaction")
    Edit(_) -> #("Edit Transaction", "Update Transaction")
  }

  let Form(amount:, type_:, is_transfer:, description:, date:) = form

  let amount_error = field_amount_error(amount)
  let description_error = field_description_error(description)
  let date_error = field_date_error(date)

  let has_error =
    option.is_some(amount_error)
    || option.is_some(description_error)
    || option.is_some(date_error)

  html.dialog(
    [
      attribute.id(dom_id),
      attribute.attribute("data-testid", "transaction-modal"),
      attribute.class(
        "mx-auto my-auto w-full max-w-md rounded-lg border border-gray-200 bg-white p-6 shadow-xl backdrop:bg-gray-900/50",
      ),
      // "closedby" = "any" is needed to allow the dialog to be closed by
      // clicking outside the dialog.
      attribute.attribute("closedby", "any"),
    ],
    [
      html.h2([attribute.class("mb-4 text-lg font-semibold text-gray-900")], [
        html.text(title),
      ]),
      html.form(
        [
          event.on_submit(fn(_) { on_submit }),
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
              attribute.value(field_amount_input(amount)),
              attribute.class(
                "block w-full rounded-md border border-gray-300 px-3 py-2 text-sm text-gray-900 shadow-sm "
                <> "focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500",
              ),
              attribute.classes([
                #(error_border_style, option.is_some(amount_error)),
              ]),
              event.on_input(on_amount_input),
            ]),
            case amount_error {
              Some(NotANumber) -> form_error_message("Not a valid number")
              Some(NotPositive) -> form_error_message("Amount must be positive")
              Some(AmountRequired) ->
                form_error_message("Amount cannot be empty")
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
                    event.on_click(on_type_click(Debit)),
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
                    attribute.attribute(
                      "data-testid",
                      "transaction-type-credit",
                    ),
                    attribute.name("transaction_type"),
                    attribute.checked(type_ == Credit),
                    attribute.class(
                      "h-4 w-4 border-gray-300 text-indigo-600 focus:ring-indigo-500",
                    ),
                    event.on_click(on_type_click(Credit)),
                  ]),
                  html.text("Credit"),
                ],
              ),
            ]),
          ]),
          html.label([attribute.class("flex items-center gap-2")], [
            html.input([
              attribute.type_("checkbox"),
              attribute.attribute(
                "data-testid",
                "transaction-is-transfer-input",
              ),
              attribute.name("is_transfer"),
              attribute.checked(is_transfer),
              attribute.class(
                "h-4 w-4 rounded border-gray-300 text-indigo-600 focus:ring-indigo-500",
              ),
              event.on_check(on_is_transfer_input),
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
              attribute.attribute(
                "data-testid",
                "transaction-description-input",
              ),
              attribute.placeholder("What was this for?"),
              attribute.class(
                "block w-full rounded-md border border-gray-300 px-3 py-2 text-sm text-gray-900 shadow-sm "
                <> "focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500",
              ),
              attribute.classes([
                #(error_border_style, option.is_some(description_error)),
              ]),
              attribute.minlength(1),
              attribute.value(field_description_input(description)),
              event.on_input(on_description_input),
            ]),
            case description_error {
              Some(DescriptionRequired) ->
                form_error_message("Description cannot be empty")
              Some(TooLong) ->
                form_error_message(
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
                <> "focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500",
              ),
              attribute.classes([
                #(error_border_style, option.is_some(date_error)),
              ]),
              attribute.value(field_date_input(date)),
              event.on_input(on_date_input),
            ]),
            case date_error {
              Some(NotADate) -> form_error_message("Not a valid date")
              Some(DateRequired) -> form_error_message("Date cannot be empty")
              None -> element.none()
            },
          ]),
          html.div([attribute.class("flex justify-end gap-3 pt-2")], [
            html.button(
              [
                attribute.type_("button"),
                attribute.attribute("data-testid", "transaction-cancel-button"),
                attribute.class(
                  "rounded-md border border-gray-300 bg-white px-4 py-2 text-sm font-medium text-gray-700 "
                  <> "hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-gray-500 focus:ring-offset-2",
                ),
                event.on_click(on_cancel),
              ],
              [html.text("Cancel")],
            ),
            html.button(
              [
                attribute.type_("submit"),
                attribute.attribute("data-testid", "transaction-submit-button"),
                attribute.class(
                  "inline-flex items-center justify-center gap-2 rounded-md bg-indigo-600 px-4 py-2 text-sm font-medium "
                  <> "text-white hover:bg-indigo-500 focus:outline-none focus:ring-2 focus:ring-indigo-500 "
                  <> "focus:ring-offset-2 disabled:cursor-not-allowed disabled:bg-gray-400 disabled:hover:bg-gray-400",
                ),
                attribute.disabled(has_error || submitting),
              ],
              case submitting {
                True -> [
                  html.span(
                    [
                      attribute.attribute("aria-hidden", "true"),
                      attribute.class(
                        "h-4 w-4 animate-spin rounded-full border-2 border-white/40 border-t-white",
                      ),
                    ],
                    [],
                  ),
                  html.text(submit_label),
                ]
                False -> [html.text(submit_label)]
              },
            ),
          ]),
        ],
      ),
    ],
  )
}

fn form_error_message(text: String) -> Element(msg) {
  html.p([attribute.class("mt-1 text-sm text-red-600")], [html.text(text)])
}
