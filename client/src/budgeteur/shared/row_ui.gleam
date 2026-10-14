//// Stateless Tailwind chrome for list and table rows that open when clicked.
//// A row is made clickable by giving it the `group relative` classes and one
//// `open_button`. A trailing `chevron` marks it as a row that opens, since
//// touch screens have no hover. Deleting starts from the dialog the row opens,
//// so rows show their content rather than a column of buttons.

import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

/// Lifts text above a row's `open_button` overlay so it can be selected and
/// copied. Positioned elements paint in DOM order, so being positioned after
/// the button is enough. `w-fit` keeps the unclickable area to the text itself.
pub const selectable_class = "relative w-fit max-w-full"

/// The button that opens a row. Its `::after` overlay stretches over the
/// nearest positioned ancestor, the row, so the whole row is the click target
/// while the button stays the row's one focusable element. Its content names
/// the row, which labels the button for screen readers. `class` lays the content
/// out, e.g. "block max-w-full truncate" to keep a name to one line.
pub fn open_button(
  testid testid: String,
  on_click on_click: msg,
  class class: String,
  children children: List(Element(msg)),
) -> Element(msg) {
  html.button(
    [
      attribute.type_("button"),
      attribute.class(
        "cursor-pointer text-left text-sm text-gray-900 group-hover:text-indigo-600 "
        <> "focus:outline-none after:absolute after:inset-0 focus-visible:after:ring-2 "
        <> "focus-visible:after:ring-inset focus-visible:after:ring-indigo-500 "
        <> class,
      ),
      attribute.attribute("data-testid", testid),
      event.on_click(on_click),
    ],
    children,
  )
}

/// A row's trailing chevron. `class` positions it in the row, e.g. "mt-0.5" to
/// line it up with the first line of text in a row whose items start at the
/// top.
pub fn chevron(class class: String) -> Element(msg) {
  html.svg(
    [
      attribute.attribute("fill", "none"),
      attribute.attribute("viewBox", "0 0 24 24"),
      attribute.attribute("stroke-width", "2"),
      attribute.attribute("stroke", "currentColor"),
      attribute.class(
        "h-4 w-4 shrink-0 text-gray-400 group-hover:text-gray-600 " <> class,
      ),
      attribute.attribute("aria-hidden", "true"),
    ],
    [
      element.namespaced(
        "http://www.w3.org/2000/svg",
        "path",
        [
          attribute.attribute("stroke-linecap", "round"),
          attribute.attribute("stroke-linejoin", "round"),
          attribute.attribute("d", "m8.25 4.5 7.5 7.5-7.5 7.5"),
        ],
        [],
      ),
    ],
  )
}

/// A row that opens a page rather than a dialog: `open_button`'s whole-row
/// target as a link, so the browser's back button and new-tab gestures work.
/// The shell routes the click without a reload.
pub fn open_link(
  testid testid: String,
  href href: String,
  class class: String,
  children children: List(Element(msg)),
) -> Element(msg) {
  html.a(
    [
      attribute.href(href),
      attribute.class(
        "text-left text-sm text-gray-900 group-hover:text-indigo-600 "
        <> "focus:outline-none after:absolute after:inset-0 focus-visible:after:ring-2 "
        <> "focus-visible:after:ring-inset focus-visible:after:ring-indigo-500 "
        <> class,
      ),
      attribute.attribute("data-testid", testid),
    ],
    children,
  )
}
