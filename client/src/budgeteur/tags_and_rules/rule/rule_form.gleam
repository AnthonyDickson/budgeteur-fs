import budgeteur/shared/api_error.{type ApiError}
import budgeteur/tags_and_rules/rule/rule.{type Rule, Rule}
import budgeteur/tags_and_rules/rule_write_request.{
  type RuleWriteRequest, RuleWriteRequest,
}
import budgeteur/tags_and_rules/tag/tag.{type Tag}
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

/// Max length of a rule pattern. Mirrored by the server.
pub const max_pattern_length = 128

/// How long a save request (create or update) may stay in flight before the
/// transport aborts it. This should be applied by the page via `effect.with_timeout`.
pub const submit_timeout_ms = 10_000

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

/// State of the rule form modal: the form fields and the mode.
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

// Update

pub type Msg {
  // "+ New Rule" clicked; the page passes the currently selected tag so the
  // create form can seed its tag select.
  CreateRequested(default_tag_id: Uuid)
  // Row "Edit" clicked; the page looks the rule up first; the form never owns
  // the list.
  EditRequested(rule: Rule)
  PatternChanged(value: String)
  // Tag select changed; the value is a uuid string (or ""), parsed here.
  TagChanged(value: String)
  SaveRequested
  // Response to the in-flight create or update; the `Created`/`Updated`
  // outcome variant is chosen from the `mode` in the `Submitting` state.
  // Transport timeouts surface here as `Error(NetworkError(...))`.
  SaveCompleted(result: Result(Rule, ApiError))
  // Cancel button (dialog stays open until page closes it)
  CancelRequested
  // browser dismissed the dialog (Esc / backdrop click)
  DialogDismissed
}

pub type Request {
  ShowDialog
  CloseDialog
  /// POST /api/rules. Same payload shape as the update request.
  CreateRule(request: RuleWriteRequest)
  /// PUT /api/rules/{id}.
  PutRule(id: Uuid, request: RuleWriteRequest)
}

pub type Outcome {
  NoChange
  Created(rule: Rule)
  Updated(rule: Rule)
}

pub fn update(
  state: Modal,
  msg: Msg,
  rules: List(Rule),
) -> #(Modal, List(Request), Outcome) {
  case msg {
    CreateRequested(default_tag_id:) ->
      case state {
        Submitting(..) -> #(state, [], NoChange)
        _ -> #(create_modal(default_tag_id), [ShowDialog], NoChange)
      }
    EditRequested(rule:) ->
      case state {
        Submitting(..) -> #(state, [], NoChange)
        _ -> #(edit_modal(rule), [ShowDialog], NoChange)
      }
    PatternChanged(value:) -> #(set_pattern(state, value), [], NoChange)
    TagChanged(value:) -> #(set_tag(state, value), [], NoChange)
    SaveRequested -> save(state, rules)
    SaveCompleted(result: Ok(rule)) -> on_save_succeeded(state, rule)
    SaveCompleted(result: Error(error)) -> on_save_failed(state, error)
    CancelRequested -> cancel(state)
    DialogDismissed -> dismiss(state)
  }
}

/// An empty modal for creating a new rule under `default_tag_id`.
fn create_modal(default_tag_id: Uuid) -> Modal {
  Active(
    form: Form(pattern: EmptyPattern(""), tag_id: ValidTag(default_tag_id)),
    mode: Create,
  )
}

/// A modal pre-filled with an existing rule, ready for editing.
fn edit_modal(rule: Rule) -> Modal {
  let Rule(id:, ..) = rule
  Active(
    form: Form(
      pattern: ValidPattern(input: rule.pattern),
      tag_id: ValidTag(rule.tag_id),
    ),
    mode: Edit(id),
  )
}

/// Validate and set the pattern field. No op for Hidden and Submitting states.
fn set_pattern(state: Modal, pattern: String) -> Modal {
  case state {
    Active(form:, ..) ->
      Active(..state, form: update_pattern_field(pattern, form))
    Errored(form:, ..) ->
      Errored(..state, form: update_pattern_field(pattern, form))
    Hidden | Submitting(..) -> state
  }
}

/// Validate and set the tag field. No op for Hidden and Submitting states.
fn set_tag(state: Modal, tag_id: String) -> Modal {
  case state {
    Active(form:, ..) -> Active(..state, form: update_tag_field(tag_id, form))
    Errored(form:, ..) -> Errored(..state, form: update_tag_field(tag_id, form))
    Hidden | Submitting(..) -> state
  }
}

