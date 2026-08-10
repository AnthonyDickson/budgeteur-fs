import budgeteur/http_effect.{
  type HttpError, type HttpMethod, Delete, Get, Patch, Post, Put, send,
}
import gleam/function
import gleam/http/request
import gleam/io
import gleam/javascript/promise
import gleam/list
import gleam/time/calendar.{type Date}
import gleam/time/timestamp

/// An inspectable description of a side effect. `update` returns one of these
/// alongside the new model; the `run` interpreter executes it against the real
/// world. Because `Effect` is pure data, tests can pattern-match on it without
/// a browser, mock HTTP, or fake localStorage.
///
/// All variants carry raw strings — the effect system describes I/O intent,
/// not data semantics. Callers own serialisation and deserialisation.
///
/// For HTTP effects, use the per-method functions below (`get`, `post`, …).
/// For custom HTTP behaviour (auth headers, non-standard methods, or
/// non-JSON content types), construct an `HttpRequest` directly.
///
pub type Effect(msg) {
  HttpRequest(
    method: HttpMethod,
    url: String,
    body: String,
    content_type: String,
    callback: fn(Result(String, HttpError)) -> msg,
    transform: fn(request.Request(String)) -> request.Request(String),
  )
  LoadFromStore(key: String, callback: fn(Result(String, String)) -> msg)
  SaveToStore(key: String, value: String)
  LogError(String)
  /// This effect makes an HTTP request and triggers a page load, therefore it cannot be batched with other effects.
  Redirect(url: String)
  SetTitle(title: String)
  After(delay: Int, message: msg)
  InitRouting(handler: fn(String) -> msg)
  /// This effect does not trigger a page load, therefore it can be batched with other effects.
  PushUrl(url: String)
  /// This effect does not trigger a page load, therefore it can be batched with other effects.
  ReplaceUrl(url: String)
  /// Call `.showModal` on the DOM element with the given selector.
  /// If the selector cannot be found, a warning is printed to the console.
  ShowDialog(selector: String)
  /// Call `.close` on the DOM element with the given selector.
  /// If the selector cannot be found, a warning is printed to the console.
  CloseDialog(selector: String)
  GetLocalDate(dispatch: fn(Date) -> msg)
  Message(msg)
  Batch(effects: List(Effect(msg)))
  None
}

/// `GET` the given URL.
///
/// ```gleam
/// effect.get("/api/todos", fn(result) {
///   case result {
///     Ok(body) -> ClientFetchedTodos(body)
///     Error(err) -> ClientRequestFailed(err)
///   }
/// })
/// ```
///
pub fn get(
  url: String,
  callback: fn(Result(String, HttpError)) -> msg,
) -> Effect(msg) {
  HttpRequest(
    method: Get,
    url:,
    body: "",
    content_type: "",
    callback:,
    transform: function.identity,
  )
}

/// `POST` a pre-serialised body to the given URL with `application/json`.
///
/// ```gleam
/// effect.post("/api/todos", json.to_string(body), fn(result) {
///   case result {
///     Ok(_) -> NoOp
///     Error(err) -> TodoActionFailed(err)
///   }
/// })
/// ```
///
pub fn post(
  url: String,
  body: String,
  callback: fn(Result(String, HttpError)) -> msg,
) -> Effect(msg) {
  HttpRequest(
    method: Post,
    url:,
    body:,
    content_type: "application/json",
    callback:,
    transform: function.identity,
  )
}

/// `PUT` a pre-serialised body to the given URL with `application/json`.
///
/// ```gleam
/// effect.put("/api/todos/" <> id, body, fn(result) {
///   case result {
///     Ok(_) -> NoOp
///     Error(err) -> TodoActionFailed(err)
///   }
/// })
/// ```
///
pub fn put(
  url: String,
  body: String,
  callback: fn(Result(String, HttpError)) -> msg,
) -> Effect(msg) {
  HttpRequest(
    method: Put,
    url:,
    body:,
    content_type: "application/json",
    callback:,
    transform: function.identity,
  )
}

