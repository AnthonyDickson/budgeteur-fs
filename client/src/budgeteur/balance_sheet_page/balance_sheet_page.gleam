import budgeteur/balance_sheet_page/account.{type Account, type AccountLine}
import budgeteur/balance_sheet_page/account_delete_modal
import budgeteur/balance_sheet_page/account_modal
import budgeteur/balance_sheet_page/account_write_request
import budgeteur/balance_sheet_page/balance_sheet.{type BalanceSheet}
import budgeteur/balance_sheet_page/balance_sheet_item.{type BalanceSheetItem}
import budgeteur/balance_sheet_page/item_delete_modal
import budgeteur/balance_sheet_page/item_kind.{type ItemKind, Asset, Liability}
import budgeteur/balance_sheet_page/item_modal
import budgeteur/balance_sheet_page/item_write_request
import budgeteur/balance_sheet_page/term.{type Term, Current, NonCurrent}
import budgeteur/shared/api_error.{type ApiError}
import budgeteur/shared/api_route
import budgeteur/shared/date
import budgeteur/shared/delete_modal
import budgeteur/shared/effect.{type Effect}
import budgeteur/shared/form_modal
import budgeteur/shared/money
import budgeteur/shared/out_msg.{type OutMsg}
import budgeteur/shared/response
import gleam/float
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import gleam/time/calendar.{type Date}
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import youid/uuid.{type Uuid}

const primary_button_class = "rounded-md bg-indigo-600 px-4 py-2 text-sm font-medium text-white "
  <> "hover:bg-indigo-500 focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:ring-offset-2"

// Types
// -----

pub type Model {
  Model(
    sheet: SheetState,
    /// The client's local date, once the `GetLocalDate` effect has reported it.
    today: Option(Date),
    item_modal: item_modal.Modal,
    item_delete_modal: item_delete_modal.DeleteModalState,
    account_modal: account_modal.Modal,
    account_delete_modal: account_delete_modal.DeleteModalState,
  )
}

/// The lifecycle of the page's snapshot.
pub type SheetState {
  /// No response yet.
  Loading
  /// The sheet loaded. It is empty for a user who tracks nothing yet.
  Loaded(BalanceSheet)
  /// The first load failed.
  Failed
}

pub type Msg {
  ClientGotToday(Date)
  // API responses
  ClientFetchedSheet(Result(BalanceSheet, ApiError))
  // Retry after a failed first load.
  UserRequestedSheetReload
  // Item modal messages
  UserRequestedItemCreation(kind: ItemKind)
  UserRequestedItemEdit(Uuid)
  ItemModalMsg(item_modal.Msg)
  // Item delete modal messages
  UserRequestedItemDelete(BalanceSheetItem)
  UserConfirmedItemDelete
  UserCancelledItemDelete
  // Server response to a delete request. 404 is folded into Ok by the page
  // (the end state matches the user's intent), so this only carries genuine
  // failures.
  ServerDeletedItem(item: BalanceSheetItem, result: Result(Nil, ApiError))
  // Account modal messages
  UserRequestedAccountCreation
  UserRequestedAccountEdit(Account)
  AccountModalMsg(account_modal.Msg)
  // Account delete modal messages
  UserRequestedAccountDelete(Account)
  UserConfirmedAccountDelete
  UserCancelledAccountDelete
  // As for items, 404 is folded into Ok.
  ServerDeletedAccount(account: Account, result: Result(Nil, ApiError))
}

// Effects
// -------

fn fetch_sheet() -> Effect(Msg) {
  effect.get(api_route.GetBalanceSheet |> api_route.to_string, fn(result) {
    case result {
      Ok(body) ->
        ClientFetchedSheet(response.decode_success(
          body,
          balance_sheet.decoder(),
        ))
      Error(http_error) ->
        ClientFetchedSheet(Error(response.http_error_to_api_error(http_error)))
    }
  })
}

// Init
// ----

