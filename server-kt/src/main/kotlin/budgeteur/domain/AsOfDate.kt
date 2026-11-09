package budgeteur.domain

import arrow.core.raise.Raise
import arrow.core.raise.context.ensure
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset

// The calendar dates a balance is accurate as of, and a line is closed on, are bounded by the
// server's clock, so a mistyped future date cannot stay current. See decision 4 in
// docs/balance-sheet.md and decision 4 in docs/reports.md.

/**
 * The latest as-of or close date accepted at the instant [now]: the server's UTC date plus one day.
 * The extra day covers a client whose local date is ahead of UTC.
 */
fun latestAcceptedDate(now: Instant): LocalDate =
    LocalDate.ofInstant(now, ZoneOffset.UTC).plusDays(1)

/** Rejects an as-of date later than [latestAcceptedDate]. */
context(_: Raise<String>)
fun requireAsOfDate(now: Instant, asOf: LocalDate): LocalDate = requireNotFuture("as-of", now, asOf)

/**
 * Rejects a close date later than [latestAcceptedDate], so a line cannot be closed in advance. The
 * current balance sheet can then leave out every closed line without knowing the client's today.
 */
context(_: Raise<String>)
fun requireCloseDate(now: Instant, closedOn: LocalDate): LocalDate =
    requireNotFuture("close", now, closedOn)

context(_: Raise<String>)
private fun requireNotFuture(what: String, now: Instant, date: LocalDate): LocalDate {
    val latest = latestAcceptedDate(now)
    ensure(date <= latest) {
        "The $what date ${date.formatCalendarDate()} is in the future. The latest accepted date " +
            "is ${latest.formatCalendarDate()}."
    }
    return date
}
