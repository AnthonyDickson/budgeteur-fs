//// Quick tagging: the transactions waiting for a tag, a batch at a time, each
//// tagged, marked as a transfer, or dismissed with one click. See
//// docs/quick-tagging.md.

import budgeteur/quick_tagging_page/queue.{
  type Queue, type QueuedTransaction, type Suggestion, type Target, Suggestion,
  TagTarget, TransferTarget,
}
import budgeteur/shared/api_error.{type ApiError}
import budgeteur/shared/api_route
import budgeteur/shared/date
import budgeteur/shared/effect.{type Effect}
import budgeteur/shared/form_modal
import budgeteur/shared/icon
import budgeteur/shared/money
import budgeteur/shared/out_msg.{type OutMsg}
import budgeteur/shared/remote.{type Remote, Failed, Loaded, Loading}
import budgeteur/shared/response
import budgeteur/shared/route
import budgeteur/shared/tag.{type Tag, Expense, Income}
import budgeteur/shared/ui/button
import budgeteur/shared/ui/card
import budgeteur/shared/ui/link
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

const choice_button_class = "inline-flex items-center gap-1.5 rounded-full border px-3 py-1 text-sm font-medium "
  <> "focus:outline-none focus-visible:ring-2 focus-visible:ring-primary disabled:cursor-wait"

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
    /// The suggested target the queue is filtered by, if any. See decision 7 in
    /// docs/transfer-rules.md.
    filter: Option(Target),
    /// Whether an approval of the filter's suggestion is in flight.
    approving: Bool,
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
  // A suggestion count was chosen, or the filter cleared.
  UserFiltered(filter: Option(Target))
  // The approval button: apply the filter's suggestion to the rows shown.
  UserApproved
  ServerApproved(target: Target, result: Result(Int, ApiError))
}

// Effects
// -------

