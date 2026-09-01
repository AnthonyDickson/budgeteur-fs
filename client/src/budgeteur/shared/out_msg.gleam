import budgeteur/shared/toast.{type ToastLevel}
import gleam/option.{type Option}

/// Messages that are sent from child modules to the parent (root) module.
pub type OutMsg {
  /// Request the root app to display a toast and optionally dismiss it
  /// automatically after `dismiss_after_ms` milliseconds.
  /// If `dismiss_after_ms` is `None`, then the toast must be manually dismissed
  /// by the user.
  PageRequestedToast(
    title: String,
    body: String,
    level: ToastLevel,
    dismiss_after_ms: Option(Int),
  )
}
