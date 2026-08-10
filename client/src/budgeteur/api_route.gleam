import youid/uuid.{type Uuid}

pub type ApiRoute {
  GetAllTransactions
  GetTransaction(id: Uuid)
  CreateTransaction
}

const api_prefix = "/api"

pub fn to_string(route: ApiRoute) -> String {
  case route {
    GetAllTransactions -> api_prefix <> "/transactions"
    GetTransaction(id:) -> api_prefix <> "/transactions/" <> uuid.to_string(id)
    CreateTransaction -> api_prefix <> "/transactions"
  }
}