fn fetch_queue(filter: Option(Target)) -> Effect(Msg) {
  let query = case filter {
    Some(target) -> queue.target_query(target)
    None -> []
  }
  effect.get(
    api_route.GetQuickTagQueue(query) |> api_route.to_string,
    fn(result) {
      case result {
        Ok(body) ->
          ClientFetchedQueue(response.decode_success(body, queue.decoder()))
        Error(http_error) ->
          ClientFetchedQueue(
            Error(response.http_error_to_api_error(http_error)),
          )
      }
    },
  )
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

/// `suggested` says whether the choice was the row's suggestion, so the server
/// records that the user accepted it. See decision 6 in docs/transfer-rules.md.
fn save(transaction_id: Uuid, choice: Choice, suggested: Bool) -> Effect(Msg) {
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
        json.object([
          #("tagId", json.string(uuid.to_string(tag_id))),
          #("suggested", json.bool(suggested)),
        ])
          |> json.to_string,
        callback,
      )
    Transfer ->
      effect.put(
        api_route.MarkTransfer(transaction_id) |> api_route.to_string,
        json.object([#("suggested", json.bool(suggested))]) |> json.to_string,
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

/// Approve the suggestion for the transactions, which the server applies to
/// those still in the queue.
fn approve(target: Target, transaction_ids: List(Uuid)) -> Effect(Msg) {
  let body =
    json.object([
      #(
        "transactionIds",
        json.array(transaction_ids, fn(id) { json.string(uuid.to_string(id)) }),
      ),
      ..queue.target_fields(target)
    ])
  let changed_decoder = {
    use changed <- decode.field("changed", decode.int)
    decode.success(changed)
  }
  effect.post(
    api_route.ApproveSuggestion |> api_route.to_string,
    json.to_string(body),
    fn(result) {
      case result {
        Ok(body) ->
          ServerApproved(target, response.decode_success(body, changed_decoder))
        Error(http_error) ->
          ServerApproved(
            target,
            Error(response.http_error_to_api_error(http_error)),
          )
      }
    },
  )
  |> effect.with_timeout(form_modal.submit_timeout_ms)
}

// Init
// ----

pub fn init() -> #(Model, Effect(Msg)) {
  #(
    Model(
      queue: Loading,
      tags: Loading,
      rows: dict.new(),
      filter: None,
      approving: False,
    ),
    effect.batch([fetch_queue(None), fetch_tags()]),
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

/// Fetch the queue again, with the filter: quick tagged and approved transactions
/// have left the queue, so it returns the next batch. Waits for saves and
/// approvals in flight, which could otherwise land after the fetch and leave a
/// tagged transaction in the batch.
fn refetch(
  model: Model,
  filter: Option(Target),
) -> #(Model, Effect(Msg), Option(OutMsg)) {
  case is_busy(model) {
    True -> #(model, effect.none(), None)
    False -> #(
      Model(..model, queue: Loading, rows: dict.new(), filter:),
      fetch_queue(filter),
      None,
    )
  }
}

/// The rows shown that have no choice on the page yet: those an approval
/// sends and counts.
pub fn undecided(model: Model, queue: Queue) -> List(QueuedTransaction) {
  list.filter(queue.transactions, fn(transaction) {
    !dict.has_key(model.rows, transaction.id)
  })
}

fn is_busy(model: Model) -> Bool {
  model.approving || is_saving(model)
}

fn loaded_tags(model: Model) -> List(Tag) {
  case model.tags {
    Loaded(tags) -> tags
    Loading | Failed -> []
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
    // The filter is kept until no queued transaction is suggested its target,
    // e.g. once the last of them is approved; then the whole queue shows.
    ClientFetchedQueue(Ok(queue)) ->
      case model.filter, queue.transactions {
        Some(_), [] -> #(
          Model(..model, filter: None, queue: Loading),
          fetch_queue(None),
          None,
        )
        _, _ -> #(Model(..model, queue: Loaded(queue)), effect.none(), None)
      }

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

    UserRequestedNextBatch -> refetch(model, model.filter)

    UserFiltered(filter:) -> refetch(model, filter)

    UserApproved ->
      case model.filter, model.queue, is_busy(model) {
        Some(target), Loaded(queue), False ->
          case undecided(model, queue) {
            [] -> #(model, effect.none(), None)
            transactions -> #(
              Model(..model, approving: True),
              approve(target, list.map(transactions, fn(t) { t.id })),
              None,
            )
          }
        _, _, _ -> #(model, effect.none(), None)
      }

    ServerApproved(target:, result: Ok(changed)) -> {
      let model = Model(..model, approving: False)
      let #(model, effect, _) = refetch(model, model.filter)
      #(
        model,
        effect,
        Some(
          out_msg.success_toast(approved_text(
            target,
            changed,
            loaded_tags(model),
          )),
        ),
      )
    }

    ServerApproved(result: Error(error), ..) -> #(
      Model(..model, approving: False),
      effect.LogError(api_error.describe(error)),
      Some(
        out_msg.error_toast(
          "Could not approve the suggestion",
          case api_error.is_not_found(error) {
            True ->
              "A transaction was deleted elsewhere. Refresh the queue and try again."
            False -> error.details
          },
        ),
      ),
    )

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
    save(
      transaction_id,
      choice,
      is_suggestion(suggestion_for(model, transaction_id), choice),
    ),
    None,
  )
}

fn suggestion_for(model: Model, transaction_id: Uuid) -> Option(Suggestion) {
  case model.queue {
    Loaded(queue) ->
      list.find(queue.transactions, fn(transaction) {
        transaction.id == transaction_id
      })
      |> option.from_result
      |> option.then(fn(transaction) { transaction.suggestion })
    Loading | Failed -> None
  }
}

/// Whether the choice is the one the row suggests. Dismissing is never a
/// suggestion.
pub fn is_suggestion(suggestion: Option(Suggestion), choice: Choice) -> Bool {
  case suggestion, choice {
    Some(Suggestion(target: TagTarget(suggested), ..)), TagWith(tag_id:) ->
      suggested == tag_id
    Some(Suggestion(target: TransferTarget, ..)), Transfer -> True
    _, _ -> False
  }
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
      attribute.class("mx-auto max-w-6xl space-y-6 px-4 py-8 sm:px-6"),
      attribute.attribute("data-testid", "quick-tagging-page"),
    ],
    [
      html.div([], [
        html.h1([attribute.class("text-2xl font-semibold text-fg")], [
          html.text("Quick tagging"),
        ]),
        case waiting(model) {
          Some(count) ->
            html.p(
              [
                attribute.class("mt-1 text-sm text-fg-muted"),
                attribute.attribute("data-testid", "quick-tag-waiting"),
              ],
              [html.text(waiting_text(count, model.filter, loaded_tags(model)))],
            )
          None -> element.none()
        },
      ]),
      case remote.both(model.queue, model.tags) {
        Loading -> loading_state()
        Failed -> failed_state()
        Loaded(#(queue, tags)) -> batch(model, queue, ordered_tags(tags))
      },
    ],
  )
}

