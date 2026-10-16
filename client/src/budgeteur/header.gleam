import budgeteur/shared/icon
import budgeteur/shared/route
import gleam/list
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html

/// The pages the header links to, in order.
const pages = [
  #(route.Dashboard, "Dashboard"),
  #(route.Reports, "Reports"),
  #(route.Transactions, "Transactions"),
  #(route.Tagging, "Tags & Rules"),
  #(route.BalanceSheet, "Balance Sheet"),
]

/// The id of the menu popover, which narrow screens show in place of the nav.
const menu_id = "nav-menu"

/// The app-wide header: brand link plus nav links to each page. The active
/// item is highlighted based on the current route.
///
/// Narrow screens have no room for the nav, so it is hidden there and the same
/// links are in a menu behind a button. The browser's popover API opens and
/// closes the menu, so the model holds no state for it. A link in the menu does
/// not close it, so the app keys the header by route: going to another page
/// replaces the header, and with it the open menu.
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
            attribute.class(
              "flex items-center gap-2 text-base font-semibold text-fg",
            ),
          ],
          [
            html.img([
              attribute.src("/favicon-128x128.png"),
              attribute.alt(""),
              attribute.class("size-7"),
            ]),
            html.text("Budgeteur"),
          ],
        ),
        html.nav(
          [attribute.class("hidden items-center gap-1 md:flex")],
          list.map(pages, fn(page) {
            nav_link(page, current_route, "px-3 py-1.5 text-sm")
          }),
        ),
        menu(current_route),
      ],
    ),
  ])
}

/// The menu button and the menu it opens, on narrow screens only.
fn menu(current_route: route.Route) -> Element(msg) {
  let anchor = "--" <> menu_id

  html.div([attribute.class("ml-auto md:hidden")], [
    html.button(
      [
        attribute.type_("button"),
        attribute.popovertarget(menu_id),
        attribute.aria_label("Menu"),
        attribute.attribute("data-testid", "nav-menu-button"),
        attribute.style("anchor-name", anchor),
        attribute.class(
          "cursor-pointer rounded-md p-3 text-fg-muted hover:bg-surface-hover hover:text-fg "
          <> "focus:outline-none focus-visible:ring-2 focus-visible:ring-primary",
        ),
      ],
      [icon.bars(class: "")],
    ),
    // No display utility here: it would override the browser's `display:
    // none` for a closed popover.
    html.nav(
      [
        attribute.id(menu_id),
        attribute.popover("auto"),
        attribute.attribute("data-testid", menu_id),
        attribute.style("position-anchor", anchor),
        attribute.class(
          "inset-auto m-0 mt-1 w-48 space-y-1 rounded-md border border-border bg-surface p-1 shadow-lg "
          <> "[position-area:bottom_span-left] [position-try-fallbacks:flip-block]",
        ),
      ],
      list.map(pages, fn(page) {
        nav_link(page, current_route, "block px-3 py-2 text-base")
      }),
    ),
  ])
}

/// A link to `page`, highlighted when it is the current section. `class` sizes
/// and lays out the link for the nav or the menu.
fn nav_link(
  page: #(route.Route, String),
  current_route: route.Route,
  class: String,
) -> Element(msg) {
  let #(target, label) = page
  let is_active = route.section(current_route) == target
  html.a(
    [
      attribute.href(route.to_string(target)),
      attribute.class(
        "whitespace-nowrap rounded-md font-medium "
        <> class
        <> " "
        <> case is_active {
          True -> "bg-primary-tint text-fg"
          False -> "text-fg-muted hover:bg-surface-hover hover:text-fg"
        },
      ),
    ],
    [html.text(label)],
  )
}