pub fn init() -> #(Model, Effect(Msg)) {
  #(
    Model(
      sheet: Loading,
      today: None,
      item_modal: item_modal.hidden(),
      item_delete_modal: item_delete_modal.empty(),
      account_modal: account_modal.hidden(),
      account_delete_modal: account_delete_modal.empty(),
    ),
    effect.batch([effect.GetLocalDate(ClientGotToday), fetch_sheet()]),
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

    ClientFetchedSheet(Ok(sheet)) -> #(
      Model(..model, sheet: Loaded(sheet)),
      effect.none(),
      None,
    )

    ClientFetchedSheet(Error(error)) -> on_fetch_failed(model, error)

    UserRequestedSheetReload -> #(
      Model(..model, sheet: Loading),
      fetch_sheet(),
      None,
    )

    UserRequestedItemCreation(kind:) ->
      run_item_modal(
        model,
        item_modal.CreateRequested(kind:, today: model.today),
      )

    UserRequestedItemEdit(id) -> {
      case list.find(model_items(model), fn(item) { item.id == id }) {
        Ok(item) -> run_item_modal(model, item_modal.EditRequested(item))
        Error(Nil) -> #(model, effect.none(), None)
      }
    }

    ItemModalMsg(inner_msg) -> run_item_modal(model, inner_msg)

    UserRequestedItemDelete(item) -> #(
      Model(..model, item_delete_modal: item_delete_modal.open(item)),
      effect.none(),
      None,
    )

    UserConfirmedItemDelete -> confirm_item_delete(model)

    ServerDeletedItem(item, result) -> {
      case result {
        Ok(_) -> on_item_delete_succeeded(model, item)
        Error(error) ->
          case api_error.is_not_found(error) {
            True -> on_item_delete_succeeded(model, item)
            False -> on_item_delete_failed(model, error)
          }
      }
    }

    UserCancelledItemDelete -> #(
      Model(..model, item_delete_modal: item_delete_modal.empty()),
      effect.none(),
      None,
    )

    UserRequestedAccountCreation ->
      run_account_modal(
        model,
        account_modal.CreateRequested(today: model.today),
      )

    UserRequestedAccountEdit(account) ->
      run_account_modal(
        model,
        account_modal.EditRequested(account:, today: model.today),
      )

    AccountModalMsg(inner_msg) -> run_account_modal(model, inner_msg)

    UserRequestedAccountDelete(account) -> #(
      Model(..model, account_delete_modal: account_delete_modal.open(account)),
      effect.none(),
      None,
    )

    UserConfirmedAccountDelete -> confirm_account_delete(model)

    ServerDeletedAccount(account, result) ->
      case result {
        Ok(_) -> on_account_delete_succeeded(model, account)
        Error(error) ->
          case api_error.is_not_found(error) {
            True -> on_account_delete_succeeded(model, account)
            False -> on_account_delete_failed(model, error)
          }
      }

    UserCancelledAccountDelete -> #(
      Model(..model, account_delete_modal: account_delete_modal.empty()),
      effect.none(),
      None,
    )
  }
}

/// A fetch failed. A sheet loaded earlier (e.g. before a refetch after a write)
/// is more useful than an error page; without one there is nothing to show, so
/// the page offers a retry.
fn on_fetch_failed(
  model: Model,
  error: ApiError,
) -> #(Model, Effect(Msg), Option(OutMsg)) {
  case model.sheet {
    Loaded(_) -> #(
      model,
      effect.LogError(api_error.describe(error)),
      Some(out_msg.error_toast(
        "Could not refresh balance sheet",
        "Showing the balance sheet loaded earlier",
      )),
    )
    Loading | Failed -> #(
      Model(..model, sheet: Failed),
      effect.LogError(api_error.describe(error)),
      None,
    )
  }
}

/// The items currently on the sheet; empty unless a snapshot has loaded.
fn model_items(model: Model) -> List(BalanceSheetItem) {
  case model.sheet {
    Loaded(sheet) -> sheet.items
    Loading | Failed -> []
  }
}

