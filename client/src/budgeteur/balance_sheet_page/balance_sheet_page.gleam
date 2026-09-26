import budgeteur/balance_sheet_page/balance_sheet.{type BalanceSheet}
import budgeteur/balance_sheet_page/balance_sheet_item.{type BalanceSheetItem}
import budgeteur/balance_sheet_page/balance_sheet_page_data.{
  type BalanceSheetPageData, BalanceSheetPageData,
}
import budgeteur/balance_sheet_page/item_delete_modal
import budgeteur/balance_sheet_page/item_kind.{type ItemKind, Asset, Liability}
import budgeteur/balance_sheet_page/item_modal
import budgeteur/balance_sheet_page/term.{type Term, Current, NonCurrent}
import budgeteur/balance_sheet_page/write_item_request
import budgeteur/shared/api_error.{type ApiError}
import budgeteur/shared/api_route
import budgeteur/shared/date
import budgeteur/shared/delete_modal
import budgeteur/shared/effect.{type Effect}
import budgeteur/shared/form_modal
import budgeteur/shared/money
import budgeteur/shared/out_msg.{type OutMsg}
import budgeteur/shared/response
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/pair
import gleam/time/calendar
import gleam/time/timestamp
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
    item_modal: item_modal.Modal,
    item_delete_modal: item_delete_modal.DeleteModalState,
  )
}

/// The lifecycle of the page's snapshot.
pub type SheetState {
  /// No response yet, and nothing cached to show.
  Loading
  /// The user has no balance sheet yet. The server creates the sheet on the
  /// first item write, so a missing sheet is an expected state, not a failure.
  Empty
  /// The sheet loaded. Its item list may be empty (every item was deleted).
  Loaded(BalanceSheet)
  /// The first load failed and there is nothing cached to fall back to.
  Failed
}

pub type Msg {
  ClientRestoredData(Option(BalanceSheetPageData))
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

fn restore_data_from_store() -> Effect(Msg) {
  effect.LoadFromStore(
    key: balance_sheet_page_data.storage_key,
    callback: fn(store_result) {
      case store_result {
        Ok(value) -> {
          case json.parse(value, using: balance_sheet_page_data.decoder()) {
            Ok(data) -> ClientRestoredData(Some(data))
            Error(_) -> ClientRestoredData(None)
          }
        }
        Error(_) -> ClientRestoredData(None)
      }
    },
  )
}

fn persist_sheet(sheet: BalanceSheet) -> Effect(Msg) {
  effect.SaveToStore(
    balance_sheet_page_data.storage_key,
    balance_sheet_page_data.to_string(BalanceSheetPageData(sheet:)),
  )
}

/// Forget the cached snapshot. An empty value is treated as absent by
/// `LoadFromStore`.
fn clear_stored_sheet() -> Effect(Msg) {
  effect.SaveToStore(balance_sheet_page_data.storage_key, "")
}

// Init
// ----

pub fn init() -> #(Model, Effect(Msg)) {
  #(
    Model(
      sheet: Loading,
      item_modal: item_modal.hidden(),
      item_delete_modal: item_delete_modal.empty(),
    ),
    effect.batch([restore_data_from_store(), fetch_sheet()]),
  )
}

// Update
// ------

pub fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg), Option(OutMsg)) {
  let #(new_model, effect, out_msg) = update_inner(model, msg)

  case msg {
    // Restored data came from the store, so don't write it straight back.
    ClientRestoredData(_) -> #(new_model, effect, out_msg)
    _ ->
      case new_model.sheet == model.sheet {
        True -> #(new_model, effect, out_msg)
        False ->
          case new_model.sheet {
            Loaded(sheet) -> #(
              new_model,
              effect.batch([effect, persist_sheet(sheet)]),
              out_msg,
            )
            // The server has no sheet for this user, so any cached snapshot
            // is stale and is dropped.
            Empty -> #(
              new_model,
              effect.batch([effect, clear_stored_sheet()]),
              out_msg,
            )
            Loading | Failed -> #(new_model, effect, out_msg)
          }
      }
  }
}

