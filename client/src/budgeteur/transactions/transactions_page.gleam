import budgeteur/api_error.{type ApiError}
import budgeteur/api_route
import budgeteur/date
import budgeteur/effect.{type Effect}
import budgeteur/money
import budgeteur/out_msg.{type OutMsg}
import budgeteur/response
import budgeteur/toast
import budgeteur/transactions/create_transaction_request.{
  type CreateTransactionRequest,
}
import budgeteur/transactions/transaction.{type Transaction}
import gleam/dynamic/decode
import gleam/float
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/string
import gleam/time/calendar.{type Date}
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

const error_border_style = "border-red-400 focus:border-red-500 focus:outline-none focus:ring-1 focus:ring-red-500"

const modal_dom_id = "transaction_modal"

const max_description_length = 256

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

pub type ModalError {
  ModalError(
    amount: Option(AmountError),
    description: Option(DescriptionError),
    date: Option(DateError),
  )
}

fn empty_modal_error() -> ModalError {
  ModalError(amount: None, description: None, date: None)
}

pub type Modal {
  CreateTransactionModal(
    amount: String,
    type_: TransactionType,
    description: String,
    date: String,
    error: ModalError,
  )
}

fn empty_create_transaction_modal() -> Modal {
  CreateTransactionModal(
    amount: "",
    type_: Debit,
    description: "",
    date: "",
    error: empty_modal_error(),
  )
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
        Ok(amount) -> Ok(int.to_float(amount))
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

fn validate_request(
  modal: Modal,
) -> Result(CreateTransactionRequest, ModalError) {
  let CreateTransactionModal(amount:, type_:, description:, date:, error: _) =
    modal

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
      ModalError(
        amount: error_from(amount),
        description: error_from(description),
        date: error_from(date),
      )
      |> Error
  }
}

pub type Model {
  Model(transactions: List(Transaction), modal: Modal)
}

pub fn model_decoder() -> decode.Decoder(Model) {
  use transactions <- decode.field(
    "transactions",
    decode.list(transaction.transaction_decoder()),
  )
  decode.success(Model(transactions:, modal: empty_create_transaction_modal()))
}

pub fn model_to_json(model: Model) -> Json {
  let Model(transactions:, ..) = model
  json.object([
    #("transactions", json.array(transactions, transaction.transaction_to_json)),
  ])
}

pub type Msg {
  ClientFetchedTransactions(Result(List(Transaction), ApiError))
  // Modal messages
  UserRequestedCreateModal
  UserUpdatedModalAmount(String)
  UserUpdatedModalType(TransactionType)
  UserUpdatedModalDescription(String)
  UserUpdatedModalDate(String)
  UserSubmittedCreateModal
  ServerCreatedTransaction(Result(Transaction, ApiError))
  UserCancelledModal
}

// TODO: Page results
fn fetch_transactions() -> Effect(Msg) {
  effect.get(api_route.GetAllTransactions |> api_route.to_string, fn(result) {
    case result {
      Ok(body) ->
        ClientFetchedTransactions(response.decode_success(
          body,
          decode.list(transaction.transaction_decoder()),
        ))
      Error(http_error) ->
        ClientFetchedTransactions(
          Error(response.http_error_to_api_error(http_error)),
        )
    }
  })
}

fn post_create_transaction(request: CreateTransactionRequest) -> Effect(Msg) {
  effect.post(
    api_route.CreateTransaction |> api_route.to_string,
    create_transaction_request.create_transaction_request_to_json(request)
      |> json.to_string,
    fn(result) {
      case result {
        Ok(body) ->
          response.decode_success(body, transaction.transaction_decoder())
          |> ServerCreatedTransaction
        Error(http_error) ->
          ServerCreatedTransaction(
            Error(response.http_error_to_api_error(http_error)),
          )
      }
    },
  )
}

fn sort_transactions(transactions: List(Transaction)) -> List(Transaction) {
  list.sort(transactions, by: fn(a, b) {
    calendar.naive_date_compare(a.date, b.date)
    |> order.negate
    |> order.lazy_break_tie(fn() {
      string.compare(a.description, b.description)
    })
  })
}

pub fn init() -> #(Model, Effect(Msg)) {
  #(
    Model(transactions: [], modal: empty_create_transaction_modal()),
    fetch_transactions(),
  )
}

