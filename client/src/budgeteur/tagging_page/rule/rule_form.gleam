import budgeteur/shared/api_error.{type ApiError}
import budgeteur/shared/field
import budgeteur/shared/form_modal
import budgeteur/tagging_page/rule/rule.{type Rule, Rule}
import budgeteur/tagging_page/rule_write_request.{
  type RuleWriteRequest, RuleWriteRequest,
}
import budgeteur/tagging_page/tag/tag.{type Tag}
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

pub type PatternField =
  field.Field(String, PatternError)

pub type TagField {
  NoTag
  ValidTag(id: Uuid)
  InvalidTag
}

pub type Form {
  Form(pattern: PatternField, tag_id: TagField)
}

pub type Modal =
  form_modal.Modal(Form)

pub type Request =
  form_modal.Request(RuleWriteRequest)

pub type Outcome =
  form_modal.Outcome(Rule)

pub fn hidden() -> Modal {
  form_modal.hidden()
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

pub fn update(
  state: Modal,
  msg: Msg,
  rules: List(Rule),
) -> #(Modal, List(Request), Outcome) {
  case msg {
    CreateRequested(default_tag_id:) ->
      case state {
        form_modal.Submitting(..) -> #(state, [], form_modal.NoChange)
        _ -> #(
          create_modal(default_tag_id),
          [form_modal.ShowDialog],
          form_modal.NoChange,
        )
      }
    EditRequested(rule:) ->
      case state {
        form_modal.Submitting(..) -> #(state, [], form_modal.NoChange)
        _ -> #(edit_modal(rule), [form_modal.ShowDialog], form_modal.NoChange)
      }
    PatternChanged(value:) -> #(
      set_pattern(state, value),
      [],
      form_modal.NoChange,
    )
    TagChanged(value:) -> #(set_tag(state, value), [], form_modal.NoChange)
    SaveRequested -> save(state, rules)
    SaveCompleted(result: Ok(rule)) -> on_save_succeeded(state, rule)
    SaveCompleted(result: Error(error)) -> #(
      form_modal.failed(state, error),
      [],
      form_modal.NoChange,
    )
    CancelRequested -> cancel(state)
    DialogDismissed -> #(form_modal.dismissed(state), [], form_modal.NoChange)
  }
}

/// An empty modal for creating a new rule under `default_tag_id`.
fn create_modal(default_tag_id: Uuid) -> Modal {
  form_modal.create(Form(
    pattern: field.Empty(""),
    tag_id: ValidTag(default_tag_id),
  ))
}

/// A modal pre-filled with an existing rule, ready for editing.
fn edit_modal(rule: Rule) -> Modal {
  let Rule(id:, ..) = rule
  form_modal.edit(
    id,
    Form(
      pattern: field.Valid(value: rule.pattern, input: rule.pattern),
      tag_id: ValidTag(rule.tag_id),
    ),
  )
}

/// Validate and set the pattern field. No op for Hidden and Submitting states.
fn set_pattern(state: Modal, pattern: String) -> Modal {
  form_modal.set_form(state, fn(form) {
    Form(
      ..form,
      pattern: field.validate(pattern, validate_pattern, is_required),
    )
  })
}

/// Validate and set the tag field. No op for Hidden and Submitting states.
fn set_tag(state: Modal, tag_id: String) -> Modal {
  form_modal.set_form(state, fn(form) {
    Form(..form, tag_id: parse_tag_id(tag_id))
  })
}

fn parse_tag_id(tag_id: String) -> TagField {
  case tag_id {
    "" -> NoTag
    _ ->
      case uuid.from_string(tag_id) {
        Ok(id) -> ValidTag(id)
        Error(Nil) -> InvalidTag
      }
  }
}

fn save(state: Modal, rules: List(Rule)) -> #(Modal, List(Request), Outcome) {
  case form_modal.mode(state) {
    None -> #(state, [], form_modal.NoChange)
    Some(mode) -> {
      let other_patterns =
        case mode {
          form_modal.Create -> rules
          form_modal.Edit(id:) -> list.filter(rules, fn(rule) { rule.id != id })
        }
        |> list.map(fn(rule) { rule.pattern })

      case
        form_modal.submit(state, fn(form) {
          validate_form(form, other_patterns)
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
  rule: Rule,
) -> #(Modal, List(Request), Outcome) {
  case form_modal.succeeded(state, rule) {
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

/// Validate the form against the other rules' patterns. On success returns the
/// write request and the (finalized) form to keep while submitting; on failure
/// returns the form with inline errors set. `other_patterns` excludes the rule
/// being edited, if any.
fn validate_form(
  form: Form,
  other_patterns: List(String),
) -> Result(#(RuleWriteRequest, Form), Form) {
  let form = finalize(form, other_patterns)

  case form {
    Form(pattern:, tag_id: ValidTag(id)) ->
      case field.value(pattern) {
        Some(value) -> Ok(#(RuleWriteRequest(value, id), form))
        None -> Error(form)
      }
    _ -> Error(form)
  }
}

/// Finalize the form after a submit attempt: blank fields become errors, and
/// the pattern is checked against the other rules' patterns. The comparison is
/// case-insensitive to mirror the matching semantics.
fn finalize(form: Form, other_patterns: List(String)) -> Form {
  let Form(pattern:, tag_id:) = form
  let pattern = field.finalize(pattern, fn() { PatternRequired })
  let pattern = case pattern {
    field.Valid(value:, ..) ->
      case
        list.any(other_patterns, fn(p) {
          string.lowercase(p) == string.lowercase(value)
        })
      {
        True -> field.mark_invalid(pattern, Duplicate)
        False -> pattern
      }
    field.Empty(..) | field.Invalid(..) -> pattern
  }
  let tag_id = case tag_id {
    NoTag -> InvalidTag
    other -> other
  }
  Form(pattern:, tag_id:)
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

/// A parse error is demoted to a blank `Empty` field (no inline error while
/// typing) only when it is the required error, e.g. a whitespace-only
/// pattern.
fn is_required(error: PatternError) -> Bool {
  case error {
    PatternRequired -> True
    TooLong | Duplicate -> False
  }
}

// View

pub fn view(state: Modal, tags: List(Tag)) -> Element(Msg) {
  case state {
    form_modal.Hidden -> view_hidden()
    form_modal.Active(form:, mode:) ->
      view_form(form, mode, tags, api_error: None, submitting: False)
    form_modal.Submitting(form:, mode:) ->
      view_form(form, mode, tags, api_error: None, submitting: True)
    form_modal.Errored(form:, mode:, error:) ->
      view_form(form, mode, tags, api_error: Some(error), submitting: False)
  }
}

fn view_form(
  form: Form,
  mode: form_modal.Mode,
  tags: List(Tag),
  api_error api_error: Option(String),
  submitting submitting: Bool,
) -> Element(Msg) {
  let Form(pattern:, tag_id:) = form

  let #(title, submit_label, submitting_label) = case mode {
    form_modal.Create -> #("Create Rule", "Create rule", "Creating rule...")
    form_modal.Edit(_) -> #("Edit Rule", "Save", "Saving...")
  }

  let pattern_error = field.error(pattern)
  let tag_error = field_tag_error(tag_id)
  let has_error = field.has_error(pattern) || tag_error

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
                #(error_border_style, field.has_error(pattern)),
              ]),
              attribute.autofocus(True),
              attribute.value(field.input(pattern)),
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