fn waiting_text(count: Int, filter: Option(Target), tags: List(Tag)) -> String {
  let transactions = case count {
    1 -> "1 transaction"
    count -> int.to_string(count) <> " transactions"
  }
  let waiting = case count {
    1 -> " is waiting for a tag"
    _ -> " are waiting for a tag"
  }
  case filter {
    None -> transactions <> waiting
    Some(target) ->
      transactions
      <> waiting
      <> ", with "
      <> target_label(target, tags)
      <> " suggested"
  }
}

/// The suggested target's name: its tag's, or "Transfer".
fn target_label(target: Target, tags: List(Tag)) -> String {
  case target {
    TransferTarget -> "Transfer"
    TagTarget(tag_id:) ->
      case list.find(tags, fn(tag) { tag.id == tag_id }) {
        Ok(tag) -> tag.name
        Error(Nil) -> "a tag"
      }
  }
}

/// The approval button's label, e.g. "Mark 14 as transfers".
fn approve_label(target: Target, count: Int, tags: List(Tag)) -> String {
  case target, count {
    TransferTarget, 1 -> "Mark 1 as a transfer"
    TransferTarget, count -> "Mark " <> int.to_string(count) <> " as transfers"
    TagTarget(..), count ->
      "Tag " <> int.to_string(count) <> " as " <> target_label(target, tags)
  }
}

/// The toast after an approval, e.g. "Marked 14 as transfers".
fn approved_text(target: Target, changed: Int, tags: List(Tag)) -> String {
  case target, changed {
    TransferTarget, 1 -> "Marked 1 as a transfer"
    TransferTarget, changed ->
      "Marked " <> int.to_string(changed) <> " as transfers"
    TagTarget(..), changed ->
      "Tagged "
      <> int.to_string(changed)
      <> " as "
      <> target_label(target, tags)
  }
}

fn batch(model: Model, queue: Queue, tags: List(Tag)) -> Element(Msg) {
  let rows = model.rows
  case queue.transactions {
    [] -> empty_state()
    transactions ->
      html.div([attribute.class("space-y-4")], [
        case tags {
          [] -> no_tags_note()
          _ -> element.none()
        },
        suggestions_bar(model, queue, tags),
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
              attribute.disabled(is_busy(model)),
              attribute.attribute("data-testid", "quick-tag-next-batch"),
              event.on_click(UserRequestedNextBatch),
            ],
            [html.text("Next batch")],
          ),
        ]),
      ])
  }
}

/// One button per suggestion count, which filters the queue to it. While
/// filtered, a control clears the filter and the approval button applies the
/// suggestion to the rows shown that have no choice yet; each row still shows
/// the pattern that suggested it. See decision 10 in docs/transfer-rules.md.
fn suggestions_bar(
  model: Model,
  queue: Queue,
  tags: List(Tag),
) -> Element(Msg) {
  case queue.suggestions, model.filter {
    [], None -> element.none()
    suggestions, filter ->
      html.div(
        [
          attribute.class("flex flex-wrap items-center gap-2"),
          attribute.attribute("data-testid", "quick-tag-suggestions"),
        ],
        list.flatten([
          [
            html.span([attribute.class("text-sm text-fg-muted")], [
              html.text("Suggested:"),
            ]),
          ],
          list.map(suggestions, fn(suggestion) {
            suggestion_count_button(suggestion, filter, tags, is_busy(model))
          }),
          case filter {
            None -> []
            Some(target) -> {
              let count = list.length(undecided(model, queue))
              [
                button.view(
                  button.Secondary,
                  button.Small,
                  [
                    attribute.disabled(is_busy(model)),
                    attribute.attribute("data-testid", "quick-tag-clear-filter"),
                    event.on_click(UserFiltered(None)),
                  ],
                  [html.text("Show all")],
                ),
                button.view(
                  button.Primary,
                  button.Small,
                  [
                    attribute.disabled(is_busy(model) || count == 0),
                    attribute.attribute("data-testid", "quick-tag-approve"),
                    event.on_click(UserApproved),
                  ],
                  [
                    button.busy_label(
                      label: approve_label(target, count, tags),
                      busy_label: "Approving...",
                      busy: model.approving,
                    ),
                  ],
                ),
              ]
            }
          },
        ]),
      )
  }
}