fn run_item_modal(
  model: Model,
  msg: item_modal.Msg,
) -> #(Model, Effect(Msg), Option(OutMsg)) {
  let #(item_modal, request, outcome) =
    item_modal.update(model.item_modal, msg, model_items(model))
  let model = Model(..model, item_modal:)
  let #(model, out_msg) = apply_item_outcome(model, outcome)
  let effects = case request {
    Some(request) -> [interpret_item_modal_request(request)]
    None -> []
  }
  let effects = case msg {
    item_modal.SaveCompleted(result: Error(error)) -> [
      effect.LogError(api_error.describe(error)),
      ..effects
    ]
    _ -> effects
  }
  // A create or update response carries only the item. The server owns the
  // totals, so the sheet is refetched rather than recomputed here.
  let effects = case outcome {
    form_modal.NoChange -> effects
    form_modal.Created(_) | form_modal.Updated(_) ->
      list.append(effects, [fetch_sheet()])
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

fn apply_item_outcome(
  model: Model,
  outcome: item_modal.Outcome,
) -> #(Model, Option(OutMsg)) {
  case outcome {
    form_modal.NoChange -> #(model, None)
    form_modal.Created(entity: item) -> #(
      model,
      Some(out_msg.success_toast("Created item '" <> item.name <> "'")),
    )
    form_modal.Updated(entity: item) -> #(
      model,
      Some(out_msg.success_toast("Updated item '" <> item.name <> "'")),
    )
  }
}

fn interpret_item_modal_request(request: item_modal.Request) -> Effect(Msg) {
  case request {
    form_modal.Post(payload) ->
      effect.post(
        api_route.CreateBalanceSheetItem |> api_route.to_string,
        item_write_request.to_json(payload) |> json.to_string,
        handle_item_response,
      )
      |> effect.with_timeout(form_modal.submit_timeout_ms)
      |> effect.map(ItemModalMsg)
    form_modal.Put(id:, payload:) ->
      effect.put(
        api_route.UpdateBalanceSheetItem(id) |> api_route.to_string,
        item_write_request.to_json(payload) |> json.to_string,
        handle_item_response,
      )
      |> effect.with_timeout(form_modal.submit_timeout_ms)
      |> effect.map(ItemModalMsg)
  }
}

fn handle_item_response(result) {
  case result {
    Ok(body) ->
      response.decode_success(body, balance_sheet_item.decoder())
      |> item_modal.SaveCompleted
    Error(http_error) ->
      item_modal.SaveCompleted(
        Error(response.http_error_to_api_error(http_error)),
      )
  }
}

fn confirm_item_delete(model: Model) -> #(Model, Effect(Msg), Option(OutMsg)) {
  case delete_modal.confirm(model.item_delete_modal) {
    Ok(#(state, item)) -> #(
      Model(..model, item_delete_modal: state),
      delete_item(item),
      None,
    )
    Error(Nil) -> #(model, effect.none(), None)
  }
}

fn delete_item(item: BalanceSheetItem) -> Effect(Msg) {
  effect.delete(
    api_route.DeleteBalanceSheetItem(item.id) |> api_route.to_string,
    fn(result) {
      case result {
        // A successful delete returns 204 with no body, so there is nothing
        // to decode.
        Ok(_) -> ServerDeletedItem(item, Ok(Nil))
        Error(http_error) ->
          ServerDeletedItem(
            item,
            Error(response.http_error_to_api_error(http_error)),
          )
      }
    },
  )
  |> effect.with_timeout(delete_modal.delete_timeout_ms)
}

fn on_item_delete_succeeded(
  model: Model,
  item: BalanceSheetItem,
) -> #(Model, Effect(Msg), Option(OutMsg)) {
  #(
    Model(..model, item_delete_modal: item_delete_modal.empty()),
    fetch_sheet(),
    Some(out_msg.success_toast("Deleted item '" <> item.name <> "'")),
  )
}

