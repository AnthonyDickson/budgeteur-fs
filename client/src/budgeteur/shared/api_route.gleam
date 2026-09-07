import youid/uuid.{type Uuid}

pub type ApiRoute {
  GetAllTransactions
  GetTransaction(id: Uuid)
  CreateTransaction
  UpdateTransaction(id: Uuid)
  DeleteTransaction(id: Uuid)
  GetTaggingData
  CreateTag
  UpdateTag(id: Uuid)
  DeleteTag(id: Uuid)
  CreateRule
  UpdateRule(id: Uuid)
  DeleteRule(id: Uuid)
}

const api_prefix = "/api"

pub fn to_string(route: ApiRoute) -> String {
  case route {
    GetAllTransactions | CreateTransaction -> api_prefix <> "/transactions"
    GetTransaction(id:) | UpdateTransaction(id:) | DeleteTransaction(id:) ->
      api_prefix <> "/transactions/" <> uuid.to_string(id)
    GetTaggingData -> api_prefix <> "/tagging"
    CreateTag -> api_prefix <> "/tags"
    UpdateTag(id:) | DeleteTag(id:) ->
      api_prefix <> "/tags/" <> uuid.to_string(id)
    CreateRule -> api_prefix <> "/rules"
    UpdateRule(id:) | DeleteRule(id:) ->
      api_prefix <> "/rules/" <> uuid.to_string(id)
  }
}
