# Dates and Timestamps

Two kinds of time value, never mixed:

|         | Calendar date                               | Instant                                           |
| ------- | ------------------------------------------- | ------------------------------------------------- |
| Use for | A day given by the user or a bank statement | An event the server records                       |
| Example | A transaction's date                        | A balance sheet's statement date                  |
| SQLite  | `DATE`                                      | `DATETIME`, UTC                                   |
| F#      | `DateOnly`                                  | `DateTimeOffset` in code, UTC `DateTime` in rows  |
| Gleam   | `calendar.Date`                             | `Timestamp`                                       |
| JSON    | ISO-8601 date, `"2026-03-08"`               | RFC 3339 with an offset, `"2026-10-03T04:23:50Z"` |

A calendar date is not converted to an instant: a statement row has no time of
day, and any chosen time (e.g. local midnight) is a different day in UTC and
shifts if the timezone used to read it changes.

## Calendar dates

- **Storage.** `DATE` columns hold `yyyy-MM-dd` text. Range queries compare the
  text, which orders correctly only while every write uses that format.
- **Parsing.** Both server and client accept only `yyyy-MM-dd`, independent of
  culture.
- **Ranges.** A date range is an inclusive `from`/`to` pair of calendar dates.
  The client works out the range from its local `today` and sends it; the server
  filters on it and does no timezone conversion. This keeps the server free of
  timezone configuration and makes endpoint tests deterministic.

## Instants

`DATETIME` columns carry no offset and are UTC. A column that deviates has to
say so in its migration comment.

- **Writing.** Convert to UTC before the value reaches the column, so the stored
  value is UTC whatever offset the caller held. SQL writes (triggers, inserts in
  SQL) are outside the type system and apply the same rule by hand; SQLite's
  `datetime('now')` is already UTC.
- **Reading.** SQLite returns the value without a kind, so each codec marks it
  as UTC when reading a row. Skipping that leaves it correct only if every
  reader happens to assume UTC.
- **Display.** Instants are converted to local time on the client, only for
  display.

Both conversions live in one kernel module (`Data/UtcDateTime.fs`). `just lint`
fails if a codec or other `Data/` file relabels a `DateTime` kind itself, so the
rule is written once. Code converting between UTC and local time is not covered
and does not need to be: it translates instants rather than relabelling them.

## Not yet decided

A server-side timezone is needed only once the server works out periods without
a client request (e.g. scheduled snapshots). Per-user timezones are likewise
deferred. See the backlog in [TODO.md](../TODO.md).
