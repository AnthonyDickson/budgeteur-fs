import budgeteur/shared/api_error.{type ApiError}
import budgeteur/tags_and_rules/tag/tag.{type Tag, Tag}
import budgeteur/tags_and_rules/tag_write_request.{
  type TagWriteRequest, TagWriteRequest,
}
import gleam/dynamic/decode
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import youid/uuid.{type Uuid}

pub const max_name_length = 64

/// Default color selected in the create form.
pub const default_color = "#6366F1"

pub const color_palette = [
  "#64748B",
  "#EF4444",
  "#F97316",
  "#F59E0B",
  "#22C55E",
  "#14B8A6",
  "#0EA5E9",
  "#6366F1",
  "#8B5CF6",
  "#EC4899",
]

const dom_id = "tag_modal"

/// The CSS selector for the modal dialog element. The `#` hash prefix is
/// composed here so callers (e.g. the show/close dialog effects) never have to
/// remember it.
pub const dom_id_selector = "#" <> dom_id

const error_border_style = "border-red-400 focus:border-red-500 focus:outline-none focus:ring-1 focus:ring-red-500"

/// How long a save request (create or update) may stay in flight before the
/// transport aborts it. This should be applied by the page via `effect.with_timeout`.
pub const submit_timeout_ms = 10_000

pub type NameError {
  NameRequired
  TooLong
  Duplicate
}

pub type NameField {
  EmptyName(input: String)
  ValidName(input: String)
  InvalidName(input: String, error: NameError)
}

pub type Form {
  Form(name: NameField, color: String)
}

/// The mode the tag form modal is in.
pub type FormMode {
  /// Open an empty form
  Create
  /// Pre-fill the form with an existing tag
  Edit(id: Uuid)
}

/// State of the tag form modal: the form fields and the mode. 
pub type Modal {
  /// The modal is not visible
  Hidden
  /// The user is editing the form, it may have client-side validation errors
  Active(form: Form, mode: FormMode)
  /// The API request is in-flight
  Submitting(form: Form, mode: FormMode)
  /// The API request failed
  Errored(form: Form, mode: FormMode, error: String)
}

pub fn hidden() -> Modal {
  Hidden
}

/// Transition to the submitting state from the Active or Errored state. Returns an error when called in other states.
pub fn submitting(state: Modal) -> Result(Modal, Nil) {
  case state {
    Active(form:, mode:) | Errored(form:, mode:, ..) ->
      Ok(Submitting(form:, mode:))
    _ -> Error(Nil)
  }
}

pub fn errored(state: Modal, api_error: String) -> Result(Modal, Nil) {
  case state {
    Submitting(form:, mode:) -> Ok(Errored(form:, mode:, error: api_error))
    _ -> Error(Nil)
  }
}

/// Get the ID of the tag being edited or None if the modal is in create mode.
pub fn get_id(state: Modal) -> Option(Uuid) {
  case state {
    Hidden -> None
    Active(mode:, ..) | Submitting(mode:, ..) | Errored(mode:, ..) ->
      case mode {
        Create -> None
        Edit(id:) -> Some(id)
      }
  }
}

pub fn get_name(state: Modal) -> Option(NameField) {
  case state {
    Active(form:, ..) | Submitting(form:, ..) | Errored(form:, ..) ->
      Some(form.name)
    Hidden -> None
  }
}

fn field_name_input(field: NameField) -> String {
  case field {
    EmptyName(input) -> input
    ValidName(input) -> input
    InvalidName(input:, ..) -> input
  }
}

fn field_name_error(field: NameField) -> Option(NameError) {
  case field {
    InvalidName(error:, ..) -> Some(error)
    _ -> None
  }
}

// Update

