import gleam/string
import gleam/uri
import youid/uuid.{type Uuid}

/// A route to a page in this SPA.
pub type Route {
  TransactionsViewAll
  TransactionsViewOne(id: Uuid)
  TransactionsNew
  TransactionsEdit(id: Uuid)
  NotFound
}

/// Convert a route into a path string.
pub fn to_string(route: Route) -> String {
  case route {
    TransactionsViewAll -> "/transactions"
    TransactionsViewOne(id:) -> "/transactions/" <> uuid.format(id, uuid.String)
    TransactionsNew -> "/transactions/new"
    TransactionsEdit(id:) ->
      "/transactions/edit/" <> uuid.format(id, uuid.String)
    NotFound -> "/not_found"
  }
}

fn from_path_segments(path: List(String)) -> Route {
  case path {
    ["transactions"] -> TransactionsViewAll
    ["transactions", "new"] -> TransactionsNew
    ["transactions", id] ->
      case uuid.from_string(id) {
        Ok(id) -> TransactionsViewOne(id:)
        Error(Nil) -> NotFound
      }
    ["transactions", "edit", id] ->
      case uuid.from_string(id) {
        Ok(id) -> TransactionsEdit(id:)
        Error(Nil) -> NotFound
      }
    _ -> NotFound
  }
}

/// Get the SPA route from the path segment of a URL.
/// Defaults to `NotFound` if given an unrecognised path or a path with an incorrectly formatted UUID.
pub fn from_string(path: String) -> Route {
  path
  |> string.lowercase
  |> uri.path_segments
  |> from_path_segments
}
