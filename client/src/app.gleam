import budgeteur/auth_route
import budgeteur/effect.{type Effect}
import budgeteur/guard
import budgeteur/header
import budgeteur/http_effect
import budgeteur/out_msg.{type OutMsg}
import budgeteur/route
import budgeteur/tags/tags_page
import budgeteur/toast.{type Toast}
import budgeteur/transactions/transactions_page
import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import lustre
import lustre/attribute
import lustre/effect as lustre_effect
import lustre/element.{type Element}
import lustre/element/html
import youid/uuid.{type Uuid}

// Consts and Types
// ----------------

pub type Page {
  TransactionsPage(transactions_page.Model)
  TagsPage(tags_page.Model)
  NotFound
}

pub type Model {
  Model(page: Page, toasts: List(Toast))
}

pub type Msg {
  SessionExpired
  TransactionsPageMsg(transactions_page.Msg)
  TagsPageMsg(tags_page.Msg)
  ToastDismissed(id: Uuid)
  UrlChanged(url: String)
  NoOp
}

// Init
// ----

pub fn init(_flags) -> #(Model, Effect(Msg)) {
  let model = Model(page: NotFound, toasts: [])

  let effects =
    effect.batch([
      effect.init_routing(UrlChanged),
      effect.set_title("Budgeteur"),
    ])

  #(model, effects)
}

// Update
// ------

fn with_out_msg(
  update_output: #(Model, Effect(Msg)),
  out_msg: Option(OutMsg),
) -> #(Model, Effect(Msg)) {
  use out_msg <- guard.some(out_msg, else_return: update_output)

  let #(model, effect) = update_output

  case out_msg {
    out_msg.PageRequestedToast(title:, body:, level:, dismiss_after_ms:) -> {
      let new_toast = toast.Toast(id: uuid.v7(), title:, body:, level:)
      let model = Model(..model, toasts: [new_toast, ..model.toasts])
      let effect = case dismiss_after_ms {
        Some(delay) ->
          effect.batch([
            effect,
            effect.After(delay, ToastDismissed(new_toast.id)),
          ])
        None -> effect
      }
      #(model, effect)
    }
  }
}

pub fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg, model {
    UrlChanged(url), _ -> {
      case route.from_string(url), model.page {
        route.Transactions, TransactionsPage(_) -> {
          let #(_, page_effect) = transactions_page.init()
          #(model, effect.map(page_effect, TransactionsPageMsg))
        }
        route.Tags, TagsPage(_) -> {
          let #(_, page_effect) = tags_page.init()
          #(model, effect.map(page_effect, TagsPageMsg))
        }
        route.Transactions, _ -> {
          let #(inner_model, inner_effect) = transactions_page.init()

          let model = Model(..model, page: TransactionsPage(inner_model))
          let effect = effect.map(inner_effect, TransactionsPageMsg)

          #(model, effect)
        }
        route.Tags, _ -> {
          let #(inner_model, inner_effect) = tags_page.init()

          let model = Model(..model, page: TagsPage(inner_model))
          let effect = effect.map(inner_effect, TagsPageMsg)

          #(model, effect)
        }
        route.NotFound, NotFound -> #(model, effect.none())
        route.NotFound, _ -> #(Model(..model, page: NotFound), effect.none())
      }
    }
    TransactionsPageMsg(inner_msg),
      Model(page: TransactionsPage(inner_model), ..)
    -> {
      let #(inner_model, inner_effect, out_msg) =
        transactions_page.update(inner_model, inner_msg)

      #(
        Model(..model, page: TransactionsPage(inner_model)),
        effect.map(inner_effect, TransactionsPageMsg),
      )
      |> with_out_msg(out_msg)
    }
    TagsPageMsg(inner_msg), Model(page: TagsPage(inner_model), ..) -> {
      let #(inner_model, inner_effect, out_msg) =
        tags_page.update(inner_model, inner_msg)

      #(
        Model(..model, page: TagsPage(inner_model)),
        effect.map(inner_effect, TagsPageMsg),
      )
      |> with_out_msg(out_msg)
    }
    ToastDismissed(id:), _ -> {
      let toasts = list.filter(model.toasts, fn(toast) { toast.id != id })
      #(Model(..model, toasts:), effect.none())
    }
    SessionExpired, _ -> #(model, effect.Redirect(auth_route.login))
    NoOp, _ -> #(model, effect.none())
    _, _ -> {
      io.println_error(
        "Unhandled combination of message and state:\n"
        <> string.inspect(msg)
        <> "\n"
        <> string.inspect(model),
      )
      #(model, effect.none())
    }
  }
}

/// Rewrite every `HttpRequest` effect so a 401 response dispatches
/// `SessionExpired` instead of reaching the page's callback. Recurses through
/// `Batch` because effects can be batched by pages and `init`.
pub fn wrap_http_requests(effect: Effect(Msg)) -> Effect(Msg) {
  case effect {
    effect.HttpRequest(callback: original_callback, ..) as request ->
      effect.HttpRequest(..request, callback: fn(result) {
        case result {
          Error(http_effect.HttpError(status: 401, ..)) -> SessionExpired
          _ -> original_callback(result)
        }
      })
    effect.Batch(effects) -> effect.Batch(list.map(effects, wrap_http_requests))
    _ -> effect
  }
}

fn with_auth_redirect(result: #(Model, Effect(Msg))) -> #(Model, Effect(Msg)) {
  let #(model, effect) = result
  #(model, wrap_http_requests(effect))
}

fn update_with_effect(
  model: Model,
  msg: Msg,
) -> #(Model, lustre_effect.Effect(Msg)) {
  let #(new_model, custom_effect) = update(model, msg) |> with_auth_redirect

  #(
    new_model,
    lustre_effect.from(fn(dispatch) { effect.run(custom_effect, dispatch) }),
  )
}

// View
// ----

pub fn view(model: Model) -> Element(Msg) {
  let page = case model.page {
    TransactionsPage(inner_model) ->
      transactions_page.view(inner_model)
      |> element.map(TransactionsPageMsg)

    TagsPage(inner_model) ->
      tags_page.view(inner_model)
      |> element.map(TagsPageMsg)

    NotFound -> view_not_found()
  }

  let toasts = toast.view_with_container(model.toasts, ToastDismissed)

  html.div([], [
    header.view(current_route(model.page)),
    page,
    toasts,
  ])
}

fn current_route(page: Page) -> route.Route {
  case page {
    TransactionsPage(_) -> route.Transactions
    TagsPage(_) -> route.Tags
    NotFound -> route.NotFound
  }
}

fn view_not_found() -> Element(Msg) {
  html.div([], [
    html.h1([], [html.text("404 Page Not Found")]),
    html.p([], [html.text("This is not the page you're looking for.")]),
    html.p([], [
      html.a([attribute.href(route.Transactions |> route.to_string)], [
        html.text("Take me home!"),
      ]),
    ]),
  ])
}

// Main Loop
// ---------

pub fn main() {
  let #(init_model, init_effect) = init(Nil) |> with_auth_redirect

  let app =
    lustre.application(
      init: fn(_) {
        #(
          init_model,
          lustre_effect.from(fn(dispatch) { effect.run(init_effect, dispatch) }),
        )
      },
      update: update_with_effect,
      view: view,
    )

  let assert Ok(_) = lustre.start(app, "#app", Nil)
  Nil
}