fn on_item_delete_failed(
  model: Model,
  error: ApiError,
) -> #(Model, Effect(Msg), Option(OutMsg)) {
  // A response can only arrive while the modal is `Deleting` (the dialog is
  // locked while the request is in flight), so `fail` normally moves it to
  // `Errored` for an inline retry. The unchanged-state check covers a stale
  // response (the modal was reset, e.g. closed and re-opened for another
  // item), which must not touch the newer session.
  let updated = delete_modal.fail(model.item_delete_modal, error)
  case updated == model.item_delete_modal {
    True -> #(model, effect.none(), None)
    False -> #(
      Model(..model, item_delete_modal: updated),
      effect.LogError(api_error.describe(error)),
      None,
    )
  }
}

fn run_account_modal(
  model: Model,
  msg: account_modal.Msg,
) -> #(Model, Effect(Msg), Option(OutMsg)) {
  let #(account_modal, request, outcome) =
    account_modal.update(model.account_modal, msg)
  let model = Model(..model, account_modal:)
  let effects = case request {
    Some(request) -> [interpret_account_modal_request(request)]
    None -> []
  }
  let effects = case msg {
    account_modal.SaveCompleted(result: Error(error)) -> [
      effect.LogError(api_error.describe(error)),
      ..effects
    ]
    _ -> effects
  }
  // A save may record a balance, which moves the account's line and the
  // totals the server computes, so the sheet is refetched.
  let #(effects, out_msg) = case outcome {
    form_modal.NoChange -> #(effects, None)
    form_modal.Created(entity: account) -> #(
      list.append(effects, [fetch_sheet()]),
      Some(out_msg.success_toast("Created account '" <> account.name <> "'")),
    )
    form_modal.Updated(entity: account) -> #(
      list.append(effects, [fetch_sheet()]),
      Some(out_msg.success_toast("Updated account '" <> account.name <> "'")),
    )
  }
  let effect = case effects {
    [] -> effect.none()
    [effect] -> effect
    _ -> effect.batch(effects)
  }
  #(model, effect, out_msg)
}

fn interpret_account_modal_request(
  request: account_modal.Request,
) -> Effect(Msg) {
  case request {
    form_modal.Post(payload) ->
      effect.post(
        api_route.CreateAccount |> api_route.to_string,
        account_write_request.to_json(payload) |> json.to_string,
        handle_account_response,
      )
    form_modal.Put(id:, payload:) ->
      effect.put(
        api_route.UpdateAccount(id) |> api_route.to_string,
        account_write_request.to_json(payload) |> json.to_string,
        handle_account_response,
      )
  }
  |> effect.with_timeout(form_modal.submit_timeout_ms)
  |> effect.map(AccountModalMsg)
}

fn handle_account_response(result) {
  case result {
    Ok(body) ->
      response.decode_success(body, account.decoder())
      |> account_modal.SaveCompleted
    Error(http_error) ->
      account_modal.SaveCompleted(
        Error(response.http_error_to_api_error(http_error)),
      )
  }
}

fn confirm_account_delete(
  model: Model,
) -> #(Model, Effect(Msg), Option(OutMsg)) {
  case delete_modal.confirm(model.account_delete_modal) {
    Ok(#(state, account)) -> #(
      Model(..model, account_delete_modal: state),
      effect.delete(
        api_route.DeleteAccount(account.id) |> api_route.to_string,
        fn(result) {
          case result {
            Ok(_) -> ServerDeletedAccount(account, Ok(Nil))
            Error(http_error) ->
              ServerDeletedAccount(
                account,
                Error(response.http_error_to_api_error(http_error)),
              )
          }
        },
      )
        |> effect.with_timeout(delete_modal.delete_timeout_ms),
      None,
    )
    Error(Nil) -> #(model, effect.none(), None)
  }
}

fn on_account_delete_succeeded(
  model: Model,
  account: Account,
) -> #(Model, Effect(Msg), Option(OutMsg)) {
  #(
    Model(..model, account_delete_modal: account_delete_modal.empty()),
    fetch_sheet(),
    Some(out_msg.success_toast("Deleted account '" <> account.name <> "'")),
  )
}

