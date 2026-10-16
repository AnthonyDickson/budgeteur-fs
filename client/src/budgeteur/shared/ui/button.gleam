//// Buttons, and links styled as buttons, in the app's colour roles. Callers
//// add behaviour attributes (event handlers, test ids, `disabled`) and layout
//// classes such as a margin; Lustre merges the classes with the button's own.

import lustre/attribute.{type Attribute}
import lustre/element.{type Element}
import lustre/element/html

/// A button's look, by what it does.
pub type Variant {
  /// The main action of a page or dialog.
  Primary
  /// Any other action, e.g. cancel or a toolbar action.
  Secondary
  /// Confirms a destructive action.
  Danger
  /// Starts a destructive action without confirming it, e.g. opening a delete
  /// confirmation.
  DangerText
  /// A minor action shown as text.
  Text
}

pub type Size {
  Regular
  /// For toolbars, beside compact selects.
  Small
}

/// A `<button type="button">`.
pub fn view(
  variant: Variant,
  size: Size,
  attributes: List(Attribute(msg)),
  children: List(Element(msg)),
) -> Element(msg) {
  html.button(
    [
      attribute.type_("button"),
      attribute.class(class(variant, size)),
      ..attributes
    ],
    children,
  )
}

/// A `<button type="submit">`, the submit button of a form.
pub fn submit(
  variant: Variant,
  size: Size,
  attributes: List(Attribute(msg)),
  children: List(Element(msg)),
) -> Element(msg) {
  html.button(
    [
      attribute.type_("submit"),
      attribute.class(class(variant, size)),
      ..attributes
    ],
    children,
  )
}

/// A link styled as a button, for an action that goes to another page.
pub fn link(
  variant: Variant,
  size: Size,
  attributes: List(Attribute(msg)),
  children: List(Element(msg)),
) -> Element(msg) {
  html.a([attribute.class(class(variant, size)), ..attributes], children)
}

/// The label of a button that starts a request: `label`, or a spinner and
/// `busy_label` while the request is in flight. Both share one grid cell and
/// the one not shown is invisible, so the button keeps the width of the wider
/// and the layout around it does not shift, e.g. a row of buttons wrapping onto
/// another line. Invisible text is left out of the button's accessible name.
pub fn busy_label(
  label label: String,
  busy_label busy_label: String,
  busy busy: Bool,
) -> Element(msg) {
  let shown = fn(visible) {
    case visible {
      True -> "[grid-area:1/1]"
      False -> "[grid-area:1/1] invisible"
    }
  }

  html.span([attribute.class("grid place-items-center")], [
    html.span([attribute.class(shown(!busy))], [html.text(label)]),
    html.span([attribute.class("flex items-center gap-2 " <> shown(busy))], [
      spinner(),
      html.text(busy_label),
    ]),
  ])
}

/// The inline spinner shown inside a busy button, in the button's text colour.
fn spinner() -> Element(msg) {
  html.span(
    [
      attribute.attribute("aria-hidden", "true"),
      attribute.class(
        "h-4 w-4 animate-spin rounded-full border-2 border-current/40 border-t-current",
      ),
    ],
    [],
  )
}

/// Hover styles apply only while enabled, so a disabled button keeps its
/// colours, faded.
fn class(variant: Variant, size: Size) -> String {
  let size_class = case size {
    Regular -> "px-4 py-2"
    Small -> "px-3 py-1.5"
  }

  let variant_class = case variant {
    Primary ->
      "bg-primary text-on-primary not-disabled:hover:bg-primary-hover focus:ring-primary"
    Secondary ->
      "border border-border-input bg-surface text-fg not-disabled:hover:bg-surface-hover focus:ring-primary"
    Danger ->
      "bg-danger text-on-primary not-disabled:hover:bg-danger-hover focus:ring-danger"
    DangerText ->
      "text-danger not-disabled:hover:bg-surface-hover focus:ring-danger"
    Text ->
      "text-fg-muted not-disabled:hover:bg-surface-hover not-disabled:hover:text-fg focus:ring-primary"
  }

  "inline-flex items-center justify-center gap-2 rounded-md text-sm font-medium "
  <> "focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-offset-surface "
  <> "disabled:cursor-not-allowed disabled:opacity-50 "
  <> size_class
  <> " "
  <> variant_class
}
