import gleam/string
import gleam/uri

/// A route to a page in this SPA.
pub type Route {
  Transactions
  TagsAndRules
  NotFound
}

/// Convert a route into a path string.
pub fn to_string(route: Route) -> String {
  case route {
    Transactions -> "/transactions"
    TagsAndRules -> "/tags-and-rules"
    NotFound -> "/not_found"
  }
}

fn from_path_segments(path: List(String)) -> Route {
  case path {
    ["transactions"] -> Transactions
    ["tags-and-rules"] -> TagsAndRules
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
