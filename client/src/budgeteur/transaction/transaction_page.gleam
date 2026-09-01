import budgeteur/shared/api_error.{type ApiError}
import budgeteur/shared/api_route
import budgeteur/shared/date
import budgeteur/shared/effect.{type Effect}
import budgeteur/shared/money
import budgeteur/shared/out_msg.{type OutMsg}
import budgeteur/shared/response
import budgeteur/shared/toast
import budgeteur/transaction/create_transaction_request.{
  type CreateTransactionRequest,
}
import budgeteur/transaction/transaction.{type Transaction}
import budgeteur/transaction/transaction_delete_modal.{
  type DeleteModalState, Confirming, Deleting,
}
import budgeteur/transaction/transaction_form.{
  type ModalState, type TransactionType, Create, Edit, ModalState,
}
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

const transactions_storage_key = "budgeteur.transactions"

pub type Model {
  Model(
    transactions: List(Transaction),
    modal: ModalState,
    delete_modal: DeleteModalState,
  )
}

pub fn stored_transactions_encoder(transactions: List(Transaction)) -> String {
  json.object([
    #("transactions", json.array(transactions, transaction.transaction_to_json)),
  ])
  |> json.to_string
}

fn persist_transactions(transactions: List(Transaction)) -> Effect(Msg) {
  effect.SaveToStore(
    transactions_storage_key,
    stored_transactions_encoder(transactions),
  )
}

pub fn stored_transactions_decoder() -> decode.Decoder(List(Transaction)) {
  decode.field(
    "transactions",
    decode.list(transaction.transaction_decoder()),
    fn(transactions) { decode.success(transactions) },
  )
}

