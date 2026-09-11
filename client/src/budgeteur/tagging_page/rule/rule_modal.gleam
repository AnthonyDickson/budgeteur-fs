import budgeteur/shared/api_error.{type ApiError}
import budgeteur/shared/field
import budgeteur/shared/form_modal
import budgeteur/shared/modal_ui
import budgeteur/tagging_page/rule/rule.{type Rule, Rule}
import budgeteur/tagging_page/rule_write_request.{
  type RuleWriteRequest, RuleWriteRequest,
}
import budgeteur/tag.{type Tag}
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

/// The id of the tag the form currently selects, if any. Used to scope the
/// duplicate-pattern check to the tag being saved to.
fn selected_tag_id(state: Modal) -> Option(Uuid) {
  case state {
    form_modal.Active(form: Form(tag_id:, ..), ..)
    | form_modal.Errored(form: Form(tag_id:, ..), ..) ->
      case tag_id {
        ValidTag(id) -> Some(id)
        NoTag | InvalidTag -> None
      }
    _ -> None
  }
}

fn save(state: Modal, rules: List(Rule)) -> #(Modal, List(Request), Outcome) {
  case form_modal.mode(state) {
    None -> #(state, [], form_modal.NoChange)
    Some(mode) -> {
      let other_patterns = case selected_tag_id(state) {
        // Patterns are unique per tag, mirroring the server's
        // UNIQUE(UserId, Pattern, TagId) constraint: only the rules under the
        // tag this form saves to can collide, so the same pattern may be
        // reused across tags. With no valid tag selected there are no rules to
        // collide with; the missing tag fails validation anyway.
        None -> []
        Some(tag_id) ->
          rules
          |> list.filter(fn(rule) { rule.tag_id == tag_id })
          |> list.filter(fn(rule) {
            case mode {
              form_modal.Create -> True
              form_modal.Edit(id:) -> rule.id != id
            }
          })
          |> list.map(fn(rule) { rule.pattern })
      }

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

/// Validate the form against the sibling rules' patterns. On success returns
/// the write request and the (finalized) form to keep while submitting; on
/// failure returns the form with inline errors set. `other_patterns` holds the
/// patterns of the rules under the form's selected tag, excluding the rule
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
/// the pattern is checked against the sibling rules' patterns for the same
/// tag. The comparison is case-insensitive to mirror the matching semantics.
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

/// Always renders the `<dialog>` element so the show/close dialog effects can
/// find it. The dialog is `closedby="none"` while a request is in flight,
/// locking it so it cannot be dismissed mid-request. The `on("close")` handler
/// covers browser-initiated dismissals (Esc / backdrop click) while open; a
/// close event can only fire when the dialog was open, so a stale one cannot
/// arrive while `Hidden` is shown.
pub fn view(state: Modal, tags: List(Tag)) -> Element(Msg) {
  let submitting = case state {
    form_modal.Submitting(..) -> True
    _ -> False
  }

  html.dialog(
    [
      event.on("close", decode.success(DialogDismissed)),
      ..modal_ui.dialog_attributes(dom_id, "rule-modal", submitting)
    ],
    case state {
      form_modal.Hidden -> []
      form_modal.Active(form:, mode:) ->
        view_form(form, mode, tags, api_error: None, submitting: False)
      form_modal.Submitting(form:, mode:) ->
        view_form(form, mode, tags, api_error: None, submitting: True)
      form_modal.Errored(form:, mode:, error:) ->
        view_form(form, mode, tags, api_error: Some(error), submitting: False)
    },
  )
}

fn view_form(
  form: Form,
  mode: form_modal.Mode,
  tags: List(Tag),
  api_error api_error: Option(String),
  submitting submitting: Bool,
) -> List(Element(Msg)) {
  let Form(pattern:, tag_id:) = form

  let #(title, submit_label, submitting_label) = case mode {
    form_modal.Create -> #("Create Rule", "Create rule", "Creating rule...")
    form_modal.Edit(_) -> #("Edit Rule", "Save", "Saving...")
  }

  let pattern_error = field.error(pattern)
  let tag_error = field_tag_error(tag_id)
  let has_error = field.has_error(pattern) || tag_error

  [
    html.h2([attribute.class("mb-4 text-lg font-semibold text-gray-900")], [
      html.text(title),
    ]),
    case api_error {
      Some(message) ->
        modal_ui.error_banner(
          testid: "rule-api-error",
          message: "Could not save rule: " <> message,
          extra_class: "",
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
              #(modal_ui.error_border_style, field.has_error(pattern)),
            ]),
            attribute.autofocus(True),
            attribute.value(field.input(pattern)),
            attribute.disabled(submitting),
            event.on_input(PatternChanged),
          ]),
          case pattern_error {
            Some(PatternRequired) ->
              modal_ui.form_error_message("Pattern cannot be empty")
            Some(TooLong) ->
              modal_ui.form_error_message(
                "Pattern cannot be longer than "
                <> int.to_string(max_pattern_length)
                <> " characters",
              )
            Some(Duplicate) ->
              modal_ui.form_error_message(
                "A rule with this pattern already exists for this tag",
              )
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
                #(modal_ui.error_border_style, tag_error),
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
            True -> modal_ui.form_error_message("Select a tag")
            False -> element.none()
          },
          html.p([attribute.class("mt-1 text-xs text-gray-500")], [
            html.text("Changing the tag moves this rule to that tag."),
          ]),
        ]),
        html.div([attribute.class("flex justify-end gap-3 pt-2")], [
          modal_ui.cancel_button(
            testid: "rule-cancel-button",
            disabled: submitting,
            on_click: CancelRequested,
          ),
          modal_ui.submit_button(
            testid: "rule-submit-button",
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
