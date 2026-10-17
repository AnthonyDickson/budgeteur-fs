//// Figure cards: a label over one headline figure, for the summary rows of the
//// dashboard, balance sheet, and reports pages. Callers add test ids and the
//// figure's data attributes, and put any detail below the figure.

import lustre/attribute.{type Attribute}
import lustre/element.{type Element}
import lustre/element/html

/// A card with `label` above its children, usually a `figure`.
pub fn card(
  label: String,
  attributes: List(Attribute(msg)),
  children: List(Element(msg)),
) -> Element(msg) {
  card_with_help(label, element.none(), attributes, children)
}

/// A card whose label has `help`, a `popover.help`, beside it, e.g. to define
/// the figure.
pub fn card_with_help(
  label: String,
  help: Element(msg),
  attributes: List(Attribute(msg)),
  children: List(Element(msg)),
) -> Element(msg) {
  html.div(
    [
      attribute.class(
        "rounded-lg border border-border bg-surface px-5 py-4 shadow-sm",
      ),
      ..attributes
    ],
    [
      html.p(
        [
          attribute.class(
            "flex items-center gap-1 text-sm font-medium text-fg-muted",
          ),
        ],
        [html.text(label), help],
      ),
      ..children
    ],
  )
}

/// The card's headline figure.
pub fn figure(attributes: List(Attribute(msg)), text: String) -> Element(msg) {
  html.p(
    [
      attribute.class(
        "mt-1 whitespace-nowrap text-2xl font-semibold tracking-tight tabular-nums text-fg",
      ),
      ..attributes
    ],
    [html.text(text)],
  )
}

/// Stands in for a figure that cannot be shown, e.g. "No income", at the
/// figure's height so the cards in a row stay level.
pub fn no_figure(text: String) -> Element(msg) {
  html.p([attribute.class("mt-1 flex h-8 items-center text-sm text-fg-muted")], [
    html.text(text),
  ])
}
