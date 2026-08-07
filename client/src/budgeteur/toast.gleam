import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import youid/uuid.{type Uuid}

pub type Toast {
  Toast(id: Uuid, title: String, body: String)
}

pub fn view(toast: Toast, on_dismiss: fn(Uuid) -> msg) -> Element(msg) {
  html.div(
    [
      attribute.class(
        "pointer-events-auto bg-gray-50 border border-gray-200 border-l-4 border-l-amber-400/40 shadow-lg p-4 max-w-sm animate-[toast-in_0.3s_ease-out]",
      ),
      attribute.role("alert"),
    ],
    [
      html.div([attribute.class("flex justify-between items-start gap-3")], [
        html.div([], [
          html.p([attribute.class("text-sm font-medium text-gray-600")], [
            html.text(toast.title),
          ]),
          html.p([attribute.class("text-sm text-gray-500 mt-1")], [
            html.text(toast.body),
          ]),
        ]),
        html.button(
          [
            attribute.class(
              "text-gray-300 hover:text-gray-500 shrink-0 text-lg leading-none cursor-pointer",
            ),
            attribute.aria_label("Dismiss"),
            event.on_click(on_dismiss(toast.id)),
          ],
          [html.text("x")],
        ),
      ]),
    ],
  )
}
