//// The dashboard: the balance sheet's net worth and working capital, and the
//// income statement for a period. The page composes the two statements'
//// endpoints rather than calling a dashboard aggregate. See docs/dashboard.md.

import budgeteur/dashboard_page/balance_summary.{type BalanceSummary}
import budgeteur/dashboard_page/income_statement.{
  type ExpenseLine, type IncomeLine, type IncomeStatement,
}
import budgeteur/dashboard_page/period.{type Period, type Preset}
import budgeteur/shared/api_error.{type ApiError}
import budgeteur/shared/api_route
import budgeteur/shared/date
import budgeteur/shared/effect.{type Effect}
import budgeteur/shared/money
import budgeteur/shared/out_msg.{type OutMsg}
import budgeteur/shared/response
import budgeteur/shared/route
import budgeteur/shared/tag_ui
import gleam/dynamic/decode
import gleam/float
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/pair
import gleam/time/calendar.{type Date}
import gleam/time/timestamp
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

/// localStorage key for the page's saved preferences.
pub const storage_key = "budgeteur.dashboard"

const primary_button_class = "rounded-md bg-indigo-600 px-4 py-2 text-sm font-medium text-white "
  <> "hover:bg-indigo-500 focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:ring-offset-2"

const card_class = "rounded-lg border border-gray-200 bg-white shadow-sm"

const link_class = "font-medium text-indigo-600 hover:text-indigo-500"

// Types
// -----

pub type Model {
  Model(
    preset: Preset,
    /// The client's local date, once the `GetLocalDate` effect has reported it.
    today: Option(Date),
    /// `Loaded(None)` is a user with no balance sheet yet: the server creates
    /// the sheet on the first item write, so this is not an error.
    balance: Remote(Option(BalanceSummary)),
    statement: Remote(IncomeStatement),
  )
}

/// The lifecycle of one statement fetched from the server.
pub type Remote(a) {
  Loading
  Loaded(a)
  /// The fetch failed; the page offers a retry.
  Failed
}

pub type Msg {
  ClientGotToday(Date)
  ClientRestoredPreset(Option(Preset))
  ClientFetchedBalance(Result(BalanceSummary, ApiError))
  /// The period the request was made for, so a response for a period the
  /// user has since moved away from is ignored.
  ClientFetchedStatement(
    period: Period,
    result: Result(IncomeStatement, ApiError),
  )
  UserSelectedPreset(Preset)
  UserRetriedBalance
  UserRetriedStatement
}

// Effects
// -------

fn fetch_balance() -> Effect(Msg) {
  effect.get(api_route.GetBalanceSheet |> api_route.to_string, fn(result) {
    case result {
      Ok(body) ->
        ClientFetchedBalance(response.decode_success(
          body,
          balance_summary.decoder(),
        ))
      Error(http_error) ->
        ClientFetchedBalance(
          Error(response.http_error_to_api_error(http_error)),
        )
    }
  })
}

fn fetch_statement(period: Period) -> Effect(Msg) {
  api_route.GetIncomeStatement(from: period.from, to: period.to)
  |> api_route.to_string
  |> effect.get(fn(result) {
    case result {
      Ok(body) ->
        ClientFetchedStatement(
          period,
          response.decode_success(body, income_statement.decoder()),
        )
      Error(http_error) ->
        ClientFetchedStatement(
          period,
          Error(response.http_error_to_api_error(http_error)),
        )
    }
  })
}

fn restore_preset() -> Effect(Msg) {
  effect.LoadFromStore(key: storage_key, callback: fn(store_result) {
    case store_result {
      Ok(value) ->
        case json.parse(value, using: preset_decoder()) {
          Ok(preset) -> ClientRestoredPreset(Some(preset))
          Error(_) -> ClientRestoredPreset(None)
        }
      Error(_) -> ClientRestoredPreset(None)
    }
  })
}

fn persist_preset(preset: Preset) -> Effect(Msg) {
  effect.SaveToStore(
    storage_key,
    json.object([#("preset", json.string(period.preset_to_string(preset)))])
      |> json.to_string,
  )
}

fn preset_decoder() -> decode.Decoder(Preset) {
  use value <- decode.field("preset", decode.string)
  case period.parse_preset(value) {
    Ok(preset) -> decode.success(preset)
    Error(Nil) -> decode.failure(period.default_preset, "Preset")
  }
}

// Init
// ----

pub fn init() -> #(Model, Effect(Msg)) {
  #(
    Model(
      preset: period.default_preset,
      today: None,
      balance: Loading,
      statement: Loading,
    ),
    effect.batch([
      restore_preset(),
      effect.GetLocalDate(ClientGotToday),
      fetch_balance(),
    ]),
  )
}

