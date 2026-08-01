# Client Architecture

Gleam/Lustre SPA with nested MVU. All I/O goes through a custom `Effect` type
with a single interpreter — `update` functions stay pure.

## Nested MVU

Two layers: `app.gleam` (shell + routing) delegates to `todo_page.gleam`
(feature page). The parent maps child effects through `effect.map`:

```gleam
pub fn update(model: Model, msg: Msg) -> #(Model, effect.Effect(Msg)) {
  case msg {
    TodoPageMsg(inner_msg) -> {
      let #(inner_model, inner_effect) =
        todo_page.update(model.todo_page, inner_msg)
      #(Model(..model, todo_page: inner_model), effect.map(inner_effect, TodoPageMsg))
    }
  }
}
```

## Effect System

`update` returns pure data — a single `effect.run` interprets effects:

| Effect               | Side effect                             |
| -------------------- | --------------------------------------- |
| `HttpRequest`        | `gleam_fetch` → typed callback          |
| `LoadFromStore`      | `window.localStorage.getItem`           |
| `SaveToStore`        | `window.localStorage.setItem`           |
| `Redirect`           | `window.location.assign`                |
| `After(delay, msg)`  | Dispatch `msg` after `delay` ms         |
| `Navigate`           | Click/popstate interception + pushState |
| `PushUrl/ReplaceUrl` | `history.pushState` / `replaceState`    |
| `Batch([...])`       | Run multiple effects                    |
| `None`               | No-op                                   |

### Bridging into Lustre

The shell wraps the inspectable `Effect` in Lustre's opaque type:

```gleam
fn update_with_effect(model, msg) -> #(Model, lustre_effect.Effect(Msg)) {
  let #(new_model, effect) = update(model, msg)
  #(new_model, lustre_effect.from(fn(dispatch) { effect.run(effect, dispatch) }))
}
```

### HTTP Helpers

Thin per-method constructors in `effect.gleam` delegate to `http_effect.send`:

```gleam
effect.get("/api/todos", callback)
effect.post(url, body, "application/json", callback)
effect.delete(url, callback)
```

## Guard Helpers

`guard.gleam` provides `use`-compatible early-return for `Option` and `Result`:

```gleam
use value <- guard.some(in: my_option, else_return: fn() { fallback })
use value <- guard.ok(in: my_result, else_return: fn(e) { handle_error(e) })
```

## Routing

No router library — custom navigation effects via browser APIs. URL path
segments determine visibility: `[]` → All, `["active"]` → Active,
`["completed"]` → Completed.

## Client Tests

Pure unit tests in `client/test/` using gleeunit. No browser or DOM — tests
call `update` with a `Model` and `Msg`, then assert the returned `Model` and
inspect the `Effect` payload.

```bash
just client-test
```

## When to add a page

| Condition                               | Pattern              |
| --------------------------------------- | -------------------- |
| Single feature, one concern             | Add to existing page |
| New feature with independent state      | New page module      |
| Feature shares state with existing page | Extend existing page |
| Global state (auth, theme, user prefs)  | Extend shell model   |