fn suggestion_count_button(
  suggestion: queue.SuggestionCount,
  filter: Option(Target),
  tags: List(Tag),
  is_busy: Bool,
) -> Element(Msg) {
  let is_pressed = filter == Some(suggestion.target)
  let swatch = case suggestion.target {
    TagTarget(tag_id:) ->
      case list.find(tags, fn(tag) { tag.id == tag_id }) {
        Ok(tag) -> [swatch.view(tag.color)]
        Error(Nil) -> []
      }
    TransferTarget -> []
  }
  html.button(
    [
      attribute.type_("button"),
      attribute.class(
        choice_button_class
        <> " "
        <> case is_pressed {
          True -> "border-primary bg-primary-tint text-fg"
          False ->
            "border-border-input bg-surface text-fg-muted hover:bg-surface-hover"
        },
      ),
      attribute.attribute("aria-pressed", case is_pressed {
        True -> "true"
        False -> "false"
      }),
      attribute.disabled(is_busy),
      attribute.attribute("data-testid", "quick-tag-suggestion-count"),
      event.on_click(UserFiltered(Some(suggestion.target))),
    ],
    list.flatten([
      swatch,
      [
        html.text(target_label(suggestion.target, tags)),
        html.span([attribute.class("tabular-nums text-fg-muted")], [
          html.text(int.to_string(suggestion.count)),
        ]),
      ],
    ]),
  )
}

fn no_tags_note() -> Element(Msg) {
  html.p([attribute.class("text-sm text-fg-muted")], [
    html.text("You have no tags yet. Create them on the "),
    link.view(
      [
        attribute.href(route.to_string(route.Tagging)),
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
    // A saved row sinks into the page, so the eye goes to the raised rows
    // still waiting for a choice.
    Some(Saved(_)) -> #("bg-transparent", "text-fg-muted")
    Some(Saving(..)) | None -> #("bg-surface shadow-sm", "text-fg")
  }

  html.li(
    [
      attribute.class(
        "rounded-lg border border-border px-4 py-3 space-y-3 " <> row_class,
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
          html.p([attribute.class("mt-0.5 text-sm text-fg-muted")], [
            html.text(details),
          ]),
        ]),
        html.div([attribute.class("flex shrink-0 items-center gap-3")], [
          row_status(state),
          html.p(
            [
              attribute.class(
                "whitespace-nowrap text-sm tabular-nums " <> text_class,
              ),
            ],
            [html.text(money.format(transaction.amount))],
          ),
        ]),
      ]),
      case transaction.suggestion {
        Some(suggestion) -> suggestion_note(suggestion)
        None -> element.none()
      },
      html.div(
        [attribute.class("flex flex-wrap gap-2")],
        list.append(
          list.map(tags, fn(tag) {
            choice_button(
              transaction.id,
              state,
              TagWith(tag.id),
              suggested: is_suggestion(transaction.suggestion, TagWith(tag.id)),
              testid: "quick-tag-button",
              children: [swatch.view(tag.color), html.text(tag.name)],
            )
          }),
          [
            choice_button(
              transaction.id,
              state,
              Transfer,
              suggested: is_suggestion(transaction.suggestion, Transfer),
              testid: "quick-tag-transfer",
              children: [html.text("Transfer")],
            ),
            choice_button(
              transaction.id,
              state,
              Dismiss,
              suggested: False,
              testid: "quick-tag-dismiss",
              children: [html.text("Dismiss")],
            ),
          ],
        ),
      ),
    ],
  )
}

/// Above the buttons: the "Suggested" label and the pattern of the rule that
/// suggests the outlined button, so the user can check why before choosing it.
fn suggestion_note(suggestion: Suggestion) -> Element(Msg) {
  html.p(
    [
      attribute.class(
        "flex flex-wrap items-center gap-1.5 text-xs text-fg-muted",
      ),
      attribute.attribute("data-testid", "quick-tag-suggestion"),
    ],
    [
      html.span([attribute.class("font-semibold text-fg")], [
        html.text("Suggested"),
      ]),
      html.text("by rule"),
      html.code(
        [
          attribute.class(
            "rounded bg-surface-hover px-1.5 py-0.5 font-medium text-fg",
          ),
        ],
        [html.text(suggestion.pattern)],
      ),
    ],
  )
}

