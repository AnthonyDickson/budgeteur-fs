import budgeteur/shared/api_error.{type ApiError}
import budgeteur/shared/api_route
import budgeteur/shared/date
import budgeteur/shared/delete_modal
import budgeteur/shared/effect.{type Effect}
import budgeteur/shared/form_modal
import budgeteur/shared/money
import budgeteur/shared/out_msg.{type OutMsg}
import budgeteur/shared/remote.{type Remote, Failed, Loaded, Loading}
import budgeteur/shared/response
import budgeteur/tag.{type Tag}
import budgeteur/transaction_page/create_transaction_request
import budgeteur/transaction_page/transaction.{type Transaction}
import budgeteur/transaction_page/transaction_delete_modal.{
  type DeleteModalState,
}
import budgeteur/transaction_page/transaction_modal
import gleam/dict
import gleam/dynamic/decode
import gleam/float
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/result
import gleam/string
import gleam/time/calendar
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import youid/uuid.{type Uuid}

pub type Model {
  Model(
    /// Newest first.
    transactions: Remote(List(Transaction)),
    /// Names the transactions' tags and fills the modal's tag select. Empty
    /// until loaded; if the fetch fails, transactions show without tag names.
    tags: List(Tag),
    modal: transaction_modal.Modal,
    delete_modal: DeleteModalState,
  )
}

pub type Msg {
  ClientFetchedTransactions(Result(List(Transaction), ApiError))
  ClientFetchedTags(Result(List(Tag), ApiError))
  // Retry after a failed first load.
  UserRequestedReload
  // Modal messages
  UserRequestedCreationForm
  UserRequestedEditForm(Uuid)
  TransactionModalMsg(transaction_modal.Msg)
  // Delete modal messages
  UserRequestedDeleteForm(Transaction)
  UserConfirmedDelete
  ServerDeletedTransaction(Transaction, Result(Nil, ApiError))
  UserCancelledDeleteModal
}

fn fetch_tags() -> Effect(Msg) {
  effect.get(api_route.GetAllTags |> api_route.to_string, fn(result) {
    case result {
      Ok(body) ->
        ClientFetchedTags(response.decode_success(
          body,
          decode.list(tag.tag_decoder()),
        ))
      Error(http_error) ->
        ClientFetchedTags(Error(response.http_error_to_api_error(http_error)))
    }
  })
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

fn sort_tags(tags: List(Tag)) -> List(Tag) {
  list.sort(tags, by: fn(a, b) { string.compare(a.name, b.name) })
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
      transactions: Loading,
      tags: [],
      modal: transaction_modal.hidden(),
      delete_modal: transaction_delete_modal.empty(),
    ),
    effect.batch([fetch_transactions(), fetch_tags()]),
  )
}

pub fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg), Option(OutMsg)) {
  case msg {
    ClientFetchedTransactions(Ok(transactions)) -> #(
      Model(..model, transactions: Loaded(sort_transactions(transactions))),
      effect.none(),
      None,
    )

    ClientFetchedTransactions(Error(error)) ->
      case model.transactions {
        // A refetch failed (e.g. on returning to the page); the loaded list is
        // still the latest the page has seen.
        Loaded(_) -> #(
          model,
          effect.LogError(api_error.describe(error)),
          Some(out_msg.error_toast(
            "Could not refresh transactions",
            "Showing the transactions loaded earlier",
          )),
        )
        Loading | Failed -> #(
          Model(..model, transactions: Failed),
          effect.LogError(api_error.describe(error)),
          None,
        )
      }

    ClientFetchedTags(Ok(tags)) -> #(
      Model(..model, tags: sort_tags(tags)),
      effect.none(),
      None,
    )

    ClientFetchedTags(Error(error)) -> #(
      model,
      effect.LogError(api_error.describe(error)),
      Some(out_msg.error_toast(
        "Could not load tags",
        "Transactions are shown without tag names",
      )),
    )

    UserRequestedReload -> #(
      Model(..model, transactions: Loading),
      effect.batch([fetch_transactions(), fetch_tags()]),
      None,
    )

    UserRequestedCreationForm ->
      run_transaction_modal(model, transaction_modal.CreateRequested)

    UserRequestedEditForm(id) -> {
      let transactions = remote.unwrap(model.transactions, or: [])
      case list.find(transactions, fn(t) { t.id == id }) {
        Ok(transaction) ->
          run_transaction_modal(
            model,
            transaction_modal.EditRequested(transaction),
          )
        Error(Nil) -> #(model, effect.none(), None)
      }
    }

    TransactionModalMsg(msg) -> run_transaction_modal(model, msg)

    UserRequestedDeleteForm(transaction) -> #(
      Model(..model, delete_modal: transaction_delete_modal.open(transaction)),
      effect.none(),
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
        False -> on_delete_failed(model, error)
      }
    }

    UserCancelledDeleteModal -> #(
      Model(..model, delete_modal: transaction_delete_modal.empty()),
      effect.none(),
      None,
    )
  }
}

