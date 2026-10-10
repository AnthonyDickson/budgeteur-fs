import budgeteur/shared/date
import gleam/time/calendar.{type Date}
import youid/uuid.{type Uuid}

pub type ApiRoute {
  GetAllTransactions
  GetTransaction(id: Uuid)
  CreateTransaction
  UpdateTransaction(id: Uuid)
  DeleteTransaction(id: Uuid)
  CreateTag
  GetAllTags
  UpdateTag(id: Uuid)
  DeleteTag(id: Uuid)
  CreateRule
  GetAllRules
  UpdateRule(id: Uuid)
  DeleteRule(id: Uuid)
  GetBalanceSheet
  CreateBalanceSheetItem
  UpdateBalanceSheetItem(id: Uuid)
  DeleteBalanceSheetItem(id: Uuid)
  GetIncomeStatement(from: Date, to: Date)
}

const api_prefix = "/api"

pub fn to_string(route: ApiRoute) -> String {
  case route {
    GetAllTransactions | CreateTransaction -> api_prefix <> "/transactions"
    GetTransaction(id:) | UpdateTransaction(id:) | DeleteTransaction(id:) ->
      api_prefix <> "/transactions/" <> uuid.to_string(id)
    CreateTag | GetAllTags -> api_prefix <> "/tags"
    UpdateTag(id:) | DeleteTag(id:) ->
      api_prefix <> "/tags/" <> uuid.to_string(id)
    CreateRule | GetAllRules -> api_prefix <> "/rules"
    UpdateRule(id:) | DeleteRule(id:) ->
      api_prefix <> "/rules/" <> uuid.to_string(id)
    GetBalanceSheet -> api_prefix <> "/balance-sheet"
    CreateBalanceSheetItem -> api_prefix <> "/balance-sheet/items"
    UpdateBalanceSheetItem(id:) | DeleteBalanceSheetItem(id:) ->
      api_prefix <> "/balance-sheet/items/" <> uuid.to_string(id)
    GetIncomeStatement(from:, to:) ->
      api_prefix
      <> "/income-statement?from="
      <> date.format(from)
      <> "&to="
      <> date.format(to)
  }
}
