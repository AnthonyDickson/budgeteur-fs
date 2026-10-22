import budgeteur/shared/api_error.{type ApiError}
import budgeteur/shared/field
import budgeteur/shared/form_modal
import budgeteur/shared/number
import budgeteur/shared/tag.{type Tag}
import budgeteur/shared/ui/banner
import budgeteur/shared/ui/dialog
import budgeteur/shared/ui/input
import budgeteur/shared/ui/popover
import budgeteur/tagging_page/rule.{type Rule, Rule, TagTarget, TransferTarget}
import budgeteur/tagging_page/rule_matches.{type RuleMatches, RuleMatches}
import budgeteur/tagging_page/rule_write_request.{
  type RuleWriteRequest, RuleWriteRequest,
}
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

/// How long the pattern field must go without input before the modal counts
/// what the pattern matches.
const match_count_delay_ms = 300

pub type PatternError {
  PatternRequired
  TooLong
  Duplicate
}

pub type PatternField =
  field.Field(String, PatternError)

/// The tag select, which ends with a "Transfer" option for a transfer rule.
pub type TagField {
  NoTag
  ValidTag(id: Uuid)
  TransferChosen
  InvalidTag
}

/// The tag select's value for the "Transfer" option. Tag options carry their
/// uuid, so it cannot collide.
const transfer_option = "transfer"

/// What the pattern matches, shown below the pattern field. Not an input: it
/// follows the pattern once typing pauses.
pub type MatchCount {
  /// Nothing to show: a new rule, or a blank or invalid pattern.
  NotCounted
  /// Waiting for the count for `pattern`.
  Counting(pattern: String)
  Counted(pattern: String, matches: RuleMatches)
  CountFailed(pattern: String)
}

pub type Form {
  Form(pattern: PatternField, tag_id: TagField, match_count: MatchCount)
}

pub type Modal =
  form_modal.Modal(Form)

/// A request the modal asks its page to send.
pub type Request {
  /// Create or update the rule.
  Save(form_modal.Request(RuleWriteRequest))
  /// Count what the pattern matches.
  CountMatches(pattern: String)
}

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

// Update

pub type Msg {
  // "+ New Rule" clicked; the page passes the currently selected tag so the
  // create form can seed its tag select.
  CreateRequested(default_tag_id: Uuid)
  // Row clicked; the page looks the rule up first; the form never owns
  // the list.
  EditRequested(rule: Rule)
  PatternChanged(value: String)
  // The pattern field went `match_count_delay_ms` without input.
  PatternSettled(value: String)
  // Response to `CountMatches`.
  MatchesCounted(pattern: String, result: Result(RuleMatches, ApiError))
  // Tag select changed; the value is a uuid string (or ""), parsed here.
  TagChanged(value: String)
  SaveRequested
  // Response to the in-flight create or update; the `Created`/`Updated`
  // outcome variant is chosen from the `mode` in the `Submitting` state.
  // Transport timeouts surface here as `Error(NetworkError(...))`.
  SaveCompleted(result: Result(Rule, ApiError))
  // Cancel button, or the browser dismissed the dialog (Esc / outside click)
  CancelRequested
  // Delete button of the edit dialog. The dialog closes, and the page opens
  // the delete confirmation in its place.
  DeleteRequested
}

