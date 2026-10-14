//// A line's observation history: every value of an item, or every balance of
//// an account, newest first, each of which can be deleted, and the form that
//// records a new one. See decision 9 in docs/reports.md.

import budgeteur/balance_sheet_page/account.{type Account}
import budgeteur/balance_sheet_page/account_write_request
import budgeteur/balance_sheet_page/balance_modal.{
  type CurrentBalance, CurrentBalance,
}
import budgeteur/balance_sheet_page/balance_sheet_item.{type BalanceSheetItem}
import budgeteur/balance_sheet_page/item_write_request
import budgeteur/balance_sheet_page/value_modal
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
import budgeteur/shared/route
import budgeteur/shared/side.{Asset, Liability}
import budgeteur/shared/term.{Current, NonCurrent}
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/time/calendar.{type Date}
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import youid/uuid.{type Uuid}

const primary_button_class = "rounded-md bg-indigo-600 px-4 py-2 text-sm font-medium text-white "
  <> "hover:bg-indigo-500 focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:ring-offset-2"

const link_class = "text-sm font-medium text-indigo-600 hover:text-indigo-500"

// Types
// -----

/// Which line the page is for, from its route.
pub type LineRef {
  ItemRef(id: Uuid)
  AccountRef(id: Uuid)
}

/// The line, as the page's header and record form need it.
pub type Line {
  ItemLine(item: BalanceSheetItem)
  AccountWithBalance(account: Account, current: Option(CurrentBalance))
}

/// One observation: an item's value, or an account's signed balance.
pub type Entry {
  Entry(as_of: Date, amount: Float)
}

pub type Model {
  Model(
    line_ref: LineRef,
    /// The client's local date, once the `GetLocalDate` effect has reported it.
    today: Option(Date),
    line: Remote(Line),
    /// Newest first.
    entries: Remote(List(Entry)),
    value_modal: value_modal.Modal,
    balance_modal: balance_modal.Modal,
    delete_modal: delete_modal.State(Entry, Nil),
  )
}

pub type Msg {
  ClientGotToday(Date)
  ClientFetchedLine(Result(Line, ApiError))
  ClientFetchedEntries(Result(List(Entry), ApiError))
  UserRetried
  UserRequestedRecord
  ValueModalMsg(value_modal.Msg)
  BalanceModalMsg(balance_modal.Msg)
  UserRequestedDelete(Entry)
  UserConfirmedDelete
  UserCancelledDelete
  // 404 is folded into Ok: the observation is gone, as the user intended.
  ServerDeletedEntry(entry: Entry, result: Result(Nil, ApiError))
}

// Effects
// -------

fn fetch_line(line_ref: LineRef) -> Effect(Msg) {
  let #(route, decoder) = case line_ref {
    ItemRef(id) -> #(
      api_route.GetBalanceSheetItem(id),
      balance_sheet_item.decoder() |> decode.map(ItemLine),
    )
    AccountRef(id) -> #(api_route.GetAccount(id), account_decoder())
  }
  effect.get(api_route.to_string(route), fn(result) {
    case result {
      Ok(body) -> ClientFetchedLine(response.decode_success(body, decoder))
      Error(http_error) ->
        ClientFetchedLine(Error(response.http_error_to_api_error(http_error)))
    }
  })
}

/// An account with its current balance, which the account endpoint returns
/// signed; the balance form takes a side and a magnitude.
fn account_decoder() -> decode.Decoder(Line) {
  use account <- decode.then(account.decoder())
  use current <- decode.optional_field(
    "balance",
    None,
    decode.optional({
      use balance <- decode.field("balance", money.decode_decimal())
      use as_of <- decode.field("asOf", date.decoder())
      decode.success(case balance <. 0.0 {
        True -> CurrentBalance(side: Liability, amount: 0.0 -. balance, as_of:)
        False -> CurrentBalance(side: Asset, amount: balance, as_of:)
      })
    }),
  )
  decode.success(AccountWithBalance(account:, current:))
}

