pub type ApiRoute {
  GetAllTransactions
}

const api_prefix = "/api"

pub fn to_string(route: ApiRoute) -> String {
  case route {
    GetAllTransactions -> api_prefix <> "/transactions"
  }
}
