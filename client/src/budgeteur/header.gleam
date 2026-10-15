import budgeteur/shared/route
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html

/// The app-wide header: brand link plus nav links to each page. The active
/// item is highlighted based on the current route.
pub fn view(current_route: route.Route) -> Element(msg) {
  html.header([attribute.class("border-b border-border bg-surface")], [
    html.div(
      [
        attribute.class(
          "mx-auto flex h-14 max-w-6xl items-center gap-6 px-4 sm:px-6",
        ),
      ],
      [
        html.a(
          [
            attribute.href(route.to_string(route.Dashboard)),
            attribute.class("text-base font-semibold text-fg"),
          ],
          [html.text("Budgeteur")],
        ),
        html.nav([attribute.class("flex items-center gap-1")], [
          nav_link(
            route.Dashboard,
            current_route,
            route.to_string(route.Dashboard),
            "Dashboard",
          ),
          nav_link(
            route.Reports,
            current_route,
            route.to_string(route.Reports),
            "Reports",
          ),
          nav_link(
            route.Transactions,
            current_route,
            route.to_string(route.Transactions),
            "Transactions",
          ),
          nav_link(
            route.Tagging,
            current_route,
            route.to_string(route.Tagging),
            "Tags & Rules",
          ),
          nav_link(
            route.BalanceSheet,
            current_route,
            route.to_string(route.BalanceSheet),
            "Balance Sheet",
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
  let is_active = route.section(current_route) == target
  html.a(
    [
      attribute.href(href),
      attribute.class(
        "rounded-md px-3 py-1.5 text-sm font-medium "
        <> case is_active {
          True -> "bg-primary-tint text-fg"
          False -> "text-fg-muted hover:bg-surface-hover hover:text-fg"
        },
      ),
    ],
    [html.text(label)],
  )
}
