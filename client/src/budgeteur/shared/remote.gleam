//// The lifecycle of data a page fetches from the server.

pub type Remote(a) {
  /// No response yet.
  Loading
  Loaded(a)
  /// The fetch failed; the page offers a retry.
  Failed
}

/// Apply `f` to loaded data. `Loading` and `Failed` are returned unchanged, so a
/// change made while nothing is loaded is dropped; the next fetch brings it in.
pub fn map(remote: Remote(a), f: fn(a) -> b) -> Remote(b) {
  case remote {
    Loaded(value) -> Loaded(f(value))
    Loading -> Loading
    Failed -> Failed
  }
}

/// Combine two fetches into one. `Loading` until both have settled, so a retry
/// offered on failure never overlaps a fetch still in flight; then `Failed` if
/// either failed.
pub fn both(a: Remote(a), b: Remote(b)) -> Remote(#(a, b)) {
  case a, b {
    Loaded(a), Loaded(b) -> Loaded(#(a, b))
    Loading, _ | _, Loading -> Loading
    Failed, _ | _, Failed -> Failed
  }
}

/// The loaded data, or `default` while loading or after a failure.
pub fn unwrap(remote: Remote(a), or default: a) -> a {
  case remote {
    Loaded(value) -> value
    Loading | Failed -> default
  }
}
