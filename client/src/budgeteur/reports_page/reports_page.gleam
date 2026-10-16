//// The reports page: one report at a time for a frequency, stepping back and
//// forward between periods. It opens on the latest complete period. See
//// decision 8 in docs/reports.md.

import budgeteur/reports_page/report.{
  type Frequency, type Line, type Report, type Sheet, type SheetLine,
}
import budgeteur/shared/api_error.{type ApiError}
import budgeteur/shared/api_route
import budgeteur/shared/date
import budgeteur/shared/effect.{type Effect}
import budgeteur/shared/icon
import budgeteur/shared/money
import budgeteur/shared/out_msg.{type OutMsg}
import budgeteur/shared/remote.{type Remote, Failed, Loaded, Loading}
import budgeteur/shared/response
import budgeteur/shared/side
import budgeteur/shared/term
import budgeteur/shared/ui/banner
import budgeteur/shared/ui/button
import budgeteur/shared/ui/card
import budgeteur/shared/ui/popover
import budgeteur/shared/ui/stat
import budgeteur/shared/ui/swatch
import gleam/dynamic/decode
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

/// localStorage key for the page's saved preferences.
pub const storage_key = "budgeteur.reports"

// Types
// -----

pub type Model {
  Model(
    frequency: Frequency,
    /// The client's local date, once the `GetLocalDate` effect has reported it.
    today: Option(Date),
    /// A date in the period to show, or None for the latest complete period.
    requested: Option(Date),
    report: Remote(Report),
  )
}

pub type Msg {
  ClientGotToday(Date)
  ClientRestoredFrequency(Option(Frequency))
  /// The request the response is for, so a response for a period the user has
  /// since moved away from is ignored.
  ClientFetchedReport(
    frequency: Frequency,
    requested: Option(Date),
    result: Result(Report, ApiError),
  )
  UserSelectedFrequency(Frequency)
  UserSteppedBack
  UserSteppedForward
  UserRetried
}

// Effects
// -------

fn fetch_report(
  frequency: Frequency,
  today: Date,
  requested: Option(Date),
) -> Effect(Msg) {
  api_route.GetReport(
    frequency: report.frequency_to_string(frequency),
    today:,
    date: requested,
  )
  |> api_route.to_string
  |> effect.get(fn(result) {
    case result {
      Ok(body) ->
        ClientFetchedReport(
          frequency,
          requested,
          response.decode_success(body, report.decoder()),
        )
      Error(http_error) ->
        ClientFetchedReport(
          frequency,
          requested,
          Error(response.http_error_to_api_error(http_error)),
        )
    }
  })
}

fn restore_frequency() -> Effect(Msg) {
  effect.LoadFromStore(key: storage_key, callback: fn(store_result) {
    let decoder = {
      use value <- decode.field("frequency", decode.string)
      case report.parse_frequency(value) {
        Ok(frequency) -> decode.success(frequency)
        Error(Nil) -> decode.failure(report.default_frequency, "Frequency")
      }
    }
    case store_result {
      Ok(value) ->
        ClientRestoredFrequency(option.from_result(json.parse(value, decoder)))
      Error(_) -> ClientRestoredFrequency(None)
    }
  })
}

fn persist_frequency(frequency: Frequency) -> Effect(Msg) {
  effect.SaveToStore(
    storage_key,
    json.object([
      #("frequency", json.string(report.frequency_to_string(frequency))),
    ])
      |> json.to_string,
  )
}

// Init
// ----

pub fn init() -> #(Model, Effect(Msg)) {
  #(
    Model(
      frequency: report.default_frequency,
      today: None,
      requested: None,
      report: Loading,
    ),
    effect.batch([restore_frequency(), effect.GetLocalDate(ClientGotToday)]),
  )
}

// Update
// ------

pub fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg), Option(OutMsg)) {
  let #(model, effect) = update_inner(model, msg)
  #(model, effect, None)
}

/// Mark the report as loading and fetch it for the model's request. Does
/// nothing until `today` is known.
fn refetch(model: Model) -> #(Model, Effect(Msg)) {
  case model.today {
    Some(today) -> #(
      Model(..model, report: Loading),
      fetch_report(model.frequency, today, model.requested),
    )
    None -> #(model, effect.none())
  }
}