/// As for items, a stale response leaves a newer dialog session alone.
fn on_account_delete_failed(
  model: Model,
  error: ApiError,
) -> #(Model, Effect(Msg), Option(OutMsg)) {
  let updated = delete_modal.fail(model.account_delete_modal, error)
  case updated == model.account_delete_modal {
    True -> #(model, effect.none(), None)
    False -> #(
      Model(..model, account_delete_modal: updated),
      effect.LogError(api_error.describe(error)),
      None,
    )
  }
}

// View
// ----

pub fn view(model: Model) -> Element(Msg) {
  html.div(
    [
      attribute.class("mx-auto max-w-6xl px-4 py-8 sm:px-6"),
      attribute.attribute("data-testid", "balance-sheet-page"),
    ],
    [
      case model.sheet {
        Loading -> loading_state()
        Loaded(sheet) -> loaded_sheet(sheet, model.today)
        Failed -> failed_state()
      },
      item_modal.view(model.item_modal)
        |> element.map(ItemModalMsg),
      item_delete_modal.view(
        model.item_delete_modal,
        on_cancel: UserCancelledItemDelete,
        on_confirm: UserConfirmedItemDelete,
      ),
      account_modal.view(model.account_modal)
        |> element.map(AccountModalMsg),
      account_delete_modal.view(
        model.account_delete_modal,
        on_cancel: UserCancelledAccountDelete,
        on_confirm: UserConfirmedAccountDelete,
      ),
    ],
  )
}

fn loaded_sheet(sheet: BalanceSheet, today: Option(Date)) -> Element(Msg) {
  html.div([], [
    page_header(statement_date_subtitle(today)),
    summary_cards(sheet),
    unknown_balances_callout(sheet.unknown_balances),
    case sheet.items, sheet.accounts, sheet.unknown_balances {
      [], [], [] -> empty_state()
      _, _, _ -> sheet_columns(sheet)
    },
  ])
}

/// The sheet is drawn for the client's today, its statement date. Each line
/// shows its own as-of date.
fn statement_date_subtitle(today: Option(Date)) -> String {
  case today {
    Some(today) -> "Balances as of " <> date.format(today)
    None -> ""
  }
}

/// The first load failed; the page offers a retry rather than an indefinite
/// loading state.
fn failed_state() -> Element(Msg) {
  html.div([], [
    page_header("Not available"),
    html.div(
      [
        attribute.class(
          "mx-auto max-w-md rounded-lg border border-gray-200 bg-white px-6 py-12 text-center shadow-sm",
        ),
        attribute.attribute("data-testid", "balance-sheet-load-error"),
      ],
      [
        html.h2([attribute.class("text-base font-semibold text-gray-900")], [
          html.text("Could not load the balance sheet"),
        ]),
        html.p([attribute.class("mt-1 text-sm text-gray-500")], [
          html.text("Check your connection and try again."),
        ]),
        html.button(
          [
            attribute.class("mt-4 " <> primary_button_class),
            attribute.attribute("data-testid", "balance-sheet-retry"),
            event.on_click(UserRequestedSheetReload),
          ],
          [html.text("Retry")],
        ),
      ],
    ),
  ])
}

fn loading_state() -> Element(Msg) {
  html.div(
    [
      attribute.class(
        "mx-auto max-w-md rounded-lg border border-gray-200 bg-white px-6 py-12 text-center shadow-sm",
      ),
      attribute.attribute("data-testid", "balance-sheet-loading-state"),
    ],
    [
      html.p([attribute.class("text-sm text-gray-500")], [
        html.text("Loading balance sheet..."),
      ]),
    ],
  )
}

