import budgeteur/shared/tag.{type TagColor}
import gleam/string
import lustre/attribute.{type Attribute}
import lustre/element.{type Element}
import lustre/element/html

/// A small coloured circle used to render a tag's colour.
pub fn view(color: TagColor) -> Element(msg) {
  html.span(
    [
      attribute.class("inline-block h-3 w-3 shrink-0 rounded-full"),
      background(color),
      attribute.attribute("aria-hidden", "true"),
    ],
    [],
  )
}

/// Fills an element with a tag colour: the palette variable of the accent, so
/// the colour follows the mode (decision 9 in docs/styling.md).
pub fn background(color: TagColor) -> Attribute(msg) {
  attribute.style(
    "background-color",
    "var(--ctp-" <> string.lowercase(tag.color_to_string(color)) <> ")",
  )
}
