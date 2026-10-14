import budgeteur/balance_sheet_page/account.{type Account, type AccountLine}
import budgeteur/balance_sheet_page/balance_sheet_item.{type BalanceSheetItem}
import budgeteur/shared/date
import budgeteur/shared/money
import gleam/dynamic/decode
import gleam/option.{type Option, None}
import gleam/time/calendar.{type Date}

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
    closed_accounts: List(ClosedAccount),
  )
}

/// A closed account, with any transactions dated after its close date.
pub type ClosedAccount {
  ClosedAccount(
    account: Account,
    // A closed account should have none, so they suggest the close date is
    // wrong. See decision 4 in docs/reports.md.
    transactions_after_close: Option(TransactionsAfterClose),
  )
}

pub type TransactionsAfterClose {
  TransactionsAfterClose(count: Int, latest: Date)
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
    decode.list(closed_account_decoder()),
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

fn closed_account_decoder() -> decode.Decoder(ClosedAccount) {
  use account <- decode.then(account.decoder())
  use transactions_after_close <- decode.optional_field(
    "transactionsAfterClose",
    None,
    decode.optional(transactions_after_close_decoder()),
  )
  decode.success(ClosedAccount(account:, transactions_after_close:))
}

/// The summary the balance sheet and account reads give a closed account's
/// transactions after its close date.
pub fn transactions_after_close_decoder() -> decode.Decoder(
  TransactionsAfterClose,
) {
  use count <- decode.field("count", decode.int)
  use latest <- decode.field("latest", date.decoder())
  decode.success(TransactionsAfterClose(count:, latest:))
}