fn update_inner(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    ClientGotToday(today) -> refetch(Model(..model, today: Some(today)))

    ClientRestoredFrequency(Some(frequency)) ->
      case frequency == model.frequency {
        True -> #(model, effect.none())
        False -> refetch(Model(..model, frequency:, requested: None))
      }
    ClientRestoredFrequency(None) -> #(model, effect.none())

    UserSelectedFrequency(frequency) -> {
      let #(model, effect) =
        refetch(Model(..model, frequency:, requested: None))
      #(model, effect.batch([effect, persist_frequency(frequency)]))
    }

    // The server aligns any date to its period, so a step asks for the day
    // either side of the report shown.
    UserSteppedBack ->
      case model.report {
        Loaded(shown) if shown.has_previous ->
          refetch(
            Model(..model, requested: Some(date.add_days(shown.from, -1))),
          )
        _ -> #(model, effect.none())
      }
    UserSteppedForward ->
      case model.report {
        Loaded(shown) if shown.has_next ->
          refetch(Model(..model, requested: Some(date.add_days(shown.to, 1))))
        _ -> #(model, effect.none())
      }

    UserRetried -> refetch(model)

    ClientFetchedReport(frequency:, requested:, result:) ->
      case frequency == model.frequency && requested == model.requested {
        False -> #(model, effect.none())
        True ->
          case result {
            Ok(shown) -> #(Model(..model, report: Loaded(shown)), effect.none())
            Error(error) -> #(
              Model(..model, report: Failed),
              effect.LogError(api_error.describe(error)),
            )
          }
      }
  }
}

// View
// ----

pub fn view(model: Model) -> Element(Msg) {
  let shown = case model.report {
    Loaded(shown) -> Some(shown)
    Loading | Failed -> None
  }

  html.div(
    [
      attribute.class("mx-auto max-w-6xl space-y-8 px-4 py-8 sm:px-6"),
      attribute.attribute("data-testid", "reports-page"),
    ],
    [
      html.div(
        [
          attribute.class(
            "flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between",
          ),
        ],
        [
          html.h1([attribute.class("text-2xl font-semibold text-fg")], [
            html.text("Reports"),
          ]),
          frequency_picker(model.frequency),
        ],
      ),
      period_bar(shown),
      case model.report {
        Loading ->
          html.p(
            [
              attribute.class("text-sm text-fg-muted"),
              attribute.attribute("data-testid", "report-loading"),
            ],
            [html.text("Loading...")],
          )
        Failed -> failed_state()
        Loaded(shown) -> loaded_report(shown)
      },
    ],
  )
}

fn frequency_picker(selected: Frequency) -> Element(Msg) {
  html.label([attribute.class("flex items-center gap-2 text-sm")], [
    html.span([attribute.class("text-fg-muted")], [html.text("Frequency")]),
    html.select(
      [
        attribute.class(
          // 16px but with a mouse on a wide screen, so Safari on iOS does not
          // zoom on focus; see `input.text`.
          "rounded-md border border-border-input bg-surface px-3 py-1.5 text-base text-fg sm:pointer-fine:text-sm",
        ),
        attribute.attribute("data-testid", "report-frequency"),
        event.on_change(fn(value) {
          case report.parse_frequency(value) {
            Ok(frequency) -> UserSelectedFrequency(frequency)
            Error(Nil) -> UserSelectedFrequency(selected)
          }
        }),
      ],
      list.map(report.frequencies, fn(frequency) {
        html.option(
          [
            attribute.value(report.frequency_to_string(frequency)),
            attribute.selected(frequency == selected),
          ],
          report.frequency_label(frequency),
        )
      }),
    ),
  ])
}

/// The period shown, with the controls that step between periods.
fn period_bar(shown: Option(Report)) -> Element(Msg) {
  let #(has_previous, has_next) = case shown {
    Some(shown) -> #(shown.has_previous, shown.has_next)
    None -> #(False, False)
  }

  html.div([attribute.class("flex items-center justify-between gap-4")], [
    button.view(
      button.Secondary,
      button.Small,
      [
        attribute.disabled(!has_previous),
        attribute.attribute("data-testid", "report-previous"),
        event.on_click(UserSteppedBack),
      ],
      [icon.chevron_left(class: ""), html.text("Previous")],
    ),
    html.div([attribute.class("text-center")], case shown {
      Some(shown) -> [
        html.h2(
          [
            attribute.class("text-lg font-semibold text-fg"),
            attribute.attribute("data-testid", "report-label"),
          ],
          [html.text(shown.label)],
        ),
        html.p([attribute.class("text-sm text-fg-muted")], [
          html.text(case shown.complete {
            True -> date.format(shown.from) <> " to " <> date.format(shown.to)
            False ->
              "To date: "
              <> date.format(shown.from)
              <> " to "
              <> date.format(shown.closing_date)
          }),
        ]),
      ]
      None -> []
    }),
    button.view(
      button.Secondary,
      button.Small,
      [
        attribute.disabled(!has_next),
        attribute.attribute("data-testid", "report-next"),
        event.on_click(UserSteppedForward),
      ],
      [html.text("Next"), icon.chevron_right(class: "")],
    ),
  ])
}

