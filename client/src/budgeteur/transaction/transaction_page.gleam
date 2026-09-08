import budgeteur/shared/api_error.{type ApiError}
import budgeteur/shared/api_route
import budgeteur/shared/date
import budgeteur/shared/delete_modal
import budgeteur/shared/effect.{type Effect}
import budgeteur/shared/form_modal
import budgeteur/shared/money
import budgeteur/shared/out_msg.{type OutMsg}
import budgeteur/shared/response
import budgeteur/transaction/create_transaction_request
import budgeteur/transaction/transaction.{type Transaction}
import budgeteur/transaction/transaction_delete_modal.{type DeleteModalState}
import budgeteur/transaction/transaction_form
import budgeteur/transaction/transaction_page_data
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/string
import gleam/time/calendar
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import youid/uuid.{type Uuid}

pub type Model {
  Model(
    transactions: List(Transaction),
    modal: transaction_form.Modal,
    delete_modal: DeleteModalState,
  )
}

fn persist_transactions(transactions: List(Transaction)) -> Effect(Msg) {
  effect.SaveToStore(
    transaction_page_data.storage_key,
    transaction_page_data.data_to_string(transactions),
  )
}

fn restore_transactions_from_store() -> Effect(Msg) {
  effect.LoadFromStore(
    key: transaction_page_data.storage_key,
    callback: fn(store_result) {
      case store_result {
        Ok(value) -> {
          case json.parse(value, using: transaction_page_data.data_decoder()) {
            Ok(transactions) -> ClientRestoredTransactions(Some(transactions))
            Error(_) -> ClientRestoredTransactions(None)
          }
        }
        Error(_) -> ClientRestoredTransactions(None)
      }
    },
  )
}

pub type Msg {
  ClientRestoredTransactions(Option(List(Transaction)))
  ClientFetchedTransactions(Result(List(Transaction), ApiError))
  // Modal messages
  UserRequestedCreationForm
  UserRequestedEditForm(Uuid)
  TransactionFormMsg(transaction_form.Msg)
  // Delete modal messages
  UserRequestedDeleteForm(Transaction)
  UserConfirmedDelete
  ServerDeletedTransaction(Transaction, Result(Nil, ApiError))
  UserCancelledDeleteModal
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

fn delete_transaction(transaction: Transaction) -> Effect(Msg) {
  effect.delete(
    api_route.DeleteTransaction(transaction.id) |> api_route.to_string,
    fn(result) {
      case result {
        // A successful delete returns 204 with no body, so there is nothing
        // to decode.
        Ok(_) -> ServerDeletedTransaction(transaction, Ok(Nil))
        Error(http_error) ->
          ServerDeletedTransaction(
            transaction,
            Error(response.http_error_to_api_error(http_error)),
          )
      }
    },
  )
  |> effect.with_timeout(delete_modal.delete_timeout_ms)
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
    Model(
      transactions: [],
      modal: transaction_form.hidden(),
      delete_modal: transaction_delete_modal.empty(),
    ),
    effect.batch([
      restore_transactions_from_store(),
      fetch_transactions(),
    ]),
  )
}

pub fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg), Option(OutMsg)) {
  let #(new_model, effect, out_msg) = update_inner(model, msg)

  case msg {
    // Restored data came from the store, so don't write it straight back.
    ClientRestoredTransactions(_) -> #(new_model, effect, out_msg)
    _ ->
      case new_model.transactions == model.transactions {
        True -> #(new_model, effect, out_msg)
        False -> #(
          new_model,
          effect.batch([effect, persist_transactions(new_model.transactions)]),
          out_msg,
        )
      }
  }
}