pub fn update(
  state: Modal,
  msg: Msg,
  rules: List(Rule),
) -> #(Modal, Option(Request), Outcome) {
  case msg {
    CreateRequested(default_tag_id:) ->
      case state {
        form_modal.Submitting(..) -> #(state, None, form_modal.NoChange)
        _ -> #(create_modal(default_tag_id), None, form_modal.NoChange)
      }
    EditRequested(rule:) ->
      case state {
        form_modal.Submitting(..) -> #(state, None, form_modal.NoChange)
        _ -> #(
          edit_modal(rule),
          Some(CountMatches(rule.pattern)),
          form_modal.NoChange,
        )
      }
    PatternChanged(value:) -> #(
      set_pattern(state, value),
      None,
      form_modal.NoChange,
    )
    PatternSettled(value:) -> count_matches(state, value)
    MatchesCounted(pattern:, result:) -> #(
      set_match_count(state, pattern, result),
      None,
      form_modal.NoChange,
    )
    TagChanged(value:) -> #(set_tag(state, value), None, form_modal.NoChange)
    SaveRequested -> save(state, rules)
    SaveCompleted(result: Ok(rule)) -> {
      let #(modal, outcome) = form_modal.succeeded(state, rule)
      #(modal, None, outcome)
    }
    SaveCompleted(result: Error(error)) -> #(
      form_modal.failed(state, error),
      None,
      form_modal.NoChange,
    )
    CancelRequested | DeleteRequested -> #(
      form_modal.cancel(state),
      None,
      form_modal.NoChange,
    )
  }
}

/// An empty modal for creating a new rule under `default_tag_id`.
fn create_modal(default_tag_id: Uuid) -> Modal {
  form_modal.create(Form(
    pattern: field.Empty(""),
    tag_id: ValidTag(default_tag_id),
    match_count: NotCounted,
  ))
}

/// A modal pre-filled with an existing rule, ready for editing.
fn edit_modal(rule: Rule) -> Modal {
  let Rule(id:, ..) = rule
  form_modal.edit(
    id,
    Form(
      pattern: field.Valid(value: rule.pattern, input: rule.pattern),
      tag_id: case rule.target {
        TagTarget(tag_id:) -> ValidTag(tag_id)
        TransferTarget -> TransferChosen
      },
      match_count: Counting(rule.pattern),
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

/// Count what the settled pattern matches, when it is valid. A blank or invalid
/// pattern clears the count instead. No op for Hidden and Submitting states.
fn count_matches(
  state: Modal,
  value: String,
) -> #(Modal, Option(Request), Outcome) {
  case form_modal.mode(state), validate_pattern(value) {
    None, _ -> #(state, None, form_modal.NoChange)
    Some(_), Ok(pattern) -> #(
      form_modal.set_form(state, fn(form) {
        Form(..form, match_count: Counting(pattern))
      }),
      Some(CountMatches(pattern)),
      form_modal.NoChange,
    )
    Some(_), Error(_) -> #(
      form_modal.set_form(state, fn(form) {
        Form(..form, match_count: NotCounted)
      }),
      None,
      form_modal.NoChange,
    )
  }
}

/// Set the count for `pattern`, unless the response is outdated: a newer
/// count was requested, or the pattern is no longer in the field. No op for
/// Hidden and Submitting states.
fn set_match_count(
  state: Modal,
  pattern: String,
  result: Result(RuleMatches, ApiError),
) -> Modal {
  form_modal.set_form(state, fn(form) {
    let current =
      form.match_count == Counting(pattern)
      && field.value(form.pattern) == Some(pattern)
    case current, result {
      False, _ -> form
      True, Ok(matches) ->
        Form(..form, match_count: Counted(pattern:, matches:))
      True, Error(_) -> Form(..form, match_count: CountFailed(pattern))
    }
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
    _ if tag_id == transfer_option -> TransferChosen
    _ ->
      case uuid.from_string(tag_id) {
        Ok(id) -> ValidTag(id)
        Error(Nil) -> InvalidTag
      }
  }
}

fn save(state: Modal, rules: List(Rule)) -> #(Modal, Option(Request), Outcome) {
  case form_modal.mode(state) {
    None -> #(state, None, form_modal.NoChange)
    Some(mode) -> {
      // Patterns are unique per user, whatever their tag, mirroring the
      // server, so every other rule's pattern can collide.
      let other_patterns =
        rules
        |> list.filter(fn(rule) {
          case mode {
            form_modal.Create -> True
            form_modal.Edit(id:) -> rule.id != id
          }
        })
        |> list.map(fn(rule) { rule.pattern })

      let #(modal, request) =
        form_modal.submit(state, fn(form) {
          validate_form(form, other_patterns)
        })
      #(modal, option.map(request, Save), form_modal.NoChange)
    }
  }
}

