//// The dashboard: where the user stands today, and the month to date against
//// the same days of earlier months. One read serves every figure. See
//// docs/dashboard.md.

import budgeteur/dashboard_page/dashboard.{
  type Dashboard, type Figure, type HistoryMonth, type Line, type Month,
  type Position, type Totals,
}
import budgeteur/shared/api_error.{type ApiError}
import budgeteur/shared/api_route
import budgeteur/shared/date
import budgeteur/shared/effect.{type Effect}
import budgeteur/shared/money
import budgeteur/shared/out_msg.{type OutMsg}
import budgeteur/shared/remote.{type Remote, Failed, Loaded, Loading}
import budgeteur/shared/response
import budgeteur/shared/route
import budgeteur/shared/tag_ui
import gleam/dynamic/decode
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/time/calendar.{type Date}
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

const primary_button_class = "rounded-md bg-indigo-600 px-4 py-2 text-sm font-medium text-white "
  <> "hover:bg-indigo-500 focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:ring-offset-2"

const card_class = "rounded-lg border border-gray-200 bg-white shadow-sm"

const link_class = "font-medium text-indigo-600 hover:text-indigo-500"

// Types
// -----

pub type Model {
  Model(
    /// The client's local date, once the `GetLocalDate` effect has reported it.
    today: Option(Date),
    dashboard: Remote(Dashboard),
    /// How many transactions are waiting for a tag, whatever the period, so the
    /// note matches the quick tagging page. See decision 7 in
    /// docs/quick-tagging.md.
    waiting: Remote(Int),
  )
}

pub type Msg {
  ClientGotToday(Date)
  ClientFetchedDashboard(Result(Dashboard, ApiError))
  ClientFetchedWaiting(Result(Int, ApiError))
  UserRetried
}

/// Which way a figure improves: up for income, net income, and the savings
/// rate; down for expenses. See decision 17 in docs/dashboard.md.
pub type Better {
  Higher
  Lower
}

// Effects
// -------

fn fetch_dashboard(today: Date) -> Effect(Msg) {
  api_route.GetDashboard(today:)
  |> api_route.to_string
  |> effect.get(fn(result) {
    case result {
      Ok(body) ->
        ClientFetchedDashboard(response.decode_success(
          body,
          dashboard.decoder(),
        ))
      Error(http_error) ->
        ClientFetchedDashboard(
          Error(response.http_error_to_api_error(http_error)),
        )
    }
  })
}

/// Reads only the quick tagging queue's total, with the page's own decoder.
fn fetch_waiting() -> Effect(Msg) {
  let decoder = {
    use total <- decode.field("total", decode.int)
    decode.success(total)
  }

  effect.get(api_route.GetQuickTagQueue |> api_route.to_string, fn(result) {
    case result {
      Ok(body) -> ClientFetchedWaiting(response.decode_success(body, decoder))
      Error(http_error) ->
        ClientFetchedWaiting(
          Error(response.http_error_to_api_error(http_error)),
        )
    }
  })
}

// Init
// ----

pub fn init() -> #(Model, Effect(Msg)) {
  #(
    Model(today: None, dashboard: Loading, waiting: Loading),
    effect.batch([effect.GetLocalDate(ClientGotToday), fetch_waiting()]),
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
    ClientGotToday(today) -> #(
      Model(..model, today: Some(today), dashboard: Loading),
      fetch_dashboard(today),
    )

    ClientFetchedDashboard(Ok(dashboard)) -> #(
      Model(..model, dashboard: Loaded(dashboard)),
      effect.none(),
    )

    ClientFetchedDashboard(Error(error)) -> #(
      Model(..model, dashboard: Failed),
      effect.LogError(api_error.describe(error)),
    )

    ClientFetchedWaiting(Ok(count)) -> #(
      Model(..model, waiting: Loaded(count)),
      effect.none(),
    )

    // The note is a footnote, so a failure hides it rather than offering a
    // retry.
    ClientFetchedWaiting(Error(error)) -> #(
      Model(..model, waiting: Failed),
      effect.LogError(api_error.describe(error)),
    )

    UserRetried ->
      case model.today {
        Some(today) -> #(
          Model(..model, dashboard: Loading),
          fetch_dashboard(today),
        )
        None -> #(model, effect.none())
      }
  }
}

