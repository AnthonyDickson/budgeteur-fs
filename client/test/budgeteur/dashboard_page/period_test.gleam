import budgeteur/dashboard_page/period.{
  Last28Days, LastMonth, Period, ThisFinancialYear, ThisMonth,
}
import gleam/list
import gleam/time/calendar.{
  April, Date, December, February, January, March, October, September,
}
import gleeunit/should

pub fn this_month_runs_from_the_first_to_today_test() {
  period.from_preset(ThisMonth, Date(2026, October, 10))
  |> should.equal(Period(
    from: Date(2026, October, 1),
    to: Date(2026, October, 10),
  ))
}

pub fn this_month_on_the_first_is_a_single_day_test() {
  period.from_preset(ThisMonth, Date(2026, October, 1))
  |> should.equal(Period(
    from: Date(2026, October, 1),
    to: Date(2026, October, 1),
  ))
}

pub fn last_month_covers_the_whole_previous_month_test() {
  period.from_preset(LastMonth, Date(2026, October, 10))
  |> should.equal(Period(
    from: Date(2026, September, 1),
    to: Date(2026, September, 30),
  ))
}

pub fn last_month_in_january_is_december_of_last_year_test() {
  period.from_preset(LastMonth, Date(2027, January, 15))
  |> should.equal(Period(
    from: Date(2026, December, 1),
    to: Date(2026, December, 31),
  ))
}

pub fn last_month_ends_on_the_29th_of_february_in_a_leap_year_test() {
  period.from_preset(LastMonth, Date(2028, March, 31))
  |> should.equal(Period(
    from: Date(2028, February, 1),
    to: Date(2028, February, 29),
  ))
}

pub fn last_month_ends_on_the_28th_of_february_otherwise_test() {
  period.from_preset(LastMonth, Date(2027, March, 1))
  |> should.equal(Period(
    from: Date(2027, February, 1),
    to: Date(2027, February, 28),
  ))
}

pub fn last_28_days_includes_today_test() {
  period.from_preset(Last28Days, Date(2026, October, 28))
  |> should.equal(Period(
    from: Date(2026, October, 1),
    to: Date(2026, October, 28),
  ))
}

pub fn last_28_days_crosses_a_year_boundary_test() {
  period.from_preset(Last28Days, Date(2027, January, 10))
  |> should.equal(Period(
    from: Date(2026, December, 14),
    to: Date(2027, January, 10),
  ))
}

pub fn last_28_days_crosses_a_leap_day_test() {
  period.from_preset(Last28Days, Date(2028, March, 10))
  |> should.equal(Period(
    from: Date(2028, February, 12),
    to: Date(2028, March, 10),
  ))
}

pub fn financial_year_starts_on_1_april_this_year_from_april_test() {
  period.from_preset(ThisFinancialYear, Date(2026, April, 1))
  |> should.equal(Period(from: Date(2026, April, 1), to: Date(2026, April, 1)))
}

pub fn financial_year_starts_on_1_april_last_year_before_april_test() {
  period.from_preset(ThisFinancialYear, Date(2027, March, 31))
  |> should.equal(Period(from: Date(2026, April, 1), to: Date(2027, March, 31)))
}

pub fn presets_round_trip_through_their_encoding_test() {
  period.presets
  |> list.each(fn(preset) {
    preset
    |> period.preset_to_string
    |> period.parse_preset
    |> should.equal(Ok(preset))
  })
}
