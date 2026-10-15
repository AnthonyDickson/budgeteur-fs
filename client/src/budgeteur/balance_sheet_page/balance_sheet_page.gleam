import budgeteur/balance_sheet_page/account.{type Account, type AccountLine}
import budgeteur/balance_sheet_page/account_modal
import budgeteur/balance_sheet_page/account_write_request
import budgeteur/balance_sheet_page/balance_sheet.{
  type BalanceSheet, type ClosedAccount, type TransactionsAfterClose,
  TransactionsAfterClose,
}
import budgeteur/balance_sheet_page/balance_sheet_item.{type BalanceSheetItem}
import budgeteur/balance_sheet_page/item_modal
import budgeteur/balance_sheet_page/item_write_request
import budgeteur/shared/api_error.{type ApiError}
import budgeteur/shared/api_route
import budgeteur/shared/date
import budgeteur/shared/effect.{type Effect}
import budgeteur/shared/form_modal
import budgeteur/shared/money
import budgeteur/shared/out_msg.{type OutMsg}
import budgeteur/shared/response
import budgeteur/shared/route
import budgeteur/shared/side.{type Side, Asset, Liability}
import budgeteur/shared/term.{type Term, Current, NonCurrent}
import budgeteur/shared/ui/banner
import budgeteur/shared/ui/button
import budgeteur/shared/ui/card
import budgeteur/shared/ui/row
import gleam/float
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import gleam/time/calendar.{type Date}
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import youid/uuid

/// Horizontal padding for subtotal and total rows. The right side matches a
/// line's padding plus its chevron and gap (4 + 4 + 3), so every amount on the
/// sheet shares one right edge.
const total_row_padding = "pl-4 pr-11"

// Types
// -----

pub type Model {
  Model(
    sheet: SheetState,
    /// The client's local date, once the `GetLocalDate` effect has reported it.
    today: Option(Date),
    // Creates items. A line's other forms are on its details page.
    item_modal: item_modal.Modal,
    // Creates accounts.
    account_modal: account_modal.Modal,
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
  UserRequestedItemCreation(side: Side)
  ItemModalMsg(item_modal.Msg)
  // Account modal messages
  UserRequestedAccountCreation
  AccountModalMsg(account_modal.Msg)
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
      account_modal: account_modal.hidden(),
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

    UserRequestedItemCreation(side:) ->
      run_item_modal(
        model,
        item_modal.CreateRequested(side:, today: model.today),
      )

    ItemModalMsg(inner_msg) -> run_item_modal(model, inner_msg)

    UserRequestedAccountCreation ->
      run_account_modal(
        model,
        account_modal.CreateRequested(today: model.today),
      )

    AccountModalMsg(inner_msg) -> run_account_modal(model, inner_msg)
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

/// The user's items, open or closed; empty unless a sheet has loaded. Closed
/// items count for the duplicate check, as they do on the server.
fn model_items(model: Model) -> List(BalanceSheetItem) {
  case model.sheet {
    Loaded(sheet) -> list.append(sheet.items, sheet.closed_items)
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
    // The page only creates items; they are edited on their details page.
    form_modal.Created(entity: item) | form_modal.Updated(entity: item) -> #(
      model,
      Some(out_msg.success_toast("Created item '" <> item.name <> "'")),
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
    // The form opens in create mode only here.
    form_modal.Put(..) -> effect.none()
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
  // A new account may have an opening balance, which changes the totals the
  // server computes, so the sheet is refetched.
  let #(effects, out_msg) = case outcome {
    form_modal.NoChange -> #(effects, None)
    // The page only creates accounts; they are edited on their details page.
    form_modal.Created(entity: account) | form_modal.Updated(entity: account) -> #(
      list.append(effects, [fetch_sheet()]),
      Some(out_msg.success_toast("Created account '" <> account.name <> "'")),
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
        account_write_request.create_json(payload) |> json.to_string,
        handle_account_response,
      )
      |> effect.with_timeout(form_modal.submit_timeout_ms)
      |> effect.map(AccountModalMsg)
    // The form opens in create mode only here.
    form_modal.Put(..) -> effect.none()
  }
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
      account_modal.view(model.account_modal)
        |> element.map(AccountModalMsg),
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
    closed_lines(sheet.closed_items, sheet.closed_accounts),
  ])
}

