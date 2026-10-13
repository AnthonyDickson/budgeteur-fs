//// Quick tagging: the transactions waiting for a tag, a batch at a time. See
//// docs/quick-tagging.md.

import budgeteur/quick_tagging_page/queue.{type Queue, type QueuedTransaction}
import budgeteur/shared/api_error.{type ApiError}
import budgeteur/shared/api_route
import budgeteur/shared/date
import budgeteur/shared/effect.{type Effect}
import budgeteur/shared/money
import budgeteur/shared/out_msg.{type OutMsg}
import budgeteur/shared/remote.{type Remote, Failed, Loaded, Loading}
import budgeteur/shared/response
import budgeteur/shared/route
import budgeteur/shared/row_ui
import budgeteur/shared/tag.{type Tag}
import gleam/dynamic/decode
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

const card_class = "rounded-lg border border-gray-200 bg-white shadow-sm"

const primary_button_class = "rounded-md bg-indigo-600 px-4 py-2 text-sm font-medium text-white "
  <> "hover:bg-indigo-500 focus:outline-none focus:ring-2 "
  <> "focus:ring-indigo-500 focus:ring-offset-2"

const secondary_button_class = "rounded-md border border-gray-300 bg-white px-4 py-2 text-sm font-medium text-gray-700 "
  <> "hover:bg-gray-50 focus:outline-none focus:ring-2 "
  <> "focus:ring-indigo-500 focus:ring-offset-2"

const link_class = "font-medium text-indigo-600 hover:text-indigo-500"

// Types
// -----

pub type Model {
  Model(queue: Remote(Queue), tags: Remote(List(Tag)))
}

pub type Msg {
  ClientFetchedQueue(Result(Queue, ApiError))
  ClientFetchedTags(Result(List(Tag), ApiError))
  UserRetried
  UserRequestedNextBatch
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

// Init
// ----

pub fn init() -> #(Model, Effect(Msg)) {
  #(
    Model(queue: Loading, tags: Loading),
    effect.batch([fetch_queue(), fetch_tags()]),
  )
}

// Update
// ------

pub fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg), Option(OutMsg)) {
  let #(model, effect) = update_inner(model, msg)
  #(model, effect, None)
}

fn update_inner(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    ClientFetchedQueue(Ok(queue)) -> #(
      Model(..model, queue: Loaded(queue)),
      effect.none(),
    )

    ClientFetchedQueue(Error(error)) -> #(
      Model(..model, queue: Failed),
      effect.LogError(api_error.describe(error)),
    )

    ClientFetchedTags(Ok(tags)) -> #(
      Model(..model, tags: Loaded(tags)),
      effect.none(),
    )

    ClientFetchedTags(Error(error)) -> #(
      Model(..model, tags: Failed),
      effect.LogError(api_error.describe(error)),
    )

    UserRetried -> init()

    // Quick tagged transactions have left the queue, so fetching it again
    // returns the next batch.
    UserRequestedNextBatch -> #(Model(..model, queue: Loading), fetch_queue())
  }
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
        case model.queue {
          Loaded(queue) ->
            html.p(
              [
                attribute.class("mt-1 text-sm text-gray-500"),
                attribute.attribute("data-testid", "quick-tag-waiting"),
              ],
              [html.text(waiting_text(queue.total))],
            )
          Loading | Failed -> element.none()
        },
      ]),
      case remote.both(model.queue, model.tags) {
        Loading -> loading_state()
        Failed -> failed_state()
        Loaded(#(queue, _tags)) -> batch(queue.transactions)
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

fn batch(transactions: List(QueuedTransaction)) -> Element(Msg) {
  case transactions {
    [] -> empty_state()
    transactions ->
      html.div([attribute.class("space-y-4")], [
        html.ul(
          [attribute.class("space-y-3")],
          list.map(transactions, transaction_row),
        ),
        html.div([attribute.class("flex justify-end")], [
          html.button(
            [
              attribute.type_("button"),
              attribute.class(secondary_button_class),
              attribute.attribute("data-testid", "quick-tag-next-batch"),
              event.on_click(UserRequestedNextBatch),
            ],
            [html.text("Next batch")],
          ),
        ]),
      ])
  }
}

/// A row reads like a statement line. It has no open-row overlay, which would
/// cover the tag buttons. See decision 5 in docs/quick-tagging.md.
fn transaction_row(transaction: QueuedTransaction) -> Element(Msg) {
  let details = case transaction.account_name {
    Some(account_name) -> date.format(transaction.date) <> " · " <> account_name
    None -> date.format(transaction.date)
  }

  html.li(
    [
      attribute.class(card_class <> " px-4 py-3"),
      attribute.attribute("data-testid", "quick-tag-row"),
    ],
    [
      html.div([attribute.class("flex items-start justify-between gap-4")], [
        html.div([attribute.class("min-w-0")], [
          html.p(
            [
              attribute.class(
                row_ui.selectable_class
                <> " break-words text-sm font-medium text-gray-900",
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
              "whitespace-nowrap text-sm tabular-nums text-gray-900",
            ),
          ],
          [html.text(money.format(transaction.amount))],
        ),
      ]),
    ],
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
      html.button(
        [
          attribute.type_("button"),
          attribute.class("mt-4 " <> primary_button_class),
          attribute.attribute("data-testid", "quick-tag-retry"),
          event.on_click(UserRetried),
        ],
        [html.text("Retry")],
      ),
    ],
  )
}