/// The balance sheet section, with the position before and after the period
/// and the closing sheet, then the income statement section.
fn loaded_report(shown: Report) -> Element(Msg) {
  html.div([attribute.class("space-y-8")], [
    html.section([attribute.class("space-y-4")], [
      html.div([], [
        section_heading("Balance sheet"),
        html.p([attribute.class("text-sm text-fg-muted")], [
          html.text(
            "Opening as of "
            <> date.format(date.add_days(shown.from, -1))
            <> ", closing as of "
            <> date.format(shown.closing_date),
          ),
        ]),
      ]),
      card_row([
        figure_card(
          "Opening net worth",
          Some(shown.opening_net_worth),
          "report-opening-net-worth",
        ),
        figure_card(
          "Closing net worth",
          Some(shown.closing.net_worth),
          "report-closing-net-worth",
        ),
        figure_card(
          "Change in net worth",
          shown.change_in_net_worth,
          "report-change-in-net-worth",
        ),
        card(
          "Other changes",
          popover.help(
            id: "report-other-changes-help",
            about: "Other changes",
            paragraphs: [
              "Other changes are what net income does not explain: revaluations, money that never passes through a tracked account (such as employer KiwiSaver contributions), and missing transactions.",
            ],
          ),
          "report-other-changes",
          money_figure(shown.other_changes),
        ),
      ]),
      card_row([
        figure_card(
          "Opening working capital",
          Some(shown.opening_working_capital),
          "report-opening-working-capital",
        ),
        figure_card(
          "Closing working capital",
          Some(shown.closing.working_capital),
          "report-closing-working-capital",
        ),
        figure_card(
          "Change in working capital",
          shown.change_in_working_capital,
          "report-change-in-working-capital",
        ),
      ]),
      transactions_after_close_note(shown.closed_accounts_with_transactions),
      sheet_table(shown.closing),
    ]),
    html.section([attribute.class("space-y-4")], [
      section_heading("Income statement"),
      card_row([
        figure_card("Income", Some(shown.income), "report-income"),
        figure_card("Expenses", Some(shown.expenses), "report-expenses"),
        figure_card("Net income", Some(shown.net_income), "report-net-income"),
        card(
          "Savings rate",
          popover.help(
            id: "report-savings-rate-help",
            about: "Savings rate",
            paragraphs: [
              "The savings rate is on take-home pay: contributions taken out of pay, such as KiwiSaver, are not in it.",
            ],
          ),
          "report-savings-rate",
          percent_figure(shown.savings_rate),
        ),
      ]),
      html.div([attribute.class("grid grid-cols-1 gap-6 lg:grid-cols-2")], [
        lines_table("Income", "report-income-lines", shown.income_lines),
        lines_table("Expenses", "report-expense-lines", shown.expense_lines),
      ]),
    ]),
  ])
}

/// Up to four figures side by side, so the opening, closing, and change
/// figures line up from row to row.
fn card_row(cards: List(Element(Msg))) -> Element(Msg) {
  html.div(
    [attribute.class("grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4")],
    cards,
  )
}

fn section_heading(title: String) -> Element(Msg) {
  html.h2([attribute.class("text-lg font-semibold text-fg")], [
    html.text(title),
  ])
}

fn figure_card(
  label: String,
  amount: Option(Float),
  testid: String,
) -> Element(Msg) {
  card(label, element.none(), testid, money_figure(amount))
}

/// A money figure, or "Not meaningful" when the server sends none.
fn money_figure(amount: Option(Float)) -> Element(Msg) {
  case amount {
    Some(amount) ->
      stat.figure(
        [attribute.attribute("data-amount", float.to_string(amount))],
        money.format(amount),
      )
    None -> stat.no_figure("Not meaningful")
  }
}

