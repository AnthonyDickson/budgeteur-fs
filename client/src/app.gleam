import gleam/uri
import lustre
import lustre/effect as lustre_effect
import lustre/element.{type Element}
import todos_mvc/effect
import todos_mvc/todo_page

pub type Model {
  Model(todo_page: todo_page.Model)
}

pub type Msg {
  UrlChanged(path: String)
  TodoPageMsg(todo_page.Msg)
}

fn path_to_visibility(path: String) -> todo_page.Visibility {
  case uri.path_segments(path) {
    [] -> todo_page.All
    ["active"] -> todo_page.Active
    ["completed"] -> todo_page.Completed
    _ -> todo_page.All
  }
}

pub fn init(_flags) -> #(Model, effect.Effect(Msg)) {
  let #(todo_model, todo_effect) = todo_page.init()
  let model = Model(todo_page: todo_model)

  let effects =
    effect.batch([
      effect.map(todo_effect, TodoPageMsg),
      effect.navigate(UrlChanged),
      effect.set_title("LustreTodos"),
    ])

  #(model, effects)
}

pub fn update(model: Model, msg: Msg) -> #(Model, effect.Effect(Msg)) {
  case msg {
    UrlChanged(path) -> {
      let visibility = path_to_visibility(path)
      let #(todo_model, todo_effect) =
        todo_page.update_with_storage(
          model.todo_page,
          todo_page.UserChangedVisibility(visibility),
        )
      #(Model(todo_page: todo_model), effect.map(todo_effect, TodoPageMsg))
    }
    TodoPageMsg(inner_msg) -> {
      let #(inner_model, inner_effect) =
        todo_page.update_with_storage(model.todo_page, inner_msg)
      #(Model(todo_page: inner_model), effect.map(inner_effect, TodoPageMsg))
    }
  }
}

pub fn view(model: Model) -> Element(Msg) {
  todo_page.view(model.todo_page)
  |> element.map(TodoPageMsg)
}

fn update_with_effect(
  model: Model,
  msg: Msg,
) -> #(Model, lustre_effect.Effect(Msg)) {
  let #(new_model, custom_effect) = update(model, msg)
  #(
    new_model,
    lustre_effect.from(fn(dispatch) { effect.run(custom_effect, dispatch) }),
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
