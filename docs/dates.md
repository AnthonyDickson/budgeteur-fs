# Dates and Timestamps

Two kinds of time value, never mixed:

|         | Calendar date                               | Instant                                                 |
| ------- | ------------------------------------------- | ------------------------------------------------------- |
| Use for | A day given by the user or a bank statement | An event the server records                             |
| Example | `Transactions.Date`                         | `BalanceSheets.StatementDate`, `TaggingQueue.CreatedAt` |
| SQLite  | `DATE`                                      | `DATETIME`, UTC                                         |
| F#      | `DateOnly`                                  | `DateTimeOffset` written, UTC `DateTime` read           |
| Gleam   | `calendar.Date`                             | `Timestamp`                                             |
| JSON    | ISO-8601 date, `"2026-03-08"`               | RFC 3339 with an offset, `"2026-10-03T04:23:50Z"`       |

A calendar date is not converted to an instant: a statement row has no time of day, and any chosen time (e.g. local
midnight) is a different day in UTC and shifts if the timezone used to read it changes.

## Calendar dates

- **Storage.** `DATE` columns hold `yyyy-MM-dd` text. Range queries compare the text, which orders correctly only while
  every write uses that format; `Transactions(UserId, Date)` is indexed for them.
- **Parsing.** The server accepts only `yyyy-MM-dd`, independent of culture (`Coders.Extra.DateOnly.tryParse`); the
  client parses with `shared/date.gleam`.
- **Ranges.** A date range is an inclusive `from`/`to` pair of calendar dates. The client works out the range from its
  local `today` (the `GetLocalDate` effect) and sends it; the server filters on it and does no timezone conversion.

## Instants

`DATETIME` columns carry no offset and are assumed to be UTC. A deviation has to be documented on the column itself.

- **Writing.** Convert before the value reaches the column. F# code carries instants as `DateTimeOffset` and converts
  with `UtcDateTime.toColumn`, so the stored value is UTC whatever offset the caller holds; see
  `BalanceSheetStore.updateOrCreate`. SQL writes (a trigger, a queue insert) are outside the type system and have to
  apply the same rule by hand; SQLite's `datetime('now')` is already UTC.
- **Reading.** SQLite hands the value back as `DateTimeKind.Unspecified`, so each codec restores the kind with
  `UtcDateTime.fromColumn`; see `BalanceSheetCodec.fromRow`. Skipping it leaves the value `Unspecified`, so it is only
  correct if every reader happens to assume UTC.
- **Display.** Instants are converted to local time on the client, only for display.

Both conversions live in `Data/UtcDateTime.fs`. `just lint` fails if `DateTime.SpecifyKind` appears in `Data/` or a
feature codec other than that file, so the relabelling is written once instead of at every column. Code converting
between UTC and local time is not covered by that check and does not need to be: it works with `TimeZoneInfo` and
`DateTimeOffset`, which translate instants rather than relabel them.