fn fetch_entries(line_ref: LineRef) -> Effect(Msg) {
  let #(route, amount_field) = case line_ref {
    ItemRef(id) -> #(api_route.GetItemObservations(id), "value")
    AccountRef(id) -> #(api_route.GetAccountObservations(id), "balance")
  }
  let decoder =
    decode.list({
      use as_of <- decode.field("asOf", date.decoder())
      use amount <- decode.field(amount_field, money.decode_decimal())
      decode.success(Entry(as_of:, amount:))
    })
  effect.get(api_route.to_string(route), fn(result) {
    case result {
      Ok(body) -> ClientFetchedEntries(response.decode_success(body, decoder))
      Error(http_error) ->
        ClientFetchedEntries(
          Error(response.http_error_to_api_error(http_error)),
        )
    }
  })
}

fn refetch(model: Model) -> #(Model, Effect(Msg)) {
  #(
    model,
    effect.batch([fetch_line(model.line_ref), fetch_entries(model.line_ref)]),
  )
}

// Init
// ----

pub fn init(line_ref: LineRef) -> #(Model, Effect(Msg)) {
  #(
    Model(
      line_ref:,
      today: None,
      line: Loading,
      entries: Loading,
      value_modal: value_modal.hidden(),
      balance_modal: balance_modal.hidden(),
      delete_modal: delete_modal.empty(),
    ),
    effect.batch([
      effect.GetLocalDate(ClientGotToday),
      fetch_line(line_ref),
      fetch_entries(line_ref),
    ]),
  )
}

// Update
// ------

pub fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg), Option(OutMsg)) {
  case msg {
    ClientGotToday(today) -> #(
      Model(..model, today: Some(today)),
      effect.none(),
      None,
    )

    ClientFetchedLine(Ok(line)) -> #(
      Model(..model, line: Loaded(line)),
      effect.none(),
      None,
    )
    ClientFetchedLine(Error(error)) -> #(
      Model(..model, line: Failed),
      effect.LogError(api_error.describe(error)),
      None,
    )

    ClientFetchedEntries(Ok(entries)) -> #(
      Model(..model, entries: Loaded(entries)),
      effect.none(),
      None,
    )
    ClientFetchedEntries(Error(error)) -> #(
      Model(..model, entries: Failed),
      effect.LogError(api_error.describe(error)),
      None,
    )

    UserRetried -> {
      let #(model, effect) =
        refetch(Model(..model, line: Loading, entries: Loading))
      #(model, effect, None)
    }

    UserRequestedRecord ->
      case model.line {
        Loaded(ItemLine(item:)) ->
          run_value_modal(
            model,
            value_modal.OpenRequested(item:, today: model.today),
          )
        Loaded(AccountWithBalance(account:, current:)) ->
          run_balance_modal(
            model,
            balance_modal.OpenRequested(account:, current:, today: model.today),
          )
        Loading | Failed -> #(model, effect.none(), None)
      }

    ValueModalMsg(inner_msg) -> run_value_modal(model, inner_msg)
    BalanceModalMsg(inner_msg) -> run_balance_modal(model, inner_msg)

    UserRequestedDelete(entry) -> #(
      Model(..model, delete_modal: delete_modal.open(entry, Nil)),
      effect.none(),
      None,
    )
    UserCancelledDelete -> #(
      Model(..model, delete_modal: delete_modal.empty()),
      effect.none(),
      None,
    )
    UserConfirmedDelete ->
      case delete_modal.confirm(model.delete_modal) {
        Ok(#(state, entry)) -> #(
          Model(..model, delete_modal: state),
          delete_entry(model.line_ref, entry),
          None,
        )
        Error(Nil) -> #(model, effect.none(), None)
      }
    ServerDeletedEntry(entry:, result:) ->
      case result {
        Ok(Nil) -> on_deleted(model, entry)
        Error(error) ->
          case api_error.is_not_found(error) {
            True -> on_deleted(model, entry)
            False -> on_delete_failed(model, error)
          }
      }
  }
}

