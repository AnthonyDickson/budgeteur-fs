import budgeteur/auth_route
import budgeteur/effect.{type Effect}
import budgeteur/guard
import budgeteur/http_effect
import budgeteur/out_msg.{type OutMsg}
import budgeteur/route
import budgeteur/toast.{type Toast}
import budgeteur/transactions/transactions_page
import gleam/dynamic/decode
import gleam/io
import gleam/json
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

const local_storage_key = "budgeteur"

const transactions_page_key = "transactions_page"

const not_found_page_key = "not_found_page"

pub type Page {
  TransactionsPage(transactions_page.Model)
  NotFound
}

fn page_decoder() -> decode.Decoder(Page) {
  use variant <- decode.field("type", decode.string)
  case variant {
    _ if variant == transactions_page_key -> {
      use page_model <- decode.field("data", transactions_page.model_decoder())
      decode.success(TransactionsPage(page_model))
    }
    _ -> decode.success(NotFound)
  }
}

fn page_to_json(page: Page) -> json.Json {
  case page {
    TransactionsPage(model) ->
      json.object([
        #("type", json.string(transactions_page_key)),
        #("data", transactions_page.model_to_json(model)),
      ])
    NotFound ->
      json.object([
        #("type", json.string(not_found_page_key)),
        #("data", json.null()),
      ])
  }
}

pub type Model {
  Model(page: Page, toasts: List(Toast))
}

fn model_decoder() -> decode.Decoder(Model) {
  use page <- decode.field("page", page_decoder())
  decode.success(Model(page:, toasts: []))
}

fn model_to_json(model: Model) -> json.Json {
  let Model(page:, toasts: _) = model
  json.object([
    #("page", page_to_json(page)),
  ])
}

pub type Msg {
  ClientRestoredModel(Model)
  SessionExpired
  TransactionsPageMsg(transactions_page.Msg)
  ToastDismissed(id: Uuid)
  UrlChanged(url: String)
  NoOp
}

// Init
// ----

fn restore_model_from_store() -> effect.Effect(Msg) {
  effect.LoadFromStore(key: local_storage_key, callback: fn(store_result) {
    case store_result {
      Ok(value) ->
        case json.parse(value, using: model_decoder()) {
          Ok(model) -> ClientRestoredModel(model)
          Error(_) -> NoOp
        }
      Error(_) -> NoOp
    }
  })
}

pub fn init(_flags) -> #(Model, Effect(Msg)) {
  let model = Model(page: NotFound, toasts: [])

  let effects =
    effect.batch([
      restore_model_from_store(),
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
    ClientRestoredModel(restored_model), _ -> #(restored_model, effect.none())
    UrlChanged(url), _ -> {
      case route.from_string(url), model.page {
        route.Transactions, TransactionsPage(_) -> {
          let #(_, page_effect) = transactions_page.init()
          #(model, effect.map(page_effect, TransactionsPageMsg))
        }
        route.Transactions, _ -> {
          let #(inner_model, inner_effect) = transactions_page.init()

          let model = Model(..model, page: TransactionsPage(inner_model))
          let effect = effect.map(inner_effect, TransactionsPageMsg)

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
/// `Batch` because effects reach this point wrapped by `with_local_storage`.
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

fn with_local_storage(result: #(Model, Effect(Msg))) -> #(Model, Effect(Msg)) {
  let #(model, effect) = result
  let model_json =
    model
    |> model_to_json
    |> json.to_string

  #(
    model,
    effect.batch([effect, effect.SaveToStore(local_storage_key, model_json)]),
  )
}

fn update_with_effect(
  model: Model,
  msg: Msg,
) -> #(Model, lustre_effect.Effect(Msg)) {
  let #(new_model, custom_effect) =
    update(model, msg)
    |> with_local_storage
    |> with_auth_redirect

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

    NotFound -> view_not_found()
  }

  let toasts = toast.view_with_container(model.toasts, ToastDismissed)

  html.div([], [
    page,
    toasts,
  ])
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
  let #(init_model, init_effect) =
    init(Nil) |> with_local_storage |> with_auth_redirect

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