// Update
// ------

/// The period the statement covers, once `today` is known.
pub fn current_period(model: Model) -> Option(Period) {
  option.map(model.today, period.from_preset(model.preset, _))
}

/// Mark the statement as loading and fetch it for the current period. Does
/// nothing until `today` is known.
fn refetch_statement(model: Model) -> #(Model, Effect(Msg)) {
  case current_period(model) {
    Some(period) -> #(
      Model(..model, statement: Loading),
      fetch_statement(period),
    )
    None -> #(model, effect.none())
  }
}

pub fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg), Option(OutMsg)) {
  let #(model, effect) = update_inner(model, msg)
  #(model, effect, None)
}

fn update_inner(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    ClientGotToday(today) ->
      refetch_statement(Model(..model, today: Some(today)))

    ClientRestoredPreset(Some(preset)) ->
      case preset == model.preset {
        True -> #(model, effect.none())
        False -> refetch_statement(Model(..model, preset:))
      }

    ClientRestoredPreset(None) -> #(model, effect.none())

    UserSelectedPreset(preset) -> {
      let #(model, effect) = refetch_statement(Model(..model, preset:))
      #(model, effect.batch([effect, persist_preset(preset)]))
    }

    ClientFetchedBalance(Ok(summary)) -> #(
      Model(..model, balance: Loaded(Some(summary))),
      effect.none(),
    )

    ClientFetchedBalance(Error(error)) ->
      case api_error.is_not_found(error) {
        True -> #(Model(..model, balance: Loaded(None)), effect.none())
        False -> #(
          Model(..model, balance: Failed),
          effect.LogError(api_error.describe(error)),
        )
      }

    ClientFetchedStatement(period:, result:) ->
      case current_period(model) == Some(period) {
        False -> #(model, effect.none())
        True ->
          case result {
            Ok(statement) -> #(
              Model(..model, statement: Loaded(statement)),
              effect.none(),
            )
            Error(error) -> #(
              Model(..model, statement: Failed),
              effect.LogError(api_error.describe(error)),
            )
          }
      }

    UserRetriedBalance -> #(Model(..model, balance: Loading), fetch_balance())

    UserRetriedStatement -> refetch_statement(model)
  }
}

// View
// ----

pub fn view(model: Model) -> Element(Msg) {
  html.div(
    [
      attribute.class("mx-auto max-w-6xl space-y-8 px-4 py-8 sm:px-6"),
      attribute.attribute("data-testid", "dashboard-page"),
    ],
    [
      html.h1([attribute.class("text-2xl font-semibold text-gray-900")], [
        html.text("Dashboard"),
      ]),
      balance_section(model.balance),
      statement_section(model),
    ],
  )
}

fn section_heading(title: String, subtitle: String) -> Element(Msg) {
  html.div([], [
    html.h2([attribute.class("text-lg font-semibold text-gray-900")], [
      html.text(title),
    ]),
    html.p([attribute.class("mt-1 text-sm text-gray-500")], [
      html.text(subtitle),
    ]),
  ])
}

// Balance sheet

fn balance_section(balance: Remote(Option(BalanceSummary))) -> Element(Msg) {
  html.section([attribute.class("space-y-4")], case balance {
    Loading -> [
      section_heading("Where you stand", "Loading balances..."),
    ]
    Loaded(None) -> [
      section_heading("Where you stand", "No balances recorded yet"),
      message_card(
        testid: "dashboard-no-balance-sheet",
        heading: "No balance sheet yet",
        body: [
          html.text("Add what you own and owe on the "),
          page_link(route.BalanceSheet, "Balance Sheet page"),
          html.text(" to see your net worth."),
        ],
      ),
    ]
    Loaded(Some(summary)) -> [
      section_heading(
        "Where you stand",
        "Balances as of "
          <> date.format(
          summary.statement_date
          |> timestamp.to_calendar(calendar.local_offset())
          |> pair.first,
        ),
      ),
      html.div([attribute.class("grid grid-cols-1 gap-4 sm:grid-cols-2")], [
        figure_card("Net worth", summary.net_worth, "dashboard-net-worth"),
        figure_card(
          "Working capital",
          summary.working_capital,
          "dashboard-working-capital",
        ),
      ]),
    ]
    Failed -> [
      section_heading("Where you stand", "Not available"),
      retry_card(
        testid: "dashboard-balance-error",
        heading: "Could not load your balances",
        on_retry: UserRetriedBalance,
      ),
    ]
  })
}