fn page_header(subtitle: String) -> Element(Msg) {
  html.div(
    [attribute.class("mb-6 flex flex-wrap items-center justify-between gap-4")],
    [
      html.div([], [
        html.h1([attribute.class("text-2xl font-semibold text-gray-900")], [
          html.text("Balance Sheet"),
        ]),
        html.p([attribute.class("mt-1 text-sm text-gray-500")], [
          html.text(subtitle),
        ]),
      ]),
      html.div([attribute.class("flex flex-wrap items-center gap-2")], [
        html.button(
          [
            attribute.class(primary_button_class),
            attribute.attribute("data-testid", "add-asset-button"),
            event.on_click(UserRequestedItemCreation(Asset)),
          ],
          [html.text("Add asset")],
        ),
        html.button(
          [
            attribute.class(primary_button_class),
            attribute.attribute("data-testid", "add-liability-button"),
            event.on_click(UserRequestedItemCreation(Liability)),
          ],
          [html.text("Add liability")],
        ),
        html.button(
          [
            attribute.class(primary_button_class),
            attribute.attribute("data-testid", "add-account-button"),
            event.on_click(UserRequestedAccountCreation),
          ],
          [html.text("Add account")],
        ),
      ]),
    ],
  )
}

fn summary_cards(sheet: BalanceSheet) -> Element(Msg) {
  html.div(
    [
      attribute.class(
        "mb-6 grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4",
      ),
    ],
    [
      summary_card("Total assets", sheet.total_assets, "total-assets"),
      summary_card(
        "Total liabilities",
        sheet.total_liabilities,
        "total-liabilities",
      ),
      summary_card("Net worth", sheet.net_worth, "net-worth"),
      summary_card("Working capital", sheet.working_capital, "working-capital"),
    ],
  )
}

fn summary_card(label: String, amount: Float, testid: String) -> Element(Msg) {
  html.div(
    [
      attribute.class(
        "rounded-lg border border-gray-200 bg-white px-4 py-3 shadow-sm",
      ),
      attribute.attribute("data-testid", testid),
    ],
    [
      html.p(
        [
          attribute.class(
            "text-xs font-medium uppercase tracking-wide text-gray-500",
          ),
        ],
        [html.text(label)],
      ),
      html.p(
        [
          attribute.class(
            "mt-1 text-xl font-semibold tabular-nums text-gray-900",
          ),
          attribute.attribute("data-amount", float.to_string(amount)),
        ],
        [html.text(money.format(amount))],
      ),
    ],
  )
}

fn sheet_columns(sheet: BalanceSheet) -> Element(Msg) {
  html.div([attribute.class("grid grid-cols-1 gap-6 lg:grid-cols-2")], [
    sheet_side(
      title: "Assets",
      groups: [
        line_group(
          sheet,
          "Current assets",
          kind: Asset,
          term: Current,
          subtotal: sheet.total_current_assets,
        ),
        line_group(
          sheet,
          "Non-current assets",
          kind: Asset,
          term: NonCurrent,
          subtotal: sheet.total_non_current_assets,
        ),
      ],
      total_label: "Total assets",
      total: sheet.total_assets,
    ),
    sheet_side(
      title: "Liabilities",
      groups: [
        line_group(
          sheet,
          "Current liabilities",
          kind: Liability,
          term: Current,
          subtotal: sheet.total_current_liabilities,
        ),
        line_group(
          sheet,
          "Non-current liabilities",
          kind: Liability,
          term: NonCurrent,
          subtotal: sheet.total_non_current_liabilities,
        ),
      ],
      total_label: "Total liabilities",
      total: sheet.total_liabilities,
    ),
  ])
}

fn sheet_side(
  title title: String,
  groups groups: List(Element(Msg)),
  total_label total_label: String,
  total total: Float,
) -> Element(Msg) {
  html.div(
    [
      attribute.class(
        "overflow-hidden rounded-lg border border-gray-200 bg-white shadow-sm",
      ),
    ],
    [
      html.h2(
        [
          attribute.class(
            "border-b border-gray-200 px-4 py-3 text-base font-semibold text-gray-900",
          ),
        ],
        [html.text(title)],
      ),
      html.div([], groups),
      html.div(
        [
          attribute.class(
            "flex items-center justify-between border-t border-gray-200 bg-gray-50 px-4 py-3",
          ),
        ],
        [
          html.span([attribute.class("text-sm font-semibold text-gray-900")], [
            html.text(total_label),
          ]),
          html.span(
            [
              attribute.class(
                "text-sm font-semibold tabular-nums text-gray-900",
              ),
              attribute.attribute("data-amount", float.to_string(total)),
            ],
            [html.text(money.format(total))],
          ),
        ],
      ),
    ],
  )
}

