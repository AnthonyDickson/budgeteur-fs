//// Quick tagging: the transactions waiting for a tag, a batch at a time, each
//// tagged, marked as a transfer, or dismissed with one click. See
//// docs/quick-tagging.md.

import budgeteur/quick_tagging_page/queue.{type Queue, type QueuedTransaction}
import budgeteur/shared/api_error.{type ApiError}
import budgeteur/shared/api_route
import budgeteur/shared/date
import budgeteur/shared/effect.{type Effect}
import budgeteur/shared/form_modal
import budgeteur/shared/money
import budgeteur/shared/out_msg.{type OutMsg}
import budgeteur/shared/remote.{type Remote, Failed, Loaded, Loading}
import budgeteur/shared/response
import budgeteur/shared/route
import budgeteur/shared/tag.{type Tag, Expense, Income}
import budgeteur/shared/ui/button
import budgeteur/shared/ui/row
import budgeteur/shared/ui/swatch
import gleam/dict.{type Dict}
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/string
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import youid/uuid.{type Uuid}

const card_class = "rounded-lg border border-gray-200 bg-white shadow-sm"

const choice_button_class = "inline-flex items-center gap-1.5 rounded-full border px-3 py-1 text-sm font-medium "
  <> "focus:outline-none focus-visible:ring-2 focus-visible:ring-indigo-500 disabled:cursor-wait"

const link_class = "font-medium text-indigo-600 hover:text-indigo-500"

// Types
// -----

/// What the user chose for a queued transaction.
pub type Choice {
  TagWith(tag_id: Uuid)
  Transfer
  Dismiss
}

/// A row the user has quick tagged. A row without one is waiting.
pub type Row {
  /// The request is in flight. `previous` is restored if it fails.
  Saving(choice: Choice, previous: Option(Choice))
  Saved(Choice)
}

pub type Model {
  Model(
    queue: Remote(Queue),
    tags: Remote(List(Tag)),
    /// Keyed by transaction id. Rows stay in place once quick tagged, so a
    /// mistake can be corrected with another click. See decision 4 in
    /// docs/quick-tagging.md.
    rows: Dict(Uuid, Row),
  )
}

pub type Msg {
  ClientFetchedQueue(Result(Queue, ApiError))
  ClientFetchedTags(Result(List(Tag), ApiError))
  UserRetried
  UserRequestedNextBatch
  UserChose(transaction_id: Uuid, choice: Choice)
  ServerSaved(
    transaction_id: Uuid,
    choice: Choice,
    result: Result(Nil, ApiError),
  )
}

// Effects
// -------