fn save(state: Modal, rules: List(Rule)) -> #(Modal, List(Request), Outcome) {
  case state {
    Active(form:, mode:) | Errored(form:, mode:, ..) -> {
      let other_patterns = case mode {
        Create -> list.map(rules, fn(rule) { rule.pattern })
        Edit(id:) ->
          rules
          |> list.filter(fn(rule) { rule.id != id })
          |> list.map(fn(rule) { rule.pattern })
      }

      case validate(state, other_patterns) {
        Ok(#(pattern, tag_id)) -> {
          let request = case mode {
            Create -> CreateRule(RuleWriteRequest(pattern, tag_id))
            Edit(id:) -> PutRule(id, RuleWriteRequest(pattern, tag_id))
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
  rule: Rule,
) -> #(Modal, List(Request), Outcome) {
  case state {
    Submitting(mode:, ..) ->
      case mode {
        Create -> #(Hidden, [CloseDialog], Created(rule))
        Edit(..) -> #(Hidden, [CloseDialog], Updated(rule))
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

/// Validate the form. On success returns the trimmed pattern and tag id; on
/// failure returns the modal with inline errors set.
fn validate(
  state: Modal,
  other_patterns: List(String),
) -> Result(#(String, Uuid), Modal) {
  case state {
    Hidden | Submitting(..) -> Error(state)
    Active(form:, ..) | Errored(form:, ..) -> {
      let form = finalize(form, other_patterns)

      case form {
        Form(pattern: ValidPattern(input: pattern), tag_id: ValidTag(id)) ->
          Ok(#(string.trim(pattern), id))
        _ -> Error(set_form(state, form))
      }
    }
  }
}

/// Finalize the form after a submit attempt: blank fields become errors, and
/// the pattern is checked against the other rules' patterns. `other_patterns`
/// excludes the rule being edited, if any. The comparison is case-insensitive
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

fn set_form(state: Modal, form: Form) -> Modal {
  case state {
    Hidden | Submitting(..) -> state
    Active(..) -> Active(..state, form:)
    Errored(..) -> Errored(..state, form:)
  }
}

fn update_pattern_field(pattern: String, form: Form) -> Form {
  // Store the untrimmed input: the field is re-rendered from this value on
  // every keystroke, so storing the trimmed pattern would eat a space the
  // user just typed. Trimming happens on save, in `finalize`.
  let pattern = case validate_pattern(pattern) {
    Ok(_) -> ValidPattern(input: pattern)
    Error(PatternRequired) -> EmptyPattern(pattern)
    Error(error) -> InvalidPattern(input: pattern, error:)
  }

  Form(..form, pattern:)
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

fn update_tag_field(tag_id: String, form: Form) -> Form {
  let tag_id = case tag_id {
    "" -> NoTag
    _ ->
      case uuid.from_string(tag_id) {
        Ok(id) -> ValidTag(id)
        Error(Nil) -> InvalidTag
      }
  }

  Form(..form, tag_id:)
}

// View

pub fn view(state: Modal, tags: List(Tag)) -> Element(Msg) {
  case state {
    Hidden -> view_hidden()
    Active(form:, mode:) ->
      view_form(form, mode, tags, api_error: None, submitting: False)
    Submitting(form:, mode:) ->
      view_form(form, mode, tags, api_error: None, submitting: True)
    Errored(form:, mode:, error:) ->
      view_form(form, mode, tags, api_error: Some(error), submitting: False)
  }
}

fn view_form(
  form: Form,
  mode: FormMode,
  tags: List(Tag),
  api_error api_error: Option(String),
  submitting submitting: Bool,
) -> Element(Msg) {
  let Form(pattern:, tag_id:) = form

  let #(title, submit_label, submitting_label) = case mode {
    Create -> #("Create Rule", "Create rule", "Creating rule...")
    Edit(_) -> #("Edit Rule", "Save", "Saving...")
  }

  let pattern_error = field_pattern_error(pattern)
  let tag_error = field_tag_error(tag_id)
  let has_error = option.is_some(pattern_error) || tag_error

  // "closedby" = "any" is needed to allow the dialog to be closed by
  // clicking outside the dialog.
  let closedby_mode = case submitting {
    True -> "none"
    False -> "any"
  }

  html.dialog(
    [
      attribute.id(dom_id),
      attribute.attribute("data-testid", "rule-modal"),
      attribute.class(
        "mx-auto my-auto w-full max-w-md rounded-lg border border-gray-200 bg-white p-6 shadow-xl backdrop:bg-gray-900/50",
      ),
      attribute.attribute("closedby", closedby_mode),
      event.on("close", decode.success(DialogDismissed)),
    ],
    [
      html.h2([attribute.class("mb-4 text-lg font-semibold text-gray-900")], [
        html.text(title),
      ]),
      case api_error {
        Some(message) ->
          html.p(
            [
              attribute.attribute("role", "alert"),
              attribute.attribute("data-testid", "rule-api-error"),
              attribute.class(
                "rounded-md border border-red-200 bg-red-50 px-3 py-2 text-sm text-red-700",
              ),
            ],
            [html.text("Could not save rule: " <> message)],
          )
        None -> element.none()
      },
      html.form(
        [
          event.on_submit(fn(_) { SaveRequested }),
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
                <> "focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500 "
                <> "disabled:cursor-not-allowed disabled:bg-gray-100 disabled:text-gray-400",
              ),
              attribute.classes([
                #(error_border_style, option.is_some(pattern_error)),
              ]),
              attribute.value(field_pattern_input(pattern)),
              attribute.disabled(submitting),
              event.on_input(PatternChanged),
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
                  <> "focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500 "
                  <> "disabled:cursor-not-allowed disabled:bg-gray-100 disabled:text-gray-400",
                ),
                attribute.classes([
                  #(error_border_style, tag_error),
                ]),
                attribute.value(field_tag_id(tag_id)),
                attribute.disabled(submitting),
                event.on_change(TagChanged),
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
                  <> "hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-gray-500 focus:ring-offset-2 "
                  <> "disabled:cursor-not-allowed disabled:bg-gray-100 disabled:text-gray-400 disabled:hover:bg-gray-100",
                ),
                attribute.disabled(submitting),
                event.on_click(CancelRequested),
              ],
              [html.text("Cancel")],
            ),
            html.button(
              [
                attribute.type_("submit"),
                attribute.attribute("data-testid", "rule-submit-button"),
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

fn view_hidden() -> Element(Msg) {
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
    [],
  )
}

fn form_error_message(text: String) -> Element(Msg) {
  html.p([attribute.class("mt-1 text-sm text-red-600")], [html.text(text)])
}