pub fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg), Option(OutMsg)) {
  case msg {
    ClientFetchedTransactions(Ok(transactions)) -> #(
      Model(..model, transactions: sort_transactions(transactions)),
      effect.none(),
      None,
    )

    ClientFetchedTransactions(Error(error)) -> {
      #(
        model,
        effect.LogError(api_error.describe(error)),
        Some(out_msg.PageRequestedToast(
          title: "Could not sync transactions",
          body: "Falling back to local data",
          level: toast.Error,
          dismiss_after_ms: Some(5000),
        )),
      )
    }

    UserRequestedCreateModal -> {
      #(
        Model(..model, modal: empty_create_transaction_modal()),
        effect.ShowDialog(selector: "#" <> modal_dom_id),
        None,
      )
    }

    UserUpdatedModalAmount(amount) -> {
      let amount = clip_amount_to_two_dp(amount)
      let error =
        ModalError(
          ..model.modal.error,
          amount: error_from(validate_amount(amount)),
        )

      #(
        Model(
          ..model,
          modal: CreateTransactionModal(..model.modal, amount:, error:),
        ),
        effect.none(),
        None,
      )
    }

    UserUpdatedModalType(type_) -> #(
      Model(..model, modal: CreateTransactionModal(..model.modal, type_:)),
      effect.none(),
      None,
    )

    UserUpdatedModalDescription(description) -> {
      let error =
        ModalError(
          ..model.modal.error,
          description: error_from(validate_description(description)),
        )

      #(
        Model(
          ..model,
          modal: CreateTransactionModal(..model.modal, description:, error:),
        ),
        effect.none(),
        None,
      )
    }

    UserUpdatedModalDate(date) -> {
      let error =
        ModalError(..model.modal.error, date: error_from(validate_date(date)))

      #(
        Model(
          ..model,
          modal: CreateTransactionModal(..model.modal, date:, error:),
        ),
        effect.none(),
        None,
      )
    }

    UserSubmittedCreateModal -> {
      case validate_request(model.modal) {
        Ok(request) -> #(model, post_create_transaction(request), None)
        Error(error) -> #(
          Model(..model, modal: CreateTransactionModal(..model.modal, error:)),
          effect.none(),
          None,
        )
      }
    }

    ServerCreatedTransaction(Ok(transaction)) -> {
      #(
        Model(
          ..model,
          transactions: [transaction, ..model.transactions] |> sort_transactions,
        ),
        effect.CloseDialog("#" <> modal_dom_id),
        Some(out_msg.PageRequestedToast(
          title: "Success",
          body: "Transaction created",
          level: toast.Success,
          dismiss_after_ms: Some(5000),
        )),
      )
    }

    ServerCreatedTransaction(Error(error)) -> #(
      model,
      effect.LogError(api_error.describe(error)),
      Some(out_msg.PageRequestedToast(
        title: "Error",
        body: "Could not create transaction",
        level: toast.Error,
        dismiss_after_ms: Some(5000),
      )),
    )

    UserCancelledModal -> #(
      model,
      effect.CloseDialog("#" <> modal_dom_id),
      None,
    )
  }
}

pub fn view(model: Model) -> Element(Msg) {
  html.div([attribute.class("mx-auto max-w-4xl px-4 py-8 sm:px-6")], [
    html.div([attribute.class("flex items-center justify-between gap-4 mb-6")], [
      html.h1([attribute.class("text-2xl font-semibold text-gray-900")], [
        html.text("Transactions"),
      ]),
      html.button(
        [
          attribute.class(
            "rounded-md bg-indigo-600 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-500 focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:ring-offset-2",
          ),
          event.on_click(UserRequestedCreateModal),
        ],
        [html.text("Record Transaction")],
      ),
    ]),
    transactions_table(model.transactions),
    create_transaction_modal(model.modal),
  ])
}

fn transactions_table(transactions: List(Transaction)) -> Element(Msg) {
  case list.is_empty(transactions) {
    True -> element.none()
    False ->
      html.div(
        [
          attribute.class(
            "overflow-hidden rounded-lg border border-gray-200 shadow-sm",
          ),
        ],
        [
          html.table([attribute.class("min-w-full divide-y divide-gray-200")], [
            html.caption([attribute.class("sr-only")], [
              html.text("All transactions"),
            ]),
            html.thead(
              [
                attribute.class(
                  "bg-gray-50 text-left text-xs font-medium uppercase tracking-wide text-gray-500",
                ),
              ],
              [
                html.tr([], [
                  html.th([attribute.class("px-4 py-3 font-medium")], [
                    html.text("Date"),
                  ]),
                  html.th(
                    [attribute.class("px-4 py-3 font-medium text-right")],
                    [
                      html.text("Amount"),
                    ],
                  ),
                  html.th([attribute.class("px-4 py-3 font-medium")], [
                    html.text("Description"),
                  ]),
                ]),
              ],
            ),
            html.tbody(
              [attribute.class("divide-y divide-gray-200 bg-white")],
              list.map(transactions, fn(transaction) {
                html.tr([attribute.class("hover:bg-gray-50")], [
                  html.td(
                    [
                      attribute.class(
                        "whitespace-nowrap px-4 py-3 text-sm text-gray-700",
                      ),
                    ],
                    [html.text(transaction.date |> date.format)],
                  ),
                  html.td(
                    [
                      attribute.class(
                        "whitespace-nowrap px-4 py-3 text-sm tabular-nums text-gray-900 text-right",
                      ),
                    ],
                    [html.text(transaction.amount |> money.format)],
                  ),
                  html.td([attribute.class("px-4 py-3 text-sm text-gray-700")], [
                    html.text(transaction.description),
                  ]),
                ])
              }),
            ),
          ]),
        ],
      )
  }
}

fn create_transaction_modal(modal: Modal) -> Element(Msg) {
  let CreateTransactionModal(amount:, type_:, description:, date:, error:) =
    modal

  let ModalError(
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
      attribute.id(modal_dom_id),
      attribute.class(
        "mx-auto my-auto w-full max-w-md rounded-lg border border-gray-200 bg-white p-6 shadow-xl backdrop:bg-gray-900/50",
      ),
      // "closedby" = "any" is needed to allow the dialog to be closed by
      // clicking outside the dialog.
      attribute.attribute("closedby", "any"),
    ],
    [
      html.h2([attribute.class("mb-4 text-lg font-semibold text-gray-900")], [
        html.text("Create Transaction"),
      ]),
      html.form(
        [
          event.on_submit(fn(_) { UserSubmittedCreateModal }),
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
              event.on_input(UserUpdatedModalAmount),
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
                    event.on_click(UserUpdatedModalType(Debit)),
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
                    event.on_click(UserUpdatedModalType(Credit)),
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
              event.on_input(UserUpdatedModalDescription),
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
              event.on_input(UserUpdatedModalDate),
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
                event.on_click(UserCancelledModal),
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
              [html.text("Save Transaction")],
            ),
          ]),
        ],
      ),
    ],
  )
}

fn form_error_message(text: String) -> Element(Msg) {
  html.p([attribute.class("mt-1 text-sm text-red-600")], [html.text(text)])
}