fn percent_figure(percent: Option(Float)) -> Element(Msg) {
  case percent {
    Some(percent) ->
      stat.figure([], float.to_string(float.to_precision(percent, 1)) <> "%")
    None -> stat.no_figure("No income")
  }
}

fn card(
  label: String,
  help: Element(Msg),
  testid: String,
  value: Element(Msg),
) -> Element(Msg) {
  stat.card_with_help(
    label,
    help,
    [attribute.attribute("data-testid", testid)],
    [
      value,
    ],
  )
}

fn lines_table(
  title: String,
  testid: String,
  lines: List(Line),
) -> Element(Msg) {
  card.panel([attribute.class("overflow-hidden")], [
    html.h3(
      [
        attribute.class(
          "border-b border-border px-4 py-3 text-base font-semibold text-fg",
        ),
      ],
      [html.text(title)],
    ),
    case lines {
      [] ->
        html.p([attribute.class("px-4 py-3 text-sm text-fg-subtle")], [
          html.text("None"),
        ])
      _ ->
        html.table(
          [
            attribute.class("w-full text-sm"),
            attribute.attribute("data-testid", testid),
          ],
          [
            html.tbody(
              [attribute.class("divide-y divide-border")],
              list.map(lines, line_row),
            ),
          ],
        )
    },
  ])
}

fn line_row(line: Line) -> Element(Msg) {
  html.tr([attribute.attribute("data-testid", "report-line")], [
    html.td([attribute.class("px-4 py-2")], [
      html.span([attribute.class("flex items-center gap-2 text-fg-muted")], [
        case line.color {
          Some(color) -> swatch.view(color)
          None ->
            html.span(
              [
                attribute.class(
                  "inline-block h-3 w-3 shrink-0 rounded-full border border-dashed border-fg-subtle",
                ),
              ],
              [],
            )
        },
        html.span([attribute.class("truncate")], [html.text(line.name)]),
      ]),
    ]),
    html.td(
      [
        attribute.class("px-4 py-2 text-right tabular-nums text-fg"),
        attribute.attribute("data-amount", float.to_string(line.amount)),
      ],
      [html.text(money.format(line.amount))],
    ),
    html.td(
      [attribute.class("w-20 px-4 py-2 text-right tabular-nums text-fg-muted")],
      [
        html.text(case line.share {
          Some(share) -> float.to_string(float.to_precision(share, 1)) <> "%"
          None -> ""
        }),
      ],
    ),
  ])
}

/// The sheet's "As of" column, hidden below sm, where account numbers leave no
/// room for it and each line shows its date under its name instead.
const as_of_column = " hidden sm:table-cell"

/// The closing balance sheet: its assets, then its liabilities, each with its
/// total, then net worth and working capital. Amounts are magnitudes, as on the
/// balance sheet page: the group gives the direction.
fn sheet_table(sheet: Sheet) -> Element(Msg) {
  let #(assets, liabilities) =
    list.partition(sheet.lines, fn(line) { line.side == side.Asset })

  card.panel([attribute.class("overflow-hidden")], [
    case sheet.lines {
      [] ->
        html.p([attribute.class("px-4 py-3 text-sm text-fg-muted")], [
          html.text("Nothing on the balance sheet on this date."),
        ])
      _ ->
        html.table(
          [
            attribute.class("w-full text-sm"),
            attribute.attribute("data-testid", "report-sheet-lines"),
          ],
          [
            html.thead(
              [attribute.class("bg-surface-hover text-left text-fg-muted")],
              [
                html.tr([], [
                  html.th([attribute.class("px-4 py-2 font-medium")], [
                    html.text("Line"),
                  ]),
                  html.th(
                    [attribute.class("px-4 py-2 font-medium" <> as_of_column)],
                    [html.text("As of")],
                  ),
                  html.th(
                    [attribute.class("px-4 py-2 text-right font-medium")],
                    [
                      html.text("Amount"),
                    ],
                  ),
                ]),
              ],
            ),
            sheet_group(
              "Assets",
              "report-sheet-assets",
              assets,
              sheet.total_assets,
            ),
            sheet_group(
              "Liabilities",
              "report-sheet-liabilities",
              liabilities,
              sheet.total_liabilities,
            ),
            html.tfoot(
              [
                attribute.class(
                  "divide-y divide-border border-t-2 border-border",
                ),
              ],
              [
                total_row("Net worth", sheet.net_worth),
                total_row("Working capital", sheet.working_capital),
              ],
            ),
          ],
        )
    },
    case sheet.unknown_balances {
      [] -> element.none()
      names ->
        html.p(
          [
            attribute.class(
              "border-t border-border bg-warning-tint px-4 py-3 text-sm text-fg",
            ),
          ],
          [
            html.text(
              "Left out of the totals, with no balance yet: "
              <> string.join(names, ", "),
            ),
          ],
        )
    },
  ])
}