fn delete_entry(line_ref: LineRef, entry: Entry) -> Effect(Msg) {
  let route = case line_ref {
    ItemRef(id) -> api_route.DeleteItemObservation(id, entry.as_of)
    AccountRef(id) -> api_route.DeleteAccountObservation(id, entry.as_of)
  }
  effect.delete(api_route.to_string(route), fn(result) {
    case result {
      // A successful delete returns 204 with no body.
      Ok(_) -> ServerDeletedEntry(entry, Ok(Nil))
      Error(http_error) ->
        ServerDeletedEntry(
          entry,
          Error(response.http_error_to_api_error(http_error)),
        )
    }
  })
  |> effect.with_timeout(delete_modal.delete_timeout_ms)
}

/// The previous observation may now be current, so the header is refetched
/// with the history.
fn on_deleted(
  model: Model,
  entry: Entry,
) -> #(Model, Effect(Msg), Option(OutMsg)) {
  let #(model, effect) =
    refetch(Model(..model, delete_modal: delete_modal.empty()))
  #(
    model,
    effect,
    Some(out_msg.success_toast(
      "Deleted the "
      <> noun(model.line_ref)
      <> " on "
      <> date.format(entry.as_of),
    )),
  )
}

/// A response can only arrive while the dialog is `Deleting`, so `fail` moves
/// it to `Errored` for an inline retry. An unchanged state means the response
/// is stale (the dialog was closed and reopened) and is ignored.
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

fn run_value_modal(
  model: Model,
  msg: value_modal.Msg,
) -> #(Model, Effect(Msg), Option(OutMsg)) {
  let #(value_modal, request, outcome) =
    value_modal.update(model.value_modal, msg)
  let model = Model(..model, value_modal:)
  let request_effect = case request {
    Some(form_modal.Put(id:, payload:)) ->
      effect.post(
        api_route.RecordItemValue(id) |> api_route.to_string,
        item_write_request.value_entry_json(payload) |> json.to_string,
        fn(result) {
          case result {
            Ok(body) ->
              response.decode_success(body, balance_sheet_item.decoder())
              |> value_modal.SaveCompleted
            Error(http_error) ->
              value_modal.SaveCompleted(
                Error(response.http_error_to_api_error(http_error)),
              )
          }
        },
      )
      |> effect.with_timeout(form_modal.submit_timeout_ms)
      |> effect.map(ValueModalMsg)
    // The modal opens in edit mode only, so its request names the item.
    Some(form_modal.Post(_)) | None -> effect.none()
  }
  let log_effect = case msg {
    value_modal.SaveCompleted(result: Error(error)) ->
      effect.LogError(api_error.describe(error))
    _ -> effect.none()
  }
  case outcome {
    form_modal.NoChange -> #(
      model,
      effect.batch([request_effect, log_effect]),
      None,
    )
    form_modal.Created(_) | form_modal.Updated(_) -> {
      let #(model, refetch_effect) = refetch(model)
      #(model, refetch_effect, Some(out_msg.success_toast("Recorded a value")))
    }
  }
}

fn run_balance_modal(
  model: Model,
  msg: balance_modal.Msg,
) -> #(Model, Effect(Msg), Option(OutMsg)) {
  let #(balance_modal, request, outcome) =
    balance_modal.update(model.balance_modal, msg)
  let model = Model(..model, balance_modal:)
  let request_effect = case request {
    Some(form_modal.Put(id:, payload:)) ->
      effect.post(
        api_route.RecordBalance(id) |> api_route.to_string,
        account_write_request.balance_entry_json(payload) |> json.to_string,
        fn(result) {
          case result {
            Ok(body) ->
              response.decode_success(body, account.decoder())
              |> balance_modal.SaveCompleted
            Error(http_error) ->
              balance_modal.SaveCompleted(
                Error(response.http_error_to_api_error(http_error)),
              )
          }
        },
      )
      |> effect.with_timeout(form_modal.submit_timeout_ms)
      |> effect.map(BalanceModalMsg)
    // The modal opens in edit mode only, so its request names the account.
    Some(form_modal.Post(_)) | None -> effect.none()
  }
  let log_effect = case msg {
    balance_modal.SaveCompleted(result: Error(error)) ->
      effect.LogError(api_error.describe(error))
    _ -> effect.none()
  }
  case outcome {
    form_modal.NoChange -> #(
      model,
      effect.batch([request_effect, log_effect]),
      None,
    )
    form_modal.Created(_) | form_modal.Updated(_) -> {
      let #(model, refetch_effect) = refetch(model)
      #(
        model,
        refetch_effect,
        Some(out_msg.success_toast("Recorded a balance")),
      )
    }
  }
}

