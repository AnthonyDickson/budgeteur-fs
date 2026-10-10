//// The lifecycle of data a page fetches from the server.

pub type Remote(a) {
  /// No response yet.
  Loading
  Loaded(a)
  /// The fetch failed; the page offers a retry.
  Failed
}
