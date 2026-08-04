import gleam/function
import gleam/http/request
import gleam/io
import gleam/javascript/promise
import gleam/list
import budgeteur/http_effect.{
  type HttpError, type HttpMethod, Delete, Get, Patch, Post, Put, send,
}

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
  Message(msg)
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
  Redirect(url: String)
  SetTitle(title: String)
  After(delay: Int, message: msg)
  Navigate(handler: fn(String) -> msg)
  PushUrl(url: String)
  ReplaceUrl(url: String)
  Batch(effects: List(Effect(msg)))
  None
}

/// `GET` the given URL.
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
pub fn navigate(handler: fn(String) -> msg) -> Effect(msg) {
  Navigate(handler:)
}

/// Push a new URL onto the browser's history stack without a full page reload.
/// Dispatches no message.
///
pub fn push_url(url: String) -> Effect(msg) {
  PushUrl(url:)
}

/// Replace the current URL in the browser's history stack without a full page
/// reload. Dispatches no message.
///
pub fn replace_url(url: String) -> Effect(msg) {
  ReplaceUrl(url:)
}

/// Set the document title (shown in the browser tab).
///
pub fn set_title(title: String) -> Effect(msg) {
  SetTitle(title:)
}

@external(javascript, "./effect_ffi.mjs", "loadFromStore")
fn raw_load_from_store(key: String) -> String

@external(javascript, "./effect_ffi.mjs", "saveToStore")
fn raw_save_to_store(key: String, value: String) -> Nil

@external(javascript, "./effect_ffi.mjs", "initNavigation")
fn raw_init_navigation(handler: fn(String) -> Nil) -> Nil

@external(javascript, "./effect_ffi.mjs", "pushUrl")
fn raw_push_url(url: String) -> Nil

@external(javascript, "./effect_ffi.mjs", "replaceUrl")
fn raw_replace_url(url: String) -> Nil

@external(javascript, "./effect_ffi.mjs", "redirect")
fn raw_redirect(url: String) -> Nil

@external(javascript, "./effect_ffi.mjs", "setTitle")
fn raw_set_title(title: String) -> Nil

/// Transform an `Effect(a)` into an `Effect(b)` by applying a function to
/// every message the effect produces. This is the analogue of `Cmd.map` in
/// Elmish — it lets a parent component embed a child's effects.
///
pub fn map(effect: Effect(a), f: fn(a) -> b) -> Effect(b) {
  case effect {
    Message(message) -> Message(f(message))
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
    Navigate(handler:) -> Navigate(handler: fn(path) { f(handler(path)) })
    PushUrl(url:) -> PushUrl(url:)
    ReplaceUrl(url:) -> ReplaceUrl(url:)
    Batch(effects:) -> Batch(list.map(effects, fn(e) { map(e, f) }))
    None -> None
  }
}

/// Combine a list of effects into a single `Batch` effect.
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
    Message(message) -> dispatch(message)

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

    Navigate(handler:) -> {
      raw_init_navigation(fn(path) { dispatch(handler(path)) })
    }

    PushUrl(url:) -> raw_push_url(url)

    ReplaceUrl(url:) -> raw_replace_url(url)

    Batch(effects:) -> {
      effects
      |> list.each(fn(e) { run(e, dispatch) })
      Nil
    }

    None -> Nil
  }
}