/// What happened to the row's last choice, beside its amount, so a tagged row
/// stands out from the untagged ones around it. The pressed button says which
/// choice it was.
fn row_status(state: Option(Row)) -> Element(Msg) {
  case state {
    None -> element.none()
    Some(Saving(..)) ->
      html.span([attribute.class("text-sm text-fg-muted")], [
        html.text("Saving…"),
      ])
    Some(Saved(choice)) ->
      html.span(
        [
          attribute.class(
            "inline-flex items-center gap-1 text-sm text-fg-muted",
          ),
          attribute.attribute("data-testid", "quick-tag-status"),
        ],
        [
          icon.check(class: ""),
          html.text(case choice {
            TagWith(_) -> "Tagged"
            Transfer -> "Marked as transfer"
            Dismiss -> "Dismissed"
          }),
        ],
      )
  }
}

/// A button for one choice. It shows as pressed while its choice is saving or
/// saved, and every button in the row is disabled while a save is in flight.
/// The suggested button keeps its place and its accessible name, and only its
/// border marks it, so the order and Vimium's link hints stay the same.
fn choice_button(
  transaction_id: Uuid,
  row: Option(Row),
  choice: Choice,
  suggested suggested: Bool,
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

  let is_saved = case row {
    Some(Saved(_)) -> True
    Some(Saving(..)) | None -> False
  }

  // A saved row's buttons sink into the page with the row: no fill, and the
  // swatches (the only child elements) faded. The pressed one keeps a darker
  // border and normal text, so the choice still reads.
  let style = case is_saved, choice, is_pressed {
    True, _, True -> "border-fg-muted bg-transparent text-fg"
    True, _, False ->
      "border-border bg-transparent text-fg-muted *:opacity-50 hover:bg-surface-hover"
    False, TagWith(_), True -> "border-primary bg-primary-tint text-fg"
    False, Transfer, True -> "border-fg-muted bg-surface-hover text-fg"
    False, Dismiss, True -> "border-fg-muted bg-surface-hover text-fg"
    False, _, False if suggested ->
      "border-primary bg-surface text-fg hover:bg-surface-hover"
    False, _, False ->
      "border-border-input bg-surface text-fg-muted hover:bg-surface-hover"
  }

  let border_style = case choice {
    Dismiss -> "border-dashed"
    TagWith(_) | Transfer -> ""
  }

  html.button(
    [
      attribute.type_("button"),
      attribute.class(
        choice_button_class <> " " <> style <> " " <> border_style,
      ),
      attribute.attribute("aria-pressed", case is_pressed {
        True -> "true"
        False -> "false"
      }),
      attribute.disabled(is_disabled),
      attribute.attribute("data-testid", testid),
      attribute.attribute("data-suggested", case suggested {
        True -> "true"
        False -> "false"
      }),
      event.on_click(UserChose(transaction_id, choice)),
    ],
    children,
  )
}

fn empty_state() -> Element(Msg) {
  card.empty_state(
    [
      attribute.attribute("data-testid", "quick-tag-empty-state"),
    ],
    [
      html.h2([attribute.class("text-base font-semibold text-fg")], [
        html.text("No transactions are waiting for a tag"),
      ]),
      html.p([attribute.class("mt-1 text-sm text-fg-muted")], [
        html.text("Import or record transactions on the "),
        link.view(
          [
            attribute.href(route.to_string(route.Transactions)),
          ],
          [html.text("Transactions page")],
        ),
        html.text("."),
      ]),
    ],
  )
}

fn loading_state() -> Element(Msg) {
  card.empty_state(
    [
      attribute.attribute("data-testid", "quick-tag-loading-state"),
    ],
    [
      html.p([attribute.class("text-sm text-fg-muted")], [
        html.text("Loading transactions..."),
      ]),
    ],
  )
}

fn failed_state() -> Element(Msg) {
  card.empty_state(
    [
      attribute.attribute("data-testid", "quick-tag-load-error"),
    ],
    [
      html.h2([attribute.class("text-base font-semibold text-fg")], [
        html.text("Could not load the transactions waiting for a tag"),
      ]),
      html.p([attribute.class("mt-1 text-sm text-fg-muted")], [
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