// Income statement

fn statement_section(model: Model) -> Element(Msg) {
  let subtitle = case current_period(model) {
    Some(period) -> date.format(period.from) <> " to " <> date.format(period.to)
    None -> ""
  }

  html.section([attribute.class("space-y-4")], [
    html.div(
      [attribute.class("flex flex-wrap items-end justify-between gap-4")],
      [
        section_heading("Where your money went", subtitle),
        preset_picker(model.preset),
      ],
    ),
    case model.statement {
      Loading ->
        html.p([attribute.class("text-sm text-gray-500")], [
          html.text("Loading income statement..."),
        ])
      Loaded(statement) -> loaded_statement(statement)
      Failed ->
        retry_card(
          testid: "dashboard-statement-error",
          heading: "Could not load the income statement",
          on_retry: UserRetriedStatement,
        )
    },
  ])
}

fn preset_picker(selected: Preset) -> Element(Msg) {
  html.div(
    [
      attribute.class("inline-flex rounded-md shadow-sm"),
      attribute.role("group"),
      attribute.aria_label("Period"),
    ],
    list.index_map(period.presets, fn(preset, index) {
      let is_selected = preset == selected
      let position = case index {
        0 -> "rounded-l-md"
        _ ->
          case index == list.length(period.presets) - 1 {
            True -> "-ml-px rounded-r-md"
            False -> "-ml-px"
          }
      }
      html.button(
        [
          attribute.type_("button"),
          attribute.class(
            "border px-3 py-1.5 text-sm font-medium focus:z-10 focus:outline-none "
            <> "focus:ring-2 focus:ring-indigo-500 "
            <> position
            <> " "
            <> case is_selected {
              True -> "border-indigo-600 bg-indigo-600 text-white"
              False -> "border-gray-300 bg-white text-gray-700 hover:bg-gray-50"
            },
          ),
          attribute.attribute("aria-pressed", case is_selected {
            True -> "true"
            False -> "false"
          }),
          attribute.attribute(
            "data-testid",
            "period-" <> period.preset_to_string(preset),
          ),
          event.on_click(UserSelectedPreset(preset)),
        ],
        [html.text(period.label(preset))],
      )
    }),
  )
}

fn loaded_statement(statement: IncomeStatement) -> Element(Msg) {
  case income_statement.is_empty(statement) {
    True ->
      message_card(
        testid: "dashboard-no-transactions",
        heading: "No transactions in this period",
        body: [
          html.text("Record transactions on the "),
          page_link(route.Transactions, "Transactions page"),
          html.text("."),
        ],
      )
    False ->
      html.div([attribute.class("space-y-4")], [
        html.div([attribute.class("grid grid-cols-1 gap-4 sm:grid-cols-3")], [
          figure_card("Income", statement.income, "dashboard-income"),
          figure_card("Expenses", statement.expenses, "dashboard-expenses"),
          figure_card(
            "Net income",
            statement.net_income,
            "dashboard-net-income",
          ),
        ]),
        untagged_notice(statement.untagged_count),
        html.div([attribute.class("grid grid-cols-1 gap-6 lg:grid-cols-2")], [
          lines_table(
            title: "Income",
            testid: "dashboard-income-lines",
            show_share: False,
            rows: list.map(statement.income_lines, income_row),
          ),
          lines_table(
            title: "Expenses",
            testid: "dashboard-expense-lines",
            show_share: True,
            rows: list.map(statement.expense_lines, expense_row),
          ),
        ]),
      ])
  }
}

fn untagged_notice(untagged_count: Int) -> Element(Msg) {
  case untagged_count {
    0 -> element.none()
    count ->
      html.p(
        [
          attribute.class(
            "rounded-md bg-amber-50 px-4 py-3 text-sm text-amber-800",
          ),
          attribute.attribute("data-testid", "dashboard-untagged-notice"),
        ],
        [
          html.text(case count {
            1 -> "1 transaction in this period has no tag. "
            _ ->
              int.to_string(count)
              <> " transactions in this period have no tag. "
          }),
          page_link(route.Transactions, "Tag them on the Transactions page"),
          html.text("."),
        ],
      )
  }
}

