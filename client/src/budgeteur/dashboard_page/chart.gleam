//// The dashboard's charts: Observable Plot inside the `<dashboard-chart>`
//// custom element. The page passes each chart's figures as a property and the
//// element redraws when they change, so no chart state lives in the model. See
//// decision 15 in docs/dashboard.md.

import budgeteur/dashboard_page/dashboard.{type HistoryMonth}
import gleam/json.{type Json}
import gleam/option.{type Option}
import lustre/attribute
import lustre/element.{type Element}

pub type Kind {
  /// Income and expense bars per month, with a net income line.
  CashFlow
  /// Net worth at each month's closing date.
  NetWorth
}

/// Define the `<dashboard-chart>` custom element that `view` renders. Call
/// once before the app starts. Plot itself loads when a chart is first drawn.
@external(javascript, "./chart_ffi.mjs", "registerChart")
pub fn register() -> Nil

pub fn view(
  kind: Kind,
  history: List(HistoryMonth),
  testid: String,
) -> Element(msg) {
  element.element(
    "dashboard-chart",
    [
      attribute.class("block text-gray-700"),
      attribute.property("spec", spec(kind, history)),
      attribute.attribute("data-testid", testid),
    ],
    [],
  )
}

fn spec(kind: Kind, history: List(HistoryMonth)) -> Json {
  json.object([
    #(
      "kind",
      json.string(case kind {
        CashFlow -> "cashFlow"
        NetWorth -> "netWorth"
      }),
    ),
    #(
      "months",
      json.array(history, fn(month) {
        json.object([
          #("label", json.string(month.label)),
          #("complete", json.bool(month.complete)),
          #("income", json.float(month.income)),
          #("expenses", json.float(month.expenses)),
          #("netIncome", json.float(month.net_income)),
          #("netWorth", optional_float(month.net_worth)),
        ])
      }),
    ),
  ])
}

fn optional_float(value: Option(Float)) -> Json {
  json.nullable(value, json.float)
}
