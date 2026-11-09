package budgeteur.domain

import arrow.core.raise.Raise
import arrow.core.raise.context.raise
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.time.format.DateTimeFormatterBuilder
import java.time.format.DateTimeParseException
import java.time.format.ResolverStyle
import java.time.temporal.ChronoField

// A calendar date is a `LocalDate`: a day from the user or a bank statement, never converted to an
// instant (see docs/dates.md). It is written as `yyyy-MM-dd` in JSON and in `TEXT` columns, whose
// text order is then date order.

/**
 * Exactly `yyyy-MM-dd`, as the F# server's `TryParseExact`. `ISO_LOCAL_DATE` would also accept
 * signed years beyond 9999. The strict resolver rejects days that do not exist, such as February
 * 30th.
 */
private val calendarDate: DateTimeFormatter =
    DateTimeFormatterBuilder()
        .appendValue(ChronoField.YEAR, 4)
        .appendLiteral('-')
        .appendValue(ChronoField.MONTH_OF_YEAR, 2)
        .appendLiteral('-')
        .appendValue(ChronoField.DAY_OF_MONTH, 2)
        .toFormatter()
        .withResolverStyle(ResolverStyle.STRICT)

context(_: Raise<String>)
fun parseCalendarDate(raw: String): LocalDate =
    try {
        LocalDate.parse(raw, calendarDate)
    } catch (_: DateTimeParseException) {
        raise("\"$raw\" is not a date, expecting yyyy-MM-dd, e.g. \"2026-03-08\".")
    }

/** Throws for years outside 0000–9999, which [parseCalendarDate] never produces. */
fun LocalDate.formatCalendarDate(): String = format(calendarDate)
