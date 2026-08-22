import budgeteur/route
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html

/// The app-wide header: brand link plus nav links to each page. The active
/// item is highlighted based on the current route.
pub fn view(current_route: route.Route) -> Element(msg) {
  html.header([attribute.class("border-b border-gray-200 bg-white")], [
    html.div(
      [
        attribute.class(
          "mx-auto flex h-14 max-w-6xl items-center gap-6 px-4 sm:px-6",
        ),
      ],
      [
        html.a(
          [
            attribute.href(route.to_string(route.Transactions)),
            attribute.class("text-base font-semibold text-gray-900"),
          ],
          [html.text("Budgeteur")],
        ),
        html.nav([attribute.class("flex items-center gap-1")], [
          nav_link(
            route.Transactions,
            current_route,
            "/transactions",
            "Transactions",
          ),
          nav_link(
            route.TagsAndRules,
            current_route,
            "/tags-and-rules",
            "Tags & Rules",
          ),
        ]),
      ],
    ),
  ])
}

fn nav_link(
  target: route.Route,
  current_route: route.Route,
  href: String,
  label: String,
) -> Element(msg) {
  let is_active = current_route == target
  html.a(
    [
      attribute.href(href),
      attribute.class(
        "rounded-md px-3 py-1.5 text-sm font-medium "
        <> case is_active {
          True -> "bg-indigo-50 text-indigo-700"
          False -> "text-gray-600 hover:bg-gray-50 hover:text-gray-900"
        },
      ),
    ],
    [html.text(label)],
  )
}
