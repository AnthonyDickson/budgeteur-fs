//// A line's details page: its name, side, term, and current value or
//// balance, and its observation history, newest first, each of which can be
//// deleted, with the form that records a new one. See decision 9 in
//// docs/reports.md.

import budgeteur/balance_sheet_page/account.{type Account}
import budgeteur/balance_sheet_page/account_delete_modal
import budgeteur/balance_sheet_page/account_modal
import budgeteur/balance_sheet_page/account_write_request
import budgeteur/balance_sheet_page/balance_modal.{
  type CurrentBalance, CurrentBalance,
}
import budgeteur/balance_sheet_page/balance_sheet_item.{type BalanceSheetItem}
import budgeteur/balance_sheet_page/close_modal
import budgeteur/balance_sheet_page/item_delete_modal
import budgeteur/balance_sheet_page/item_modal
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
import gleam/result
import gleam/time/calendar.{type Date}
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import youid/uuid.{type Uuid}

const primary_button_class = "rounded-md bg-indigo-600 px-4 py-2 text-sm font-medium text-white "
  <> "hover:bg-indigo-500 focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:ring-offset-2"

const secondary_button_class = "rounded-md border border-gray-300 bg-white px-4 py-2 text-sm font-medium text-gray-700 "
  <> "hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:ring-offset-2"

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

/// Where an entry sits in the line's history, which decides what deleting it
/// does to the balance sheets drawn from it.
pub type Place {
  /// The entry before it takes over from its date.
  HasEarlier
  /// Sheets before the next entry leave the line out.
  Earliest
  /// The account's balance becomes unknown. An item's only value cannot be
  /// deleted.
  Only
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
    close_modal: close_modal.Modal,
    item_modal: item_modal.Modal,
    account_modal: account_modal.Modal,
    item_delete_modal: item_delete_modal.DeleteModalState,
    account_delete_modal: account_delete_modal.DeleteModalState,
    delete_modal: delete_modal.State(Entry, Place),
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
  UserRequestedClose
  CloseModalMsg(close_modal.Msg)
  UserRequestedReopen
  ServerReopened(Result(Nil, ApiError))
  // The edit forms' `DeleteRequested` opens the line's delete confirmation.
  UserRequestedEdit
  ItemModalMsg(item_modal.Msg)
  AccountModalMsg(account_modal.Msg)
  UserConfirmedLineDelete
  UserCancelledLineDelete
  // 404 is folded into Ok: the line is gone, as the user intended.
  ServerDeletedLine(Result(Nil, ApiError))
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
      close_modal: close_modal.hidden(),
      item_modal: item_modal.hidden(),
      account_modal: account_modal.hidden(),
      item_delete_modal: item_delete_modal.empty(),
      account_delete_modal: account_delete_modal.empty(),
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

    UserRequestedClose ->
      case model.line {
        Loaded(ItemLine(item:)) ->
          run_close_modal(
            model,
            close_modal.OpenRequested(
              id: item.id,
              kind: close_modal.Item,
              name: item.name,
              today: model.today,
            ),
          )
        Loaded(AccountWithBalance(account:, ..)) ->
          run_close_modal(
            model,
            close_modal.OpenRequested(
              id: account.id,
              kind: close_modal.Account,
              name: account.name,
              today: model.today,
            ),
          )
        Loading | Failed -> #(model, effect.none(), None)
      }
    CloseModalMsg(inner_msg) -> run_close_modal(model, inner_msg)

    UserRequestedEdit ->
      case model.line {
        Loaded(ItemLine(item:)) ->
          run_item_modal(model, item_modal.EditRequested(item:))
        Loaded(AccountWithBalance(account:, ..)) ->
          run_account_modal(model, account_modal.EditRequested(account:))
        Loading | Failed -> #(model, effect.none(), None)
      }
    ItemModalMsg(item_modal.DeleteRequested as inner_msg) ->
      open_line_delete(model) |> run_item_modal(inner_msg)
    ItemModalMsg(inner_msg) -> run_item_modal(model, inner_msg)
    AccountModalMsg(account_modal.DeleteRequested as inner_msg) ->
      open_line_delete(model) |> run_account_modal(inner_msg)
    AccountModalMsg(inner_msg) -> run_account_modal(model, inner_msg)

    UserConfirmedLineDelete -> confirm_line_delete(model)
    UserCancelledLineDelete -> #(
      Model(
        ..model,
        item_delete_modal: item_delete_modal.empty(),
        account_delete_modal: account_delete_modal.empty(),
      ),
      effect.none(),
      None,
    )
    ServerDeletedLine(Ok(Nil)) -> on_line_deleted(model)
    ServerDeletedLine(Error(error)) ->
      case api_error.is_not_found(error) {
        True -> on_line_deleted(model)
        False -> on_line_delete_failed(model, error)
      }

    UserRequestedReopen -> #(model, reopen(model.line_ref), None)
    ServerReopened(Ok(Nil)) -> {
      let #(model, effect) = refetch(model)
      #(model, effect, Some(out_msg.success_toast("Reopened")))
    }
    ServerReopened(Error(error)) -> #(
      model,
      effect.LogError(api_error.describe(error)),
      Some(out_msg.error_toast("Could not reopen", error.details)),
    )

    UserRequestedDelete(entry) -> {
      let place = case model.entries {
        Loaded(entries) -> place_of(entries, entry)
        Loading | Failed -> HasEarlier
      }
      #(
        Model(..model, delete_modal: delete_modal.open(entry, place)),
        effect.none(),
        None,
      )
    }
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

