import budgeteur/auth_route
import budgeteur/effect.{type Effect}
import budgeteur/http_effect
import budgeteur/out_msg.{type OutMsg}
import budgeteur/route
import budgeteur/toast.{type Toast}
import budgeteur/transactions/pages/view_all as transactions_view_all
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import lustre
import lustre/effect as lustre_effect
import lustre/element.{type Element}
import lustre/element/html
import youid/uuid.{type Uuid}

// Consts and Types
// ----------------

const local_storage_key = "budgeteur"

pub type Page {
  TransactionsViewAllPage(transactions_view_all.Model)
}

fn page_to_json(page: Page) -> json.Json {
  case page {
    TransactionsViewAllPage(inner_model) ->
      transactions_view_all.model_to_json(inner_model)
  }
}

pub type Model {
  Model(page: Page, toasts: List(Toast))
}

fn model_to_json(model: Model) -> json.Json {
  let Model(page:, toasts: _) = model
  json.object([
    #("page", page_to_json(page)),
  ])
}

pub type Msg {
  SessionExpired
  TransactionsViewAllMsg(transactions_view_all.Msg)
  ToastDismissed(id: Uuid)
  UrlChanged(url: String)
}

// Init
// ----

pub fn init(_flags) -> #(Model, Effect(Msg)) {
  let #(page_model, page_effect) = transactions_view_all.init()
  let model = Model(page: TransactionsViewAllPage(page_model), toasts: [])

  let effects =
    effect.batch([
      // TODO: Restore state from local storage
      effect.map(page_effect, TransactionsViewAllMsg),
      effect.init_routing(UrlChanged),
      effect.set_title("Budgeteur"),
    ])

  #(model, effects)
}

// Update
// ------

fn map_out_msg(
  out_msg: OutMsg,
  model: Model,
  effect: Effect(Msg),
) -> #(Model, Effect(Msg)) {
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

fn with_out_msgs(
  update_output: #(Model, Effect(Msg)),
  out_msgs: List(OutMsg),
) -> #(Model, Effect(Msg)) {
  case out_msgs {
    [] -> update_output
    [msg, ..other_msgs] -> {
      let #(model, effect) = update_output
      map_out_msg(msg, model, effect)
      |> with_out_msgs(other_msgs)
    }
  }
}

pub fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg, model {
    UrlChanged(url), _ -> {
      case route.from_string(url) {
        _ -> #(
          Model(
            ..model,
            page: TransactionsViewAllPage(transactions_view_all.Model([])),
          ),
          effect.none(),
        )
      }
    }
    TransactionsViewAllMsg(inner_msg),
      Model(page: TransactionsViewAllPage(inner_model), ..)
    -> {
      let #(inner_model, inner_effect, out_msgs) =
        transactions_view_all.update(inner_model, inner_msg)

      #(
        Model(..model, page: TransactionsViewAllPage(inner_model)),
        effect.map(inner_effect, TransactionsViewAllMsg),
      )
      |> with_out_msgs(out_msgs)
    }
    ToastDismissed(id:), _ -> {
      let toasts = list.filter(model.toasts, fn(toast) { toast.id != id })
      #(Model(..model, toasts:), effect.none())
    }
    SessionExpired, _ -> #(model, effect.Redirect(auth_route.login))
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
    TransactionsViewAllPage(inner_model) ->
      transactions_view_all.view(inner_model)
      |> element.map(TransactionsViewAllMsg)
  }

  let toasts = toast.view_with_container(model.toasts, ToastDismissed)

  html.div([], [
    page,
    toasts,
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
