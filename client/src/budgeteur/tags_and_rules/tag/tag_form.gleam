import budgeteur/tags_and_rules/tag/tag.{type Tag, Tag}
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

/// Default color selected in the create form. Matches the `Categories.Color`
/// default from migration 001.
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

/// State of the tag form modal: the form fields and the mode. Saving is
/// synchronous in the local MVP, so there is no `submitting` flag.
pub type ModalState {
  ModalState(form: Form, mode: FormMode)
}

pub fn empty_modal() -> ModalState {
  ModalState(
    form: Form(name: EmptyName(""), color: default_color),
    mode: Create,
  )
}

/// A modal pre-filled with an existing tag, ready for renaming.
pub fn edit_modal(tag: Tag) -> ModalState {
  let Tag(id:, ..) = tag
  ModalState(
    form: Form(name: ValidName(input: tag.name), color: tag.color),
    mode: Edit(id),
  )
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

pub fn set_name(state: ModalState, name: String) -> ModalState {
  let ModalState(form:, ..) = state
  let name = case validate_name(name) {
    Ok(_) -> ValidName(input: name)
    Error(NameRequired) -> EmptyName(name)
    Error(error) -> InvalidName(input: name, error:)
  }
  ModalState(..state, form: Form(..form, name:))
}

pub fn set_color(state: ModalState, color: String) -> ModalState {
  let ModalState(form:, ..) = state
  ModalState(..state, form: Form(..form, color:))
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

/// Validate the form. On success returns the trimmed name and color; on
/// failure returns the form with inline errors set.
pub fn validate(
  state: ModalState,
  other_tag_names: List(String),
) -> Result(#(String, String), Form) {
  let ModalState(form:, ..) = state
  let form = finalize(form, other_tag_names)

  case form {
    Form(name: ValidName(input: name), color:) ->
      Ok(#(string.trim(name), color))
    _ -> Error(form)
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

pub fn view(
  state: ModalState,
  on_name_input on_name_input: fn(String) -> msg,
  on_color_click on_color_click: fn(String) -> msg,
  on_submit on_submit: msg,
  on_cancel on_cancel: msg,
) -> Element(msg) {
  let ModalState(form:, mode:) = state
  let Form(name:, color:) = form

  let #(title, submit_label) = case mode {
    Create -> #("Create Tag", "Create tag")
    Edit(_) -> #("Edit Tag", "Save")
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
    ],
    [
      html.h2([attribute.class("mb-4 text-lg font-semibold text-gray-900")], [
        html.text(title),
      ]),
      html.form(
        [
          event.on_submit(fn(_) { on_submit }),
          attribute.class("space-y-4"),
        ],
        [
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
              event.on_input(on_name_input),
            ]),
            case name_error {
              Some(NameRequired) -> form_error_message("Name cannot be empty")
              Some(TooLong) ->
                form_error_message(
                  "Name cannot be longer than "
                  <> int.to_string(max_name_length)
                  <> " characters",
                )
              Some(Duplicate) ->
                form_error_message("A tag with this name already exists")
              None -> element.none()
            },
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
                    event.on_click(on_color_click(palette_color)),
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
                  <> "hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-gray-500 focus:ring-offset-2",
                ),
                event.on_click(on_cancel),
              ],
              [html.text("Cancel")],
            ),
            html.button(
              [
                attribute.type_("submit"),
                attribute.attribute("data-testid", "tag-submit-button"),
                attribute.class(
                  "rounded-md bg-indigo-600 px-4 py-2 text-sm font-medium text-white "
                  <> "hover:bg-indigo-500 focus:outline-none focus:ring-2 "
                  <> "focus:ring-indigo-500 focus:ring-offset-2",
                ),
                attribute.disabled(has_error),
              ],
              [html.text(submit_label)],
            ),
          ]),
        ],
      ),
    ],
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