fn run_close_modal(
  model: Model,
  msg: close_modal.Msg,
) -> #(Model, Effect(Msg), Option(OutMsg)) {
  let #(close_modal, request, outcome) =
    close_modal.update(model.close_modal, msg)
  let model = Model(..model, close_modal:)
  let request_effect = case request {
    Some(form_modal.Put(payload: closed_on, ..)) ->
      effect.put(
        api_route.to_string(case model.line_ref {
          ItemRef(id) -> api_route.CloseItem(id)
          AccountRef(id) -> api_route.CloseAccount(id)
        }),
        json.object([#("closedOn", date.encode(closed_on))]) |> json.to_string,
        fn(result) {
          // The response is the closed line, which the page refetches.
          case result {
            Ok(_) -> close_modal.SaveCompleted(Ok(Nil))
            Error(http_error) ->
              close_modal.SaveCompleted(
                Error(response.http_error_to_api_error(http_error)),
              )
          }
        },
      )
      |> effect.with_timeout(form_modal.submit_timeout_ms)
      |> effect.map(CloseModalMsg)
    // The modal opens in edit mode only, so its request names the line.
    Some(form_modal.Post(_)) | None -> effect.none()
  }
  let log_effect = case msg {
    close_modal.SaveCompleted(result: Error(error)) ->
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
      #(model, refetch_effect, Some(out_msg.success_toast("Closed")))
    }
  }
}

/// Clear the line's close date. Reopening needs no form: closing again undoes
/// it.
fn reopen(line_ref: LineRef) -> Effect(Msg) {
  effect.delete(
    api_route.to_string(case line_ref {
      ItemRef(id) -> api_route.ReopenItem(id)
      AccountRef(id) -> api_route.ReopenAccount(id)
    }),
    fn(result) {
      case result {
        // A successful reopen returns 204 with no body.
        Ok(_) -> ServerReopened(Ok(Nil))
        Error(http_error) ->
          ServerReopened(Error(response.http_error_to_api_error(http_error)))
      }
    },
  )
}

