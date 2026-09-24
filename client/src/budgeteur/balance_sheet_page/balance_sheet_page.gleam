import budgeteur/balance_sheet_page/balance_sheet.{
  type BalanceSheet, BalanceSheet,
}
import budgeteur/balance_sheet_page/balance_sheet_item.{
  type BalanceSheetItem, BalanceSheetItem,
}
import budgeteur/balance_sheet_page/item_kind.{type ItemKind, Asset, Liability}
import budgeteur/balance_sheet_page/term.{type Term, Current, NonCurrent}
import budgeteur/shared/date
import budgeteur/shared/effect.{type Effect}
import budgeteur/shared/money
import budgeteur/shared/out_msg.{type OutMsg}
import gleam/list
import gleam/option.{type Option, None}
import gleam/pair
import gleam/time/calendar
import gleam/time/duration
import gleam/time/timestamp
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import youid/uuid.{type Uuid}

// Types
// -----

pub type Model {
  Model(balance_sheet: BalanceSheet)
}

pub type Msg {
  UserRequestedItemCreation
  UserRequestedItemEdit(Uuid)
  UserRequestedItemDelete(BalanceSheetItem)
}

// Init
// ----

pub fn init() -> #(Model, Effect(Msg)) {
  #(Model(sample_balance_sheet()), effect.none())
}

fn sample_balance_sheet() -> BalanceSheet {
  BalanceSheet(
    statement_date: timestamp.from_calendar(
      calendar.Date(2026, calendar.January, 1),
      calendar.TimeOfDay(0, 0, 0, 0),
      duration.seconds(0),
    ),
    total_assets: 407_000.0,
    total_liabilities: 301_500.0,
    net_worth: 105_500.0,
    total_current_assets: 7000.0,
    total_non_current_assets: 400_000.0,
    total_current_liabilities: 1500.0,
    total_non_current_liabilities: 300_000.0,
    working_capital: 5500.0,
    items: [
      BalanceSheetItem(
        id: uuid.v7(),
        name: "Chequing",
        kind: Asset,
        term: Current,
        balance: 2000.0,
      ),
      BalanceSheetItem(
        id: uuid.v7(),
        name: "Savings",
        kind: Asset,
        term: Current,
        balance: 5000.0,
      ),
      BalanceSheetItem(
        id: uuid.v7(),
        name: "House",
        kind: Asset,
        term: NonCurrent,
        balance: 400_000.0,
      ),
      BalanceSheetItem(
        id: uuid.v7(),
        name: "Credit card",
        kind: Liability,
        term: Current,
        balance: 1500.0,
      ),
      BalanceSheetItem(
        id: uuid.v7(),
        name: "Mortgage",
        kind: Liability,
        term: NonCurrent,
        balance: 300_000.0,
      ),
    ],
  )
}

// Update
// ------

pub fn update(
  model: Model,
  _msg: Msg,
) -> #(Model, Effect(Msg), Option(OutMsg)) {
  #(model, effect.none(), None)
}

// View
// ----

pub fn view(model: Model) -> Element(Msg) {
  let sheet = model.balance_sheet

  html.div(
    [
      attribute.class("mx-auto max-w-6xl px-4 py-8 sm:px-6"),
      attribute.attribute("data-testid", "balance-sheet-page"),
    ],
    [
      page_header(sheet),
      summary_cards(sheet),
      case list.is_empty(sheet.items) {
        True -> empty_state()
        False -> sheet_columns(sheet)
      },
    ],
  )
}

fn page_header(sheet: BalanceSheet) -> Element(Msg) {
  html.div(
    [attribute.class("mb-6 flex flex-wrap items-center justify-between gap-4")],
    [
      html.div([], [
        html.h1([attribute.class("text-2xl font-semibold text-gray-900")], [
          html.text("Balance Sheet"),
        ]),
        html.p([attribute.class("mt-1 text-sm text-gray-500")], [
          html.text(
            "Balances as of "
            <> date.format(
              sheet.statement_date
              |> timestamp.to_calendar(calendar.local_offset())
              |> pair.first,
            ),
          ),
        ]),
      ]),
      html.button(
        [
          attribute.class(
            "rounded-md bg-indigo-600 px-4 py-2 text-sm font-medium text-white "
            <> "hover:bg-indigo-500 focus:outline-none focus:ring-2 "
            <> "focus:ring-indigo-500 focus:ring-offset-2",
          ),
          attribute.attribute("data-testid", "add-item-button"),
          event.on_click(UserRequestedItemCreation),
        ],
        [html.text("Add item")],
      ),
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
  html.div(
    [
      attribute.class(
        "mx-auto max-w-md rounded-lg border border-gray-200 bg-white px-6 py-12 text-center shadow-sm",
      ),
      attribute.attribute("data-testid", "no-items-empty-state"),
    ],
    [
      html.h2([attribute.class("text-base font-semibold text-gray-900")], [
        html.text("Nothing on the balance sheet yet"),
      ]),
      html.p([attribute.class("mt-1 text-sm text-gray-500")], [
        html.text(
          "Track what you own and owe to see your net worth at a glance.",
        ),
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