/// `PATCH` a pre-serialised body to the given URL with `application/json`.
///
/// ```gleam
/// effect.patch("/api/todos/" <> id, body, fn(result) {
///   case result {
///     Ok(_) -> NoOp
///     Error(err) -> TodoActionFailed(err)
///   }
/// })
/// ```
///
pub fn patch(
  url: String,
  body: String,
  callback: fn(Result(String, HttpError)) -> msg,
) -> Effect(msg) {
  HttpRequest(
    method: Patch,
    url:,
    body:,
    content_type: "application/json",
    callback:,
    transform: function.identity,
  )
}

/// `DELETE` the resource at the given URL.
///
/// ```gleam
/// effect.delete("/api/todos/" <> id, fn(result) {
///   case result {
///     Ok(_) -> NoOp
///     Error(err) -> TodoActionFailed(err)
///   }
/// })
/// ```
///
pub fn delete(
  url: String,
  callback: fn(Result(String, HttpError)) -> msg,
) -> Effect(msg) {
  HttpRequest(
    method: Delete,
    url:,
    body: "",
    content_type: "",
    callback:,
    transform: function.identity,
  )
}

/// Set up client-side routing: intercept clicks on internal links, listen for
/// back/forward navigation, and dispatch the initial URL. The handler receives
/// the full path (pathname + search + hash).
///
/// The handler turns each path into a message that your `update` function
/// receives. Return it from `init` so routing is active for the app's lifetime:
///
/// ```gleam
/// // in update
/// UrlChanged(path) -> #(model, effect.none()) // dispatch as a message
///
/// // in init
/// #(model, effect.init_routing(fn(path) { UrlChanged(path) }))
/// ```
///
/// Combined with `push_url` / `replace_url`, this drives an SPA without full
/// page reloads: navigating emits a `UrlChanged` that `update` handles.
///
pub fn init_routing(handler: fn(String) -> msg) -> Effect(msg) {
  InitRouting(handler:)
}

/// Push a new URL onto the browser's history stack without a full page reload.
/// Dispatches no message — the subsequent popstate/click handling (set up by
/// `init_routing`) delivers the new path as a message to `update`:
///
/// ```gleam
/// effect.push_url("/active"),
/// ```
///
pub fn push_url(url: String) -> Effect(msg) {
  PushUrl(url:)
}

/// Replace the current URL in the browser's history stack without a full page
/// reload. Dispatches no message — as with `push_url`, `init_routing` delivers
/// the new path to `update` as a message.
///
/// ```gleam
/// effect.replace_url("/active"),
/// ```
///
pub fn replace_url(url: String) -> Effect(msg) {
  ReplaceUrl(url:)
}

/// Set the document title (shown in the browser tab).
///
/// ```gleam
/// effect.set_title("My App")
/// ```
///
pub fn set_title(title: String) -> Effect(msg) {
  SetTitle(title:)
}

@external(javascript, "./effect_ffi.mjs", "loadFromStore")
fn raw_load_from_store(key: String) -> String

@external(javascript, "./effect_ffi.mjs", "saveToStore")
fn raw_save_to_store(key: String, value: String) -> Nil

@external(javascript, "./effect_ffi.mjs", "initRouting")
fn raw_init_routing(handler: fn(String) -> Nil) -> Nil

@external(javascript, "./effect_ffi.mjs", "pushUrl")
fn raw_push_url(url: String) -> Nil

@external(javascript, "./effect_ffi.mjs", "replaceUrl")
fn raw_replace_url(url: String) -> Nil

@external(javascript, "./effect_ffi.mjs", "redirect")
fn raw_redirect(url: String) -> Nil

@external(javascript, "./effect_ffi.mjs", "setTitle")
fn raw_set_title(title: String) -> Nil

@external(javascript, "./effect_ffi.mjs", "showDialog")
fn raw_show_dialog(selector: String) -> Nil

@external(javascript, "./effect_ffi.mjs", "closeDialog")
fn raw_close_dialog(selector: String) -> Nil

