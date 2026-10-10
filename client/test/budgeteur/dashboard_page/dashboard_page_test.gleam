import budgeteur/dashboard_page/balance_summary.{BalanceSummary}
import budgeteur/dashboard_page/dashboard_page.{
  ClientFetchedBalance, ClientFetchedStatement, ClientGotToday,
  ClientRestoredPreset, UserRetriedBalance, UserRetriedStatement,
  UserSelectedPreset,
}
import budgeteur/dashboard_page/income_statement.{IncomeStatement}
import budgeteur/dashboard_page/period.{LastMonth, Period, ThisMonth}
import budgeteur/shared/api_error.{type ApiError, ApiError}
import budgeteur/shared/api_route
import budgeteur/shared/effect
import budgeteur/shared/remote.{Failed, Loaded, Loading}
import gleam/option.{None, Some}
import gleam/time/calendar.{Date, October, September}
import gleam/time/timestamp
import gleeunit/should

const today = Date(2026, October, 10)

fn this_month() -> period.Period {
  Period(from: Date(2026, October, 1), to: today)
}

fn last_month() -> period.Period {
  Period(from: Date(2026, September, 1), to: Date(2026, September, 30))
}

fn statement_url(period: period.Period) -> String {
  api_route.GetIncomeStatement(from: period.from, to: period.to)
  |> api_route.to_string
}

fn statement(period: period.Period) -> income_statement.IncomeStatement {
  IncomeStatement(
    from: period.from,
    to: period.to,
    income: 5000.0,
    expenses: 2000.0,
    net_income: 3000.0,
    income_lines: [],
    expense_lines: [],
    untagged_count: 0,
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

/// A page that knows today and has fetched nothing yet.
fn model_with_today() -> dashboard_page.Model {
  let #(model, _) = dashboard_page.init()
  let #(model, _) = update(model, ClientGotToday(today))
  model
}

pub fn init_restores_the_preset_asks_for_today_and_fetches_the_balance_test() {
  let #(model, effect) = dashboard_page.init()

  model.preset |> should.equal(period.default_preset)
  model.statement |> should.equal(Loading)
  model.balance |> should.equal(Loading)

  let assert effect.Batch([
    effect.LoadFromStore(key:, ..),
    effect.GetLocalDate(_),
    effect.HttpRequest(url:, ..),
  ]) = effect
  key |> should.equal(dashboard_page.storage_key)
  url |> should.equal(api_route.to_string(api_route.GetBalanceSheet))
}

pub fn today_fetches_the_statement_for_the_default_preset_test() {
  let #(model, _) = dashboard_page.init()

  let #(model, effect) = update(model, ClientGotToday(today))

  dashboard_page.current_period(model) |> should.equal(Some(this_month()))
  let assert effect.HttpRequest(url:, ..) = effect
  url |> should.equal(statement_url(this_month()))
}

pub fn the_statement_loads_for_the_current_period_test() {
  let #(model, _) =
    update(
      model_with_today(),
      ClientFetchedStatement(this_month(), Ok(statement(this_month()))),
    )

  model.statement |> should.equal(Loaded(statement(this_month())))
}

pub fn choosing_a_preset_refetches_and_saves_it_test() {
  let #(model, _) =
    update(
      model_with_today(),
      ClientFetchedStatement(this_month(), Ok(statement(this_month()))),
    )

  let #(model, effect) = update(model, UserSelectedPreset(LastMonth))

  model.preset |> should.equal(LastMonth)
  model.statement |> should.equal(Loading)
  let assert effect.Batch([
    effect.HttpRequest(url:, ..),
    effect.SaveToStore(key:, value:),
  ]) = effect
  url |> should.equal(statement_url(last_month()))
  key |> should.equal(dashboard_page.storage_key)
  value |> should.equal("{\"preset\":\"LastMonth\"}")
}

pub fn a_response_for_an_earlier_period_is_ignored_test() {
  let #(model, _) = update(model_with_today(), UserSelectedPreset(LastMonth))

  // The this-month request was still in flight when the user switched.
  let #(model, _) =
    update(
      model,
      ClientFetchedStatement(this_month(), Ok(statement(this_month()))),
    )
  model.statement |> should.equal(Loading)

  let #(model, _) =
    update(
      model,
      ClientFetchedStatement(last_month(), Ok(statement(last_month()))),
    )
  model.statement |> should.equal(Loaded(statement(last_month())))
}

pub fn a_restored_preset_refetches_the_statement_test() {
  let #(model, effect) =
    update(model_with_today(), ClientRestoredPreset(Some(LastMonth)))

  model.preset |> should.equal(LastMonth)
  let assert effect.HttpRequest(url:, ..) = effect
  url |> should.equal(statement_url(last_month()))
}

pub fn a_preset_restored_before_today_waits_for_today_test() {
  let #(model, _) = dashboard_page.init()

  let #(model, effect) = update(model, ClientRestoredPreset(Some(LastMonth)))
  effect |> should.equal(effect.none())

  let #(_, effect) = update(model, ClientGotToday(today))
  let assert effect.HttpRequest(url:, ..) = effect
  url |> should.equal(statement_url(last_month()))
}

pub fn restoring_the_same_preset_does_not_refetch_test() {
  let #(_, effect) =
    update(model_with_today(), ClientRestoredPreset(Some(ThisMonth)))

  effect |> should.equal(effect.none())
}

pub fn a_failed_statement_can_be_retried_test() {
  let #(model, effect) =
    update(
      model_with_today(),
      ClientFetchedStatement(this_month(), Error(api_error(500))),
    )
  model.statement |> should.equal(Failed)
  let assert effect.LogError(_) = effect

  let #(model, effect) = update(model, UserRetriedStatement)
  model.statement |> should.equal(Loading)
  let assert effect.HttpRequest(url:, ..) = effect
  url |> should.equal(statement_url(this_month()))

  let #(model, _) =
    update(
      model,
      ClientFetchedStatement(this_month(), Ok(statement(this_month()))),
    )
  model.statement |> should.equal(Loaded(statement(this_month())))
}

pub fn a_missing_balance_sheet_is_an_empty_state_test() {
  let #(model, effect) =
    update(model_with_today(), ClientFetchedBalance(Error(api_error(404))))

  model.balance |> should.equal(Loaded(None))
  effect |> should.equal(effect.none())
}

pub fn a_failed_balance_can_be_retried_test() {
  let #(model, _) =
    update(model_with_today(), ClientFetchedBalance(Error(api_error(500))))
  model.balance |> should.equal(Failed)

  let #(model, effect) = update(model, UserRetriedBalance)
  model.balance |> should.equal(Loading)
  let assert effect.HttpRequest(url:, ..) = effect
  url |> should.equal(api_route.to_string(api_route.GetBalanceSheet))

  let summary =
    BalanceSummary(
      statement_date: timestamp.from_unix_seconds(1_772_000_000),
      net_worth: 100_500.0,
      working_capital: 500.0,
    )
  let #(model, _) = update(model, ClientFetchedBalance(Ok(summary)))
  model.balance |> should.equal(Loaded(Some(summary)))
}