/// What the line's observations are called.
fn noun(line_ref: LineRef) -> String {
  case line_ref {
    ItemRef(..) -> "value"
    AccountRef(..) -> "balance"
  }
}

// View
// ----

pub fn view(model: Model) -> Element(Msg) {
  html.div(
    [
      attribute.class("mx-auto max-w-3xl px-4 py-8 sm:px-6"),
      attribute.attribute("data-testid", "observation-history-page"),
    ],
    [
      html.a(
        [
          attribute.href(route.to_string(route.BalanceSheet)),
          attribute.class(link_class),
          attribute.attribute("data-testid", "observation-history-back"),
        ],
        [html.text("← Balance sheet")],
      ),
      case remote.both(model.line, model.entries) {
        Loading -> loading_state()
        Failed -> failed_state()
        Loaded(#(line, entries)) ->
          html.div([], [
            header(line),
            entry_table(model.line_ref, entries),
          ])
      },
      value_modal.view(model.value_modal, editable: False)
        |> element.map(ValueModalMsg),
      balance_modal.view(model.balance_modal, editable: False)
        |> element.map(BalanceModalMsg),
      delete_modal.view(
        model.delete_modal,
        delete_options(model.line_ref),
        on_cancel: UserCancelledDelete,
        on_confirm: UserConfirmedDelete,
      ),
    ],
  )
}

fn header(line: Line) -> Element(Msg) {
  let #(name, details, current, closed_on, action) = case line {
    ItemLine(item:) -> #(
      item.name,
      side_label(item.side) <> " · " <> term_label(item.side, item.term),
      "Current value "
        <> money.format(item.value)
        <> " as of "
        <> date.format(item.as_of),
      item.closed_on,
      "Record value",
    )
    AccountWithBalance(account:, current:) -> #(
      account.name,
      "Account · "
        <> case account.term {
        Current -> "Current"
        NonCurrent -> "Non-current"
      }
        <> case account.number {
        Some(number) -> " · " <> number
        None -> ""
      },
      case current {
        Some(current) ->
          "Current balance "
          <> money.format(current.amount)
          <> " "
          <> case current.side {
            Asset -> "asset"
            Liability -> "liability"
          }
          <> " as of "
          <> date.format(current.as_of)
        None -> "Balance unknown"
      },
      account.closed_on,
      "Record balance",
    )
  }

  html.div(
    [
      attribute.class(
        "mt-4 mb-6 flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between",
      ),
    ],
    [
      html.div([], [
        html.h1([attribute.class("text-2xl font-semibold text-gray-900")], [
          html.text(name),
        ]),
        html.p([attribute.class("mt-1 text-sm text-gray-500")], [
          html.text(details),
        ]),
        html.p(
          [
            attribute.class("mt-1 text-sm text-gray-700"),
            attribute.attribute("data-testid", "observation-history-current"),
          ],
          [html.text(current)],
        ),
        case closed_on {
          Some(closed_on) ->
            html.p([attribute.class("mt-1 text-sm text-gray-500")], [
              html.text("Closed on " <> date.format(closed_on)),
            ])
          None -> element.none()
        },
      ]),
      html.button(
        [
          attribute.class(primary_button_class),
          attribute.attribute("data-testid", "record-observation-button"),
          event.on_click(UserRequestedRecord),
        ],
        [html.text(action)],
      ),
    ],
  )
}

fn side_label(side: side.Side) -> String {
  case side {
    Asset -> "Asset"
    Liability -> "Liability"
  }
}

/// The term as the item form labels it.
fn term_label(side: side.Side, term: term.Term) -> String {
  case side, term {
    Asset, Current -> "Liquid"
    Asset, NonCurrent -> "Fixed"
    Liability, Current -> "Short-term"
    Liability, NonCurrent -> "Long-term"
  }
}