/// Transform an `Effect(a)` into an `Effect(b)` by applying a function to
/// every message the effect produces. This is the analogue of `Cmd.map` in
/// Elmish — it lets a parent component embed a child's effects.
///
pub fn map(effect: Effect(a), f: fn(a) -> b) -> Effect(b) {
  case effect {
    HttpRequest(method:, url:, body:, content_type:, callback:, transform:) ->
      HttpRequest(
        method:,
        url:,
        body:,
        content_type:,
        callback: fn(result) { f(callback(result)) },
        transform:,
      )
    LoadFromStore(key:, callback:) ->
      LoadFromStore(key:, callback: fn(result) { f(callback(result)) })
    SaveToStore(key:, value:) -> SaveToStore(key:, value:)
    LogError(message) -> LogError(message)
    Redirect(url:) -> Redirect(url:)
    SetTitle(title:) -> SetTitle(title:)
    After(delay:, message:) -> After(delay:, message: f(message))
    InitRouting(handler:) -> InitRouting(handler: fn(path) { f(handler(path)) })
    PushUrl(url:) -> PushUrl(url:)
    ReplaceUrl(url:) -> ReplaceUrl(url:)
    ShowDialog(selector:) -> ShowDialog(selector:)
    CloseDialog(selector:) -> CloseDialog(selector:)
    GetLocalDate(message) -> GetLocalDate(fn(date) { f(message(date)) })
    Message(message) -> Message(f(message))
    Batch(effects:) -> Batch(list.map(effects, fn(e) { map(e, f) }))
    None -> None
  }
}

/// Combine a list of effects into a single `Batch` effect.
///
/// ```gleam
/// effect.batch([fetch_todos(), load_todos_from_store()])
/// ```
///
pub fn batch(effects: List(Effect(msg))) -> Effect(msg) {
  Batch(effects)
}

/// A no-op effect — produces no messages.
///
pub fn none() -> Effect(msg) {
  None
}

/// Execute an `Effect` against the real world. This is the single point where
/// the application touches browser APIs — all `update` logic stays pure.
///
/// Wired into Lustre via:
/// ```gleam
/// lustre_effect.from(fn(dispatch) { effect.run(effect, dispatch) })
/// ```
///
pub fn run(effect: Effect(msg), dispatch: fn(msg) -> Nil) -> Nil {
  case effect {
    HttpRequest(method:, url:, body:, content_type:, callback:, transform:) -> {
      let _ =
        send(method, url, body, content_type, transform)
        |> promise.map(fn(result) { dispatch(callback(result)) })
      Nil
    }

    LoadFromStore(key:, callback:) -> {
      let value = raw_load_from_store(key)
      let result = case value {
        "" -> Error("Not found")
        _ -> Ok(value)
      }
      dispatch(callback(result))
    }

    SaveToStore(key:, value:) -> raw_save_to_store(key, value)

    LogError(message) -> io.println_error(message)

    Redirect(url:) -> raw_redirect(url)

    SetTitle(title:) -> raw_set_title(title)

    After(delay:, message:) -> {
      let _ =
        promise.wait(delay)
        |> promise.tap(fn(_) { dispatch(message) })
      Nil
    }

    InitRouting(handler:) -> {
      raw_init_routing(fn(path) { dispatch(handler(path)) })
    }

    PushUrl(url:) -> raw_push_url(url)

    ReplaceUrl(url:) -> raw_replace_url(url)

    ShowDialog(selector:) -> raw_show_dialog(selector)

    CloseDialog(selector:) -> raw_close_dialog(selector)

    GetLocalDate(message) -> {
      let now = timestamp.system_time()
      let #(date, _) = timestamp.to_calendar(now, calendar.local_offset())
      dispatch(message(date))
    }

    Message(message) -> dispatch(message)

    Batch(effects:) -> {
      effects
      |> list.each(fn(e) { run(e, dispatch) })
      Nil
    }

    None -> Nil
  }
}
