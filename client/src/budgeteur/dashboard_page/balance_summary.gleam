//// The balance sheet fields the dashboard shows. The page decodes them with
//// its own decoder rather than importing the balance sheet page's, so the two
//// pages can change independently.

import budgeteur/shared/money
import budgeteur/shared/timestamp_helpers
import gleam/dynamic/decode
import gleam/time/timestamp.{type Timestamp}

pub type BalanceSummary {
  BalanceSummary(
    statement_date: Timestamp,
    net_worth: Float,
    working_capital: Float,
  )
}

pub fn decoder() -> decode.Decoder(BalanceSummary) {
  use statement_date <- decode.field(
    "statementDate",
    timestamp_helpers.decoder(),
  )
  use net_worth <- decode.field("netWorth", money.decode_decimal())
  use working_capital <- decode.field("workingCapital", money.decode_decimal())
  decode.success(BalanceSummary(statement_date:, net_worth:, working_capital:))
}
