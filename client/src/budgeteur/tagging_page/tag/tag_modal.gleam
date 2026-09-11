import budgeteur/shared/api_error.{type ApiError}
import budgeteur/shared/field
import budgeteur/shared/form_modal
import budgeteur/shared/modal_ui
import budgeteur/tag.{type Tag, Tag}
import budgeteur/tagging_page/tag_write_request.{
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

pub type NameError {
  NameRequired
  TooLong
  Duplicate
}

pub type NameField =
  field.Field(String, NameError)

pub type Form {
  Form(name: NameField, color: String)
}

pub type Modal =
  form_modal.Modal(Form)

pub type Request =
  form_modal.Request(TagWriteRequest)

pub type Outcome =
  form_modal.Outcome(Tag)

pub fn hidden() -> Modal {
  form_modal.hidden()
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

pub fn update(
  state: Modal,
  msg: Msg,
  tags: List(Tag),
) -> #(Modal, List(Request), Outcome) {
  case msg {
    CreateRequested ->
      case state {
        form_modal.Submitting(..) -> #(state, [], form_modal.NoChange)
        _ -> #(create_modal(), [form_modal.ShowDialog], form_modal.NoChange)
      }
    EditRequested(tag:) ->
      case state {
        form_modal.Submitting(..) -> #(state, [], form_modal.NoChange)
        _ -> #(edit_modal(tag), [form_modal.ShowDialog], form_modal.NoChange)
      }
    NameChanged(value:) -> #(set_name(state, value), [], form_modal.NoChange)
    ColorChosen(value:) -> #(set_color(state, value), [], form_modal.NoChange)
    SaveRequested -> save(state, tags)
    SaveCompleted(result: Ok(tag)) -> on_save_succeeded(state, tag)
    SaveCompleted(result: Error(error)) -> #(
      form_modal.failed(state, error),
      [],
      form_modal.NoChange,
    )
    CancelRequested -> cancel(state)
    DialogDismissed -> #(form_modal.dismissed(state), [], form_modal.NoChange)
  }
}

/// An empty modal for creating a new tag.
fn create_modal() -> Modal {
  form_modal.create(Form(name: field.Empty(""), color: default_color))
}

/// A modal pre-filled with an existing tag, ready for renaming.
fn edit_modal(tag: Tag) -> Modal {
  let Tag(id:, ..) = tag
  form_modal.edit(
    id,
    Form(name: field.Valid(value: tag.name, input: tag.name), color: tag.color),
  )
}

/// Validate and set the name field. No op for Hidden and Submitting states.
fn set_name(state: Modal, name: String) -> Modal {
  form_modal.set_form(state, fn(form) {
    Form(..form, name: field.validate(name, validate_name, is_required))
  })
}

/// Validate and set the color field. No op for Hidden and Submitting states.
fn set_color(state: Modal, color: String) -> Modal {
  form_modal.set_form(state, fn(form) { Form(..form, color:) })
}

fn save(state: Modal, tags: List(Tag)) -> #(Modal, List(Request), Outcome) {
  case form_modal.mode(state) {
    None -> #(state, [], form_modal.NoChange)
    Some(mode) -> {
      let other_tag_names =
        case mode {
          form_modal.Create -> tags
          form_modal.Edit(id:) -> list.filter(tags, fn(tag) { tag.id != id })
        }
        |> list.map(fn(tag) { tag.name })

      case
        form_modal.submit(state, fn(form) {
          validate_form(form, other_tag_names)
        })
      {
        #(modal, Some(request)) -> #(modal, [request], form_modal.NoChange)
        #(modal, None) -> #(modal, [], form_modal.NoChange)
      }
    }
  }
}

fn on_save_succeeded(
  state: Modal,
  tag: Tag,
) -> #(Modal, List(Request), Outcome) {
  case form_modal.succeeded(state, tag) {
    #(modal, outcome) ->
      case outcome {
        form_modal.NoChange -> #(modal, [], form_modal.NoChange)
        form_modal.Created(_) | form_modal.Updated(_) -> #(
          modal,
          [form_modal.CloseDialog],
          outcome,
        )
      }
  }
}

fn cancel(state: Modal) -> #(Modal, List(Request), Outcome) {
  case form_modal.cancel(state) {
    #(modal, True) -> #(modal, [form_modal.CloseDialog], form_modal.NoChange)
    #(modal, False) -> #(modal, [], form_modal.NoChange)
  }
}

// Validation

