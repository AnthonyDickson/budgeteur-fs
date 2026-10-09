//// Periods for the income statement: an inclusive pair of calendar dates,
//// worked out from the client's local `today` and a named preset. See
//// docs/dashboard.md (decision 6) and docs/dates.md.

import gleam/pair
import gleam/time/calendar.{type Date, Date}
import gleam/time/duration
import gleam/time/timestamp

/// An inclusive range of calendar dates.
pub type Period {
  Period(from: Date, to: Date)
}

/// A named rule that turns `today` into a period.
pub type Preset {
  /// The first of the month up to today. The default.
  ThisMonth
  /// The whole of the previous calendar month.
  LastMonth
  /// Today and the 27 days before it.
  Last28Days
  /// From 1 April up to today.
  ThisFinancialYear
}

pub const default_preset = ThisMonth

/// Every preset, in the order the page offers them.
pub const presets = [ThisMonth, LastMonth, Last28Days, ThisFinancialYear]

/// The period a preset covers on the given day.
pub fn from_preset(preset: Preset, today: Date) -> Period {
  case preset {
    ThisMonth -> Period(from: first_of_month(today), to: today)
    LastMonth -> {
      let first_of_this_month = first_of_month(today)
      let last_of_last_month = add_days(first_of_this_month, -1)
      Period(from: first_of_month(last_of_last_month), to: last_of_last_month)
    }
    Last28Days -> Period(from: add_days(today, -27), to: today)
    ThisFinancialYear -> {
      let year = case calendar.month_to_int(today.month) >= 4 {
        True -> today.year
        False -> today.year - 1
      }
      Period(from: Date(year, calendar.April, 1), to: today)
    }
  }
}

/// The label shown to the user.
pub fn label(preset: Preset) -> String {
  case preset {
    ThisMonth -> "This month"
    LastMonth -> "Last month"
    Last28Days -> "Last 28 days"
    ThisFinancialYear -> "This financial year"
  }
}

/// The encoded string for a preset, used for localStorage and form values.
pub fn preset_to_string(preset: Preset) -> String {
  case preset {
    ThisMonth -> "ThisMonth"
    LastMonth -> "LastMonth"
    Last28Days -> "Last28Days"
    ThisFinancialYear -> "ThisFinancialYear"
  }
}

/// Parse a preset from its encoded string.
pub fn parse_preset(value: String) -> Result(Preset, Nil) {
  case value {
    "ThisMonth" -> Ok(ThisMonth)
    "LastMonth" -> Ok(LastMonth)
    "Last28Days" -> Ok(Last28Days)
    "ThisFinancialYear" -> Ok(ThisFinancialYear)
    _ -> Error(Nil)
  }
}

fn first_of_month(date: Date) -> Date {
  Date(..date, day: 1)
}

/// Move a date by a number of days. The arithmetic runs on UTC midnight, which
/// has no daylight saving changes, so every day is exactly 24 hours.
fn add_days(date: Date, days: Int) -> Date {
  timestamp.from_calendar(
    date:,
    time: calendar.TimeOfDay(0, 0, 0, 0),
    offset: calendar.utc_offset,
  )
  |> timestamp.add(duration.hours(days * 24))
  |> timestamp.to_calendar(calendar.utc_offset)
  |> pair.first
}