/// One kind and term's lines: its items, then its accounts, with the subtotal.
fn line_group(
  sheet: BalanceSheet,
  title: String,
  kind kind: ItemKind,
  term term: Term,
  subtotal subtotal: Float,
) -> Element(Msg) {
  let rows =
    list.append(
      items_with(sheet.items, kind:, term:) |> list.map(item_row),
      accounts_with(sheet.accounts, kind:, term:) |> list.map(account_row),
    )

  html.div([], [
    html.div(
      [
        attribute.class(
          "flex items-center justify-between bg-gray-50 px-4 py-2",
        ),
      ],
      [
        html.h3(
          [
            attribute.class(
              "text-xs font-semibold uppercase tracking-wide text-gray-500",
            ),
          ],
          [html.text(title)],
        ),
        html.span(
          [
            attribute.class("text-xs font-semibold text-gray-500"),
            attribute.attribute("data-amount", float.to_string(subtotal)),
          ],
          [html.text(money.format(subtotal))],
        ),
      ],
    ),
    case rows {
      [] ->
        html.p([attribute.class("px-4 py-3 text-sm text-gray-400")], [
          html.text("None"),
        ])
      _ -> html.ul([attribute.class("divide-y divide-gray-100")], rows)
    },
  ])
}

fn item_row(item: BalanceSheetItem) -> Element(Msg) {
  line_row(
    line: "item",
    id: item.id,
    name: item.name,
    details: ["As of " <> date.format(item.as_of)],
    balance: item.balance,
    on_edit: UserRequestedItemEdit(item.id),
    on_delete: UserRequestedItemDelete(item),
  )
}

/// An account line is marked with its number, when it has one, and its current
/// balance's as-of date.
fn account_row(line: AccountLine) -> Element(Msg) {
  let as_of = "As of " <> date.format(line.as_of)

  line_row(
    line: "account",
    id: line.account.id,
    name: line.account.name,
    details: case line.account.number {
      Some(number) -> [number, as_of]
      None -> [as_of]
    },
    balance: line.balance,
    on_edit: UserRequestedAccountEdit(line.account),
    on_delete: UserRequestedAccountDelete(line.account),
  )
}

/// A line on the sheet with its edit and delete buttons. `line` names the
/// source ("item" or "account") in the test ids.
fn line_row(
  line line: String,
  id id: Uuid,
  name name: String,
  details details: List(String),
  balance balance: Float,
  on_edit on_edit: Msg,
  on_delete on_delete: Msg,
) -> Element(Msg) {
  let testid = uuid.to_string(id)

  html.li(
    [
      attribute.class("flex items-center gap-3 px-4 py-3"),
      attribute.attribute(
        "data-testid",
        "balance-sheet-" <> line <> "-" <> testid,
      ),
    ],
    [
      html.div([attribute.class("min-w-0 flex-1")], [
        html.p([attribute.class("truncate text-sm text-gray-700")], [
          html.text(name),
        ]),
        html.p([attribute.class("text-xs text-gray-400")], [
          html.text(string.join(details, " · ")),
        ]),
      ]),
      html.span(
        [
          attribute.class("text-right text-sm tabular-nums text-gray-900"),
          attribute.attribute("data-amount", float.to_string(balance)),
        ],
        [html.text(money.format(balance))],
      ),
      html.div([attribute.class("flex items-center gap-1")], [
        html.button(
          [
            attribute.class(
              "rounded-md px-3 py-1 text-sm font-medium text-indigo-600 "
              <> "hover:bg-indigo-50 hover:text-indigo-700 "
              <> "focus:outline-none focus:ring-2 focus:ring-indigo-500 "
              <> "focus:ring-offset-2",
            ),
            attribute.attribute("data-testid", "edit-" <> line <> "-" <> testid),
            event.on_click(on_edit),
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
              "delete-" <> line <> "-" <> testid,
            ),
            event.on_click(on_delete),
          ],
          [html.text("Delete")],
        ),
      ]),
    ],
  )
}