pub type Msg {
  CreateRequested
  EditRequested(tag: Tag)
  NameChanged(value: String)
  ColorChosen(value: String)
  SaveRequested
  // Response to the in-flight create or update; the `Created`/`Updated`
  // outcome variant is chosen from the `mode` in the `Submitting` state.
  // Transport timeouts surface here as `Error(NetworkError(...))`.
  SaveCompleted(result: Result(Tag, ApiError))
  // Cancel button (dialog stays open until page closes it)
  CancelRequested
  // browser dismissed the dialog (Esc / backdrop click)
  DialogDismissed
}

pub type Request {
  ShowDialog
  CloseDialog
  /// POST /api/tags. Same payload shape as the update request.
  CreateTag(request: TagWriteRequest)
  /// PUT /api/tags/{id}.
  PutTag(id: Uuid, request: TagWriteRequest)
}

pub type Outcome {
  NoChange
  Created(tag: Tag)
  Updated(tag: Tag)
}

pub fn update(
  state: Modal,
  msg: Msg,
  tags: List(Tag),
) -> #(Modal, List(Request), Outcome) {
  case msg {
    CreateRequested ->
      case state {
        Submitting(..) -> #(state, [], NoChange)
        _ -> #(create_modal(), [ShowDialog], NoChange)
      }
    EditRequested(tag:) ->
      case state {
        Submitting(..) -> #(state, [], NoChange)
        _ -> #(edit_modal(tag), [ShowDialog], NoChange)
      }
    NameChanged(value:) -> #(set_name(state, value), [], NoChange)
    ColorChosen(value:) -> #(set_color(state, value), [], NoChange)
    SaveRequested -> save(state, tags)
    SaveCompleted(result: Ok(tag)) -> on_save_succeeded(state, tag)
    SaveCompleted(result: Error(error)) -> on_save_failed(state, error)
    CancelRequested -> cancel(state)
    DialogDismissed -> dismiss(state)
  }
}

/// An empty modal for creating a new tag.
pub fn create_modal() -> Modal {
  Active(form: Form(name: EmptyName(""), color: default_color), mode: Create)
}

/// A modal pre-filled with an existing tag, ready for renaming.
pub fn edit_modal(tag: Tag) -> Modal {
  let Tag(id:, ..) = tag
  Active(
    form: Form(name: ValidName(input: tag.name), color: tag.color),
    mode: Edit(id),
  )
}

/// Validate and set the name field. No op for Hidden and Submitting states.
pub fn set_name(state: Modal, name: String) -> Modal {
  case state {
    Active(form:, ..) -> Active(..state, form: update_name_field(name, form))
    Errored(form:, ..) -> Errored(..state, form: update_name_field(name, form))
    Hidden | Submitting(..) -> state
  }
}

/// Validate and set the color field. No op for Hidden and Submitting states.
pub fn set_color(state: Modal, color: String) -> Modal {
  case state {
    Active(form:, ..) -> Active(..state, form: Form(..form, color:))
    Errored(form:, ..) -> Errored(..state, form: Form(..form, color:))
    Hidden | Submitting(..) -> state
  }
}

fn save(state: Modal, tags: List(Tag)) -> #(Modal, List(Request), Outcome) {
  case state {
    Active(form:, mode:) | Errored(form:, mode:, ..) -> {
      let other_tags =
        case mode {
          Create -> tags
          Edit(id:) -> list.filter(tags, fn(tag) { tag.id != id })
        }
        |> list.map(fn(tag) { tag.name })

      case validate(state, other_tags) {
        Ok(#(name, color)) -> {
          let request = case mode {
            Create -> CreateTag(TagWriteRequest(name, color))
            Edit(id:) -> PutTag(id, TagWriteRequest(name, color))
          }

          #(Submitting(form, mode), [request], NoChange)
        }
        Error(updated_state_with_errors) -> #(
          updated_state_with_errors,
          [],
          NoChange,
        )
      }
    }

    Submitting(..) | Hidden -> #(state, [], NoChange)
  }
}

