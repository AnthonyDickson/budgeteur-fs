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
import budgeteur/transactions/transaction_form.{type Form, type TransactionType}
import gleam/dynamic/decode
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/string
import gleam/time/calendar
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

pub type Model {
  Model(transactions: List(Transaction), form: Form)
}

pub fn model_decoder() -> decode.Decoder(Model) {
  use transactions <- decode.field(
    "transactions",
    decode.list(transaction.transaction_decoder()),
  )
  decode.success(Model(transactions:, form: transaction_form.empty()))
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
  UserRequestedCreationForm
  UserUpdatedFormAmount(String)
  UserUpdatedFormType(TransactionType)
  UserUpdatedFormDescription(String)
  UserUpdatedFormDate(String)
  UserSubmittedCreationForm
  ServerCreatedTransaction(Result(Transaction, ApiError))
  UserCancelledFormModal
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
    Model(transactions: [], form: transaction_form.empty()),
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

    UserRequestedCreationForm -> {
      #(
        Model(..model, form: transaction_form.empty()),
        effect.ShowDialog(selector: "#" <> transaction_form.dom_id),
        None,
      )
    }

    UserUpdatedFormAmount(amount) -> {
      let form = transaction_form.set_amount(model.form, amount)
      #(Model(..model, form:), effect.none(), None)
    }

    UserUpdatedFormType(type_) -> {
      let form = transaction_form.set_type_(model.form, type_)
      #(Model(..model, form:), effect.none(), None)
    }

    UserUpdatedFormDescription(description) -> {
      let form = transaction_form.set_description(model.form, description)
      #(Model(..model, form:), effect.none(), None)
    }

    UserUpdatedFormDate(date) -> {
      let form = transaction_form.set_date(model.form, date)
      #(Model(..model, form:), effect.none(), None)
    }

    UserSubmittedCreationForm -> {
      case transaction_form.validate(model.form) {
        Ok(request) -> #(model, post_create_transaction(request), None)
        Error(error) -> #(
          Model(..model, form: transaction_form.with_error(model.form, error)),
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
        effect.CloseDialog("#" <> transaction_form.dom_id),
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

    UserCancelledFormModal -> #(
      model,
      effect.CloseDialog("#" <> transaction_form.dom_id),
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
            "rounded-md bg-indigo-600 px-4 py-2 text-sm font-medium text-white "
            <> "hover:bg-indigo-500 focus:outline-none focus:ring-2 "
            <> "focus:ring-indigo-500 focus:ring-offset-2",
          ),
          event.on_click(UserRequestedCreationForm),
        ],
        [html.text("Record Transaction")],
      ),
    ]),
    transactions_table(model.transactions),
    transaction_form.view(
      model.form,
      title: "Create Transaction",
      submit_label: "Save Transaction",
      on_amount_input: UserUpdatedFormAmount,
      on_type_click: UserUpdatedFormType,
      on_description_input: UserUpdatedFormDescription,
      on_date_input: UserUpdatedFormDate,
      on_submit: UserSubmittedCreationForm,
      on_cancel: UserCancelledFormModal,
    ),
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
