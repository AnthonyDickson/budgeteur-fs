//// Messages about the page or a form, in a status tint with normal text (see
//// decision 7 in docs/styling.md). Callers add behaviour attributes and
//// layout classes such as a margin.

import lustre/attribute.{type Attribute}
import lustre/element.{type Element}
import lustre/element/html

pub type Level {
  /// Something failed, e.g. a save. Announced to screen readers when shown.
  Error
  /// Something the user should know about the content, e.g. figures left out.
  Warning
}

pub fn view(
  level: Level,
  attributes: List(Attribute(msg)),
  children: List(Element(msg)),
) -> Element(msg) {
  let #(level_class, role) = case level {
    Error -> #("border-danger/50 bg-danger-tint", attribute.role("alert"))
    Warning -> #("border-warning/60 bg-warning-tint", attribute.none())
  }

  html.div(
    [
      attribute.class(
        "rounded-md border px-4 py-3 text-sm text-fg " <> level_class,
      ),
      role,
      ..attributes
    ],
    children,
  )
}