fn on_save_succeeded(
  state: Modal,
  tag: Tag,
) -> #(Modal, List(Request), Outcome) {
  case state {
    Submitting(mode:, ..) ->
      case mode {
        Create -> #(Hidden, [CloseDialog], Created(tag))
        Edit(..) -> #(Hidden, [CloseDialog], Updated(tag))
      }
    _ -> #(state, [], NoChange)
  }
}

fn on_save_failed(
  state: Modal,
  api_error: ApiError,
) -> #(Modal, List(Request), Outcome) {
  case state {
    Submitting(form:, mode:) -> #(
      Errored(form:, mode:, error: api_error.details),
      [],
      NoChange,
    )
    _ -> #(state, [], NoChange)
  }
}

fn cancel(state: Modal) -> #(Modal, List(Request), Outcome) {
  case state {
    Submitting(..) | Hidden -> #(state, [], NoChange)
    Active(..) | Errored(..) -> #(Hidden, [CloseDialog], NoChange)
  }
}

fn dismiss(state: Modal) -> #(Modal, List(Request), Outcome) {
  case state {
    Submitting(..) | Hidden -> #(state, [], NoChange)
    Active(..) | Errored(..) -> #(Hidden, [], NoChange)
  }
}

// Validation

/// Validate the form. On success returns the trimmed name and color; on
/// failure returns the modal with the form with inline errors set.
pub fn validate(
  state: Modal,
  other_tag_names: List(String),
) -> Result(#(String, String), Modal) {
  case state {
    Hidden | Submitting(..) -> Error(state)
    Active(form:, ..) | Errored(form:, ..) -> {
      let form = finalize(form, other_tag_names)

      case form {
        Form(name: ValidName(input: name), color:) ->
          Ok(#(string.trim(name), color))
        _ -> Error(set_form(state, form))
      }
    }
  }
}

/// Finalize the form after a submit attempt: blank fields become errors, and
/// the name is checked against the names of the other tags. `other_tag_names`
/// excludes the tag being edited, if any. Duplicate checks are case-sensitive
/// to mirror the future `UNIQUE(UserId, Name)` DB constraint.
fn finalize(form: Form, other_tag_names: List(String)) -> Form {
  let Form(name:, ..) = form
  let name = case name {
    EmptyName(input) -> InvalidName(input:, error: NameRequired)
    ValidName(input) -> {
      let trimmed = string.trim(input)
      case list.contains(other_tag_names, trimmed) {
        True -> InvalidName(input:, error: Duplicate)
        False -> ValidName(input: trimmed)
      }
    }
    other -> other
  }
  Form(..form, name:)
}

fn set_form(state: Modal, form: Form) -> Modal {
  case state {
    Hidden | Submitting(..) -> state
    Active(..) -> Active(..state, form:)
    Errored(..) -> Errored(..state, form:)
  }
}

fn update_name_field(name: String, form: Form) -> Form {
  let name = case validate_name(name) {
    Ok(name) -> ValidName(input: name)
    Error(NameRequired) -> EmptyName(name)
    Error(error) -> InvalidName(input: name, error:)
  }

  Form(..form, name:)
}

fn validate_name(name: String) -> Result(String, NameError) {
  let trimmed = string.trim(name)

  case string.is_empty(trimmed) {
    True -> Error(NameRequired)
    False ->
      case string.length(trimmed) > max_name_length {
        True -> Error(TooLong)
        False -> Ok(trimmed)
      }
  }
}

// View

type ViewContext(msg) {
  ViewContext(
    state: Modal,
    on_name_input: fn(String) -> msg,
    on_color_click: fn(String) -> msg,
    on_submit: msg,
    on_cancel: msg,
    on_close: msg,
  )
}

pub fn view(
  state: Modal,
  on_name_input on_name_input: fn(String) -> msg,
  on_color_click on_color_click: fn(String) -> msg,
  on_submit on_submit: msg,
  on_cancel on_cancel: msg,
  on_close on_close: msg,
) -> Element(msg) {
  let context =
    ViewContext(
      state,
      on_name_input:,
      on_color_click:,
      on_submit:,
      on_cancel:,
      on_close:,
    )

  case state {
    Hidden -> view_hidden()
    Active(form:, mode:) ->
      view_form(form, mode, api_error: None, submitting: False, context:)
    Submitting(form:, mode:) ->
      view_form(form, mode, api_error: None, submitting: True, context:)
    Errored(form:, mode:, error:) ->
      view_form(form, mode, api_error: Some(error), submitting: False, context:)
  }
}

fn view_form(
  form: Form,
  mode: FormMode,
  api_error api_error: Option(String),
  submitting submitting: Bool,
  context context: ViewContext(msg),
) -> Element(msg) {
  let Form(name:, color:) = form

  let #(title, submit_label, submitting_label) = case mode {
    Create -> #("Create Tag", "Create tag", "Creating tag...")
    Edit(_) -> #("Edit Tag", "Save", "Saving...")
  }

  let name_error = field_name_error(name)
  let has_error = option.is_some(name_error)

  html.dialog(
    [
      attribute.id(dom_id),
      attribute.attribute("data-testid", "tag-modal"),
      attribute.class(
        "mx-auto my-auto w-full max-w-md rounded-lg border border-gray-200 bg-white p-6 shadow-xl backdrop:bg-gray-900/50",
      ),
      // "closedby" = "any" is needed to allow the dialog to be closed by
      // clicking outside the dialog.
      attribute.attribute("closedby", "any"),
      event.on("close", decode.success(context.on_close)),
    ],
    [
      html.h2([attribute.class("mb-4 text-lg font-semibold text-gray-900")], [
        html.text(title),
      ]),
      html.form(
        [
          event.on_submit(fn(_) { context.on_submit }),
          attribute.class("space-y-4"),
        ],
        [
          case api_error {
            Some(message) ->
              html.p(
                [
                  attribute.attribute("role", "alert"),
                  attribute.attribute("data-testid", "tag-api-error"),
                  attribute.class(
                    "rounded-md border border-red-200 bg-red-50 px-3 py-2 text-sm text-red-700",
                  ),
                ],
                [html.text("Could not save tag: " <> message)],
              )
            None -> element.none()
          },
          html.label([attribute.class("block")], [
            html.span(
              [attribute.class("mb-1 block text-sm font-medium text-gray-700")],
              [html.text("Name")],
            ),
            html.input([
              attribute.type_("text"),
              attribute.attribute("data-testid", "tag-name-input"),
              attribute.placeholder("e.g. Food & Drink"),
              attribute.class(
                "block w-full rounded-md border border-gray-300 px-3 py-2 text-sm text-gray-900 shadow-sm "
                <> "focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500",
              ),
              attribute.classes([
                #(error_border_style, option.is_some(name_error)),
              ]),
              attribute.value(field_name_input(name)),
              event.on_input(context.on_name_input),
            ]),
            view_name_error(name_error),
            html.p([attribute.class("mt-1 text-xs text-gray-500")], [
              html.text(
                "Prefer broad categories, e.g. Food & Drink over Coffee.",
              ),
            ]),
          ]),
          html.fieldset([attribute.class("block")], [
            html.legend(
              [attribute.class("mb-1 block text-sm font-medium text-gray-700")],
              [html.text("Color")],
            ),
            html.div(
              [attribute.class("flex flex-wrap gap-3")],
              list.map(color_palette, fn(palette_color) {
                let is_selected = palette_color == color
                html.button(
                  [
                    attribute.type_("button"),
                    attribute.attribute(
                      "data-testid",
                      "tag-color-" <> string.replace(palette_color, "#", "hex"),
                    ),
                    attribute.class(
                      "flex h-8 w-8 items-center justify-center rounded-full "
                      <> "focus:outline-none focus:ring-2 focus:ring-offset-2 "
                      <> case is_selected {
                        True ->
                          "ring-2 ring-gray-900 ring-offset-2 "
                          <> "border-2 border-white"
                        False -> "hover:scale-105"
                      },
                    ),
                    attribute.style("background-color", palette_color),
                    attribute.aria_label("Use color " <> palette_color),
                    event.on_click(context.on_color_click(palette_color)),
                  ],
                  case is_selected {
                    True -> [check_icon()]
                    False -> []
                  },
                )
              }),
            ),
          ]),
          html.div([attribute.class("flex justify-end gap-3 pt-2")], [
            html.button(
              [
                attribute.type_("button"),
                attribute.attribute("data-testid", "tag-cancel-button"),
                attribute.class(
                  "rounded-md border border-gray-300 bg-white px-4 py-2 text-sm font-medium text-gray-700 "
                  <> "hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-gray-500 focus:ring-offset-2 "
                  <> "disabled:cursor-not-allowed disabled:bg-gray-100 disabled:text-gray-400 disabled:hover:bg-gray-100",
                ),
                attribute.disabled(submitting),
                event.on_click(context.on_cancel),
              ],
              [html.text("Cancel")],
            ),
            html.button(
              [
                attribute.type_("submit"),
                attribute.attribute("data-testid", "tag-submit-button"),
                attribute.class(
                  "inline-flex items-center justify-center gap-2 rounded-md bg-indigo-600 px-4 py-2 text-sm font-medium "
                  <> "text-white hover:bg-indigo-500 focus:outline-none focus:ring-2 focus:ring-indigo-500 "
                  <> "focus:ring-offset-2 disabled:cursor-not-allowed disabled:bg-gray-400 disabled:hover:bg-gray-400",
                ),
                attribute.disabled(has_error || submitting),
              ],
              case submitting {
                True -> [
                  html.span(
                    [
                      attribute.attribute("aria-hidden", "true"),
                      attribute.class(
                        "h-4 w-4 animate-spin rounded-full border-2 border-white/40 border-t-white",
                      ),
                    ],
                    [],
                  ),
                  html.text(submitting_label),
                ]
                False -> [html.text(submit_label)]
              },
            ),
          ]),
        ],
      ),
    ],
  )
}

