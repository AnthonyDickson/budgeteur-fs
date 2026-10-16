//// Help behind an info button, for notes that explain a field or figure but
//// would clutter the page if always shown. The browser's popover API opens
//// and closes it, so the model holds no state for it: a click toggles it, and
//// Escape or a click elsewhere closes it. It opens in the top layer, above
//// modal dialogs, anchored below the button.

import budgeteur/shared/icon
import gleam/list
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html

/// An info button labelled "About `about`" that shows `paragraphs`. `id` is
/// the popover's id, unique on the page, so a field can point
/// `aria-describedby` at it. The test ids are `id` and `id <> "-button"`.
///
/// Both elements are spans, so the help can sit inside a label, legend, or
/// paragraph.
pub fn help(
  id id: String,
  about about: String,
  paragraphs paragraphs: List(String),
) -> Element(msg) {
  let anchor = "--" <> id

  html.span([attribute.class("inline-flex")], [
    html.button(
      [
        attribute.type_("button"),
        attribute.popovertarget(id),
        attribute.aria_label("About " <> about),
        attribute.attribute("data-testid", id <> "-button"),
        attribute.style("anchor-name", anchor),
        // The padding makes a 24px target around the 16px icon, the minimum
        // in WCAG 2.5.8, and the negative margin keeps the layout of a bare
        // icon.
        attribute.class(
          "-m-1 cursor-pointer rounded-full p-1 text-fg-subtle hover:text-fg-muted "
          <> "focus:outline-none focus-visible:ring-2 focus-visible:ring-primary",
        ),
      ],
      [icon.info(class: "")],
    ),
    // No display utility here: it would override the browser's `display:
    // none` for a closed popover.
    html.span(
      [
        attribute.id(id),
        attribute.popover("auto"),
        attribute.attribute("data-testid", id),
        attribute.style("position-anchor", anchor),
        attribute.class(
          "inset-auto m-0 mt-1 w-max max-w-xs space-y-2 rounded-md border border-border "
          <> "bg-surface px-3 py-2 text-left text-sm font-normal normal-case tracking-normal text-fg shadow-lg "
          <> "[position-area:bottom_span-right] [position-try-fallbacks:flip-block,flip-inline]",
        ),
      ],
      list.map(paragraphs, fn(paragraph) {
        html.span([attribute.class("block")], [html.text(paragraph)])
      }),
    ),
  ])
}