fn lines_table(
  title title: String,
  testid testid: String,
  show_share show_share: Bool,
  rows rows: List(Element(Msg)),
) -> Element(Msg) {
  html.div([attribute.class("overflow-hidden " <> card_class)], [
    html.h3(
      [
        attribute.class(
          "border-b border-gray-200 px-4 py-3 text-base font-semibold text-gray-900",
        ),
      ],
      [html.text(title)],
    ),
    case rows {
      [] ->
        html.p([attribute.class("px-4 py-3 text-sm text-gray-400")], [
          html.text("None"),
        ])
      _ ->
        html.table(
          [
            attribute.class("w-full text-sm"),
            attribute.attribute("data-testid", testid),
          ],
          [
            html.thead([attribute.class("sr-only")], [
              html.tr([], [
                html.th([attribute.scope("col")], [html.text("Tag")]),
                html.th([attribute.scope("col")], [html.text("Amount")]),
                case show_share {
                  True ->
                    html.th([attribute.scope("col")], [html.text("Share")])
                  False -> element.none()
                },
              ]),
            ]),
            html.tbody([attribute.class("divide-y divide-gray-100")], rows),
          ],
        )
    },
  ])
}

fn income_row(line: IncomeLine) -> Element(Msg) {
  line_row(line.name, line.color, line.amount, [])
}

fn expense_row(line: ExpenseLine) -> Element(Msg) {
  line_row(line.name, line.color, line.amount, [
    html.td(
      [attribute.class("w-20 px-4 py-2 text-right tabular-nums text-gray-500")],
      [
        html.text(case line.share {
          Some(share) -> float.to_string(float.to_precision(share, 1)) <> "%"
          None -> ""
        }),
      ],
    ),
  ])
}

fn line_row(
  name: String,
  color: Option(String),
  amount: Float,
  extra_cells: List(Element(Msg)),
) -> Element(Msg) {
  html.tr([attribute.attribute("data-testid", "dashboard-line")], [
    html.td([attribute.class("px-4 py-2")], [
      html.span([attribute.class("flex items-center gap-2 text-gray-700")], [
        case color {
          Some(color) -> tag_ui.color_swatch(color)
          None ->
            html.span(
              [
                attribute.class(
                  "inline-block h-3 w-3 shrink-0 rounded-full border border-dashed border-gray-400",
                ),
              ],
              [],
            )
        },
        html.span([attribute.class("truncate")], [html.text(name)]),
      ]),
    ]),
    html.td(
      [
        attribute.class("px-4 py-2 text-right tabular-nums text-gray-900"),
        attribute.attribute("data-amount", float.to_string(amount)),
      ],
      [html.text(money.format(amount))],
    ),
    ..extra_cells
  ])
}

// Shared pieces

fn figure_card(label: String, amount: Float, testid: String) -> Element(Msg) {
  html.div(
    [
      attribute.class(card_class <> " px-4 py-3"),
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

fn message_card(
  testid testid: String,
  heading heading: String,
  body body: List(Element(Msg)),
) -> Element(Msg) {
  html.div(
    [
      attribute.class(card_class <> " px-6 py-8 text-center"),
      attribute.attribute("data-testid", testid),
    ],
    [
      html.h3([attribute.class("text-base font-semibold text-gray-900")], [
        html.text(heading),
      ]),
      html.p([attribute.class("mt-1 text-sm text-gray-500")], body),
    ],
  )
}

fn retry_card(
  testid testid: String,
  heading heading: String,
  on_retry on_retry: Msg,
) -> Element(Msg) {
  html.div(
    [
      attribute.class(card_class <> " px-6 py-8 text-center"),
      attribute.attribute("data-testid", testid),
    ],
    [
      html.h3([attribute.class("text-base font-semibold text-gray-900")], [
        html.text(heading),
      ]),
      html.p([attribute.class("mt-1 text-sm text-gray-500")], [
        html.text("Check your connection and try again."),
      ]),
      html.button(
        [
          attribute.class("mt-4 " <> primary_button_class),
          event.on_click(on_retry),
        ],
        [html.text("Retry")],
      ),
    ],
  )
}

fn page_link(target: route.Route, label: String) -> Element(Msg) {
  html.a(
    [attribute.href(route.to_string(target)), attribute.class(link_class)],
    [
      html.text(label),
    ],
  )
}