/// Save the item's details. The form's duplicate check has no other items to
/// compare against here, so the server's check reports a duplicate.
fn run_item_modal(
  model: Model,
  msg: item_modal.Msg,
) -> #(Model, Effect(Msg), Option(OutMsg)) {
  let #(item_modal, request, outcome) =
    item_modal.update(model.item_modal, msg, [])
  let model = Model(..model, item_modal:)
  let request_effect = case request {
    Some(form_modal.Put(id:, payload:)) ->
      effect.put(
        api_route.UpdateBalanceSheetItem(id) |> api_route.to_string,
        item_write_request.to_json(payload) |> json.to_string,
        fn(result) {
          case result {
            Ok(body) ->
              response.decode_success(body, balance_sheet_item.decoder())
              |> item_modal.SaveCompleted
            Error(http_error) ->
              item_modal.SaveCompleted(
                Error(response.http_error_to_api_error(http_error)),
              )
          }
        },
      )
      |> effect.with_timeout(form_modal.submit_timeout_ms)
      |> effect.map(ItemModalMsg)
    // The page edits its item; items are created on the balance sheet.
    Some(form_modal.Post(_)) | None -> effect.none()
  }
  let log_effect = case msg {
    item_modal.SaveCompleted(result: Error(error)) ->
      effect.LogError(api_error.describe(error))
    _ -> effect.none()
  }
  on_saved(model, outcome, effect.batch([request_effect, log_effect]))
}

fn run_account_modal(
  model: Model,
  msg: account_modal.Msg,
) -> #(Model, Effect(Msg), Option(OutMsg)) {
  let #(account_modal, request, outcome) =
    account_modal.update(model.account_modal, msg)
  let model = Model(..model, account_modal:)
  let request_effect = case request {
    Some(form_modal.Put(id:, payload:)) ->
      effect.put(
        api_route.UpdateAccount(id) |> api_route.to_string,
        account_write_request.update_json(payload) |> json.to_string,
        fn(result) {
          case result {
            Ok(body) ->
              response.decode_success(body, account.decoder())
              |> account_modal.SaveCompleted
            Error(http_error) ->
              account_modal.SaveCompleted(
                Error(response.http_error_to_api_error(http_error)),
              )
          }
        },
      )
      |> effect.with_timeout(form_modal.submit_timeout_ms)
      |> effect.map(AccountModalMsg)
    // The page edits its account; accounts are created on the balance sheet.
    Some(form_modal.Post(_)) | None -> effect.none()
  }
  let log_effect = case msg {
    account_modal.SaveCompleted(result: Error(error)) ->
      effect.LogError(api_error.describe(error))
    _ -> effect.none()
  }
  on_saved(model, outcome, effect.batch([request_effect, log_effect]))
}

/// A saved edit refetches the line for its header.
fn on_saved(
  model: Model,
  outcome: form_modal.Outcome(entity),
  effect: Effect(Msg),
) -> #(Model, Effect(Msg), Option(OutMsg)) {
  case outcome {
    form_modal.NoChange -> #(model, effect, None)
    form_modal.Created(_) | form_modal.Updated(_) -> {
      let #(model, refetch_effect) = refetch(model)
      #(model, refetch_effect, Some(out_msg.success_toast("Saved")))
    }
  }
}

/// Open the delete confirmation for the line. Its edit form closes itself on
/// the same message.
fn open_line_delete(model: Model) -> Model {
  case model.line {
    Loaded(ItemLine(item:)) ->
      Model(..model, item_delete_modal: item_delete_modal.open(item))
    Loaded(AccountWithBalance(account:, ..)) ->
      Model(..model, account_delete_modal: account_delete_modal.open(account))
    Loading | Failed -> model
  }
}

fn confirm_line_delete(model: Model) -> #(Model, Effect(Msg), Option(OutMsg)) {
  let callback = fn(result) {
    case result {
      // A successful delete returns 204 with no body.
      Ok(_) -> ServerDeletedLine(Ok(Nil))
      Error(http_error) ->
        ServerDeletedLine(Error(response.http_error_to_api_error(http_error)))
    }
  }
  let confirmed = case model.line_ref {
    ItemRef(..) ->
      delete_modal.confirm(model.item_delete_modal)
      |> result.map(fn(confirmed) {
        let #(state, item) = confirmed
        #(
          Model(..model, item_delete_modal: state),
          api_route.DeleteBalanceSheetItem(item.id),
        )
      })
    AccountRef(..) ->
      delete_modal.confirm(model.account_delete_modal)
      |> result.map(fn(confirmed) {
        let #(state, account) = confirmed
        #(
          Model(..model, account_delete_modal: state),
          api_route.DeleteAccount(account.id),
        )
      })
  }
  case confirmed {
    Ok(#(model, route)) -> #(
      model,
      effect.delete(api_route.to_string(route), callback)
        |> effect.with_timeout(delete_modal.delete_timeout_ms),
      None,
    )
    Error(Nil) -> #(model, effect.none(), None)
  }
}

