import budgeteur/reports_page/report.{
  type Report, FinancialYear, Line, Monthly, Report, Sheet,
}
import budgeteur/reports_page/reports_page
import budgeteur/shared/api_route
import budgeteur/shared/effect
import budgeteur/shared/remote
import budgeteur/shared/side.{Liability}
import budgeteur/shared/term.{NonCurrent}
import gleam/json
import gleam/option.{None, Some}
import gleam/time/calendar.{Date, February, March, October}
import gleeunit/should

const today = Date(2026, October, 14)

fn march() -> Report {
  Report(
    label: "March 2026",
    from: Date(2026, March, 1),
    to: Date(2026, March, 31),
    closing_date: Date(2026, March, 31),
    complete: True,
    has_previous: True,
    has_next: True,
    opening_net_worth: 400_000.0,
    opening_working_capital: 0.0,
    closing: Sheet(
      total_assets: 410_000.0,
      total_liabilities: 0.0,
      net_worth: 410_000.0,
      working_capital: 0.0,
      lines: [],
      unknown_balances: [],
    ),
    change_in_net_worth: Some(10_000.0),
    other_changes: Some(12_000.0),
    income: 0.0,
    expenses: 2000.0,
    net_income: -2000.0,
    savings_rate: None,
    income_lines: [],
    expense_lines: [],
  )
}

fn loaded(shown: Report) -> reports_page.Model {
  reports_page.Model(
    frequency: Monthly,
    today: Some(today),
    requested: Some(Date(2026, March, 10)),
    report: remote.Loaded(shown),
  )
}

fn url(effect: effect.Effect(msg)) -> String {
  let assert effect.HttpRequest(url:, ..) = effect
  url
}

pub fn the_report_is_fetched_once_today_is_known_test() {
  let #(model, effect) = reports_page.init()

  let assert effect.Batch([effect.LoadFromStore(..), effect.GetLocalDate(_)]) =
    effect

  // A restored frequency waits for today.
  let #(model, effect, _) =
    reports_page.update(
      model,
      reports_page.ClientRestoredFrequency(Some(FinancialYear)),
    )
  effect |> should.equal(effect.none())

  // Today brings the latest complete period: no date is sent.
  let #(_, effect, _) =
    reports_page.update(model, reports_page.ClientGotToday(today))
  url(effect)
  |> should.equal(
    api_route.to_string(api_route.GetReport("FinancialYear", today, None)),
  )
}

pub fn selecting_a_frequency_saves_it_and_shows_its_latest_report_test() {
  let #(model, effect, _) =
    reports_page.update(
      loaded(march()),
      reports_page.UserSelectedFrequency(FinancialYear),
    )

  model.requested |> should.equal(None)
  model.report |> should.equal(remote.Loading)
  let assert effect.Batch([request, effect.SaveToStore(key:, value:)]) = effect
  url(request)
  |> should.equal(
    api_route.to_string(api_route.GetReport("FinancialYear", today, None)),
  )
  key |> should.equal(reports_page.storage_key)
  value |> should.equal("{\"frequency\":\"FinancialYear\"}")
}

pub fn stepping_asks_for_the_day_either_side_test() {
  let #(back, effect, _) =
    reports_page.update(loaded(march()), reports_page.UserSteppedBack)
  back.requested |> should.equal(Some(Date(2026, February, 28)))
  url(effect)
  |> should.equal(
    api_route.to_string(api_route.GetReport(
      "Monthly",
      today,
      Some(Date(2026, February, 28)),
    )),
  )

  let #(forward, _, _) =
    reports_page.update(loaded(march()), reports_page.UserSteppedForward)
  forward.requested |> should.equal(Some(Date(2026, calendar.April, 1)))

  // With no earlier report, stepping back does nothing.
  let first = Report(..march(), has_previous: False)
  let #(unchanged, effect, _) =
    reports_page.update(loaded(first), reports_page.UserSteppedBack)
  unchanged |> should.equal(loaded(first))
  effect |> should.equal(effect.none())
}

pub fn a_stale_response_is_ignored_test() {
  // The user has stepped on to February since asking for March.
  let model =
    reports_page.Model(
      ..loaded(march()),
      requested: Some(Date(2026, February, 28)),
      report: remote.Loading,
    )

  let #(after, _, _) =
    reports_page.update(
      model,
      reports_page.ClientFetchedReport(
        Monthly,
        Some(Date(2026, March, 10)),
        Ok(march()),
      ),
    )

  after |> should.equal(model)
}

pub fn a_report_decodes_with_figures_that_are_not_meaningful_test() {
  let body =
    json.object([
      #("frequency", json.string("Monthly")),
      #("label", json.string("January 2026")),
      #("from", json.string("2026-01-01")),
      #("to", json.string("2026-01-31")),
      #("closingDate", json.string("2026-01-31")),
      #("complete", json.bool(True)),
      #("hasPrevious", json.bool(False)),
      #("hasNext", json.bool(True)),
      #(
        "opening",
        json.object([
          #("netWorth", json.string("0")),
          #("workingCapital", json.string("0")),
        ]),
      ),
      #(
        "closing",
        json.object([
          #("totalAssets", json.string("400000")),
          #("totalLiabilities", json.string("0")),
          #("netWorth", json.string("400000")),
          #("workingCapital", json.string("0")),
          #(
            "lines",
            json.preprocessed_array([
              json.object([
                #("id", json.string("0199a1b2-0000-7000-8000-000000000001")),
                #("name", json.string("Mortgage")),
                #("side", json.string("Liability")),
                #("term", json.string("NonCurrent")),
                #("amount", json.string("300000")),
                #("asOf", json.string("2026-01-15")),
              ]),
            ]),
          ),
          #("unknownBalances", json.array(["New card"], json.string)),
        ]),
      ),
      #("changeInNetWorth", json.null()),
      #("otherChanges", json.null()),
      #("income", json.string("5000")),
      #("expenses", json.string("2000")),
      #("netIncome", json.string("3000")),
      #("savingsRate", json.string("60")),
      #("incomeLines", json.preprocessed_array([])),
      #(
        "expenseLines",
        json.preprocessed_array([
          json.object([
            #("tagId", json.null()),
            #("name", json.string("Untagged expenses")),
            #("color", json.null()),
            #("amount", json.string("2000")),
            #("share", json.string("100")),
          ]),
        ]),
      ),
    ])
    |> json.to_string

  let assert Ok(decoded) = json.parse(body, report.decoder())
  decoded.change_in_net_worth |> should.equal(None)
  decoded.other_changes |> should.equal(None)
  decoded.savings_rate |> should.equal(Some(60.0))
  decoded.closing.unknown_balances |> should.equal(["New card"])
  let assert [mortgage] = decoded.closing.lines
  #(mortgage.side, mortgage.term)
  |> should.equal(#(Liability, NonCurrent))
  decoded.expense_lines
  |> should.equal([
    Line(
      tag_id: None,
      name: "Untagged expenses",
      color: None,
      amount: 2000.0,
      share: Some(100.0),
    ),
  ])
}
