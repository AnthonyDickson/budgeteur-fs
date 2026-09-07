import lustre/attribute.{type Attribute}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

/// Stateless Tailwind chrome shared by the feature modal dialogs. Scoped to
/// what a modal dialog needs: the `<dialog>` element, its buttons, and its
/// message banners. Field widgets stay per-feature.
/// Classes for a modal `<dialog>` element.
pub const dialog_class = "mx-auto my-auto w-full max-w-md rounded-lg border border-gray-200 bg-white p-6 shadow-xl backdrop:bg-gray-900/50"

/// Classes for a modal dialog's secondary (cancel) button.
const cancel_button_class = "rounded-md border border-gray-300 bg-white px-4 py-2 text-sm font-medium text-gray-700 "
  <> "hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-gray-500 focus:ring-offset-2 "
  <> "disabled:cursor-not-allowed disabled:bg-gray-100 disabled:text-gray-400 disabled:hover:bg-gray-100"

/// Classes for a dialog's primary submit button.
const submit_button_class = "inline-flex items-center justify-center gap-2 rounded-md bg-indigo-600 px-4 py-2 text-sm font-medium "
  <> "text-white hover:bg-indigo-500 focus:outline-none focus:ring-2 focus:ring-indigo-500 "
  <> "focus:ring-offset-2 disabled:cursor-not-allowed disabled:bg-gray-400 disabled:hover:bg-gray-400"

/// Classes for a dialog's destructive confirm (delete) button.
const delete_button_class = "inline-flex items-center justify-center gap-2 rounded-md bg-red-600 px-4 py-2 text-sm font-medium "
  <> "text-white hover:bg-red-500 focus:outline-none focus:ring-2 focus:ring-red-500 "
  <> "focus:ring-offset-2 disabled:cursor-not-allowed disabled:bg-gray-400 disabled:hover:bg-gray-400"

/// The `closedby` value for a modal dialog: "any" allows dismissal via
/// Escape or an outside click, while "none" locks the dialog while a request
/// is in flight so it cannot be dismissed mid-request.
pub fn closedby_value(busy: Bool) -> String {
  case busy {
    True -> "none"
    False -> "any"
  }
}

/// Attributes shared by every feature modal dialog: its id (which the
/// show/close dialog effects target), its `data-testid`, the shared dialog
/// classes, and the `closedby` value derived from whether a request is in
/// flight.
pub fn dialog_attributes(
  id: String,
  testid: String,
  busy: Bool,
) -> List(Attribute(msg)) {
  [
    attribute.id(id),
    attribute.attribute("data-testid", testid),
    attribute.class(dialog_class),
    attribute.attribute("closedby", closedby_value(busy)),
  ]
}

/// The inline spinner shown inside a busy button.
pub fn spinner() -> Element(msg) {
  html.span(
    [
      attribute.attribute("aria-hidden", "true"),
      attribute.class(
        "h-4 w-4 animate-spin rounded-full border-2 border-white/40 border-t-white",
      ),
    ],
    [],
  )
}

/// A secondary button that closes the dialog.
pub fn cancel_button(
  testid testid: String,
  disabled disabled: Bool,
  on_click on_click: msg,
) -> Element(msg) {
  html.button(
    [
      attribute.type_("button"),
      attribute.attribute("data-testid", testid),
      attribute.class(cancel_button_class),
      attribute.disabled(disabled),
      event.on_click(on_click),
    ],
    [html.text("Cancel")],
  )
}

/// A dialog's primary submit button, showing a spinner and `busy_label` while
/// a request is in flight.
pub fn submit_button(
  testid testid: String,
  idle_label idle_label: String,
  busy_label busy_label: String,
  busy busy: Bool,
  disabled disabled: Bool,
) -> Element(msg) {
  html.button(
    [
      attribute.type_("submit"),
      attribute.attribute("data-testid", testid),
      attribute.class(submit_button_class),
      attribute.disabled(disabled || busy),
    ],
    case busy {
      True -> [spinner(), html.text(busy_label)]
      False -> [html.text(idle_label)]
    },
  )
}

/// The destructive confirm button of a delete dialog, showing a spinner while
/// the delete request is in flight.
pub fn delete_button(
  testid testid: String,
  busy busy: Bool,
  on_click on_click: msg,
) -> Element(msg) {
  html.button(
    [
      attribute.type_("button"),
      attribute.attribute("data-testid", testid),
      attribute.class(delete_button_class),
      attribute.disabled(busy),
      event.on_click(on_click),
    ],
    case busy {
      True -> [spinner(), html.text("Deleting...")]
      False -> [html.text("Delete")]
    },
  )
}

/// A red banner reporting an API-level failure. `extra_class` carries any
/// spacing the surrounding flow needs (e.g. "mb-4" after paragraphs).
pub fn error_banner(
  testid testid: String,
  message message: String,
  extra_class extra_class: String,
) -> Element(msg) {
  html.p(
    [
      attribute.attribute("role", "alert"),
      attribute.attribute("data-testid", testid),
      attribute.class(
        extra_class
        <> " rounded-md border border-red-200 bg-red-50 px-3 py-2 text-sm text-red-700",
      ),
    ],
    [html.text(message)],
  )
}

/// A small inline error message shown under an invalid field inside a modal
/// form.
pub fn form_error_message(text: String) -> Element(msg) {
  html.p([attribute.class("mt-1 text-sm text-red-600")], [html.text(text)])
}
