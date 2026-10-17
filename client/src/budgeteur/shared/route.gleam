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
  /// An item's details page, with its observation history.
  ItemDetails(id: Uuid)
  /// An account's details page, with its observation history.
  AccountDetails(id: Uuid)
  Reports
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
    ItemDetails(id:) -> "/balance-sheet/items/" <> uuid.to_string(id)
    AccountDetails(id:) -> "/balance-sheet/accounts/" <> uuid.to_string(id)
    Reports -> "/reports"
    NotFound -> "/not_found"
  }
}

/// The name of the page at a route, as the header nav and the browser title show
/// it. A line's details page is part of the balance sheet.
pub fn name(route: Route) -> String {
  case route {
    Dashboard -> "Dashboard"
    Transactions -> "Transactions"
    QuickTagging -> "Quick tagging"
    Tagging -> "Tags & Rules"
    BalanceSheet | ItemDetails(..) | AccountDetails(..) -> "Balance Sheet"
    Reports -> "Reports"
    NotFound -> "Page Not Found"
  }
}

/// The browser title for a route: the page's name, then the app's.
pub fn title(route: Route) -> String {
  name(route) <> " | Budgeteur"
}

/// The header section a route belongs to: a line's details page is part of the
/// balance sheet.
pub fn section(route: Route) -> Route {
  case route {
    ItemDetails(..) | AccountDetails(..) -> BalanceSheet
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
    ["balance-sheet", "items", id] -> with_id(id, ItemDetails)
    ["balance-sheet", "accounts", id] -> with_id(id, AccountDetails)
    ["reports"] -> Reports
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