fn fetch_queue() -> Effect(Msg) {
  effect.get(api_route.GetQuickTagQueue |> api_route.to_string, fn(result) {
    case result {
      Ok(body) ->
        ClientFetchedQueue(response.decode_success(body, queue.decoder()))
      Error(http_error) ->
        ClientFetchedQueue(Error(response.http_error_to_api_error(http_error)))
    }
  })
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

fn save(transaction_id: Uuid, choice: Choice) -> Effect(Msg) {
  let callback = fn(result) {
    case result {
      // Both writes return 204 with no body, so there is nothing to decode.
      Ok(_) -> ServerSaved(transaction_id, choice, Ok(Nil))
      Error(http_error) ->
        ServerSaved(
          transaction_id,
          choice,
          Error(response.http_error_to_api_error(http_error)),
        )
    }
  }

  case choice {
    TagWith(tag_id:) ->
      effect.put(
        api_route.QuickTagTransaction(transaction_id) |> api_route.to_string,
        json.object([#("tagId", json.string(uuid.to_string(tag_id)))])
          |> json.to_string,
        callback,
      )
    // The transfer endpoint takes no body.
    Transfer ->
      effect.put(
        api_route.MarkTransfer(transaction_id) |> api_route.to_string,
        "",
        callback,
      )
    Dismiss ->
      effect.delete(
        api_route.DismissTransaction(transaction_id) |> api_route.to_string,
        callback,
      )
  }
  |> effect.with_timeout(form_modal.submit_timeout_ms)
}

// Init
// ----

pub fn init() -> #(Model, Effect(Msg)) {
  #(
    Model(queue: Loading, tags: Loading, rows: dict.new()),
    effect.batch([fetch_queue(), fetch_tags()]),
  )
}

// Update
// ------

/// How many transactions are still waiting: the queue's total less the rows
/// quick tagged in this batch. `None` until the queue has loaded.
pub fn waiting(model: Model) -> Option(Int) {
  case model.queue {
    Loaded(queue) -> {
      let saved =
        dict.values(model.rows)
        |> list.count(fn(row) {
          case row {
            Saved(_) -> True
            Saving(..) -> False
          }
        })
      Some(queue.total - saved)
    }
    Loading | Failed -> None
  }
}

fn is_saving(model: Model) -> Bool {
  dict.values(model.rows)
  |> list.any(fn(row) {
    case row {
      Saving(..) -> True
      Saved(_) -> False
    }
  })
}

pub fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg), Option(OutMsg)) {
  case msg {
    ClientFetchedQueue(Ok(queue)) -> #(
      Model(..model, queue: Loaded(queue)),
      effect.none(),
      None,
    )

    ClientFetchedQueue(Error(error)) -> #(
      Model(..model, queue: Failed),
      effect.LogError(api_error.describe(error)),
      None,
    )

    ClientFetchedTags(Ok(tags)) -> #(
      Model(..model, tags: Loaded(tags)),
      effect.none(),
      None,
    )

    ClientFetchedTags(Error(error)) -> #(
      Model(..model, tags: Failed),
      effect.LogError(api_error.describe(error)),
      None,
    )

    UserRetried -> {
      let #(model, effect) = init()
      #(model, effect, None)
    }

    // Quick tagged transactions have left the queue, so fetching it again
    // returns the next batch. Waits for saves in flight, which could otherwise
    // land after the fetch and leave a tagged transaction in the batch.
    UserRequestedNextBatch ->
      case is_saving(model) {
        True -> #(model, effect.none(), None)
        False -> #(
          Model(..model, queue: Loading, rows: dict.new()),
          fetch_queue(),
          None,
        )
      }

    UserChose(transaction_id:, choice:) ->
      case dict.get(model.rows, transaction_id) {
        Ok(Saving(..)) -> #(model, effect.none(), None)
        Ok(Saved(saved)) if saved == choice -> #(model, effect.none(), None)
        Ok(Saved(saved)) ->
          start_save(model, transaction_id, choice, Some(saved))
        Error(Nil) -> start_save(model, transaction_id, choice, None)
      }

    ServerSaved(transaction_id:, choice:, result:) ->
      case dict.get(model.rows, transaction_id), result {
        Ok(Saving(choice: saving, ..)), Ok(Nil) if saving == choice -> #(
          Model(
            ..model,
            rows: dict.insert(model.rows, transaction_id, Saved(choice)),
          ),
          effect.none(),
          None,
        )
        Ok(Saving(choice: saving, previous:)), Error(error)
          if saving == choice
        -> #(
          Model(..model, rows: case previous {
            Some(previous) ->
              dict.insert(model.rows, transaction_id, Saved(previous))
            None -> dict.delete(model.rows, transaction_id)
          }),
          effect.LogError(api_error.describe(error)),
          Some(out_msg.error_toast(
            case choice {
              TagWith(_) -> "Could not tag the transaction"
              Transfer -> "Could not mark the transaction as a transfer"
              Dismiss -> "Could not dismiss the transaction"
            },
            error.details,
          )),
        )
        // A response for a row no longer saving that choice, e.g. after the
        // page reloaded.
        _, _ -> #(model, effect.none(), None)
      }
  }
}

fn start_save(
  model: Model,
  transaction_id: Uuid,
  choice: Choice,
  previous: Option(Choice),
) -> #(Model, Effect(Msg), Option(OutMsg)) {
  #(
    Model(
      ..model,
      rows: dict.insert(model.rows, transaction_id, Saving(choice:, previous:)),
    ),
    save(transaction_id, choice),
    None,
  )
}

/// Tags in the order the buttons show them, the same on every row: expense
/// tags, then income tags, each by name. See decision 5 in
/// docs/quick-tagging.md.
pub fn ordered_tags(tags: List(Tag)) -> List(Tag) {
  let kind_rank = fn(tag: Tag) {
    case tag.kind {
      Expense -> 0
      Income -> 1
    }
  }

  list.sort(tags, by: fn(a, b) {
    int.compare(kind_rank(a), kind_rank(b))
    |> order.lazy_break_tie(fn() { string.compare(a.name, b.name) })
  })
}