fn update_inner(
  model: Model,
  msg: Msg,
) -> #(Model, Effect(Msg), Option(OutMsg)) {
  case msg {
    ClientRestoredTransactions(Some(transactions)) -> #(
      Model(..model, transactions: sort_transactions(transactions)),
      effect.none(),
      None,
    )

    ClientRestoredTransactions(None) -> #(model, effect.none(), None)

    ClientFetchedTransactions(Ok(transactions)) -> #(
      Model(..model, transactions: sort_transactions(transactions)),
      effect.none(),
      None,
    )

    ClientFetchedTransactions(Error(error)) -> {
      #(
        model,
        effect.LogError(api_error.describe(error)),
        Some(out_msg.error_toast(
          "Could not sync transactions",
          "Falling back to local data",
        )),
      )
    }

    UserRequestedCreationForm ->
      run_transaction_form(model, transaction_form.CreateRequested)

    UserRequestedEditForm(id) -> {
      case list.find(model.transactions, fn(t) { t.id == id }) {
        Ok(transaction) ->
          run_transaction_form(
            model,
            transaction_form.EditRequested(transaction),
          )
        Error(Nil) -> #(model, effect.none(), None)
      }
    }

    TransactionFormMsg(msg) -> run_transaction_form(model, msg)

    UserRequestedDeleteForm(transaction) -> #(
      Model(..model, delete_modal: transaction_delete_modal.open(transaction)),
      effect.ShowDialog(selector: transaction_delete_modal.dom_id_selector),
      None,
    )

    UserConfirmedDelete -> {
      case delete_modal.confirm(model.delete_modal) {
        Ok(#(state, transaction)) -> #(
          Model(..model, delete_modal: state),
          delete_transaction(transaction),
          None,
        )
        Error(Nil) -> #(model, effect.none(), None)
      }
    }

    ServerDeletedTransaction(transaction, Ok(_)) ->
      on_delete_succeeded(model, transaction)

    ServerDeletedTransaction(transaction, Error(error)) -> {
      case api_error.is_not_found(error) {
        True -> on_delete_succeeded(model, transaction)
        False -> on_delete_failed(model, transaction, error)
      }
    }

    UserCancelledDeleteModal -> #(
      Model(..model, delete_modal: transaction_delete_modal.empty()),
      effect.CloseDialog(selector: transaction_delete_modal.dom_id_selector),
      None,
    )
  }
}

fn run_transaction_form(
  model: Model,
  msg: transaction_form.Msg,
) -> #(Model, Effect(Msg), Option(OutMsg)) {
  let #(modal, requests, outcome) = transaction_form.update(model.modal, msg)
  let model = Model(..model, modal:)
  let error_effect = case msg {
    transaction_form.SaveCompleted(result: Error(error)) ->
      Some(effect.LogError(api_error.describe(error)))
    _ -> None
  }
  fold_form(
    model,
    requests,
    outcome,
    error_effect,
    apply_outcome,
    interpret_transaction_request,
  )
}

fn apply_outcome(
  model: Model,
  outcome: transaction_form.Outcome,
) -> #(Model, Option(OutMsg)) {
  case outcome {
    form_modal.NoChange -> #(model, None)
    form_modal.Created(entity: transaction) -> {
      let transactions =
        [transaction, ..model.transactions] |> sort_transactions
      let model = Model(..model, transactions:)
      #(model, Some(out_msg.success_toast("Transaction created")))
    }
    form_modal.Updated(entity: updated) -> {
      let transactions =
        list.map(model.transactions, fn(t) {
          case t.id == updated.id {
            True -> updated
            False -> t
          }
        })
        |> sort_transactions
      let model = Model(..model, transactions:)
      #(model, Some(out_msg.success_toast("Transaction updated")))
    }
  }
}

fn interpret_transaction_request(
  request: transaction_form.Request,
) -> Effect(Msg) {
  case request {
    form_modal.ShowDialog ->
      effect.ShowDialog(selector: transaction_form.dom_id_selector)
    form_modal.CloseDialog ->
      effect.CloseDialog(selector: transaction_form.dom_id_selector)
    form_modal.Post(payload) ->
      effect.post(
        api_route.CreateTransaction |> api_route.to_string,
        create_transaction_request.create_transaction_request_to_json(payload)
          |> json.to_string,
        handle_save_response,
      )
      |> effect.with_timeout(form_modal.submit_timeout_ms)
      |> effect.map(TransactionFormMsg)
    form_modal.Put(id:, payload:) ->
      effect.put(
        api_route.UpdateTransaction(id) |> api_route.to_string,
        create_transaction_request.create_transaction_request_to_json(payload)
          |> json.to_string,
        handle_save_response,
      )
      |> effect.with_timeout(form_modal.submit_timeout_ms)
      |> effect.map(TransactionFormMsg)
  }
}

fn handle_save_response(result) {
  case result {
    Ok(body) ->
      response.decode_success(body, transaction.transaction_decoder())
      |> transaction_form.SaveCompleted
    Error(http_error) ->
      transaction_form.SaveCompleted(
        Error(response.http_error_to_api_error(http_error)),
      )
  }
}

