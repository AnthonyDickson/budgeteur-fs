import gleam/string
import gleam/uri

/// A route to a page in this SPA.
pub type Route {
  Dashboard
  Transactions
  Tagging
  BalanceSheet
  NotFound
}

/// Convert a route into a path string.
pub fn to_string(route: Route) -> String {
  case route {
    Dashboard -> "/"
    Transactions -> "/transactions"
    Tagging -> "/tagging"
    BalanceSheet -> "/balance-sheet"
    NotFound -> "/not_found"
  }
}

fn from_path_segments(path: List(String)) -> Route {
  case path {
    [] -> Dashboard
    ["transactions"] -> Transactions
    ["tagging"] -> Tagging
    ["balance-sheet"] -> BalanceSheet
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