// View
// ----

pub fn view(model: Model) -> Element(Msg) {
  html.div(
    [
      attribute.class("mx-auto max-w-4xl space-y-6 px-4 py-8 sm:px-6"),
      attribute.attribute("data-testid", "quick-tagging-page"),
    ],
    [
      html.div([], [
        html.h1([attribute.class("text-2xl font-semibold text-gray-900")], [
          html.text("Quick tagging"),
        ]),
        case waiting(model) {
          Some(count) ->
            html.p(
              [
                attribute.class("mt-1 text-sm text-gray-500"),
                attribute.attribute("data-testid", "quick-tag-waiting"),
              ],
              [html.text(waiting_text(count))],
            )
          None -> element.none()
        },
      ]),
      case remote.both(model.queue, model.tags) {
        Loading -> loading_state()
        Failed -> failed_state()
        Loaded(#(queue, tags)) ->
          batch(
            queue.transactions,
            ordered_tags(tags),
            model.rows,
            is_saving(model),
          )
      },
    ],
  )
}

fn waiting_text(count: Int) -> String {
  case count {
    1 -> "1 transaction is waiting for a tag"
    count -> int.to_string(count) <> " transactions are waiting for a tag"
  }
}

fn batch(
  transactions: List(QueuedTransaction),
  tags: List(Tag),
  rows: Dict(Uuid, Row),
  is_saving: Bool,
) -> Element(Msg) {
  case transactions {
    [] -> empty_state()
    transactions ->
      html.div([attribute.class("space-y-4")], [
        case tags {
          [] -> no_tags_note()
          _ -> element.none()
        },
        html.ul(
          [attribute.class("space-y-3")],
          list.map(transactions, fn(transaction) {
            transaction_row(
              transaction,
              tags,
              dict.get(rows, transaction.id) |> option.from_result,
            )
          }),
        ),
        html.div([attribute.class("flex justify-end")], [
          button.view(
            button.Secondary,
            button.Regular,
            [
              attribute.disabled(is_saving),
              attribute.attribute("data-testid", "quick-tag-next-batch"),
              event.on_click(UserRequestedNextBatch),
            ],
            [html.text("Next batch")],
          ),
        ]),
      ])
  }
}

fn no_tags_note() -> Element(Msg) {
  html.p([attribute.class("text-sm text-gray-500")], [
    html.text("You have no tags yet. Create them on the "),
    html.a(
      [
        attribute.href(route.to_string(route.Tagging)),
        attribute.class(link_class),
      ],
      [html.text("Tags & Rules page")],
    ),
    html.text("."),
  ])
}

/// A row reads like a statement line, followed by a button per tag,
/// "Transfer", and "Dismiss". The buttons are native buttons and the row has
/// no open-row overlay, so Vimium's link hints find every choice. See decision 5 in
/// docs/quick-tagging.md.
fn transaction_row(
  transaction: QueuedTransaction,
  tags: List(Tag),
  state: Option(Row),
) -> Element(Msg) {
  let details = case transaction.account_name {
    Some(account_name) -> date.format(transaction.date) <> " · " <> account_name
    None -> date.format(transaction.date)
  }

  let #(row_class, text_class) = case state {
    Some(Saved(_)) -> #("bg-gray-50", "text-gray-500")
    Some(Saving(..)) | None -> #("bg-white", "text-gray-900")
  }

  html.li(
    [
      attribute.class(
        "rounded-lg border border-gray-200 px-4 py-3 shadow-sm space-y-3 "
        <> row_class,
      ),
      attribute.attribute("data-testid", "quick-tag-row"),
    ],
    [
      html.div([attribute.class("flex items-start justify-between gap-4")], [
        html.div([attribute.class("min-w-0")], [
          html.p(
            [
              attribute.class(
                row.selectable_class
                <> " break-words text-sm font-medium "
                <> text_class,
              ),
            ],
            [html.text(transaction.description)],
          ),
          html.p([attribute.class("mt-0.5 text-sm text-gray-500")], [
            html.text(details),
          ]),
        ]),
        html.p(
          [
            attribute.class(
              "whitespace-nowrap text-sm tabular-nums " <> text_class,
            ),
          ],
          [html.text(money.format(transaction.amount))],
        ),
      ]),
      html.div(
        [attribute.class("flex flex-wrap gap-2")],
        list.append(
          list.map(tags, fn(tag) {
            choice_button(
              transaction.id,
              state,
              TagWith(tag.id),
              testid: "quick-tag-button",
              children: [swatch.view(tag.color), html.text(tag.name)],
            )
          }),
          [
            choice_button(
              transaction.id,
              state,
              Transfer,
              testid: "quick-tag-transfer",
              children: [html.text("Transfer")],
            ),
            choice_button(
              transaction.id,
              state,
              Dismiss,
              testid: "quick-tag-dismiss",
              children: [html.text("Dismiss")],
            ),
          ],
        ),
      ),
    ],
  )
}