/// Fold a form's `#(modal, requests, outcome)` triple into page state: store
/// the modal, apply the outcome to the transactions list (with a toast), turn
/// the requests into effects, and log the API error when the triggering
/// message was a save failure.
fn fold_form(
  model: Model,
  requests: List(request),
  outcome: outcome,
  error_effect: Option(Effect(Msg)),
  apply_outcome: fn(Model, outcome) -> #(Model, Option(OutMsg)),
  interpret: fn(request) -> Effect(Msg),
) -> #(Model, Effect(Msg), Option(OutMsg)) {
  let #(model, out_msg) = apply_outcome(model, outcome)
  let effects = list.map(requests, interpret)
  let effects = case error_effect {
    Some(error_effect) -> [error_effect, ..effects]
    None -> effects
  }
  // A single effect stays unwrapped so the caller's persist batching does not
  // nest one-element batches; several effects are batched.
  let effect = case effects {
    [] -> effect.none()
    [effect] -> effect
    _ -> effect.batch(effects)
  }
  #(model, effect, out_msg)
}

fn on_delete_succeeded(
  model: Model,
  transaction: Transaction,
) -> #(Model, Effect(Msg), Option(OutMsg)) {
  #(
    Model(
      ..model,
      transactions: list.filter(model.transactions, fn(t) {
        t.id != transaction.id
      }),
      delete_modal: transaction_delete_modal.empty(),
    ),
    effect.CloseDialog(selector: transaction_delete_modal.dom_id_selector),
    Some(out_msg.success_toast(
      "Deleted transaction " <> transaction.description,
    )),
  )
}

fn on_delete_failed(
  model: Model,
  transaction: Transaction,
  error: ApiError,
) -> #(Model, Effect(Msg), Option(OutMsg)) {
  let updated =
    delete_modal.fail(
      model.delete_modal,
      fn(target) { target == transaction },
      error,
    )
  case updated == model.delete_modal {
    True -> #(model, effect.none(), None)
    False -> #(
      Model(..model, delete_modal: updated),
      effect.LogError(api_error.describe(error)),
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
          attribute.attribute("data-testid", "record-transaction-button"),
          event.on_click(UserRequestedCreationForm),
        ],
        [html.text("Record Transaction")],
      ),
    ]),
    transactions_table(model.transactions),
    transaction_form.view(model.modal)
      |> element.map(TransactionFormMsg),
    transaction_delete_modal.view(
      model.delete_modal,
      on_cancel: UserCancelledDeleteModal,
      on_confirm: UserConfirmedDelete,
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
                  html.th(
                    [attribute.class("px-4 py-3 font-medium text-right")],
                    [html.text("Actions")],
                  ),
                ]),
              ],
            ),
            html.tbody(
              [attribute.class("divide-y divide-gray-200 bg-white")],
              list.map(transactions, fn(transaction) {
                html.tr(
                  [
                    attribute.class("hover:bg-gray-50"),
                    attribute.attribute("data-testid", "transaction-row"),
                  ],
                  [
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
                    html.td(
                      [attribute.class("px-4 py-3 text-sm text-gray-700")],
                      [
                        html.text(transaction.description),
                      ],
                    ),
                    html.td(
                      [
                        attribute.class(
                          "whitespace-nowrap px-4 py-3 text-right",
                        ),
                      ],
                      [
                        html.div(
                          [
                            attribute.class(
                              "flex items-center justify-end gap-2",
                            ),
                          ],
                          [
                            html.button(
                              [
                                attribute.class(
                                  "rounded-md px-3 py-1 text-sm font-medium text-indigo-600 "
                                  <> "hover:bg-indigo-50 hover:text-indigo-700 "
                                  <> "focus:outline-none focus:ring-2 focus:ring-indigo-500 "
                                  <> "focus:ring-offset-2",
                                ),
                                attribute.attribute(
                                  "data-testid",
                                  "edit-transaction-"
                                    <> uuid.to_string(transaction.id),
                                ),
                                event.on_click(UserRequestedEditForm(
                                  transaction.id,
                                )),
                              ],
                              [html.text("Edit")],
                            ),
                            html.button(
                              [
                                attribute.class(
                                  "rounded-md px-3 py-1 text-sm font-medium text-red-600 "
                                  <> "hover:bg-red-50 hover:text-red-700 "
                                  <> "focus:outline-none focus:ring-2 focus:ring-red-500 "
                                  <> "focus:ring-offset-2",
                                ),
                                attribute.attribute(
                                  "data-testid",
                                  "delete-transaction-"
                                    <> uuid.to_string(transaction.id),
                                ),
                                event.on_click(UserRequestedDeleteForm(
                                  transaction,
                                )),
                              ],
                              [html.text("Delete")],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                )
              }),
            ),
          ]),
        ],
      )
  }
}