fn update_inner(
  model: Model,
  msg: Msg,
) -> #(Model, Effect(Msg), Option(OutMsg)) {
  case msg {
    ClientRestoredData(Some(data)) -> #(
      Model(..model, sheet: Loaded(data.sheet)),
      effect.none(),
      None,
    )

    ClientRestoredData(None) -> #(model, effect.none(), None)

    ClientFetchedSheet(Ok(sheet)) -> #(
      Model(..model, sheet: Loaded(sheet)),
      effect.none(),
      None,
    )

    ClientFetchedSheet(Error(error)) ->
      case api_error.is_not_found(error) {
        // A user with no sheet yet. Expected, so it is not an error.
        True -> #(Model(..model, sheet: Empty), effect.none(), None)
        False -> on_fetch_failed(model, error)
      }

    UserRequestedSheetReload -> #(
      Model(..model, sheet: Loading),
      fetch_sheet(),
      None,
    )

    UserRequestedItemCreation(kind:) ->
      run_item_modal(model, item_modal.CreateRequested(kind))

    UserRequestedItemEdit(id) -> {
      case list.find(model_items(model), fn(item) { item.id == id }) {
        Ok(item) -> run_item_modal(model, item_modal.EditRequested(item))
        Error(Nil) -> #(model, effect.none(), None)
      }
    }

    ItemModalMsg(inner_msg) -> run_item_modal(model, inner_msg)

    UserRequestedItemDelete(item) -> #(
      Model(..model, item_delete_modal: item_delete_modal.open(item)),
      effect.ShowDialog(selector: item_delete_modal.dom_id_selector),
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
      effect.CloseDialog(selector: item_delete_modal.dom_id_selector),
      None,
    )
  }
}

/// A fetch failed for a reason other than a missing sheet. A cached snapshot
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
        "Could not sync balance sheet",
        "Falling back to local data",
      )),
    )
    Loading | Empty | Failed -> #(
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
    Loading | Empty | Failed -> []
  }
}

fn run_item_modal(
  model: Model,
  msg: item_modal.Msg,
) -> #(Model, Effect(Msg), Option(OutMsg)) {
  let #(item_modal, requests, outcome) =
    item_modal.update(model.item_modal, msg, model_items(model))
  let model = Model(..model, item_modal:)
  let #(model, out_msg) = apply_item_outcome(model, outcome)
  let effects = list.map(requests, interpret_item_modal_request)
  let effects = case msg {
    item_modal.SaveCompleted(result: Error(error)) -> [
      effect.LogError(api_error.describe(error)),
      ..effects
    ]
    _ -> effects
  }
  // A create or update response carries only the item. The server owns the
  // statement date and the totals, so the sheet is refetched rather than
  // recomputed here.
  let effects = case outcome {
    form_modal.NoChange -> effects
    form_modal.Created(_) | form_modal.Updated(_) ->
      list.append(effects, [fetch_sheet()])
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
    form_modal.ShowDialog ->
      effect.ShowDialog(selector: item_modal.dom_id_selector)
    form_modal.CloseDialog ->
      effect.CloseDialog(selector: item_modal.dom_id_selector)
    form_modal.Post(payload) ->
      effect.post(
        api_route.CreateBalanceSheetItem |> api_route.to_string,
        write_item_request.to_json(payload) |> json.to_string,
        handle_item_response,
      )
      |> effect.with_timeout(form_modal.submit_timeout_ms)
      |> effect.map(ItemModalMsg)
    form_modal.Put(id:, payload:) ->
      effect.put(
        api_route.UpdateBalanceSheetItem(id) |> api_route.to_string,
        write_item_request.to_json(payload) |> json.to_string,
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
    effect.batch([
      effect.CloseDialog(selector: item_delete_modal.dom_id_selector),
      fetch_sheet(),
    ]),
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
        Empty -> no_sheet_state()
        Loaded(sheet) -> loaded_sheet(sheet)
        Failed -> failed_state()
      },
      item_modal.view(model.item_modal)
        |> element.map(ItemModalMsg),
      item_delete_modal.view(
        model.item_delete_modal,
        on_cancel: UserCancelledItemDelete,
        on_confirm: UserConfirmedItemDelete,
      ),
    ],
  )
}