/// A button for one choice. It shows as pressed while its choice is saving or
/// saved, and every button in the row is disabled while a save is in flight.
fn choice_button(
  transaction_id: Uuid,
  row: Option(Row),
  choice: Choice,
  testid testid: String,
  children children: List(Element(Msg)),
) -> Element(Msg) {
  let is_pressed = case row {
    Some(Saving(choice: chosen, ..)) | Some(Saved(chosen)) -> chosen == choice
    None -> False
  }

  let is_disabled = case row {
    Some(Saving(..)) -> True
    Some(Saved(_)) | None -> False
  }

  let style = case choice, is_pressed {
    TagWith(_), True -> "border-indigo-600 bg-indigo-50 text-indigo-700"
    TagWith(_), False ->
      "border-gray-300 bg-white text-gray-700 hover:bg-gray-50"
    Transfer, True -> "border-gray-600 bg-gray-100 text-gray-800"
    Transfer, False -> "border-gray-300 bg-white text-gray-600 hover:bg-gray-50"
    Dismiss, True -> "border-dashed border-gray-500 bg-gray-100 text-gray-700"
    Dismiss, False ->
      "border-dashed border-gray-300 bg-white text-gray-500 hover:bg-gray-50"
  }

  html.button(
    [
      attribute.type_("button"),
      attribute.class(choice_button_class <> " " <> style),
      attribute.attribute("aria-pressed", case is_pressed {
        True -> "true"
        False -> "false"
      }),
      attribute.disabled(is_disabled),
      attribute.attribute("data-testid", testid),
      event.on_click(UserChose(transaction_id, choice)),
    ],
    children,
  )
}

fn empty_state() -> Element(Msg) {
  html.div(
    [
      attribute.class(card_class <> " px-6 py-12 text-center"),
      attribute.attribute("data-testid", "quick-tag-empty-state"),
    ],
    [
      html.h2([attribute.class("text-base font-semibold text-gray-900")], [
        html.text("No transactions are waiting for a tag"),
      ]),
      html.p([attribute.class("mt-1 text-sm text-gray-500")], [
        html.text("Import or record transactions on the "),
        html.a(
          [
            attribute.href(route.to_string(route.Transactions)),
            attribute.class(link_class),
          ],
          [html.text("Transactions page")],
        ),
        html.text("."),
      ]),
    ],
  )
}

fn loading_state() -> Element(Msg) {
  html.div(
    [
      attribute.class(card_class <> " px-6 py-12 text-center"),
      attribute.attribute("data-testid", "quick-tag-loading-state"),
    ],
    [
      html.p([attribute.class("text-sm text-gray-500")], [
        html.text("Loading transactions..."),
      ]),
    ],
  )
}

fn failed_state() -> Element(Msg) {
  html.div(
    [
      attribute.class(card_class <> " px-6 py-12 text-center"),
      attribute.attribute("data-testid", "quick-tag-load-error"),
    ],
    [
      html.h2([attribute.class("text-base font-semibold text-gray-900")], [
        html.text("Could not load the transactions waiting for a tag"),
      ]),
      html.p([attribute.class("mt-1 text-sm text-gray-500")], [
        html.text("Check your connection and try again."),
      ]),
      button.view(
        button.Primary,
        button.Regular,
        [
          attribute.class("mt-4"),
          attribute.attribute("data-testid", "quick-tag-retry"),
          event.on_click(UserRetried),
        ],
        [html.text("Retry")],
      ),
    ],
  )
}
