import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html

/// A small colored circle used to render a tag's color.
pub fn color_swatch(color: String) -> Element(msg) {
  html.span(
    [
      attribute.class("inline-block h-3 w-3 shrink-0 rounded-full"),
      attribute.style("background-color", color),
      attribute.attribute("aria-hidden", "true"),
    ],
    [],
  )
}