fn view_name_error(name_error: Option(NameError)) -> Element(msg) {
  case name_error {
    Some(NameRequired) -> form_error_message("Name cannot be empty")
    Some(TooLong) ->
      form_error_message(
        "Name cannot be longer than "
        <> int.to_string(max_name_length)
        <> " characters",
      )
    Some(Duplicate) -> form_error_message("A tag with this name already exists")
    None -> element.none()
  }
}

fn view_hidden() -> Element(msg) {
  html.dialog(
    [
      attribute.id(dom_id),
      attribute.attribute("data-testid", "tag-modal"),
      attribute.class(
        "mx-auto my-auto w-full max-w-md rounded-lg border border-gray-200 bg-white p-6 shadow-xl backdrop:bg-gray-900/50",
      ),
      // "closedby" = "any" is needed to allow the dialog to be closed by
      // clicking outside the dialog.
      attribute.attribute("closedby", "any"),
    ],
    [],
  )
}

fn check_icon() -> Element(msg) {
  html.svg(
    [
      attribute.attribute("fill", "none"),
      attribute.attribute("viewBox", "0 0 24 24"),
      attribute.attribute("stroke-width", "3"),
      attribute.attribute("stroke", "currentColor"),
      attribute.class("h-4 w-4 text-white"),
      attribute.attribute("aria-hidden", "true"),
    ],
    [
      element.namespaced(
        "http://www.w3.org/2000/svg",
        "path",
        [
          attribute.attribute("stroke-linecap", "round"),
          attribute.attribute("stroke-linejoin", "round"),
          attribute.attribute("d", "m4.5 12.75 6 6 9-13.5"),
        ],
        [],
      ),
    ],
  )
}

fn form_error_message(text: String) -> Element(msg) {
  html.p([attribute.class("mt-1 text-sm text-red-600")], [html.text(text)])
}
