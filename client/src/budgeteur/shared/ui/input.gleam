//// Form controls in the app's colour roles: text inputs, selects, checkboxes,
//// radio groups, and their labels and error messages. Callers add behaviour
//// attributes (type, value, event handlers, test ids, `disabled`), and mark a
//// field holding an error with `invalid`.

import gleam/list
import lustre/attribute.{type Attribute}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

/// An invalid field is styled from its `aria-invalid` attribute, so the state
/// screen readers announce is the state the field shows.
const field_class = "block w-full rounded-md border border-border-input bg-surface px-3 py-2 text-sm text-fg shadow-sm "
  <> "placeholder:text-fg-subtle focus:border-primary focus:outline-none focus:ring-1 focus:ring-primary "
  <> "aria-[invalid=true]:border-danger aria-[invalid=true]:focus:ring-danger "
  <> "disabled:cursor-not-allowed disabled:bg-surface-hover disabled:text-fg-subtle"

/// An `<input>` holding text, e.g. a text, search, or date input. The caller
/// sets its type.
pub fn text(attributes: List(Attribute(msg))) -> Element(msg) {
  html.input([attribute.class(field_class), ..attributes])
}

pub fn select(
  attributes: List(Attribute(msg)),
  children: List(Element(msg)),
) -> Element(msg) {
  html.select([attribute.class(field_class), ..attributes], children)
}

pub fn checkbox(attributes: List(Attribute(msg))) -> Element(msg) {
  html.input([
    attribute.type_("checkbox"),
    attribute.class("h-4 w-4 accent-primary disabled:cursor-not-allowed"),
    ..attributes
  ])
}

/// Marks a text input or select as holding an error.
pub fn invalid(is_invalid: Bool) -> Attribute(msg) {
  case is_invalid {
    True -> attribute.attribute("aria-invalid", "true")
    False -> attribute.none()
  }
}

/// The text above a field, inside the field's `<label>`.
pub fn label(text: String) -> Element(msg) {
  html.span([attribute.class("mb-1 block text-sm font-medium text-fg-muted")], [
    html.text(text),
  ])
}

/// A field's error message, shown below it.
pub fn error_message(text: String) -> Element(msg) {
  html.p([attribute.class("mt-1 text-sm text-danger")], [html.text(text)])
}

/// A radio group for a closed set of options, e.g. an item's term or a tag's
/// kind. Each option is a value, its label, whether it is selected, and the
/// message sent when it is chosen.
pub fn radio_group(
  legend legend: String,
  testid testid: String,
  disabled disabled: Bool,
  options options: List(#(String, String, Bool, fn(String) -> msg)),
) -> Element(msg) {
  html.fieldset([attribute.class("block")], [
    html.legend(
      [attribute.class("mb-1 block text-sm font-medium text-fg-muted")],
      [html.text(legend)],
    ),
    html.div(
      [attribute.class("grid grid-cols-2 gap-2")],
      list.map(options, fn(option) {
        let #(value, label, selected, on_change) = option

        let option_class = case selected {
          True -> "border-primary bg-primary-tint font-medium text-fg"
          False ->
            "border-border-input bg-surface text-fg hover:bg-surface-hover"
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
                "h-4 w-4 accent-primary disabled:cursor-not-allowed",
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
