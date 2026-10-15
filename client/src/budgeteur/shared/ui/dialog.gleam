import budgeteur/shared/ui/button
import gleam/dynamic/decode
import gleam/list
import gleam/option.{type Option}
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

/// Stateless Tailwind chrome shared by the feature modal dialogs. Scoped to
/// what a modal dialog needs: the `<dialog>` element, its buttons, and its
/// message banners. Field widgets stay per-feature.
/// Classes for the `<dialog>` element of `dialog`.
const dialog_class = "mx-auto my-auto w-full max-w-md rounded-lg border border-gray-200 bg-white p-6 shadow-xl backdrop:bg-gray-900/50"

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

/// Extra classes applied to a text input or select that currently holds an
/// error, turning its border red. Combined with the field's base classes via
/// `attribute.classes`, e.g.
/// `[attribute.classes([#(dialog.error_border_style, field.has_error(f))])]`.
pub const error_border_style = "border-red-400 focus:border-red-500 focus:outline-none focus:ring-1 focus:ring-red-500"

/// A radio group for a closed set of options, e.g. an item's term or a tag's kind.
pub fn radio_group(
  legend legend: String,
  testid testid: String,
  disabled disabled: Bool,
  options options: List(#(String, String, Bool, fn(String) -> msg)),
) -> Element(msg) {
  html.fieldset([attribute.class("block")], [
    html.legend(
      [attribute.class("mb-1 block text-sm font-medium text-gray-700")],
      [html.text(legend)],
    ),
    html.div(
      [attribute.class("grid grid-cols-2 gap-2")],
      list.map(options, fn(option) {
        let #(value, label, selected, on_change) = option

        let option_class = case selected {
          True -> "border-indigo-600 bg-indigo-50 font-medium text-indigo-700"
          False -> "border-gray-300 bg-white text-gray-700 hover:bg-gray-50"
        }

        let option_class = case disabled {
          True -> option_class <> " cursor-not-allowed opacity-60"
          False -> option_class
        }

        html.label(
          [
            attribute.class(
              "flex cursor-pointer items-center gap-2 rounded-md border px-3 py-2 text-sm "
              <> option_class,
            ),
          ],
          [
            html.input([
              attribute.type_("radio"),
              attribute.name(testid),
              attribute.value(value),
              attribute.checked(selected),
              attribute.attribute("data-testid", testid <> "-" <> value),
              attribute.class(
                "h-4 w-4 border-gray-300 text-indigo-600 focus:ring-indigo-500 disabled:cursor-not-allowed",
              ),
              attribute.disabled(disabled),
              event.on_change(on_change),
            ]),
            html.text(label),
          ],
        )
      }),
    ),
  ])
}
