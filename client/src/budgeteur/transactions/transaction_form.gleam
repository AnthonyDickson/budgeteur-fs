import budgeteur/date
import budgeteur/transactions/create_transaction_request.{
  type CreateTransactionRequest,
}
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

pub const dom_id = "transaction_modal"

const error_border_style = "border-red-400 focus:border-red-500 focus:outline-none focus:ring-1 focus:ring-red-500"

pub type TransactionType {
  Debit
  Credit
}

pub type AmountError {
  NotANumber
  NotPositive
}

pub type DescriptionError {
  EmptyDescription
  TooLong
}

pub type DateError {
  NotADate
  EmptyDate
}

pub type FormError {
  FormError(
    amount: Option(AmountError),
    description: Option(DescriptionError),
    date: Option(DateError),
  )
}

pub fn empty_error() -> FormError {
  FormError(amount: None, description: None, date: None)
}

pub type Form {
  Form(
    amount: String,
    type_: TransactionType,
    description: String,
    date: String,
    error: FormError,
  )
}

pub fn empty() -> Form {
  Form(
    amount: "",
    type_: Debit,
    description: "",
    date: "",
    error: empty_error(),
  )
}

/// Build a form from known-good values without running validation. Used when
/// pre-filling the form for an existing transaction (e.g. the edit modal).
pub fn from(
  amount: String,
  type_: TransactionType,
  description: String,
  date: String,
) -> Form {
  Form(amount:, type_:, description:, date:, error: empty_error())
}

pub fn clip_amount_to_two_dp(amount: String) -> String {
  case string.split(amount, ".") {
    [whole, fraction, ..] ->
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
    True -> Error(EmptyDescription)
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
    True -> Error(EmptyDate)
    False ->
      case date.parse(trimmed) {
        Ok(date) -> Ok(date)
        Error(Nil) -> Error(NotADate)
      }
  }
}

fn error_from(result: Result(_, a)) -> Option(a) {
  case result {
    Ok(_) -> None
    Error(error) -> Some(error)
  }
}

pub fn set_amount(form: Form, amount: String) -> Form {
  let amount = clip_amount_to_two_dp(amount)
  let error =
    FormError(..form.error, amount: error_from(validate_amount(amount)))
  Form(..form, amount:, error:)
}

pub fn set_type_(form: Form, type_: TransactionType) -> Form {
  Form(..form, type_:)
}

pub fn set_description(form: Form, description: String) -> Form {
  let error =
    FormError(
      ..form.error,
      description: error_from(validate_description(description)),
    )
  Form(..form, description:, error:)
}

pub fn set_date(form: Form, date: String) -> Form {
  let error = FormError(..form.error, date: error_from(validate_date(date)))
  Form(..form, date:, error:)
}

pub fn with_error(form: Form, error: FormError) -> Form {
  Form(..form, error:)
}

/// Pure validation — returns a request on success, the full error map otherwise.
pub fn validate(form: Form) -> Result(CreateTransactionRequest, FormError) {
  let Form(amount:, type_:, description:, date:, error: _) = form

  let amount = validate_amount(amount)
  let description = validate_description(description)
  let date = validate_date(date)

  case amount, description, date {
    Ok(amount), Ok(description), Ok(date) -> {
      let amount = case type_ {
        Debit -> -1.0 *. amount
        Credit -> amount
      }

      create_transaction_request.CreateTransactionRequest(
        amount:,
        description: description,
        date: date,
      )
      |> Ok
    }

    _, _, _ ->
      FormError(
        amount: error_from(amount),
        description: error_from(description),
        date: error_from(date),
      )
      |> Error
  }
}

