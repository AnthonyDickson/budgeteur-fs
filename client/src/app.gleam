import budgeteur/effect.{type Effect}
import budgeteur/route
import budgeteur/transactions/pages/view_all as transactions_view_all
import gleam/io
import gleam/json
import gleam/string
import lustre
import lustre/effect as lustre_effect
import lustre/element.{type Element}

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
  Model(page: Page)
}

fn model_to_json(model: Model) -> json.Json {
  let Model(page:) = model
  json.object([
    #("page", page_to_json(page)),
  ])
}

pub type Msg {
  UrlChanged(url: String)
  TransactionsViewAllMsg(transactions_view_all.Msg)
}

pub fn init(_flags) -> #(Model, Effect(Msg)) {
  let #(page_model, page_effect) = transactions_view_all.init()
  let model = Model(page: TransactionsViewAllPage(page_model))

  let effects =
    effect.batch([
      // TODO: Restore state from local storage
      effect.map(page_effect, TransactionsViewAllMsg),
      effect.init_routing(UrlChanged),
      effect.set_title("Budgeteur"),
    ])

  #(model, effects)
}

pub fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg, model {
    UrlChanged(url), _ -> {
      case route.from_string(url) {
        _ -> #(
          Model(page: TransactionsViewAllPage(transactions_view_all.Model([]))),
          effect.none(),
        )
      }
    }
    TransactionsViewAllMsg(inner_msg),
      Model(page: TransactionsViewAllPage(inner_model))
    -> {
      let #(inner_model, inner_effect) =
        transactions_view_all.update(inner_model, inner_msg)
      #(
        Model(page: TransactionsViewAllPage(inner_model)),
        effect.map(inner_effect, TransactionsViewAllMsg),
      )
    }
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

pub fn view(model: Model) -> Element(Msg) {
  case model.page {
    TransactionsViewAllPage(inner_model) ->
      transactions_view_all.view(inner_model)
      |> element.map(TransactionsViewAllMsg)
  }
}

fn update_with_effect(
  model: Model,
  msg: Msg,
) -> #(Model, lustre_effect.Effect(Msg)) {
  let #(new_model, custom_effect) =
    update(model, msg)
    |> with_local_storage

  #(
    new_model,
    lustre_effect.from(fn(dispatch) { effect.run(custom_effect, dispatch) }),
  )
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

pub fn main() {
  let #(init_model, init_effect) = init(Nil)

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