fn run_transaction_modal(
  model: Model,
  msg: transaction_modal.Msg,
) -> #(Model, Effect(Msg), Option(OutMsg)) {
  let #(modal, request, outcome) = transaction_modal.update(model.modal, msg)
  let model = Model(..model, modal:)
  let error_effect = case msg {
    transaction_modal.SaveCompleted(result: Error(error)) ->
      Some(effect.LogError(api_error.describe(error)))
    _ -> None
  }
  fold_form(
    model,
    request,
    outcome,
    error_effect,
    apply_outcome,
    interpret_transaction_request,
  )
}

fn apply_outcome(
  model: Model,
  outcome: transaction_modal.Outcome,
) -> #(Model, Option(OutMsg)) {
  case outcome {
    form_modal.NoChange -> #(model, None)
    form_modal.Created(entity: transaction) -> {
      let transactions =
        remote.map(model.transactions, fn(transactions) {
          [transaction, ..transactions] |> sort_transactions
        })
      let model = Model(..model, transactions:)
      #(model, Some(out_msg.success_toast("Transaction created")))
    }
    form_modal.Updated(entity: updated) -> {
      let transactions =
        remote.map(model.transactions, fn(transactions) {
          list.map(transactions, fn(t) {
            case t.id == updated.id {
              True -> updated
              False -> t
            }
          })
          |> sort_transactions
        })
      let model = Model(..model, transactions:)
      #(model, Some(out_msg.success_toast("Transaction updated")))
    }
  }
}

fn interpret_transaction_request(
  request: transaction_modal.Request,
) -> Effect(Msg) {
  case request {
    form_modal.Post(payload) ->
      effect.post(
        api_route.CreateTransaction |> api_route.to_string,
        create_transaction_request.create_transaction_request_to_json(payload)
          |> json.to_string,
        handle_save_response,
      )
      |> effect.with_timeout(form_modal.submit_timeout_ms)
      |> effect.map(TransactionModalMsg)
    form_modal.Put(id:, payload:) ->
      effect.put(
        api_route.UpdateTransaction(id) |> api_route.to_string,
        create_transaction_request.create_transaction_request_to_json(payload)
          |> json.to_string,
        handle_save_response,
      )
      |> effect.with_timeout(form_modal.submit_timeout_ms)
      |> effect.map(TransactionModalMsg)
  }
}

fn handle_save_response(result) {
  case result {
    Ok(body) ->
      response.decode_success(body, transaction.transaction_decoder())
      |> transaction_modal.SaveCompleted
    Error(http_error) ->
      transaction_modal.SaveCompleted(
        Error(response.http_error_to_api_error(http_error)),
      )
  }
}

/// Fold a form's `#(modal, request, outcome)` triple into page state: store
/// the modal, apply the outcome to the transactions list (with a toast), turn
/// the request into an effect, and log the API error when the triggering
/// message was a save failure.
fn fold_form(
  model: Model,
  request: Option(request),
  outcome: outcome,
  error_effect: Option(Effect(Msg)),
  apply_outcome: fn(Model, outcome) -> #(Model, Option(OutMsg)),
  interpret: fn(request) -> Effect(Msg),
) -> #(Model, Effect(Msg), Option(OutMsg)) {
  let #(model, out_msg) = apply_outcome(model, outcome)
  let effects = case request {
    Some(request) -> [interpret(request)]
    None -> []
  }
  let effects = case error_effect {
    Some(error_effect) -> [error_effect, ..effects]
    None -> effects
  }
  // A single effect stays unwrapped rather than becoming a one-element batch;
  // several effects are batched.
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
      transactions: remote.map(
        model.transactions,
        list.filter(_, fn(t) { t.id != transaction.id }),
      ),
      delete_modal: transaction_delete_modal.empty(),
    ),
    effect.none(),
    Some(out_msg.success_toast(
      "Deleted transaction " <> transaction.description,
    )),
  )
}

