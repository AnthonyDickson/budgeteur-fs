//// Accounts as the balance sheet page reads them: somewhere the user's
//// transactions happen, shown as a line when its balance is known. See
//// docs/csv-import.md.

import budgeteur/shared/date
import budgeteur/shared/money
import budgeteur/shared/side.{type Side}
import budgeteur/shared/term.{type Term}
import budgeteur/shared/uuid as uuid_decoder
import gleam/dynamic/decode
import gleam/option.{type Option, None}
import gleam/time/calendar.{type Date}
import youid/uuid.{type Uuid}

/// An account's identity and settings: what the account form edits.
pub type Account {
  Account(
    id: Uuid,
    // The user's alias for the account.
    name: String,
    // The number statements identify the account by, in canonical form.
    number: Option(String),
    // Whether the account is current or non-current.
    term: Term,
    // The date the account was closed; None while it is open.
    closed_on: Option(Date),
  )
}

/// An account with a known balance, as a balance sheet line.
pub type AccountLine {
  AccountLine(
    account: Account,
    // Asset when the balance is zero or more, liability when it is negative.
    side: Side,
    // The magnitude of the current balance. Direction is implied by side.
    balance: Float,
    // The date the current balance is accurate as of.
    as_of: Date,
  )
}

/// Decodes the account fields shared by account lines, unknown balances, and
/// the account endpoints' responses.
pub fn decoder() -> decode.Decoder(Account) {
  use id <- decode.field("id", uuid_decoder.decoder())
  use name <- decode.field("name", decode.string)
  use number <- decode.optional_field(
    "number",
    None,
    decode.optional(decode.string),
  )
  use term <- decode.field("term", term.decoder())
  use closed_on <- decode.optional_field(
    "closedOn",
    None,
    decode.optional(date.decoder()),
  )
  decode.success(Account(id:, name:, number:, term:, closed_on:))
}

pub fn line_decoder() -> decode.Decoder(AccountLine) {
  use account <- decode.then(decoder())
  use side <- decode.field("side", side.decoder())
  use balance <- decode.field("balance", money.decode_decimal())
  use as_of <- decode.field("asOf", date.decoder())
  decode.success(AccountLine(account:, side:, balance:, as_of:))
}
