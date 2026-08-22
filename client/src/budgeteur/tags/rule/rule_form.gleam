import budgeteur/tags/rule/rule.{type Rule, Rule}
import budgeteur/tags/tag/tag.{type Tag}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import youid/uuid.{type Uuid}

/// Max length of a rule pattern. A client constant for the MVP; the future
/// server mirrors it.
pub const max_pattern_length = 128

const dom_id = "rule_modal"

/// The CSS selector for the modal dialog element. The `#` hash prefix is
/// composed here so callers (e.g. the show/close dialog effects) never have to
/// remember it.
pub const dom_id_selector = "#" <> dom_id

const error_border_style = "border-red-400 focus:border-red-500 focus:outline-none focus:ring-1 focus:ring-red-500"

pub type PatternError {
  PatternRequired
  TooLong
  Duplicate
}

pub type PatternField {
  EmptyPattern(input: String)
  ValidPattern(input: String)
  InvalidPattern(input: String, error: PatternError)
}

pub type TagField {
  NoTag
  ValidTag(id: Uuid)
  InvalidTag
}

pub type Form {
  Form(pattern: PatternField, tag_id: TagField)
}

/// The mode the rule form modal is in.
pub type FormMode {
  /// Open an empty form
  Create
  /// Pre-fill the form with an existing rule
  Edit(id: Uuid)
}

/// State of the rule form modal: the form fields and the mode. Saving is
/// synchronous in the local MVP, so there is no `submitting` flag.
pub type ModalState {
  ModalState(form: Form, mode: FormMode)
}

/// Open an empty form targeting `default_tag_id`, the currently selected tag.
pub fn create_modal(default_tag_id: Uuid) -> ModalState {
  ModalState(
    form: Form(pattern: EmptyPattern(""), tag_id: ValidTag(default_tag_id)),
    mode: Create,
  )
}

/// A modal pre-filled with an existing rule, ready for editing.
pub fn edit_modal(rule: Rule) -> ModalState {
  let Rule(id:, ..) = rule
  ModalState(
    form: Form(
      pattern: ValidPattern(input: rule.pattern),
      tag_id: ValidTag(rule.tag_id),
    ),
    mode: Edit(id),
  )
}

fn validate_pattern(pattern: String) -> Result(String, PatternError) {
  let trimmed = string.trim(pattern)

  case string.is_empty(trimmed) {
    True -> Error(PatternRequired)
    False ->
      case string.length(trimmed) > max_pattern_length {
        True -> Error(TooLong)
        False -> Ok(trimmed)
      }
  }
}

pub fn set_pattern(state: ModalState, pattern: String) -> ModalState {
  let ModalState(form:, ..) = state
  let pattern = case validate_pattern(pattern) {
    Ok(_) -> ValidPattern(input: pattern)
    Error(PatternRequired) -> EmptyPattern(pattern)
    Error(error) -> InvalidPattern(input: pattern, error:)
  }
  ModalState(..state, form: Form(..form, pattern:))
}

pub fn set_tag(state: ModalState, tag_id: String) -> ModalState {
  let ModalState(form:, ..) = state
  let tag_id = case tag_id {
    "" -> NoTag
    _ ->
      case uuid.from_string(tag_id) {
        Ok(id) -> ValidTag(id)
        Error(Nil) -> InvalidTag
      }
  }
  ModalState(..state, form: Form(..form, tag_id:))
}

/// Finalize the form after a submit attempt: blank fields become errors, and
/// the pattern is checked against the other rules' patterns (`other_patterns`
/// excludes the rule being edited, if any). The comparison is case-insensitive
/// to mirror the matching semantics.
fn finalize(form: Form, other_patterns: List(String)) -> Form {
  let Form(pattern:, tag_id:) = form
  let pattern = case pattern {
    EmptyPattern(input) -> InvalidPattern(input:, error: PatternRequired)
    ValidPattern(input) -> {
      let trimmed = string.trim(input)
      let lowercased = string.lowercase(trimmed)
      case
        list.any(other_patterns, fn(p) { string.lowercase(p) == lowercased })
      {
        True -> InvalidPattern(input:, error: Duplicate)
        False -> ValidPattern(input: trimmed)
      }
    }
    other -> other
  }
  let tag_id = case tag_id {
    NoTag -> InvalidTag
    other -> other
  }
  Form(pattern:, tag_id:)
}

