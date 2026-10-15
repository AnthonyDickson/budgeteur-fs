//// Panels raised off the page, in the app's colour roles. Callers add
//// behaviour attributes and layout classes such as padding.

import lustre/attribute.{type Attribute}
import lustre/element.{type Element}
import lustre/element/html

const panel_class = "rounded-lg border border-border bg-surface shadow-sm"

/// A panel holding a section of a page, e.g. a table or a summary.
pub fn panel(
  attributes: List(Attribute(msg)),
  children: List(Element(msg)),
) -> Element(msg) {
  html.div([attribute.class(panel_class), ..attributes], children)
}

/// A panel standing in for content that is loading, failed to load, or empty,
/// with its message centred.
pub fn empty_state(
  attributes: List(Attribute(msg)),
  children: List(Element(msg)),
) -> Element(msg) {
  html.div(
    [attribute.class(panel_class <> " px-6 py-12 text-center"), ..attributes],
    children,
  )
}
