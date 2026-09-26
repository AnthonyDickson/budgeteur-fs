import budgeteur/balance_sheet_page/balance_sheet.{type BalanceSheet}
import gleam/dynamic/decode
import gleam/json

/// localStorage key for the cached balance sheet snapshot.
pub const storage_key = "budgeteur.balance-sheet"

pub type BalanceSheetPageData {
  BalanceSheetPageData(sheet: BalanceSheet)
}

pub fn decoder() -> decode.Decoder(BalanceSheetPageData) {
  use sheet <- decode.field("sheet", balance_sheet.decoder())
  decode.success(BalanceSheetPageData(sheet:))
}

pub fn to_json(data: BalanceSheetPageData) -> json.Json {
  let BalanceSheetPageData(sheet:) = data
  json.object([#("sheet", balance_sheet.to_json(sheet))])
}

pub fn to_string(data: BalanceSheetPageData) -> String {
  to_json(data) |> json.to_string
}
