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

/// Three horizontal bars, for a button that opens a menu.
pub fn bars(class class: String) -> Element(msg) {
  stroked(class, "M3.75 6.75h16.5M3.75 12h16.5m-16.5 5.25h16.5")
}

/// A circled "i", for a button that shows help.
pub fn info(class class: String) -> Element(msg) {
  stroked(
    class,
    "m11.25 11.25.041-.02a.75.75 0 0 1 1.063.852l-.708 2.836a.75.75 0 0 0 1.063.853l.041-.021M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0Zm-9-3.75h.008v.008H12V8.25Z",
  )
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