fn on_delete_failed(
  model: Model,
  error: ApiError,
) -> #(Model, Effect(Msg), Option(OutMsg)) {
  let updated = delete_modal.fail(model.delete_modal, error)
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
  let tag_names_by_id =
    model.tags |> list.map(fn(tag) { #(tag.id, tag.name) }) |> dict.from_list

  html.div([attribute.class("mx-auto max-w-4xl px-4 py-8 sm:px-6")], [
    html.div([attribute.class("flex items-center justify-between gap-4 mb-6")], [
      html.h1([attribute.class("text-2xl font-semibold text-gray-900")], [
        html.text("Transactions"),
      ]),
      // Offered only once the list has loaded, so a new transaction always
      // has a list to join.
      case model.transactions {
        Loaded(_) ->
          html.button(
            [
              attribute.class(primary_button_class),
              attribute.attribute("data-testid", "record-transaction-button"),
              event.on_click(UserRequestedCreationForm),
            ],
            [html.text("Record Transaction")],
          )
        Loading | Failed -> element.none()
      },
    ]),
    case model.transactions {
      Loading -> loading_state()
      Failed -> failed_state()
      Loaded(transactions) -> transactions_table(transactions, tag_names_by_id)
    },
    transaction_modal.view(model.modal, model.tags)
      |> element.map(TransactionModalMsg),
    transaction_delete_modal.view(
      model.delete_modal,
      on_cancel: UserCancelledDeleteModal,
      on_confirm: UserConfirmedDelete,
    ),
  ])
}

fn tag_name(
  transaction: Transaction,
  tag_names_by_id: dict.Dict(Uuid, String),
) -> Option(String) {
  transaction.tag_id
  |> option.to_result(Nil)
  |> result.try(fn(tag_id) { dict.get(tag_names_by_id, tag_id) })
  |> option.from_result
}

fn transactions_table(
  transactions: List(Transaction),
  tag_names_by_id: dict.Dict(Uuid, String),
) -> Element(Msg) {
  case list.is_empty(transactions) {
    True -> no_transactions_empty_state()
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
                  html.th([attribute.class("px-4 py-3 font-medium")], [
                    html.text("Tag"),
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
                        attribute.attribute(
                          "data-amount",
                          float.to_string(transaction.amount),
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
                      [attribute.class("px-4 py-3 text-sm text-gray-700")],
                      [
                        html.text(
                          tag_name(transaction, tag_names_by_id)
                          |> option.unwrap("-"),
                        ),
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

/// Shown in place of the table when there are no transactions yet. The
/// "Record Transaction" button in the page header stays visible, so no extra
/// call to action is needed here.
fn no_transactions_empty_state() -> Element(Msg) {
  html.div(
    [
      attribute.class(
        "rounded-lg border border-gray-200 bg-white px-6 py-12 text-center shadow-sm",
      ),
      attribute.attribute("data-testid", "no-transactions-empty-state"),
    ],
    [
      html.h2([attribute.class("text-base font-semibold text-gray-900")], [
        html.text("No transactions yet"),
      ]),
      html.p([attribute.class("mt-1 text-sm text-gray-500")], [
        html.text("Use \"Record Transaction\" to add your first one."),
      ]),
    ],
  )
}

const primary_button_class = "rounded-md bg-indigo-600 px-4 py-2 text-sm font-medium text-white "
  <> "hover:bg-indigo-500 focus:outline-none focus:ring-2 "
  <> "focus:ring-indigo-500 focus:ring-offset-2"

fn loading_state() -> Element(Msg) {
  html.div(
    [
      attribute.class(
        "rounded-lg border border-gray-200 bg-white px-6 py-12 text-center shadow-sm",
      ),
      attribute.attribute("data-testid", "transactions-loading-state"),
    ],
    [
      html.p([attribute.class("text-sm text-gray-500")], [
        html.text("Loading transactions..."),
      ]),
    ],
  )
}

/// The first load failed; the page offers a retry rather than an indefinite
/// loading state.
fn failed_state() -> Element(Msg) {
  html.div(
    [
      attribute.class(
        "rounded-lg border border-gray-200 bg-white px-6 py-12 text-center shadow-sm",
      ),
      attribute.attribute("data-testid", "transactions-load-error"),
    ],
    [
      html.h2([attribute.class("text-base font-semibold text-gray-900")], [
        html.text("Could not load transactions"),
      ]),
      html.p([attribute.class("mt-1 text-sm text-gray-500")], [
        html.text("Check your connection and try again."),
      ]),
      html.button(
        [
          attribute.class("mt-4 " <> primary_button_class),
          attribute.attribute("data-testid", "transactions-retry"),
          event.on_click(UserRequestedReload),
        ],
        [html.text("Retry")],
      ),
    ],
  )
}