/// Lines the user no longer has are left off the sheet. They are listed,
/// collapsed, each linking to its details page, where it is reopened.
/// A closed account with transactions after its close date is flagged, and the
/// list opens so the flag is seen: the close date is likely wrong. See
/// decision 4 in docs/reports.md.
fn closed_lines(
  items: List(BalanceSheetItem),
  accounts: List(ClosedAccount),
) -> Element(Msg) {
  let item_rows =
    list.map(items, fn(item) {
      closed_row(
        testid: "closed-item-" <> uuid.to_string(item.id),
        name: item.name,
        closed_on: item.closed_on,
        after_close: None,
        page: route.ItemDetails(item.id),
      )
    })
  let account_rows =
    list.map(accounts, fn(closed) {
      closed_row(
        testid: "closed-account-" <> uuid.to_string(closed.account.id),
        name: closed.account.name,
        closed_on: closed.account.closed_on,
        after_close: closed.transactions_after_close,
        page: route.AccountDetails(closed.account.id),
      )
    })
  let flagged =
    list.count(accounts, fn(closed) {
      option.is_some(closed.transactions_after_close)
    })

  case list.append(item_rows, account_rows) {
    [] -> element.none()
    rows ->
      html.details(
        [
          attribute.class("mt-8 rounded-lg border border-border bg-surface"),
          attribute.attribute("data-testid", "closed-lines"),
          attribute.open(flagged > 0),
        ],
        [
          html.summary(
            [
              attribute.class(
                "cursor-pointer px-4 py-3 text-sm font-medium text-fg-muted",
              ),
            ],
            [
              html.text("Closed (" <> int.to_string(list.length(rows)) <> ")"),
              case flagged {
                0 -> element.none()
                _ ->
                  html.span(
                    [
                      attribute.class(
                        "ml-2 rounded-full bg-warning-tint px-2 py-0.5 text-xs text-fg",
                      ),
                    ],
                    [
                      html.text(
                        int.to_string(flagged)
                        <> " with transactions after closing",
                      ),
                    ],
                  )
              },
            ],
          ),
          html.ul([attribute.class("divide-y divide-border border-t")], rows),
        ],
      )
  }
}

