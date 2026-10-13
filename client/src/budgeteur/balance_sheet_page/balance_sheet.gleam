import budgeteur/balance_sheet_page/account.{type Account, type AccountLine}
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
    // Accounts with a known balance, as lines.
    accounts: List(AccountLine),
    // Accounts whose balance is unknown, left out of the totals.
    unknown_balances: List(Account),
    // Items that were sold or repaid, left out of the sheet.
    closed_items: List(BalanceSheetItem),
    // Accounts that were closed, left out of the sheet.
    closed_accounts: List(Account),
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
  use accounts <- decode.field("accounts", decode.list(account.line_decoder()))
  use unknown_balances <- decode.field(
    "unknownBalances",
    decode.list(account.decoder()),
  )
  use closed_items <- decode.field(
    "closedItems",
    decode.list(balance_sheet_item.decoder()),
  )
  use closed_accounts <- decode.field(
    "closedAccounts",
    decode.list(account.decoder()),
  )
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
    accounts:,
    unknown_balances:,
    closed_items:,
    closed_accounts:,
  ))
}