fn entry_table(line_ref: LineRef, entries: List(Entry)) -> Element(Msg) {
  case entries {
    [] ->
      html.p(
        [
          attribute.class(
            "rounded-lg border border-gray-200 bg-white px-4 py-8 text-center text-sm text-gray-500",
          ),
          attribute.attribute("data-testid", "observation-history-empty"),
        ],
        [html.text("No balances recorded yet.")],
      )
    _ ->
      html.table(
        [
          attribute.class(
            "w-full overflow-hidden rounded-lg border border-gray-200 bg-white text-sm",
          ),
        ],
        [
          html.thead([attribute.class("bg-gray-50 text-left text-gray-500")], [
            html.tr([], [
              html.th([attribute.class("px-4 py-2 font-medium")], [
                html.text("As of"),
              ]),
              html.th([attribute.class("px-4 py-2 text-right font-medium")], [
                html.text(case line_ref {
                  ItemRef(..) -> "Value"
                  AccountRef(..) -> "Balance"
                }),
              ]),
              html.th([attribute.class("px-4 py-2")], [
                html.span([attribute.class("sr-only")], [html.text("Actions")]),
              ]),
            ]),
          ]),
          html.tbody(
            [attribute.class("divide-y divide-gray-100")],
            list.map(entries, entry_row),
          ),
        ],
      )
  }
}

fn entry_row(entry: Entry) -> Element(Msg) {
  let as_of = date.format(entry.as_of)
  html.tr([attribute.attribute("data-testid", "observation-" <> as_of)], [
    html.td([attribute.class("px-4 py-2 text-gray-900")], [html.text(as_of)]),
    html.td(
      [
        attribute.class("px-4 py-2 text-right tabular-nums text-gray-900"),
        attribute.attribute("data-amount", money.to_string(entry.amount)),
      ],
      [html.text(money.format(entry.amount))],
    ),
    html.td([attribute.class("px-4 py-2 text-right")], [
      html.button(
        [
          attribute.class("text-sm font-medium text-red-600 hover:text-red-500"),
          attribute.attribute("data-testid", "delete-observation-" <> as_of),
          event.on_click(UserRequestedDelete(entry)),
        ],
        [html.text("Delete")],
      ),
    ]),
  ])
}

fn delete_options(line_ref: LineRef) -> delete_modal.Options(Entry, Nil, Msg) {
  let noun = noun(line_ref)
  delete_modal.Options(
    title: "Delete " <> noun,
    modal_testid: "delete-observation-modal",
    error_testid: "delete-observation-error",
    error_prefix: "Could not delete " <> noun,
    cancel_testid: "delete-observation-cancel-button",
    confirm_testid: "delete-observation-confirm-button",
    body: fn(entry: Entry, _context: Nil) {
      html.p([attribute.class("mb-4 text-sm text-gray-700")], [
        html.text(
          "Delete the "
          <> noun
          <> " of "
          <> money.format(entry.amount)
          <> " on "
          <> date.format(entry.as_of)
          <> "? Reports for that date use the "
          <> noun
          <> " before it instead.",
        ),
      ])
    },
  )
}

fn loading_state() -> Element(Msg) {
  html.p(
    [
      attribute.class("mt-6 text-sm text-gray-500"),
      attribute.attribute("data-testid", "observation-history-loading"),
    ],
    [html.text("Loading...")],
  )
}

fn failed_state() -> Element(Msg) {
  html.div(
    [
      attribute.class(
        "mt-6 rounded-lg border border-gray-200 bg-white px-6 py-12 text-center shadow-sm",
      ),
      attribute.attribute("data-testid", "observation-history-load-error"),
    ],
    [
      html.p([attribute.class("text-sm text-gray-700")], [
        html.text("Could not load the history."),
      ]),
      html.button(
        [
          attribute.class("mt-4 " <> primary_button_class),
          attribute.attribute("data-testid", "observation-history-retry"),
          event.on_click(UserRetried),
        ],
        [html.text("Retry")],
      ),
    ],
  )
}