fn restore_transactions_from_store() -> Effect(Msg) {
  effect.LoadFromStore(
    key: transactions_storage_key,
    callback: fn(store_result) {
      case store_result {
        Ok(value) -> {
          case json.parse(value, using: stored_transactions_decoder()) {
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
  UserUpdatedFormAmount(String)
  UserUpdatedFormType(TransactionType)
  UserUpdatedFormIsTransfer(Bool)
  UserUpdatedFormDescription(String)
  UserUpdatedFormDate(String)
  UserSubmittedForm
  ServerCreatedTransaction(Result(Transaction, ApiError))
  ServerUpdatedTransaction(Result(Transaction, ApiError))
  UserCancelledFormModal
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

fn put_update_transaction(
  id: Uuid,
  request: CreateTransactionRequest,
) -> Effect(Msg) {
  effect.put(
    api_route.UpdateTransaction(id) |> api_route.to_string,
    create_transaction_request.create_transaction_request_to_json(request)
      |> json.to_string,
    fn(result) {
      case result {
        Ok(body) ->
          response.decode_success(body, transaction.transaction_decoder())
          |> ServerUpdatedTransaction
        Error(http_error) ->
          ServerUpdatedTransaction(
            Error(response.http_error_to_api_error(http_error)),
          )
      }
    },
  )
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
      modal: transaction_form.empty_modal(),
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
        Model(..model, modal: transaction_form.empty_modal()),
        effect.ShowDialog(selector: transaction_form.dom_id_selector),
        None,
      )
    }

    UserRequestedEditForm(id) -> {
      case list.find(model.transactions, fn(t) { t.id == id }) {
        Ok(transaction) -> #(
          Model(..model, modal: transaction_form.edit_modal(transaction)),
          effect.ShowDialog(selector: transaction_form.dom_id_selector),
          None,
        )
        Error(Nil) -> #(model, effect.none(), None)
      }
    }

    UserUpdatedFormAmount(amount) -> {
      let modal = transaction_form.set_amount(model.modal, amount)
      #(Model(..model, modal:), effect.none(), None)
    }

    UserUpdatedFormType(type_) -> {
      let modal = transaction_form.set_type_(model.modal, type_)
      #(Model(..model, modal:), effect.none(), None)
    }

    UserUpdatedFormIsTransfer(is_transfer) -> {
      let modal = transaction_form.set_is_transfer(model.modal, is_transfer)
      #(Model(..model, modal:), effect.none(), None)
    }

    UserUpdatedFormDescription(description) -> {
      let modal = transaction_form.set_description(model.modal, description)
      #(Model(..model, modal:), effect.none(), None)
    }

    UserUpdatedFormDate(date) -> {
      let modal = transaction_form.set_date(model.modal, date)
      #(Model(..model, modal:), effect.none(), None)
    }

    UserSubmittedForm -> {
      case transaction_form.validate(model.modal) {
        Ok(request) -> {
          let effect = case model.modal.mode {
            Edit(id) -> put_update_transaction(id, request)
            Create -> post_create_transaction(request)
          }
          #(
            Model(..model, modal: ModalState(..model.modal, submitting: True)),
            effect,
            None,
          )
        }
        Error(form) -> #(
          Model(..model, modal: ModalState(..model.modal, form: form)),
          effect.none(),
          None,
        )
      }
    }

    ServerCreatedTransaction(Ok(transaction)) -> {
      #(
        Model(
          transactions: [transaction, ..model.transactions] |> sort_transactions,
          modal: ModalState(..model.modal, mode: Create, submitting: False),
          delete_modal: model.delete_modal,
        ),
        effect.CloseDialog(selector: transaction_form.dom_id_selector),
        Some(out_msg.PageRequestedToast(
          title: "Success",
          body: "Transaction created",
          level: toast.Success,
          dismiss_after_ms: Some(5000),
        )),
      )
    }

    ServerCreatedTransaction(Error(error)) -> #(
      Model(..model, modal: ModalState(..model.modal, submitting: False)),
      effect.LogError(api_error.describe(error)),
      Some(out_msg.PageRequestedToast(
        title: "Error",
        body: "Could not create transaction",
        level: toast.Error,
        dismiss_after_ms: Some(5000),
      )),
    )

    ServerUpdatedTransaction(Ok(updated)) -> {
      #(
        Model(
          transactions: model.transactions
            |> list.map(fn(t) {
              case t.id == updated.id {
                True -> updated
                False -> t
              }
            })
            |> sort_transactions,
          modal: ModalState(..model.modal, mode: Create, submitting: False),
          delete_modal: model.delete_modal,
        ),
        effect.CloseDialog(selector: transaction_form.dom_id_selector),
        Some(out_msg.PageRequestedToast(
          title: "Success",
          body: "Transaction updated",
          level: toast.Success,
          dismiss_after_ms: Some(5000),
        )),
      )
    }

    ServerUpdatedTransaction(Error(error)) -> #(
      Model(..model, modal: ModalState(..model.modal, submitting: False)),
      effect.LogError(api_error.describe(error)),
      Some(out_msg.PageRequestedToast(
        title: "Error",
        body: "Could not update transaction",
        level: toast.Error,
        dismiss_after_ms: Some(5000),
      )),
    )

    UserCancelledFormModal -> #(
      model,
      effect.CloseDialog(selector: transaction_form.dom_id_selector),
      None,
    )

    UserRequestedDeleteForm(transaction) -> #(
      Model(..model, delete_modal: transaction_delete_modal.open(transaction)),
      effect.ShowDialog(selector: transaction_delete_modal.dom_id_selector),
      None,
    )

    UserConfirmedDelete -> {
      case model.delete_modal {
        Confirming(transaction) -> #(
          Model(..model, delete_modal: Deleting(transaction)),
          delete_transaction(transaction),
          None,
        )
        _ -> #(model, effect.none(), None)
      }
    }

    // The message carries the full transaction so the list is updated
    // regardless of the modal state (keeping the view consistent with the
    // server even if the dialog was closed while the request was in flight)
    // and the toast can name the deleted transaction.
    ServerDeletedTransaction(transaction, Ok(_)) -> #(
      Model(
        ..model,
        transactions: list.filter(model.transactions, fn(t) {
          t.id != transaction.id
        }),
        delete_modal: transaction_delete_modal.empty(),
      ),
      effect.CloseDialog(selector: transaction_delete_modal.dom_id_selector),
      Some(out_msg.PageRequestedToast(
        title: "Success",
        body: "Deleted transaction " <> transaction.description,
        level: toast.Success,
        dismiss_after_ms: Some(5000),
      )),
    )

    // Revert to Confirming so the user can retry in place when the dialog is
    // still open (the common failure case). When the dialog was dismissed
    // (Escape/outside-click) while the request was in flight, the state here
    // goes stale but that is harmless: the dialog stays hidden and the next
    // Delete click resets it via `open`. See the `DeleteModalState` docs for
    // the full tradeoff.
    ServerDeletedTransaction(transaction, Error(error)) -> #(
      Model(..model, delete_modal: case model.delete_modal {
        Deleting(transaction) ->
          transaction_delete_modal.Confirming(transaction)
        other -> other
      }),
      effect.LogError(api_error.describe(error)),
      Some(out_msg.PageRequestedToast(
        title: "Error",
        body: "Could not delete " <> transaction.description,
        level: toast.Error,
        dismiss_after_ms: Some(5000),
      )),
    )

    UserCancelledDeleteModal -> #(
      Model(..model, delete_modal: transaction_delete_modal.empty()),
      effect.CloseDialog(selector: transaction_delete_modal.dom_id_selector),
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
    transaction_form.view(
      model.modal,
      on_amount_input: UserUpdatedFormAmount,
      on_type_click: UserUpdatedFormType,
      on_is_transfer_input: UserUpdatedFormIsTransfer,
      on_description_input: UserUpdatedFormDescription,
      on_date_input: UserUpdatedFormDate,
      on_submit: UserSubmittedForm,
      on_cancel: UserCancelledFormModal,
    ),
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
