import youid/uuid.{type Uuid}

pub type ApiRoute {
  GetAllTransactions
  GetTransaction(id: Uuid)
  CreateTransaction
  UpdateTransaction(id: Uuid)
  DeleteTransaction(id: Uuid)
  GetTagsAndRules
  CreateTag
  UpdateTag(id: Uuid)
  CreateRule
  UpdateRule(id: Uuid)
}

const api_prefix = "/api"

pub fn to_string(route: ApiRoute) -> String {
  case route {
    GetAllTransactions | CreateTransaction -> api_prefix <> "/transactions"
    GetTransaction(id:) | UpdateTransaction(id:) | DeleteTransaction(id:) ->
      api_prefix <> "/transactions/" <> uuid.to_string(id)
    GetTagsAndRules -> api_prefix <> "/tags-and-rules"
    CreateTag -> api_prefix <> "/tags"
    UpdateTag(id:) -> api_prefix <> "/tags/" <> uuid.to_string(id)
    CreateRule -> api_prefix <> "/rules"
    UpdateRule(id:) -> api_prefix <> "/rules/" <> uuid.to_string(id)
  }
}
