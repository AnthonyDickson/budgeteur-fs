import budgeteur/balance_sheet_page/balance_sheet_item.{type BalanceSheetItem}
import budgeteur/shared/money
import gleam/dynamic/decode

pub type BalanceSheet {
  BalanceSheet(
    total_assets: Float,
    total_liabilities: Float,
    net_worth: Float,
    total_current_assets: Float,
    total_non_current_assets: Float,
    total_current_liabilities: Float,
    total_non_current_liabilities: Float,
    working_capital: Float,
    items: List(BalanceSheetItem),
  )
}

pub fn decoder() -> decode.Decoder(BalanceSheet) {
  use total_assets <- decode.field("totalAssets", money.decode_decimal())
  use total_liabilities <- decode.field(
    "totalLiabilities",
    money.decode_decimal(),
  )
  use net_worth <- decode.field("netWorth", money.decode_decimal())
  use total_current_assets <- decode.field(
    "totalCurrentAssets",
    money.decode_decimal(),
  )
  use total_non_current_assets <- decode.field(
    "totalNonCurrentAssets",
    money.decode_decimal(),
  )
  use total_current_liabilities <- decode.field(
    "totalCurrentLiabilities",
    money.decode_decimal(),
  )
  use total_non_current_liabilities <- decode.field(
    "totalNonCurrentLiabilities",
    money.decode_decimal(),
  )
  use working_capital <- decode.field("workingCapital", money.decode_decimal())
  use items <- decode.field("items", decode.list(balance_sheet_item.decoder()))
  decode.success(BalanceSheet(
    total_assets:,
    total_liabilities:,
    net_worth:,
    total_current_assets:,
    total_non_current_assets:,
    total_current_liabilities:,
    total_non_current_liabilities:,
    working_capital:,
    items:,
  ))
}