pub fn view(
  form: Form,
  title title: String,
  submit_label submit_label: String,
  on_amount_input on_amount_input: fn(String) -> msg,
  on_type_click on_type_click: fn(TransactionType) -> msg,
  on_description_input on_description_input: fn(String) -> msg,
  on_date_input on_date_input: fn(String) -> msg,
  on_submit on_submit: msg,
  on_cancel on_cancel: msg,
) -> Element(msg) {
  let Form(amount:, type_:, description:, date:, error:) = form

  let FormError(
    amount: amount_error,
    description: description_error,
    date: date_error,
  ) = error

  let has_error =
    option.is_some(amount_error)
    || option.is_some(description_error)
    || option.is_some(date_error)

  html.dialog(
    [
      attribute.id(dom_id),
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
              attribute.inputmode("decimal"),
              attribute.step("0.01"),
              attribute.placeholder("0.00"),
              attribute.min("0"),
              attribute.value(amount),
              attribute.class(
                "block w-full rounded-md border border-gray-300 px-3 py-2 text-sm text-gray-900 shadow-sm focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500",
              ),
              attribute.classes([
                #(error_border_style, option.is_some(amount_error)),
              ]),
              event.on_input(on_amount_input),
            ]),
            case amount_error {
              Some(NotANumber) -> form_error_message("Not a valid number")
              Some(NotPositive) -> form_error_message("Amount must be positive")
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
                    "flex cursor-pointer items-center justify-center gap-2 rounded-md border border-gray-300 bg-white px-4 py-2 text-sm font-medium text-gray-700 shadow-sm hover:bg-gray-50 has-checked:border-indigo-600 has-checked:bg-indigo-50 has-checked:text-indigo-700",
                  ),
                ],
                [
                  html.input([
                    attribute.type_("radio"),
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
                    "flex cursor-pointer items-center justify-center gap-2 rounded-md border border-gray-300 bg-white px-4 py-2 text-sm font-medium text-gray-700 shadow-sm hover:bg-gray-50 has-checked:border-indigo-600 has-checked:bg-indigo-50 has-checked:text-indigo-700",
                  ),
                ],
                [
                  html.input([
                    attribute.type_("radio"),
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
          html.label([attribute.class("block")], [
            html.span(
              [attribute.class("mb-1 block text-sm font-medium text-gray-700")],
              [html.text("Description")],
            ),
            html.input([
              attribute.type_("text"),
              attribute.placeholder("What was this for?"),
              attribute.class(
                "block w-full rounded-md border border-gray-300 px-3 py-2 text-sm text-gray-900 shadow-sm focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500",
              ),
              attribute.classes([
                #(error_border_style, option.is_some(description_error)),
              ]),
              attribute.minlength(1),
              attribute.value(description),
              event.on_input(on_description_input),
            ]),
            case description_error {
              Some(EmptyDescription) ->
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
              attribute.class(
                "block w-full rounded-md border border-gray-300 px-3 py-2 text-sm text-gray-900 shadow-sm focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500",
              ),
              attribute.classes([
                #(error_border_style, option.is_some(date_error)),
              ]),
              attribute.value(date),
              event.on_input(on_date_input),
            ]),
            case date_error {
              Some(NotADate) -> form_error_message("Not a valid date")
              Some(EmptyDate) -> form_error_message("Date cannot be empty")
              None -> element.none()
            },
          ]),
          html.div([attribute.class("flex justify-end gap-3 pt-2")], [
            html.button(
              [
                attribute.type_("button"),
                attribute.class(
                  "rounded-md border border-gray-300 bg-white px-4 py-2 text-sm font-medium text-gray-700 hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-gray-500 focus:ring-offset-2",
                ),
                event.on_click(on_cancel),
              ],
              [html.text("Cancel")],
            ),
            html.button(
              [
                attribute.type_("submit"),
                attribute.class(
                  "rounded-md bg-indigo-600 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-500 focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:ring-offset-2 disabled:cursor-not-allowed disabled:bg-gray-400 disabled:hover:bg-gray-400",
                ),
                attribute.disabled(has_error),
              ],
              [html.text(submit_label)],
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
