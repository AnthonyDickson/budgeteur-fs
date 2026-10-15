//// A link within text. The text is the normal text colour, so it reads on any
//// background, and a primary underline marks it as a link: primary text on the
//// page background falls short of AA in Latte (decision 6 in
//// docs/styling.md).

import lustre/attribute.{type Attribute}
import lustre/element.{type Element}
import lustre/element/html

pub fn view(
  attributes: List(Attribute(msg)),
  children: List(Element(msg)),
) -> Element(msg) {
  html.a(
    [
      attribute.class(
        "font-medium text-fg underline decoration-primary decoration-2 underline-offset-2 hover:decoration-primary-hover",
      ),
      ..attributes
    ],
    children,
  )
}