// Validation

/// Validate the form against the other rules' patterns. On success returns
/// the write request and the (finalized) form to keep while submitting; on
/// failure returns the form with inline errors set. `other_patterns` holds the
/// patterns of the user's rules, excluding the rule being edited, if any.
fn validate_form(
  form: Form,
  other_patterns: List(String),
) -> Result(#(RuleWriteRequest, Form), Form) {
  let form = finalize(form, other_patterns)

  let target = case form.tag_id {
    ValidTag(id) -> Some(TagTarget(id))
    TransferChosen -> Some(TransferTarget)
    NoTag | InvalidTag -> None
  }
  case field.value(form.pattern), target {
    Some(value), Some(target) -> Ok(#(RuleWriteRequest(value, target), form))
    _, _ -> Error(form)
  }
}

/// Finalize the form after a submit attempt: blank fields become errors, and
/// the pattern is checked against the other rules' patterns. Lowercasing
/// approximates the server's ordinal case-insensitive comparison, which
/// remains authoritative.
fn finalize(form: Form, other_patterns: List(String)) -> Form {
  let Form(pattern:, tag_id:, ..) = form
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
  Form(..form, pattern:, tag_id:)
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

/// Renders nothing while `Hidden`, otherwise the open dialog. The dialog is
/// locked while a request is in flight so it cannot be dismissed mid-request.
pub fn view(state: Modal, tags: List(Tag)) -> Element(Msg) {
  let open = fn(children, submitting) {
    dialog.dialog(
      testid: "rule-modal",
      busy: submitting,
      on_dismiss: CancelRequested,
      children:,
    )
  }

  case state {
    form_modal.Hidden -> element.none()
    form_modal.Active(form:, mode:) ->
      open(
        view_form(form, mode, tags, api_error: None, submitting: False),
        False,
      )
    form_modal.Submitting(form:, mode:) ->
      open(view_form(form, mode, tags, api_error: None, submitting: True), True)
    form_modal.Errored(form:, mode:, error:) ->
      open(
        view_form(form, mode, tags, api_error: Some(error), submitting: False),
        False,
      )
  }
}

fn view_form(
  form: Form,
  mode: form_modal.Mode,
  tags: List(Tag),
  api_error api_error: Option(String),
  submitting submitting: Bool,
) -> List(Element(Msg)) {
  let Form(pattern:, tag_id:, match_count:) = form

  let #(title, submit_label, submitting_label) = case mode {
    form_modal.Create -> #("Create Rule", "Create rule", "Creating rule...")
    form_modal.Edit(_) -> #("Edit Rule", "Save", "Saving...")
  }

  let pattern_error = field.error(pattern)
  let tag_error = field_tag_error(tag_id)
  let has_error = field.has_error(pattern) || tag_error

  [
    html.h2([attribute.class("mb-4 text-lg font-semibold text-fg")], [
      html.text(title),
    ]),
    case api_error {
      Some(message) ->
        banner.view(
          banner.Error,
          [attribute.attribute("data-testid", "rule-api-error")],
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
        html.div(
          [
            // The input's own handler stays immediate, so validation and save
            // always see the current value. Input events bubble to this div,
            // which counts matches once typing pauses.
            event.debounce(event.on_input(PatternSettled), match_count_delay_ms),
          ],
          [
            input.label_with_help(
              "Pattern",
              for: "rule-pattern-input",
              help: popover.help(
                id: "rule-pattern-help",
                about: "Pattern",
                paragraphs: ["Prefer longer, more specific patterns."],
              ),
            ),
            input.text([
              attribute.id("rule-pattern-input"),
              attribute.type_("text"),
              attribute.attribute("data-testid", "rule-pattern-input"),
              attribute.placeholder("e.g. STARBUCKS"),
              attribute.aria_describedby("rule-pattern-help"),
              attribute.autofocus(True),
              attribute.value(field.input(pattern)),
              attribute.disabled(submitting),
              event.on_input(PatternChanged),
              input.invalid(field.has_error(pattern)),
            ]),
            case pattern_error {
              Some(PatternRequired) ->
                input.error_message("Pattern cannot be empty")
              Some(TooLong) ->
                input.error_message(
                  "Pattern cannot be longer than "
                  <> int.to_string(max_pattern_length)
                  <> " characters",
                )
              Some(Duplicate) ->
                input.error_message("A rule with this pattern already exists")
              None -> element.none()
            },
            view_match_count(pattern, match_count),
          ],
        ),
        html.div([], [
          input.label_with_help(
            "Tag",
            for: "rule-tag-select",
            help: popover.help(id: "rule-tag-help", about: "Tag", paragraphs: [
              "Changing the tag moves this rule to that tag.",
              "A Transfer rule suggests matching transactions as transfers in quick tagging, rather than marking them.",
            ]),
          ),
          input.select(
            [
              attribute.id("rule-tag-select"),
              attribute.attribute("data-testid", "rule-tag-select"),
              attribute.aria_describedby("rule-tag-help"),
              attribute.disabled(submitting),
              event.on_change(TagChanged),
              input.invalid(tag_error),
            ],
            // The options carry the selection: a `value` on the select is
            // applied before its options exist, so the browser would show the
            // first tag.
            list.append(
              list.map(tags, fn(tag) {
                html.option(
                  [
                    attribute.value(uuid.to_string(tag.id)),
                    attribute.selected(tag_id == ValidTag(tag.id)),
                  ],
                  tag.name,
                )
              }),
              [
                html.option(
                  [
                    attribute.value(transfer_option),
                    attribute.selected(tag_id == TransferChosen),
                  ],
                  "Transfer",
                ),
              ],
            ),
          ),
          case tag_error {
            True -> input.error_message("Select a tag")
            False -> element.none()
          },
        ]),
        dialog.form_footer(
          leading: case mode {
            form_modal.Create -> None
            form_modal.Edit(_) ->
              Some(dialog.delete_request_button(
                testid: "rule-delete-button",
                disabled: submitting,
                on_click: DeleteRequested,
              ))
          },
          cancel: dialog.cancel_button(
            testid: "rule-cancel-button",
            disabled: submitting,
            on_click: CancelRequested,
          ),
          submit: dialog.submit_button(
            testid: "rule-submit-button",
            idle_label: submit_label,
            busy_label: submitting_label,
            busy: submitting,
            disabled: has_error,
          ),
        ),
      ],
    ),
  ]
}

/// The count and samples below the pattern field, while the pattern is valid.
fn view_match_count(
  pattern: PatternField,
  match_count: MatchCount,
) -> Element(Msg) {
  let status = fn(text) {
    html.p(
      [
        attribute.attribute("data-testid", "rule-match-count"),
        attribute.class("mt-1 text-xs text-fg-muted"),
      ],
      [html.text(text)],
    )
  }

  case field.value(pattern), match_count {
    None, _ | Some(_), NotCounted -> element.none()
    Some(_), Counting(..) -> status("Counting matches...")
    Some(_), CountFailed(..) -> status("Could not count matches")
    Some(_), Counted(matches: RuleMatches(count:, total:, samples:), ..) ->
      html.div([], [
        status(
          "Matches "
          <> number.format_int(count)
          <> " of "
          <> number.format_int(total)
          <> case total {
            1 -> " transaction"
            _ -> " transactions"
          },
        ),
        html.ul(
          [
            attribute.attribute("data-testid", "rule-match-samples"),
            attribute.class("mt-1 space-y-0.5 text-xs text-fg-muted"),
          ],
          list.map(samples, fn(sample) {
            html.li([attribute.class("truncate")], [html.text(sample)])
          }),
        ),
      ])
  }
}
