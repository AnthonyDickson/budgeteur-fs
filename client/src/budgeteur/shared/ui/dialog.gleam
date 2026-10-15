//// Stateless chrome shared by the feature modal dialogs: the `<dialog>`
//// element, its footer, and its standard buttons. Fields and banners come from
//// the `input` and `banner` modules.

import budgeteur/shared/ui/button
import gleam/dynamic/decode
import gleam/option.{type Option}
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

/// Classes for the `<dialog>` element of `dialog`.
const dialog_class = "mx-auto my-auto w-full max-w-md rounded-lg border border-border bg-surface p-6 text-fg shadow-xl backdrop:bg-backdrop/50"

/// Define the `<modal-dialog>` custom element that `dialog` renders. Call once
/// before the app starts.
@external(javascript, "./modal_dialog_ffi.mjs", "registerModalDialog")
pub fn register() -> Nil

/// A modal dialog, open for as long as the view renders it: render it while
/// the modal is open and `element.none()` otherwise. The dialog opens as a
/// modal when it is inserted and closes when it is removed, so the model is
/// the only source of truth for whether it is open.
///
/// `on_dismiss` is sent when the browser closes the dialog itself (Escape or
/// an outside click). While `busy` (a request is in flight) the dialog cannot
/// be dismissed.
pub fn dialog(
  testid testid: String,
  busy busy: Bool,
  on_dismiss on_dismiss: msg,
  children children: List(Element(msg)),
) -> Element(msg) {
  let closedby = case busy {
    True -> "none"
    False -> "any"
  }

  element.element(
    "modal-dialog",
    [event.on("dismiss", decode.success(on_dismiss))],
    [
      html.dialog(
        [
          attribute.attribute("data-testid", testid),
          attribute.class(dialog_class),
          attribute.attribute("closedby", closedby),
        ],
        children,
      ),
    ],
  )
}

/// A secondary button that closes the dialog.
pub fn cancel_button(
  testid testid: String,
  disabled disabled: Bool,
  on_click on_click: msg,
) -> Element(msg) {
  button.view(
    button.Secondary,
    button.Regular,
    [
      attribute.attribute("data-testid", testid),
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
  button.submit(
    button.Primary,
    button.Regular,
    [
      attribute.attribute("data-testid", testid),
      attribute.disabled(disabled || busy),
    ],
    case busy {
      True -> [button.spinner(), html.text(busy_label)]
      False -> [html.text(idle_label)]
    },
  )
}

/// The primary button of a confirmation dialog that closes when confirmed.
pub fn confirm_button(
  testid testid: String,
  label label: String,
  on_click on_click: msg,
) -> Element(msg) {
  button.view(
    button.Primary,
    button.Regular,
    [attribute.attribute("data-testid", testid), event.on_click(on_click)],
    [html.text(label)],
  )
}

/// The destructive confirm button of a delete dialog, showing a spinner while
/// the delete request is in flight.
pub fn delete_button(
  testid testid: String,
  busy busy: Bool,
  on_click on_click: msg,
) -> Element(msg) {
  button.view(
    button.Danger,
    button.Regular,
    [
      attribute.attribute("data-testid", testid),
      attribute.disabled(busy),
      event.on_click(on_click),
    ],
    case busy {
      True -> [button.spinner(), html.text("Deleting...")]
      False -> [html.text("Delete")]
    },
  )
}

/// The footer of a form dialog: an optional button on the left, such as a
/// delete or a switch to another form, and the cancel and submit buttons on the
/// right.
pub fn form_footer(
  leading leading: Option(Element(msg)),
  cancel cancel: Element(msg),
  submit submit: Element(msg),
) -> Element(msg) {
  html.div([attribute.class("flex items-center gap-3 pt-2")], [
    option.unwrap(leading, element.none()),
    html.div([attribute.class("ml-auto flex gap-3")], [cancel, submit]),
  ])
}

/// An edit dialog's delete button. The page closes the dialog and opens the
/// delete confirmation in its place.
pub fn delete_request_button(
  testid testid: String,
  disabled disabled: Bool,
  on_click on_click: msg,
) -> Element(msg) {
  button.view(
    button.DangerText,
    button.Regular,
    [
      attribute.attribute("data-testid", testid),
      attribute.disabled(disabled),
      event.on_click(on_click),
    ],
    [html.text("Delete")],
  )
}

/// A dialog's secondary text button, for an action other than submitting or
/// cancelling.
pub fn text_button(
  label label: String,
  testid testid: String,
  disabled disabled: Bool,
  on_click on_click: msg,
) -> Element(msg) {
  button.view(
    button.Text,
    button.Regular,
    [
      attribute.attribute("data-testid", testid),
      attribute.disabled(disabled),
      event.on_click(on_click),
    ],
    [html.text(label)],
  )
}