fn closed_row(
  testid testid: String,
  name name: String,
  closed_on closed_on: Option(Date),
  after_close after_close: Option(TransactionsAfterClose),
  page page: route.Route,
) -> Element(Msg) {
  html.li(
    [
      attribute.class(
        "group relative flex items-center gap-3 px-4 py-3 hover:bg-surface-hover",
      ),
      attribute.attribute("data-testid", testid),
    ],
    [
      html.div([attribute.class("min-w-0 flex-1")], [
        row.open_link(
          testid: "open-" <> testid,
          href: route.to_string(page),
          class: "block max-w-full truncate",
          children: [html.text(name)],
        ),
        html.p(
          [attribute.class(row.selectable_class <> " text-xs text-fg-muted")],
          [
            html.text(case closed_on {
              Some(closed_on) -> "Closed on " <> date.format(closed_on)
              None -> ""
            }),
          ],
        ),
        case after_close {
          Some(TransactionsAfterClose(count:, latest:)) ->
            html.p(
              [
                attribute.class(
                  row.selectable_class <> " text-xs text-fg-muted",
                ),
                attribute.attribute("data-testid", "transactions-after-close"),
              ],
              [
                html.text(
                  int.to_string(count)
                  <> case count {
                    1 -> " transaction"
                    _ -> " transactions"
                  }
                  <> " after the close date, the latest on "
                  <> date.format(latest)
                  <> ". Check the close date.",
                ),
              ],
            )
          None -> element.none()
        },
      ]),
      row.chevron(class: ""),
    ],
  )
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
    card.empty_state(
      [
        attribute.class("mx-auto max-w-md"),
        attribute.attribute("data-testid", "balance-sheet-load-error"),
      ],
      [
        html.h2([attribute.class("text-base font-semibold text-fg")], [
          html.text("Could not load the balance sheet"),
        ]),
        html.p([attribute.class("mt-1 text-sm text-fg-muted")], [
          html.text("Check your connection and try again."),
        ]),
        button.view(
          button.Primary,
          button.Regular,
          [
            attribute.class("mt-4"),
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
  card.empty_state(
    [
      attribute.class("mx-auto max-w-md"),
      attribute.attribute("data-testid", "balance-sheet-loading-state"),
    ],
    [
      html.p([attribute.class("text-sm text-fg-muted")], [
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
        html.h1([attribute.class("text-2xl font-semibold text-fg")], [
          html.text("Balance Sheet"),
        ]),
        html.p([attribute.class("mt-1 text-sm text-fg-muted")], [
          html.text(subtitle),
        ]),
      ]),
      html.div([attribute.class("flex flex-wrap items-center gap-2")], [
        button.view(
          button.Primary,
          button.Regular,
          [
            attribute.attribute("data-testid", "add-asset-button"),
            event.on_click(UserRequestedItemCreation(Asset)),
          ],
          [html.text("Add asset")],
        ),
        button.view(
          button.Primary,
          button.Regular,
          [
            attribute.attribute("data-testid", "add-liability-button"),
            event.on_click(UserRequestedItemCreation(Liability)),
          ],
          [html.text("Add liability")],
        ),
        button.view(
          button.Primary,
          button.Regular,
          [
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
  card.panel(
    [
      attribute.class("px-4 py-3"),
      attribute.attribute("data-testid", testid),
    ],
    [
      html.p(
        [
          attribute.class(
            "text-xs font-medium uppercase tracking-wide text-fg-muted",
          ),
        ],
        [html.text(label)],
      ),
      html.p(
        [
          attribute.class("mt-1 text-xl font-semibold tabular-nums text-fg"),
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
          side: Asset,
          term: Current,
          subtotal: sheet.total_current_assets,
        ),
        line_group(
          sheet,
          "Non-current assets",
          side: Asset,
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
          side: Liability,
          term: Current,
          subtotal: sheet.total_current_liabilities,
        ),
        line_group(
          sheet,
          "Non-current liabilities",
          side: Liability,
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
  card.panel(
    [
      attribute.class("overflow-hidden"),
    ],
    [
      html.h2(
        [
          attribute.class(
            "border-b border-border px-4 py-3 text-base font-semibold text-fg",
          ),
        ],
        [html.text(title)],
      ),
      html.div([], groups),
      html.div(
        [
          attribute.class(
            "flex items-center justify-between border-t border-border bg-surface-hover py-3 "
            <> total_row_padding,
          ),
        ],
        [
          html.span([attribute.class("text-sm font-semibold text-fg")], [
            html.text(total_label),
          ]),
          html.span(
            [
              attribute.class("text-sm font-semibold tabular-nums text-fg"),
              attribute.attribute("data-amount", float.to_string(total)),
            ],
            [html.text(money.format(total))],
          ),
        ],
      ),
    ],
  )
}

/// One side and term's lines: its items, then its accounts, with the subtotal.
fn line_group(
  sheet: BalanceSheet,
  title: String,
  side side: Side,
  term term: Term,
  subtotal subtotal: Float,
) -> Element(Msg) {
  let rows =
    list.append(
      items_with(sheet.items, side:, term:) |> list.map(item_row),
      accounts_with(sheet.accounts, side:, term:) |> list.map(account_row),
    )

  html.div([], [
    html.div(
      [
        attribute.class(
          "flex items-center justify-between bg-surface-hover py-2 "
          <> total_row_padding,
        ),
      ],
      [
        html.h3(
          [
            attribute.class(
              "text-xs font-semibold uppercase tracking-wide text-fg-muted",
            ),
          ],
          [html.text(title)],
        ),
        html.span(
          [
            attribute.class("text-xs font-semibold text-fg-muted"),
            attribute.attribute("data-amount", float.to_string(subtotal)),
          ],
          [html.text(money.format(subtotal))],
        ),
      ],
    ),
    case rows {
      [] ->
        html.p([attribute.class("px-4 py-3 text-sm text-fg-subtle")], [
          html.text("None"),
        ])
      _ -> html.ul([attribute.class("divide-y divide-border")], rows)
    },
  ])
}

fn item_row(item: BalanceSheetItem) -> Element(Msg) {
  let testid = uuid.to_string(item.id)

  line_row(
    testid: "balance-sheet-item-" <> testid,
    name: line_link(
      testid: "open-item-" <> testid,
      page: route.ItemDetails(item.id),
      name: item.name,
    ),
    details: ["As of " <> date.format(item.as_of)],
    amount: item.value,
  )
}

/// An account line is marked with its number, when it has one, and its current
/// balance's as-of date.
fn account_row(line: AccountLine) -> Element(Msg) {
  let as_of = "As of " <> date.format(line.as_of)

  line_row(
    testid: "balance-sheet-account-" <> uuid.to_string(line.account.id),
    name: account_link(line.account),
    details: case line.account.number {
      Some(number) -> [number, as_of]
      None -> [as_of]
    },
    amount: line.balance,
  )
}

/// A line on the sheet. Clicking it, anywhere but its selectable text, opens
/// its details page, where its value or balance is recorded, its details are
/// edited, and it is closed or deleted. The trailing chevron marks the line as
/// one that opens, since touch screens have no hover.
fn line_row(
  testid testid: String,
  name name: Element(Msg),
  details details: List(String),
  amount amount: Float,
) -> Element(Msg) {
  html.li(
    [
      attribute.class(
        "group relative flex items-start gap-3 px-4 py-3 hover:bg-surface-hover",
      ),
      attribute.attribute("data-testid", testid),
    ],
    [
      html.div([attribute.class("min-w-0 flex-1")], [
        name,
        html.p(
          [attribute.class(row.selectable_class <> " text-xs text-fg-subtle")],
          [html.text(string.join(details, " · "))],
        ),
      ]),
      html.span(
        [
          attribute.class(
            row.selectable_class <> " text-right text-sm tabular-nums text-fg",
          ),
          attribute.attribute("data-amount", float.to_string(amount)),
        ],
        [html.text(money.format(amount))],
      ),
      row.chevron(class: "mt-0.5"),
    ],
  )
}

/// The link that opens a line's row: its name, to its details page.
fn line_link(
  testid testid: String,
  page page: route.Route,
  name name: String,
) -> Element(Msg) {
  row.open_link(
    testid:,
    href: route.to_string(page),
    class: "block max-w-full truncate",
    children: [html.text(name)],
  )
}

fn account_link(account: Account) -> Element(Msg) {
  line_link(
    testid: "open-account-" <> uuid.to_string(account.id),
    page: route.AccountDetails(account.id),
    name: account.name,
  )
}

/// Accounts whose balance is unknown are left out of the totals, so the page
/// asks for their balances above the sheet. Each is a tile that opens the
/// account's details page, like a line on the sheet. The callout spans the
/// page, so tiles in a grid keep each name next to its chevron.
fn unknown_balances_callout(accounts: List(Account)) -> Element(Msg) {
  case accounts {
    [] -> element.none()
    _ ->
      banner.view(
        banner.Warning,
        [
          attribute.class("mb-6"),
          attribute.attribute("data-testid", "unknown-balances"),
        ],
        [
          html.h2([attribute.class("text-sm font-semibold")], [
            html.text("Unknown balances"),
          ]),
          html.p([attribute.class("mt-1")], [
            html.text(
              "These accounts have no balance yet, so they are left out of the totals.",
            ),
          ]),
          html.ul(
            [
              attribute.class(
                "mt-3 grid grid-cols-1 gap-2 sm:grid-cols-2 lg:grid-cols-3",
              ),
            ],
            list.map(accounts, fn(account) {
              html.li(
                [
                  attribute.class(
                    "group relative flex items-start gap-3 overflow-hidden rounded-md border "
                    <> "border-warning/60 bg-surface px-3 py-2 hover:bg-surface-hover",
                  ),
                  attribute.attribute(
                    "data-testid",
                    "unknown-balance-" <> uuid.to_string(account.id),
                  ),
                ],
                [
                  html.div([attribute.class("min-w-0 flex-1")], [
                    account_link(account),
                    case account.number {
                      Some(number) ->
                        html.p(
                          [
                            attribute.class(
                              row.selectable_class <> " text-xs text-fg-muted",
                            ),
                          ],
                          [
                            html.text(number),
                          ],
                        )
                      None -> element.none()
                    },
                  ]),
                  row.chevron(class: "mt-0.5"),
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
  card.empty_state(
    [
      attribute.class("mx-auto max-w-md"),
      attribute.attribute("data-testid", testid),
    ],
    [
      html.h2([attribute.class("text-base font-semibold text-fg")], [
        html.text(heading),
      ]),
      html.p([attribute.class("mt-1 text-sm text-fg-muted")], [
        html.text(body),
      ]),
    ],
  )
}

fn items_with(
  items: List(BalanceSheetItem),
  side side: Side,
  term term: Term,
) -> List(BalanceSheetItem) {
  list.filter(items, fn(item) { item.side == side && item.term == term })
}

fn accounts_with(
  accounts: List(AccountLine),
  side side: Side,
  term term: Term,
) -> List(AccountLine) {
  list.filter(accounts, fn(line) {
    line.side == side && line.account.term == term
  })
}