/// The line is gone, so the page returns to the balance sheet.
fn on_line_deleted(model: Model) -> #(Model, Effect(Msg), Option(OutMsg)) {
  let name = case model.line {
    Loaded(ItemLine(item:)) -> item.name
    Loaded(AccountWithBalance(account:, ..)) -> account.name
    Loading | Failed -> "the line"
  }
  #(
    Model(
      ..model,
      item_delete_modal: item_delete_modal.empty(),
      account_delete_modal: account_delete_modal.empty(),
    ),
    effect.push_url(route.to_string(route.BalanceSheet)),
    Some(out_msg.success_toast("Deleted '" <> name <> "'")),
  )
}

/// As for an entry, a stale response leaves a newer dialog session alone.
fn on_line_delete_failed(
  model: Model,
  error: ApiError,
) -> #(Model, Effect(Msg), Option(OutMsg)) {
  let updated =
    Model(
      ..model,
      item_delete_modal: delete_modal.fail(model.item_delete_modal, error),
      account_delete_modal: delete_modal.fail(model.account_delete_modal, error),
    )
  case updated == model {
    True -> #(model, effect.none(), None)
    False -> #(updated, effect.LogError(api_error.describe(error)), None)
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
      attribute.attribute("data-testid", "line-details-page"),
    ],
    [
      html.a(
        [
          attribute.href(route.to_string(route.BalanceSheet)),
          attribute.class(link_class),
          attribute.attribute("data-testid", "line-details-back"),
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
      value_modal.view(model.value_modal)
        |> element.map(ValueModalMsg),
      balance_modal.view(model.balance_modal)
        |> element.map(BalanceModalMsg),
      close_modal.view(model.close_modal) |> element.map(CloseModalMsg),
      item_modal.view(model.item_modal) |> element.map(ItemModalMsg),
      account_modal.view(model.account_modal) |> element.map(AccountModalMsg),
      item_delete_modal.view(
        model.item_delete_modal,
        on_cancel: UserCancelledLineDelete,
        on_confirm: UserConfirmedLineDelete,
      ),
      account_delete_modal.view(
        model.account_delete_modal,
        on_cancel: UserCancelledLineDelete,
        on_confirm: UserConfirmedLineDelete,
      ),
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
      side_label(item.side) <> " · " <> term.label(item.term, item.side),
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
            attribute.attribute("data-testid", "line-details-current"),
          ],
          [html.text(current)],
        ),
        case closed_on {
          Some(closed_on) ->
            html.p(
              [
                attribute.class("mt-1 text-sm text-gray-500"),
                attribute.attribute("data-testid", "line-details-closed-on"),
              ],
              [html.text("Closed on " <> date.format(closed_on))],
            )
          None -> element.none()
        },
      ]),
      html.div([attribute.class("flex shrink-0 gap-2")], [
        html.button(
          [
            attribute.class(secondary_button_class),
            attribute.attribute("data-testid", "edit-line-button"),
            event.on_click(UserRequestedEdit),
          ],
          [html.text("Edit details")],
        ),
        // A closed line is reopened rather than closed again; closing is
        // apart from editing, since it is an event rather than a detail.
        case closed_on {
          None ->
            html.button(
              [
                attribute.class(secondary_button_class),
                attribute.attribute("data-testid", "close-line-button"),
                event.on_click(UserRequestedClose),
              ],
              [html.text("Close")],
            )
          Some(_) ->
            html.button(
              [
                attribute.class(secondary_button_class),
                attribute.attribute("data-testid", "reopen-line-button"),
                event.on_click(UserRequestedReopen),
              ],
              [html.text("Reopen")],
            )
        },
        html.button(
          [
            attribute.class(primary_button_class),
            attribute.attribute("data-testid", "record-observation-button"),
            event.on_click(UserRequestedRecord),
          ],
          [html.text(action)],
        ),
      ]),
    ],
  )
}

