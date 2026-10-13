import budgeteur/shared/date
import gleam/time/calendar.{type Date}
import gleam/uri
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
  CreateAccount
  GetAllAccounts
  UpdateAccount(id: Uuid)
  DeleteAccount(id: Uuid)
  RecordBalance(account_id: Uuid)
  RecordItemValue(item_id: Uuid)
  GetBalanceSheetItem(id: Uuid)
  GetItemObservations(item_id: Uuid)
  DeleteItemObservation(item_id: Uuid, as_of: Date)
  GetAccount(id: Uuid)
  GetAccountObservations(account_id: Uuid)
  DeleteAccountObservation(account_id: Uuid, as_of: Date)
  GetIncomeStatement(from: Date, to: Date)
  RunAutoTag
  GetRuleMatches(pattern: String)
  ImportStatements
  GetQuickTagQueue
  QuickTagTransaction(id: Uuid)
  DismissTransaction(id: Uuid)
  MarkTransfer(id: Uuid)
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
    GetBalanceSheetItem(id:)
    | UpdateBalanceSheetItem(id:)
    | DeleteBalanceSheetItem(id:) ->
      api_prefix <> "/balance-sheet/items/" <> uuid.to_string(id)
    RecordItemValue(item_id:) | GetItemObservations(item_id:) ->
      api_prefix
      <> "/balance-sheet/items/"
      <> uuid.to_string(item_id)
      <> "/observations"
    DeleteItemObservation(item_id:, as_of:) ->
      api_prefix
      <> "/balance-sheet/items/"
      <> uuid.to_string(item_id)
      <> "/observations/"
      <> date.format(as_of)
    DeleteAccountObservation(account_id:, as_of:) ->
      api_prefix
      <> "/accounts/"
      <> uuid.to_string(account_id)
      <> "/observations/"
      <> date.format(as_of)
    CreateAccount | GetAllAccounts -> api_prefix <> "/accounts"
    GetAccount(id:) | UpdateAccount(id:) | DeleteAccount(id:) ->
      api_prefix <> "/accounts/" <> uuid.to_string(id)
    RecordBalance(account_id:) | GetAccountObservations(account_id:) ->
      api_prefix
      <> "/accounts/"
      <> uuid.to_string(account_id)
      <> "/observations"
    GetIncomeStatement(from:, to:) ->
      api_prefix
      <> "/income-statement?from="
      <> date.format(from)
      <> "&to="
      <> date.format(to)
    RunAutoTag -> api_prefix <> "/auto-tag"
    ImportStatements -> api_prefix <> "/imports"
    GetQuickTagQueue -> api_prefix <> "/quick-tag"
    QuickTagTransaction(id:) | DismissTransaction(id:) ->
      api_prefix <> "/quick-tag/" <> uuid.to_string(id)
    MarkTransfer(id:) ->
      api_prefix <> "/quick-tag/" <> uuid.to_string(id) <> "/transfer"
    GetRuleMatches(pattern:) ->
      api_prefix
      <> "/auto-tag/matches?"
      <> uri.query_to_string([#("pattern", pattern)])
  }
}