/// Validate the form. On success returns the trimmed pattern and tag id; on
/// failure returns the form with inline errors set.
pub fn validate(
  state: ModalState,
  other_patterns: List(String),
) -> Result(#(String, Uuid), Form) {
  let ModalState(form:, ..) = state
  let form = finalize(form, other_patterns)

  case form {
    Form(pattern: ValidPattern(input: pattern), tag_id: ValidTag(id)) ->
      Ok(#(string.trim(pattern), id))
    _ -> Error(form)
  }
}

fn field_pattern_input(field: PatternField) -> String {
  case field {
    EmptyPattern(input) -> input
    ValidPattern(input) -> input
    InvalidPattern(input:, ..) -> input
  }
}

fn field_pattern_error(field: PatternField) -> Option(PatternError) {
  case field {
    InvalidPattern(error:, ..) -> Some(error)
    _ -> None
  }
}

fn field_tag_error(field: TagField) -> Bool {
  case field {
    InvalidTag -> True
    _ -> False
  }
}

fn field_tag_id(field: TagField) -> String {
  case field {
    ValidTag(id) -> uuid.to_string(id)
    _ -> ""
  }
}

pub fn view(
  state: ModalState,
  tags: List(Tag),
  on_pattern_input on_pattern_input: fn(String) -> msg,
  on_tag_change on_tag_change: fn(String) -> msg,
  on_submit on_submit: msg,
  on_cancel on_cancel: msg,
) -> Element(msg) {
  let ModalState(form:, mode:) = state
  let Form(pattern:, tag_id:) = form

  let #(title, submit_label) = case mode {
    Create -> #("Create Rule", "Create rule")
    Edit(_) -> #("Edit Rule", "Save")
  }

  let pattern_error = field_pattern_error(pattern)
  let tag_error = field_tag_error(tag_id)
  let has_error = option.is_some(pattern_error) || tag_error

  html.dialog(
    [
      attribute.id(dom_id),
      attribute.attribute("data-testid", "rule-modal"),
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
              [html.text("Pattern")],
            ),
            html.input([
              attribute.type_("text"),
              attribute.attribute("data-testid", "rule-pattern-input"),
              attribute.placeholder("e.g. STARBUCKS"),
              attribute.class(
                "block w-full rounded-md border border-gray-300 px-3 py-2 text-sm text-gray-900 shadow-sm "
                <> "focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500",
              ),
              attribute.classes([
                #(error_border_style, option.is_some(pattern_error)),
              ]),
              attribute.value(field_pattern_input(pattern)),
              event.on_input(on_pattern_input),
            ]),
            case pattern_error {
              Some(PatternRequired) ->
                form_error_message("Pattern cannot be empty")
              Some(TooLong) ->
                form_error_message(
                  "Pattern cannot be longer than "
                  <> int.to_string(max_pattern_length)
                  <> " characters",
                )
              Some(Duplicate) -> form_error_message("This rule already exists")
              None -> element.none()
            },
          ]),
          html.label([attribute.class("block")], [
            html.span(
              [attribute.class("mb-1 block text-sm font-medium text-gray-700")],
              [html.text("Tag")],
            ),
            html.select(
              [
                attribute.attribute("data-testid", "rule-tag-select"),
                attribute.class(
                  "block w-full rounded-md border border-gray-300 bg-white px-3 py-2 text-sm text-gray-900 shadow-sm "
                  <> "focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500",
                ),
                attribute.classes([
                  #(error_border_style, tag_error),
                ]),
                attribute.value(field_tag_id(tag_id)),
                event.on_change(on_tag_change),
              ],
              list.map(tags, fn(tag) {
                html.option([attribute.value(uuid.to_string(tag.id))], tag.name)
              }),
            ),
            case tag_error {
              True -> form_error_message("Select a tag")
              False -> element.none()
            },
            html.p([attribute.class("mt-1 text-xs text-gray-500")], [
              html.text("Changing the tag moves this rule to that tag."),
            ]),
          ]),
          html.div([attribute.class("flex justify-end gap-3 pt-2")], [
            html.button(
              [
                attribute.type_("button"),
                attribute.attribute("data-testid", "rule-cancel-button"),
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
                attribute.attribute("data-testid", "rule-submit-button"),
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

fn form_error_message(text: String) -> Element(msg) {
  html.p([attribute.class("mt-1 text-sm text-red-600")], [html.text(text)])
}
