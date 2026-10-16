//// Inline SVG icons drawn in `currentColor`, so they take the colour and the
//// hover and disabled states of the text they sit next to. `class` sizes and
//// positions the icon.

import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html

/// A chevron pointing left, for "back" and "previous".
pub fn chevron_left(class class: String) -> Element(msg) {
  stroked(class, "m15.75 19.5-7.5-7.5 7.5-7.5")
}

/// A chevron pointing right, for "next" and rows that open.
pub fn chevron_right(class class: String) -> Element(msg) {
  stroked(class, "m8.25 4.5 7.5 7.5-7.5 7.5")
}

/// A tick, for work that is done, e.g. a saved choice.
pub fn check(class class: String) -> Element(msg) {
  stroked(class, "m4.5 12.75 6 6 9-13.5")
}

fn stroked(class: String, path: String) -> Element(msg) {
  html.svg(
    [
      attribute.attribute("fill", "none"),
      attribute.attribute("viewBox", "0 0 24 24"),
      attribute.attribute("stroke-width", "2"),
      attribute.attribute("stroke", "currentColor"),
      attribute.class("h-4 w-4 shrink-0 " <> class),
      attribute.attribute("aria-hidden", "true"),
    ],
    [
      element.namespaced(
        "http://www.w3.org/2000/svg",
        "path",
        [
          attribute.attribute("stroke-linecap", "round"),
          attribute.attribute("stroke-linejoin", "round"),
          attribute.attribute("d", path),
        ],
        [],
      ),
    ],
  )
}
