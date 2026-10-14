import budgeteur/dashboard_page/dashboard.{
  type Dashboard, Dashboard, Figure, Line, Month, Position,
}
import budgeteur/dashboard_page/dashboard_page.{
  ClientFetchedDashboard, ClientGotToday, Higher, Lower, UserRetried,
}
import budgeteur/shared/api_error.{type ApiError, ApiError}
import budgeteur/shared/api_route
import budgeteur/shared/effect
import budgeteur/shared/remote.{Failed, Loaded, Loading}
import gleam/json
import gleam/option.{None, Some}
import gleam/time/calendar.{Date, October}
import gleeunit/should

const today = Date(2026, October, 14)

fn dashboard_url() -> String {
  api_route.GetDashboard(today:) |> api_route.to_string
}

fn no_change(amount: Float) -> dashboard.Figure {
  Figure(amount:, baseline: None, change: None, change_percent: None)
}

fn dashboard() -> Dashboard {
  Dashboard(
    position: Position(
      is_empty: False,
      net_worth: 400_000.0,
      working_capital: 6000.0,
      runway: Some(3.0),
      oldest_as_of: Some(Date(2026, October, 5)),
    ),
    month: Month(
      label: "October 2026",
      from: Date(2026, October, 1),
      to: today,
      income: no_change(5000.0),
      expenses: no_change(400.0),
      net_income: no_change(4600.0),
      savings_rate: Some(92.0),
      savings_rate_baseline: None,
      savings_rate_change: None,
      baseline_month_count: 0,
      latest_transaction: Some(Date(2026, October, 5)),
      income_lines: [],
      expense_lines: [],
    ),
  )
}

fn api_error(status_code: Int) -> ApiError {
  ApiError(
    error: "Error",
    details: "boom",
    status_code: Some(status_code),
    request_id: None,
  )
}

fn update(model: dashboard_page.Model, msg: dashboard_page.Msg) {
  let #(model, effect, out_msg) = dashboard_page.update(model, msg)
  out_msg |> should.equal(None)
  #(model, effect)
}

pub fn init_asks_for_today_and_fetches_the_waiting_count_test() {
  let #(model, effect) = dashboard_page.init()

  model.dashboard |> should.equal(Loading)
  model.waiting |> should.equal(Loading)

  let assert effect.Batch([
    effect.GetLocalDate(_),
    effect.HttpRequest(url: waiting_url, ..),
  ]) = effect
  waiting_url |> should.equal(api_route.to_string(api_route.GetQuickTagQueue))
}

pub fn today_fetches_the_dashboard_test() {
  let #(model, _) = dashboard_page.init()

  let #(model, effect) = update(model, ClientGotToday(today))
  let assert effect.HttpRequest(url:, ..) = effect
  url |> should.equal("/api/dashboard?today=2026-10-14")
  url |> should.equal(dashboard_url())

  let #(model, _) = update(model, ClientFetchedDashboard(Ok(dashboard())))
  model.dashboard |> should.equal(Loaded(dashboard()))
}

pub fn a_failed_dashboard_can_be_retried_test() {
  let #(model, _) = dashboard_page.init()
  let #(model, _) = update(model, ClientGotToday(today))

  let #(model, effect) =
    update(model, ClientFetchedDashboard(Error(api_error(500))))
  model.dashboard |> should.equal(Failed)
  let assert effect.LogError(_) = effect

  let #(model, effect) = update(model, UserRetried)
  model.dashboard |> should.equal(Loading)
  let assert effect.HttpRequest(url:, ..) = effect
  url |> should.equal(dashboard_url())
}

pub fn improvements_are_decreases_in_expenses_and_increases_elsewhere_test() {
  dashboard_page.is_improvement(-50.0, Lower) |> should.be_true
  dashboard_page.is_improvement(50.0, Lower) |> should.be_false
  dashboard_page.is_improvement(50.0, Higher) |> should.be_true
  dashboard_page.is_improvement(-50.0, Higher) |> should.be_false
  dashboard_page.is_improvement(0.0, Higher) |> should.be_false
}

pub fn the_decoder_reads_figures_and_lines_with_their_baselines_test() {
  let body =
    "{\"position\":{\"isEmpty\":false,\"netWorth\":\"400000\",\"workingCapital\":\"6000.50\",\"runway\":null},"
    <> "\"month\":{\"label\":\"October 2026\",\"from\":\"2026-10-01\",\"to\":\"2026-10-14\","
    <> "\"income\":{\"amount\":\"5000\",\"baseline\":\"4000\",\"change\":\"1000\",\"changePercent\":\"25\"},"
    <> "\"expenses\":{\"amount\":\"400\",\"baseline\":\"0\",\"change\":\"400\",\"changePercent\":null},"
    <> "\"netIncome\":{\"amount\":\"4600\"},"
    <> "\"savingsRate\":\"92\",\"savingsRateBaseline\":\"80\",\"savingsRateChange\":\"12\","
    <> "\"baselineMonthCount\":2,\"latestTransaction\":\"2026-10-05\","
    <> "\"incomeLines\":[],"
    <> "\"expenseLines\":[{\"tagId\":null,\"name\":\"Untagged expenses\",\"color\":null,"
    <> "\"amount\":\"0\",\"share\":\"0\",\"baseline\":\"20\",\"change\":\"-20\",\"changePercent\":\"-100\"}]}}"

  let assert Ok(decoded) = json.parse(body, dashboard.decoder())

  decoded.position.working_capital |> should.equal(6000.5)
  decoded.position.runway |> should.equal(None)
  decoded.month.income
  |> should.equal(Figure(
    amount: 5000.0,
    baseline: Some(4000.0),
    change: Some(1000.0),
    change_percent: Some(25.0),
  ))
  decoded.month.net_income |> should.equal(no_change(4600.0))
  decoded.month.latest_transaction |> should.equal(Some(Date(2026, October, 5)))
  decoded.month.expense_lines
  |> should.equal([
    Line(
      name: "Untagged expenses",
      color: None,
      figure: Figure(
        amount: 0.0,
        baseline: Some(20.0),
        change: Some(-20.0),
        change_percent: Some(-100.0),
      ),
      share: Some(0.0),
    ),
  ])
}
