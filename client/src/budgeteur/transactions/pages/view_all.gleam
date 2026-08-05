import budgeteur/api_error.{type ApiError}
import budgeteur/api_route
import budgeteur/effect.{type Effect}
import budgeteur/money
import budgeteur/response
import budgeteur/transactions/transaction.{type Transaction}
import gleam/dynamic/decode
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{Some}
import gleam/pair
import gleam/string
import gleam/time/calendar
import gleam/time/timestamp.{type Timestamp}
import lustre/element.{type Element}
import lustre/element/html

pub type Model {
  Model(transactions: List(Transaction))
}

pub fn model_to_json(model: Model) -> Json {
  let Model(transactions:) = model
  json.object([
    #("transactions", json.array(transactions, transaction.transaction_to_json)),
  ])
}

pub type Msg {
  ClientFetchedTransactions(Result(List(Transaction), ApiError))
}

fn fetch_transactions() -> effect.Effect(Msg) {
  effect.get(api_route.GetAllTransactions |> api_route.to_string, fn(result) {
    case result {
      Ok(body) ->
        ClientFetchedTransactions(response.decode_success(
          body,
          decode.list(transaction.transaction_decoder()),
        ))
      Error(http_err) ->
        ClientFetchedTransactions(
          Error(response.http_error_to_api_error(http_err)),
        )
    }
  })
}

pub fn init() -> #(Model, Effect(Msg)) {
  #(Model(transactions: []), fetch_transactions())
}

pub fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    ClientFetchedTransactions(Ok(transactions)) -> #(
      Model(transactions:),
      effect.none(),
    )
    ClientFetchedTransactions(Error(error)) ->
      case error.status_code {
        Some(401) -> #(model, effect.Redirect("/login"))
        _ -> {
          // TODO: Centralise toasts on app.gleam? Pros: keeps toasts an app level
          // concern rather than page level. Cons: wiring between parent and child apps
          //
          // let toast =
          //   Toast(
          //     id: uuid.v7(),
          //     title: "Could not sync todos",
          //     body: "Falling back to local data",
          //   )
          // #(
          //   Model(..model, toasts: list.append(model.toasts, [toast])),
          //   effect.batch([
          //     effect.LogError(api_error.describe(error)),
          //     effect.After(5000, ToastDismissed(toast.id)),
          //   ]),
          // )
          #(model, effect.LogError(api_error.describe(error)))
        }
      }
  }
}

pub fn view(model: Model) -> Element(Msg) {
  html.div([], [
    html.p([], [
      html.text("Hello, world!"),
    ]),
    transactions_table(model.transactions),
  ])
}

fn timestamp_to_naive_date_string(timestamp: Timestamp) -> String {
  let date =
    timestamp
    |> timestamp.to_calendar(calendar.local_offset())
    |> pair.first

  let year = date.year |> int.to_string
  let month =
    date.month
    |> calendar.month_to_int
    |> int.to_string
    |> string.pad_start(to: 2, with: "0")
  let day = date.day |> int.to_string |> string.pad_start(to: 2, with: "0")

  year <> "-" <> month <> "-" <> day
}

fn transactions_table(
  transactions: List(transaction.Transaction),
) -> Element(Msg) {
  case list.is_empty(transactions) {
    True -> element.none()
    False ->
      html.table([], [
        html.caption([], [
          html.text("All transactions"),
        ]),
        html.thead([], [
          html.tr([], [
            html.th([], [html.text("Date")]),
            html.th([], [html.text("Amount")]),
            html.th([], [html.text("Description")]),
          ]),
        ]),
        html.tbody(
          [],
          list.map(transactions, fn(transaction) {
            html.tr([], [
              html.td([], [
                html.text(transaction.date |> timestamp_to_naive_date_string),
              ]),
              html.td([], [
                html.text(transaction.amount |> money.format),
              ]),
              html.td([], [
                html.text(transaction.description),
              ]),
            ])
          }),
        ),
      ])
  }
}