fn side_label(side: side.Side) -> String {
  case side {
    Asset -> "Asset"
    Liability -> "Liability"
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
          attribute.attribute("data-testid", "line-details-empty"),
        ],
        [html.text("No balances recorded yet.")],
      )
    _ -> {
      let deletable = case line_ref, entries {
        ItemRef(..), [_] -> False
        _, _ -> True
      }
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
            list.map(entries, entry_row(_, deletable)),
          ),
        ],
      )
    }
  }
}

/// `deletable` is False for an item's only value, which the server keeps: an
/// item always has a value.
fn entry_row(entry: Entry, deletable: Bool) -> Element(Msg) {
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
          attribute.class(
            "text-sm font-medium text-red-600 hover:text-red-500 "
            <> "disabled:cursor-not-allowed disabled:text-gray-400",
          ),
          attribute.attribute("data-testid", "delete-observation-" <> as_of),
          attribute.disabled(!deletable),
          case deletable {
            True -> attribute.none()
            False ->
              attribute.title(
                "An item always has a value. Delete the item to remove it.",
              )
          },
          event.on_click(UserRequestedDelete(entry)),
        ],
        [html.text("Delete")],
      ),
    ]),
  ])
}

/// The entry's place in `entries`, which are newest first.
fn place_of(entries: List(Entry), entry: Entry) -> Place {
  case entries, list.last(entries) {
    [_], _ -> Only
    _, Ok(earliest) if earliest == entry -> Earliest
    _, _ -> HasEarlier
  }
}

fn delete_options(
  line_ref: LineRef,
) -> delete_modal.Options(Entry, Place, Msg) {
  let noun = noun(line_ref)
  let line_noun = case line_ref {
    ItemRef(..) -> "item"
    AccountRef(..) -> "account"
  }
  delete_modal.Options(
    title: "Delete " <> noun,
    modal_testid: "delete-observation-modal",
    error_testid: "delete-observation-error",
    error_prefix: "Could not delete " <> noun,
    cancel_testid: "delete-observation-cancel-button",
    confirm_testid: "delete-observation-confirm-button",
    body: fn(entry: Entry, place: Place) {
      html.p([attribute.class("mb-4 text-sm text-gray-700")], [
        html.text(
          "Delete the "
          <> noun
          <> " of "
          <> money.format(entry.amount)
          <> " on "
          <> date.format(entry.as_of)
          <> "? "
          <> case place {
            HasEarlier ->
              "Balance sheets from that date use the " <> noun <> " before it."
            Earliest ->
              "It is the earliest, so balance sheets before the next "
              <> noun
              <> " leave the "
              <> line_noun
              <> " out."
            Only ->
              "It is the only one, so the "
              <> line_noun
              <> "'s "
              <> noun
              <> " becomes unknown."
          },
        ),
      ])
    },
  )
}

fn loading_state() -> Element(Msg) {
  html.p(
    [
      attribute.class("mt-6 text-sm text-gray-500"),
      attribute.attribute("data-testid", "line-details-loading"),
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
      attribute.attribute("data-testid", "line-details-load-error"),
    ],
    [
      html.p([attribute.class("text-sm text-gray-700")], [
        html.text("Could not load the line."),
      ]),
      html.button(
        [
          attribute.class("mt-4 " <> primary_button_class),
          attribute.attribute("data-testid", "line-details-retry"),
          event.on_click(UserRetried),
        ],
        [html.text("Retry")],
      ),
    ],
  )
}