/// Accounts whose balance is unknown are left out of the totals, so the page
/// asks for their balances above the sheet.
fn unknown_balances_callout(accounts: List(Account)) -> Element(Msg) {
  case accounts {
    [] -> element.none()
    _ ->
      html.div(
        [
          attribute.class(
            "mb-6 rounded-lg border border-amber-200 bg-amber-50 px-4 py-3",
          ),
          attribute.attribute("data-testid", "unknown-balances"),
        ],
        [
          html.h2([attribute.class("text-sm font-semibold text-amber-900")], [
            html.text("Balances needed"),
          ]),
          html.p([attribute.class("mt-1 text-sm text-amber-800")], [
            html.text(
              "These accounts have no balance yet, so they are left out of the totals.",
            ),
          ]),
          html.ul(
            [attribute.class("mt-2 divide-y divide-amber-200")],
            list.map(accounts, fn(account) {
              let testid = uuid.to_string(account.id)

              html.li(
                [
                  attribute.class("flex items-center gap-3 py-2"),
                  attribute.attribute(
                    "data-testid",
                    "unknown-balance-" <> testid,
                  ),
                ],
                [
                  html.span(
                    [attribute.class("min-w-0 flex-1 truncate text-sm")],
                    [
                      html.text(account.name),
                      case account.number {
                        Some(number) ->
                          html.span([attribute.class("ml-2 text-amber-700")], [
                            html.text(number),
                          ])
                        None -> element.none()
                      },
                    ],
                  ),
                  html.button(
                    [
                      attribute.class(
                        "rounded-md px-3 py-1 text-sm font-medium text-indigo-600 "
                        <> "hover:bg-indigo-50 hover:text-indigo-700 "
                        <> "focus:outline-none focus:ring-2 focus:ring-indigo-500",
                      ),
                      attribute.attribute(
                        "data-testid",
                        "enter-balance-" <> testid,
                      ),
                      event.on_click(UserRequestedAccountEdit(account)),
                    ],
                    [html.text("Enter balance")],
                  ),
                  html.button(
                    [
                      attribute.class(
                        "rounded-md px-3 py-1 text-sm font-medium text-red-600 "
                        <> "hover:bg-red-50 hover:text-red-700 "
                        <> "focus:outline-none focus:ring-2 focus:ring-red-500",
                      ),
                      attribute.attribute(
                        "data-testid",
                        "delete-account-" <> testid,
                      ),
                      event.on_click(UserRequestedAccountDelete(account)),
                    ],
                    [html.text("Delete")],
                  ),
                ],
              )
            }),
          ),
        ],
      )
  }
}

fn empty_state() -> Element(Msg) {
  empty_card(
    testid: "no-items-empty-state",
    heading: "Nothing on the balance sheet yet",
    body: "Track what you own and owe to see your net worth at a glance.",
  )
}

fn empty_card(
  testid testid: String,
  heading heading: String,
  body body: String,
) -> Element(Msg) {
  html.div(
    [
      attribute.class(
        "mx-auto max-w-md rounded-lg border border-gray-200 bg-white px-6 py-12 text-center shadow-sm",
      ),
      attribute.attribute("data-testid", testid),
    ],
    [
      html.h2([attribute.class("text-base font-semibold text-gray-900")], [
        html.text(heading),
      ]),
      html.p([attribute.class("mt-1 text-sm text-gray-500")], [
        html.text(body),
      ]),
    ],
  )
}

fn items_with(
  items: List(BalanceSheetItem),
  kind kind: ItemKind,
  term term: Term,
) -> List(BalanceSheetItem) {
  list.filter(items, fn(item) { item.kind == kind && item.term == term })
}

fn accounts_with(
  accounts: List(AccountLine),
  kind kind: ItemKind,
  term term: Term,
) -> List(AccountLine) {
  list.filter(accounts, fn(line) {
    line.kind == kind && line.account.term == term
  })
}