/// Whether a change is an improvement, which the page shows in green. A zero
/// change is not.
pub fn is_improvement(change: Float, better: Better) -> Bool {
  case better {
    Higher -> change >. 0.0
    Lower -> change <. 0.0
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
      ..case model.dashboard {
        Loading -> [
          html.p([attribute.class("text-sm text-gray-500")], [
            html.text("Loading the dashboard..."),
          ]),
        ]
        Failed -> [
          retry_card(
            testid: "dashboard-error",
            heading: "Could not load the dashboard",
            on_retry: UserRetried,
          ),
        ]
        Loaded(dashboard) -> [
          position_section(dashboard.position),
          month_section(dashboard.month, model.waiting),
          history_section(dashboard.history, dashboard.totals),
        ]
      }
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

// Position

fn position_section(position: Position) -> Element(Msg) {
  html.section([attribute.class("space-y-4")], case position.is_empty {
    True -> [
      section_heading("Where you stand", "No balances recorded yet"),
      message_card(
        testid: "dashboard-empty-balance-sheet",
        heading: "Nothing on the balance sheet yet",
        body: [
          html.text("Add what you own and owe on the "),
          page_link(route.BalanceSheet, "Balance Sheet page"),
          html.text(" to see your net worth."),
        ],
      ),
    ]
    False -> [
      section_heading("Where you stand", case position.oldest_as_of {
        Some(as_of) -> "Oldest balance as of " <> date.format(as_of)
        None -> "No balances known yet"
      }),
      html.div([attribute.class("grid grid-cols-1 gap-4 sm:grid-cols-3")], [
        money_card("Net worth", position.net_worth, "dashboard-net-worth"),
        money_card(
          "Working capital",
          position.working_capital,
          "dashboard-working-capital",
        ),
        card("Runway", "dashboard-runway", [
          html.p([attribute.class(big_figure_class)], [
            html.text(case position.runway {
              Some(runway) -> float.to_string(runway) <> " months"
              None -> "Not available"
            }),
          ]),
          html.p([attribute.class("mt-1 text-xs text-gray-500")], [
            html.text("Working capital over average monthly expenses"),
          ]),
        ]),
      ]),
    ]
  })
}

// Month

fn month_section(month: Month, waiting: Remote(Int)) -> Element(Msg) {
  let compared = month.baseline_month_count > 0

  html.section(
    [
      attribute.class("space-y-4"),
      attribute.attribute("data-testid", "dashboard-month"),
    ],
    [
      section_heading(
        month.label <> " to date",
        date.format(month.from)
          <> " to "
          <> date.format(month.to)
          <> case month.baseline_month_count {
          0 -> ""
          1 -> ", against the same days of last month"
          count ->
            ", against the same days of the last "
            <> int.to_string(count)
            <> " months"
        },
      ),
      html.p(
        [
          attribute.class("text-sm text-gray-500"),
          attribute.attribute("data-testid", "dashboard-freshness"),
        ],
        [
          html.text(case month.latest_transaction {
            Some(latest) -> "Latest transaction " <> date.format(latest)
            None -> "No transactions yet this month"
          }),
          html.text(case compared {
            True -> ""
            False ->
              ". Typical figures appear after your first complete month of transactions."
          }),
        ],
      ),
      html.div([attribute.class("grid grid-cols-1 gap-4 sm:grid-cols-4")], [
        figure_card("Income", month.income, Higher, "dashboard-income"),
        figure_card("Expenses", month.expenses, Lower, "dashboard-expenses"),
        figure_card(
          "Net income",
          month.net_income,
          Higher,
          "dashboard-net-income",
        ),
        savings_rate_card(month),
      ]),
      html.p([attribute.class("text-sm text-gray-500")], [
        html.text(
          "The savings rate is on take-home pay: contributions taken out of pay, such as KiwiSaver, are not in it.",
        ),
      ]),
      case month.income_lines, month.expense_lines {
        [], [] ->
          message_card(
            testid: "dashboard-no-transactions",
            heading: "No transactions this month",
            body: [
              html.text("Record transactions on the "),
              page_link(route.Transactions, "Transactions page"),
              html.text("."),
            ],
          )
        income_lines, expense_lines ->
          html.div([attribute.class("space-y-6")], [
            lines_table(
              title: "Income",
              testid: "dashboard-income-lines",
              lines: income_lines,
              better: Higher,
              compared:,
            ),
            lines_table(
              title: "Expenses",
              testid: "dashboard-expense-lines",
              lines: expense_lines,
              better: Lower,
              compared:,
            ),
          ])
      },
      untagged_note(waiting),
    ],
  )
}

const big_figure_class = "mt-1 text-xl font-semibold tabular-nums text-gray-900"

/// A total with its typical amount and change below it, once there is a
/// baseline.
fn figure_card(
  label: String,
  figure: Figure,
  better: Better,
  testid: String,
) -> Element(Msg) {
  card(label, testid, [
    html.p(
      [
        attribute.class(big_figure_class),
        attribute.attribute("data-amount", float.to_string(figure.amount)),
      ],
      [html.text(money.format(figure.amount))],
    ),
    case figure.baseline, figure.change {
      Some(baseline), Some(change) ->
        html.p([attribute.class("mt-1 text-sm text-gray-500")], [
          html.text("Typical " <> money.format(baseline) <> " · "),
          change_text(
            signed_money(change) <> percent_suffix(figure.change_percent),
            change,
            better,
          ),
        ])
      _, _ -> element.none()
    },
  ])
}

fn savings_rate_card(month: Month) -> Element(Msg) {
  card("Savings rate", "dashboard-savings-rate", [
    html.p([attribute.class(big_figure_class)], [
      html.text(case month.savings_rate {
        Some(rate) -> percent(rate)
        None -> "No income"
      }),
    ]),
    case month.savings_rate_baseline {
      Some(baseline) ->
        html.p([attribute.class("mt-1 text-sm text-gray-500")], [
          html.text("Typical " <> percent(baseline)),
          case month.savings_rate_change {
            Some(change) ->
              element.fragment([
                html.text(" · "),
                change_text(signed_points(change), change, Higher),
              ])
            None -> element.none()
          },
        ])
      None -> element.none()
    },
  ])
}

fn lines_table(
  title title: String,
  testid testid: String,
  lines lines: List(Line),
  better better: Better,
  compared compared: Bool,
) -> Element(Msg) {
  let header_class =
    "px-4 py-2 text-right text-xs font-medium uppercase tracking-wide text-gray-500"

  html.div([attribute.class("overflow-hidden " <> card_class)], [
    html.h3(
      [
        attribute.class(
          "border-b border-gray-200 px-4 py-3 text-base font-semibold text-gray-900",
        ),
      ],
      [html.text(title)],
    ),
    case lines {
      [] ->
        html.p([attribute.class("px-4 py-3 text-sm text-gray-400")], [
          html.text("None"),
        ])
      _ ->
        html.table(
          [
            attribute.class("w-full table-fixed text-sm"),
            attribute.attribute("data-testid", testid),
          ],
          [
            html.thead([attribute.class("border-b border-gray-100")], [
              html.tr([], [
                html.th(
                  [
                    attribute.scope("col"),
                    attribute.class(
                      "px-4 py-2 text-left text-xs font-medium uppercase tracking-wide text-gray-500",
                    ),
                  ],
                  [html.text("Tag")],
                ),
                html.th(
                  [attribute.scope("col"), attribute.class(header_class)],
                  [
                    html.text("This month"),
                  ],
                ),
                ..case compared {
                  True -> [
                    html.th(
                      [attribute.scope("col"), attribute.class(header_class)],
                      [html.text("Typical")],
                    ),
                    html.th(
                      [attribute.scope("col"), attribute.class(header_class)],
                      [html.text("Change")],
                    ),
                  ]
                  False -> []
                }
              ]),
            ]),
            html.tbody(
              [attribute.class("divide-y divide-gray-100")],
              list.map(lines, line_row(_, better, compared)),
            ),
          ],
        )
    },
  ])
}

fn line_row(line: Line, better: Better, compared: Bool) -> Element(Msg) {
  let figure = line.figure
  let number_class = "px-4 py-2 text-right tabular-nums"

  html.tr([attribute.attribute("data-testid", "dashboard-line")], [
    html.td([attribute.class("px-4 py-2")], [
      html.span([attribute.class("flex items-center gap-2 text-gray-700")], [
        case line.color {
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
        html.span([attribute.class("truncate")], [html.text(line.name)]),
      ]),
      share_bar(line.share),
    ]),
    html.td(
      [
        attribute.class(number_class <> " text-gray-900"),
        attribute.attribute("data-amount", float.to_string(figure.amount)),
      ],
      [html.text(money.format(figure.amount))],
    ),
    ..case compared {
      True -> [
        html.td([attribute.class(number_class <> " text-gray-500")], [
          html.text(case figure.baseline {
            Some(baseline) -> money.format(baseline)
            None -> ""
          }),
        ]),
        html.td([attribute.class(number_class)], [
          case figure.change {
            Some(change) ->
              change_text(
                signed_money(change) <> percent_suffix(figure.change_percent),
                change,
                better,
              )
            None -> element.none()
          },
        ]),
      ]
      False -> []
    }
  ])
}

/// A thin strip under an expense line, as wide as its share of the month's
/// expenses, with the percentage on hover. Negative shares draw nothing. See decision 17 in
/// docs/dashboard.md.
fn share_bar(share: Option(Float)) -> Element(Msg) {
  case share {
    Some(share) if share >. 0.0 ->
      html.div(
        [
          attribute.class("mt-1 h-1 rounded-full bg-gray-100"),
          attribute.title(percent(share) <> " of expenses"),
          attribute.attribute("data-testid", "dashboard-share-bar"),
        ],
        [
          html.div(
            [
              attribute.class("h-1 rounded-full bg-indigo-400"),
              attribute.style(
                "width",
                float.to_string(float.min(share, 100.0)) <> "%",
              ),
            ],
            [],
          ),
        ],
      )
    _ -> element.none()
  }
}

/// A change, green when it is an improvement and uncoloured otherwise. The
/// sign carries the direction, so colour is not the only cue.
fn change_text(text: String, change: Float, better: Better) -> Element(Msg) {
  html.span(
    [
      attribute.class(case is_improvement(change, better) {
        True -> "font-medium text-green-700"
        False -> "text-gray-700"
      }),
      attribute.attribute("data-testid", "dashboard-change"),
    ],
    [html.text(text)],
  )
}

fn signed_money(amount: Float) -> String {
  case amount >. 0.0 {
    True -> "+" <> money.format(amount)
    False -> money.format(amount)
  }
}

fn percent_suffix(change_percent: Option(Float)) -> String {
  case change_percent {
    Some(change_percent) ->
      " ("
      <> case change_percent >. 0.0 {
        True -> "+"
        False -> ""
      }
      <> percent(change_percent)
      <> ")"
    None -> ""
  }
}

fn signed_points(points: Float) -> String {
  case points >. 0.0 {
    True -> "+"
    False -> ""
  }
  <> float.to_string(float.to_precision(points, 1))
  <> " pts"
}

fn percent(value: Float) -> String {
  float.to_string(float.to_precision(value, 1)) <> "%"
}

/// A footnote to the untagged lines rather than a callout: leaving some
/// transactions untagged is normal. Counts every transaction waiting for a tag,
/// whatever the period, so it matches the quick tagging page it links to.
fn untagged_note(waiting: Remote(Int)) -> Element(Msg) {
  case waiting {
    Loaded(0) | Loading | Failed -> element.none()
    Loaded(count) ->
      html.p(
        [
          attribute.class("text-sm text-gray-500"),
          attribute.attribute("data-testid", "dashboard-untagged-note"),
        ],
        [
          html.text(case count {
            1 -> "1 transaction is waiting for a tag. "
            _ -> int.to_string(count) <> " transactions are waiting for a tag. "
          }),
          page_link(route.QuickTagging, "Quick tag them"),
          html.text("."),
        ],
      )
  }
}

// History

/// The history section's heading: how many complete months it shows, and the
/// month to date.
pub fn history_heading(history: List(HistoryMonth)) -> String {
  let to_date = case list.find(history, fn(month) { !month.complete }) {
    Ok(month) -> month.label <> " to date"
    Error(Nil) -> "this month to date"
  }

  case list.count(history, fn(month) { month.complete }) {
    0 -> to_date
    count -> months_label(count) <> " and " <> to_date
  }
}

/// "Last month" or "Last 7 months".
fn months_label(count: Int) -> String {
  case count {
    1 -> "Last month"
    count -> "Last " <> int.to_string(count) <> " months"
  }
}

fn history_section(
  history: List(HistoryMonth),
  totals: Option(Totals),
) -> Element(Msg) {
  html.section(
    [
      attribute.class("space-y-4"),
      attribute.attribute("data-testid", "dashboard-history"),
    ],
    [
      section_heading(
        history_heading(history),
        "Totals cover the complete months since your first transaction",
      ),
      totals_cards(totals),
      html.div([attribute.class("grid grid-cols-1 gap-6 lg:grid-cols-2")], [
        history_table(
          title: "Cash flow",
          testid: "dashboard-cash-flow",
          columns: ["Income", "Expenses", "Net income"],
          history:,
          cells: fn(month) {
            [
              Some(month.income),
              Some(month.expenses),
              Some(month.net_income),
            ]
          },
        ),
        history_table(
          title: "Net worth",
          testid: "dashboard-net-worth-history",
          columns: ["Net worth", "Working capital"],
          history:,
          cells: fn(month) { [month.net_worth, month.working_capital] },
        ),
      ]),
    ],
  )
}

fn totals_cards(totals: Option(Totals)) -> Element(Msg) {
  case totals {
    None ->
      html.p(
        [
          attribute.class("text-sm text-gray-500"),
          attribute.attribute("data-testid", "dashboard-no-totals"),
        ],
        [
          html.text(
            "Totals appear after your first complete month of transactions.",
          ),
        ],
      )
    Some(totals) ->
      html.div([attribute.class("space-y-2")], [
        html.h3([attribute.class("text-base font-semibold text-gray-900")], [
          html.text(months_label(totals.month_count)),
        ]),
        html.div([attribute.class("grid grid-cols-1 gap-4 sm:grid-cols-4")], [
          total_card(
            "Income",
            totals.income,
            totals.average_income,
            "dashboard-total-income",
          ),
          total_card(
            "Expenses",
            totals.expenses,
            totals.average_expenses,
            "dashboard-total-expenses",
          ),
          total_card(
            "Net income",
            totals.net_income,
            totals.average_net_income,
            "dashboard-total-net-income",
          ),
          card("Savings rate", "dashboard-total-savings-rate", [
            html.p([attribute.class(big_figure_class)], [
              html.text(case totals.savings_rate {
                Some(rate) -> percent(rate)
                None -> "No income"
              }),
            ]),
          ]),
        ]),
      ])
  }
}

/// A total over the baseline months with its monthly average below it.
fn total_card(
  label: String,
  total: Float,
  average: Float,
  testid: String,
) -> Element(Msg) {
  card(label, testid, [
    html.p(
      [
        attribute.class(big_figure_class),
        attribute.attribute("data-amount", float.to_string(total)),
      ],
      [html.text(money.format(total))],
    ),
    html.p([attribute.class("mt-1 text-sm text-gray-500")], [
      html.text(money.format(average) <> " a month"),
    ]),
  ])
}

/// The history's months as rows, oldest first, with the month to date marked.
/// An amount the server does not know shows as a dash.
fn history_table(
  title title: String,
  testid testid: String,
  columns columns: List(String),
  history history: List(HistoryMonth),
  cells cells: fn(HistoryMonth) -> List(Option(Float)),
) -> Element(Msg) {
  let header_class =
    "px-4 py-2 text-right text-xs font-medium uppercase tracking-wide text-gray-500"
  let number_class = "px-4 py-2 text-right tabular-nums text-gray-900"

  html.div([attribute.class("overflow-hidden " <> card_class)], [
    html.h3(
      [
        attribute.class(
          "border-b border-gray-200 px-4 py-3 text-base font-semibold text-gray-900",
        ),
      ],
      [html.text(title)],
    ),
    html.table(
      [
        attribute.class("w-full text-sm"),
        attribute.attribute("data-testid", testid),
      ],
      [
        html.thead([attribute.class("border-b border-gray-100")], [
          html.tr([], [
            html.th(
              [
                attribute.scope("col"),
                attribute.class(
                  "px-4 py-2 text-left text-xs font-medium uppercase tracking-wide text-gray-500",
                ),
              ],
              [html.text("Month")],
            ),
            ..list.map(columns, fn(column) {
              html.th([attribute.scope("col"), attribute.class(header_class)], [
                html.text(column),
              ])
            })
          ]),
        ]),
        html.tbody(
          [attribute.class("divide-y divide-gray-100")],
          list.map(history, fn(month) {
            html.tr(
              [attribute.attribute("data-testid", "dashboard-month-row")],
              [
                html.td([attribute.class("px-4 py-2 text-gray-700")], [
                  html.text(case month.complete {
                    True -> month.label
                    False -> month.label <> " to date"
                  }),
                ]),
                ..list.map(cells(month), fn(cell) {
                  case cell {
                    Some(amount) ->
                      html.td(
                        [
                          attribute.class(number_class),
                          attribute.attribute(
                            "data-amount",
                            float.to_string(amount),
                          ),
                        ],
                        [html.text(money.format(amount))],
                      )
                    None ->
                      html.td([attribute.class(number_class)], [html.text("—")])
                  }
                })
              ],
            )
          }),
        ),
      ],
    ),
  ])
}

// Shared pieces

fn card(
  label: String,
  testid: String,
  children: List(Element(Msg)),
) -> Element(Msg) {
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
      ..children
    ],
  )
}

fn money_card(label: String, amount: Float, testid: String) -> Element(Msg) {
  card(label, testid, [
    html.p(
      [
        attribute.class(big_figure_class),
        attribute.attribute("data-amount", float.to_string(amount)),
      ],
      [html.text(money.format(amount))],
    ),
  ])
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
    [html.text(label)],
  )
}
