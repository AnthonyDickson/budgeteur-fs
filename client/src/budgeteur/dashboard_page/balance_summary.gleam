//// The balance sheet fields the dashboard shows. The page decodes them with
//// its own decoder rather than importing the balance sheet page's, so the two
//// pages can change independently.

import budgeteur/shared/money
import gleam/dynamic/decode
import gleam/list

pub type BalanceSummary {
  BalanceSummary(
    net_worth: Float,
    working_capital: Float,
    /// Whether the sheet has no lines, so the page shows an empty state
    /// instead of zero figures.
    is_empty: Bool,
  )
}

pub fn decoder() -> decode.Decoder(BalanceSummary) {
  use net_worth <- decode.field("netWorth", money.decode_decimal())
  use working_capital <- decode.field("workingCapital", money.decode_decimal())
  use items <- decode.field("items", decode.list(decode.dynamic))
  use accounts <- decode.field("accounts", decode.list(decode.dynamic))
  use unknown_balances <- decode.field(
    "unknownBalances",
    decode.list(decode.dynamic),
  )
  decode.success(BalanceSummary(
    net_worth:,
    working_capital:,
    is_empty: list.is_empty(items)
      && list.is_empty(accounts)
      && list.is_empty(unknown_balances),
  ))
}