/// One side's lines with its total, or nothing when the side has none.
fn sheet_group(
  title: String,
  testid: String,
  lines: List(SheetLine),
  total: Float,
) -> Element(Msg) {
  case lines {
    [] -> element.none()
    _ ->
      html.tbody(
        [
          attribute.class("divide-y divide-border border-t border-border"),
          attribute.attribute("data-testid", testid),
        ],
        list.flatten([
          [
            html.tr([], [
              html.th(
                [
                  attribute.class(
                    "px-4 pt-3 pb-1 text-left text-xs font-semibold uppercase tracking-wide text-fg-muted",
                  ),
                  attribute.attribute("colspan", "3"),
                ],
                [html.text(title)],
              ),
            ]),
          ],
          list.map(lines, sheet_row),
          [total_row("Total " <> string.lowercase(title), total)],
        ]),
      )
  }
}

fn sheet_row(line: SheetLine) -> Element(Msg) {
  html.tr([], [
    html.td([attribute.class("px-4 py-2")], [
      html.p([attribute.class("text-fg")], [html.text(line.name)]),
      html.p([attribute.class("text-xs text-fg-muted")], [
        html.text(term.label(line.term, line.side)),
        html.span([attribute.class("sm:hidden")], [
          html.text(" · as of " <> date.format(line.as_of)),
        ]),
      ]),
    ]),
    html.td([attribute.class("px-4 py-2 text-fg-muted" <> as_of_column)], [
      html.text(date.format(line.as_of)),
    ]),
    html.td(
      [
        attribute.class("px-4 py-2 text-right tabular-nums text-fg"),
        attribute.attribute("data-amount", float.to_string(line.amount)),
      ],
      [html.text(money.format(line.amount))],
    ),
  ])
}

/// A total, shaded and bold so it stands apart from the lines it sums.
fn total_row(label: String, amount: Float) -> Element(Msg) {
  html.tr([attribute.class("bg-surface-hover")], [
    // An empty "As of" cell rather than a colspan, so the amount stays in its
    // column when the "As of" column is hidden.
    html.th([attribute.class("px-4 py-2 text-left font-semibold text-fg")], [
      html.text(label),
    ]),
    html.td([attribute.class("px-4 py-2" <> as_of_column)], []),
    html.td(
      [
        attribute.class(
          "px-4 py-2 text-right font-semibold tabular-nums text-fg",
        ),
        attribute.attribute("data-amount", float.to_string(amount)),
      ],
      [html.text(money.format(amount))],
    ),
  ])
}

fn failed_state() -> Element(Msg) {
  card.empty_state(
    [
      attribute.attribute("data-testid", "report-load-error"),
    ],
    [
      html.p([attribute.class("text-sm text-fg-muted")], [
        html.text("Could not load the report."),
      ]),
      button.view(
        button.Secondary,
        button.Small,
        [
          attribute.class("mt-4"),
          attribute.attribute("data-testid", "report-retry"),
          event.on_click(UserRetried),
        ],
        [html.text("Retry")],
      ),
    ],
  )
}

/// Closed accounts with transactions in the period after their close date:
/// the income statement counts the transactions, but the balance sheets leave
/// the accounts out. See decision 4 in docs/reports.md.
fn transactions_after_close_note(names: List(String)) -> Element(Msg) {
  case names {
    [] -> element.none()
    names ->
      banner.view(
        banner.Warning,
        [
          attribute.attribute("data-testid", "report-transactions-after-close"),
        ],
        [
          html.text(
            "Transactions after the close date of "
            <> string.join(names, ", ")
            <> " count in the income statement, but the closed accounts are left off the balance sheets, so other changes are off by their net amount. Check the close dates on the balance sheet page.",
          ),
        ],
      )
  }
}