/// Validate the form against the other tags' names. On success returns the
/// write request and the (finalized) form to keep while submitting; on
/// failure returns the form with inline errors set. `other_tag_names`
/// excludes the tag being edited, if any.
fn validate_form(
  form: Form,
  other_tag_names: List(String),
) -> Result(#(TagWriteRequest, Form), Form) {
  let form = finalize(form, other_tag_names)

  case field.value(form.name) {
    Some(name) -> Ok(#(TagWriteRequest(name, form.color), form))
    None -> Error(form)
  }
}

/// Finalize the form after a submit attempt: blank fields become errors, and
/// the name is checked against the names of the other tags. Duplicate checks
/// are case-sensitive, mirroring the server's `UNIQUE(UserId, Name)`
/// constraint so a duplicate is caught inline before the round trip; the
/// server check remains authoritative when the client's tag list is stale.
fn finalize(form: Form, other_tag_names: List(String)) -> Form {
  let Form(name:, ..) = form
  let name = field.finalize(name, fn() { NameRequired })
  let name = case name {
    field.Valid(value:, ..) ->
      case list.contains(other_tag_names, value) {
        True -> field.mark_invalid(name, Duplicate)
        False -> name
      }
    field.Empty(..) | field.Invalid(..) -> name
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

/// A parse error is demoted to a blank `Empty` field (no inline error while
/// typing) only when it is the required error, e.g. a whitespace-only name.
fn is_required(error: NameError) -> Bool {
  case error {
    NameRequired -> True
    TooLong | Duplicate -> False
  }
}

// View

/// Always renders the `<dialog>` element so the show/close dialog effects can
/// find it. The dialog is `closedby="none"` while a request is in flight,
/// locking it so it cannot be dismissed mid-request. The `on("close")` handler
/// covers browser-initiated dismissals (Esc / backdrop click) while open; a
/// close event can only fire when the dialog was open, so a stale one cannot
/// arrive while `Hidden` is shown.
pub fn view(state: Modal) -> Element(Msg) {
  let submitting = case state {
    form_modal.Submitting(..) -> True
    _ -> False
  }

  html.dialog(
    [
      event.on("close", decode.success(DialogDismissed)),
      ..modal_ui.dialog_attributes(dom_id, "tag-modal", submitting)
    ],
    case state {
      form_modal.Hidden -> []
      form_modal.Active(form:, mode:) ->
        view_form(form, mode, api_error: None, submitting: False)
      form_modal.Submitting(form:, mode:) ->
        view_form(form, mode, api_error: None, submitting: True)
      form_modal.Errored(form:, mode:, error:) ->
        view_form(form, mode, api_error: Some(error), submitting: False)
    },
  )
}

fn view_form(
  form: Form,
  mode: form_modal.Mode,
  api_error api_error: Option(String),
  submitting submitting: Bool,
) -> List(Element(Msg)) {
  let Form(name:, color:) = form

  let #(title, submit_label, submitting_label) = case mode {
    form_modal.Create -> #("Create Tag", "Create tag", "Creating tag...")
    form_modal.Edit(_) -> #("Edit Tag", "Save", "Saving...")
  }

  let name_error = field.error(name)
  let has_error = field.has_error(name)

  [
    html.h2([attribute.class("mb-4 text-lg font-semibold text-gray-900")], [
      html.text(title),
    ]),
    html.form(
      [
        event.on_submit(fn(_) { SaveRequested }),
        attribute.class("space-y-4"),
      ],
      [
        case api_error {
          Some(message) ->
            modal_ui.error_banner(
              testid: "tag-api-error",
              message: "Could not save tag: " <> message,
              extra_class: "",
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
              <> "focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500 "
              <> "disabled:cursor-not-allowed disabled:bg-gray-100 disabled:text-gray-400",
            ),
            attribute.classes([
              #(modal_ui.error_border_style, has_error),
            ]),
            attribute.autofocus(True),
            attribute.value(field.input(name)),
            attribute.disabled(submitting),
            event.on_input(NameChanged),
          ]),
          view_name_error(name_error),
          html.p([attribute.class("mt-1 text-xs text-gray-500")], [
            html.text("Prefer broad categories, e.g. Food & Drink over Coffee."),
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
                    <> "disabled:cursor-not-allowed disabled:opacity-60 "
                    <> case is_selected {
                      True ->
                        "ring-2 ring-gray-900 ring-offset-2 "
                        <> "border-2 border-white"
                      False -> "hover:scale-105"
                    },
                  ),
                  attribute.style("background-color", palette_color),
                  attribute.aria_label("Use color " <> palette_color),
                  attribute.disabled(submitting),
                  event.on_click(ColorChosen(palette_color)),
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
          modal_ui.cancel_button(
            testid: "tag-cancel-button",
            disabled: submitting,
            on_click: CancelRequested,
          ),
          modal_ui.submit_button(
            testid: "tag-submit-button",
            idle_label: submit_label,
            busy_label: submitting_label,
            busy: submitting,
            disabled: has_error,
          ),
        ]),
      ],
    ),
  ]
}

fn view_name_error(name_error: Option(NameError)) -> Element(Msg) {
  case name_error {
    Some(NameRequired) -> modal_ui.form_error_message("Name cannot be empty")
    Some(TooLong) ->
      modal_ui.form_error_message(
        "Name cannot be longer than "
        <> int.to_string(max_name_length)
        <> " characters",
      )
    Some(Duplicate) ->
      modal_ui.form_error_message("A tag with this name already exists")
    None -> element.none()
  }
}

fn check_icon() -> Element(Msg) {
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
