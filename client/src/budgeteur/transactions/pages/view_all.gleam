import budgeteur/effect.{type Effect}
import gleam/json.{type Json}
import lustre/element.{type Element}
import lustre/element/html

pub type Model {
  Model
}

pub fn model_to_json(_model: Model) -> Json {
  json.string("model")
}

pub type Msg

pub fn init() -> #(Model, Effect(Msg)) {
  #(Model, effect.none())
}

pub fn update(model: Model, _msg: Msg) -> #(Model, Effect(Msg)) {
  #(model, effect.none())
}

pub fn view(_model: Model) -> Element(Msg) {
  html.div([], [html.p([], [html.text("Hello, world!")])])
}
