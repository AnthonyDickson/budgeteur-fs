import gleam/string
import gleam/uri
import youid/uuid.{type Uuid}

/// A route to a page in this SPA.
pub type Route {
  Dashboard
  Transactions
  QuickTagging
  Tagging
  BalanceSheet
  /// An item's observation history.
  ItemHistory(id: Uuid)
  /// An account's observation history.
  AccountHistory(id: Uuid)
  NotFound
}

/// Convert a route into a path string.
pub fn to_string(route: Route) -> String {
  case route {
    Dashboard -> "/"
    Transactions -> "/transactions"
    QuickTagging -> "/quick-tagging"
    Tagging -> "/tagging"
    BalanceSheet -> "/balance-sheet"
    ItemHistory(id:) -> "/balance-sheet/items/" <> uuid.to_string(id)
    AccountHistory(id:) -> "/balance-sheet/accounts/" <> uuid.to_string(id)
    NotFound -> "/not_found"
  }
}

/// The header section a route belongs to: a line's history is part of the
/// balance sheet.
pub fn section(route: Route) -> Route {
  case route {
    ItemHistory(..) | AccountHistory(..) -> BalanceSheet
    _ -> route
  }
}

fn from_path_segments(path: List(String)) -> Route {
  case path {
    [] -> Dashboard
    ["transactions"] -> Transactions
    ["quick-tagging"] -> QuickTagging
    ["tagging"] -> Tagging
    ["balance-sheet"] -> BalanceSheet
    ["balance-sheet", "items", id] -> with_id(id, ItemHistory)
    ["balance-sheet", "accounts", id] -> with_id(id, AccountHistory)
    _ -> NotFound
  }
}

fn with_id(id: String, route: fn(Uuid) -> Route) -> Route {
  case uuid.from_string(id) {
    Ok(id) -> route(id)
    Error(Nil) -> NotFound
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