fn loaded_sheet(sheet: BalanceSheet) -> Element(Msg) {
  html.div([], [
    page_header(statement_date_subtitle(sheet)),
    summary_cards(sheet),
    case list.is_empty(sheet.items) {
      True -> empty_state()
      False -> sheet_columns(sheet)
    },
  ])
}

fn statement_date_subtitle(sheet: BalanceSheet) -> String {
  "Balances as of "
  <> date.format(
    sheet.statement_date
    |> timestamp.to_calendar(calendar.local_offset())
    |> pair.first,
  )
}

/// A user who has never added an item has no balance sheet on the server yet.
fn no_sheet_state() -> Element(Msg) {
  html.div([], [
    page_header("No balances recorded yet"),
    empty_card(
      testid: "no-balance-sheet-empty-state",
      heading: "No balance sheet yet",
      body: "Add what you own and owe to see your net worth and working capital.",
    ),
  ])
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
      html.div([attribute.class("flex items-center gap-2")], [
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
        item_group(
          "Current assets",
          items_with(sheet.items, kind: Asset, term: Current),
          subtotal: sheet.total_current_assets,
        ),
        item_group(
          "Non-current assets",
          items_with(sheet.items, kind: Asset, term: NonCurrent),
          subtotal: sheet.total_non_current_assets,
        ),
      ],
      total_label: "Total assets",
      total: sheet.total_assets,
    ),
    sheet_side(
      title: "Liabilities",
      groups: [
        item_group(
          "Current liabilities",
          items_with(sheet.items, kind: Liability, term: Current),
          subtotal: sheet.total_current_liabilities,
        ),
        item_group(
          "Non-current liabilities",
          items_with(sheet.items, kind: Liability, term: NonCurrent),
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
            ],
            [html.text(money.format(total))],
          ),
        ],
      ),
    ],
  )
}

fn item_group(
  title: String,
  items: List(BalanceSheetItem),
  subtotal subtotal: Float,
) -> Element(Msg) {
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
        html.span([attribute.class("text-xs font-semibold text-gray-500")], [
          html.text(money.format(subtotal)),
        ]),
      ],
    ),
    case list.is_empty(items) {
      True ->
        html.p([attribute.class("px-4 py-3 text-sm text-gray-400")], [
          html.text("None"),
        ])
      False ->
        html.ul(
          [attribute.class("divide-y divide-gray-100")],
          list.map(items, item_row),
        )
    },
  ])
}

fn item_row(item: BalanceSheetItem) -> Element(Msg) {
  let testid = uuid.to_string(item.id)

  html.li(
    [
      attribute.class("flex items-center gap-3 px-4 py-3"),
      attribute.attribute("data-testid", "balance-sheet-item-" <> testid),
    ],
    [
      html.span([attribute.class("flex-1 truncate text-sm text-gray-700")], [
        html.text(item.name),
      ]),
      html.span(
        [attribute.class("text-right text-sm tabular-nums text-gray-900")],
        [html.text(money.format(item.balance))],
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
            attribute.attribute("data-testid", "edit-item-" <> testid),
            event.on_click(UserRequestedItemEdit(item.id)),
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
            attribute.attribute("data-testid", "delete-item-" <> testid),
            event.on_click(UserRequestedItemDelete(item)),
          ],
          [html.text("Delete")],
        ),
      ]),
    ],
  )
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
