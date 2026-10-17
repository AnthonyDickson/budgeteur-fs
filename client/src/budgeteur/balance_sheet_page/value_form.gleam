//// The value fields the item and value forms share: the value as a magnitude
//// and its as-of date. An item's side is fixed, so unlike the balance form
//// there is no side to choose. The form is plain data in its modal's form; the
//// modal forwards these fields' messages to `update`. See decision 2 in
//// docs/reports.md.

import budgeteur/balance_sheet_page/item_write_request.{
  type ValueEntry, ValueEntry,
}
import budgeteur/shared/date
import budgeteur/shared/field
import budgeteur/shared/money
import budgeteur/shared/side.{type Side, Asset, Liability}
import budgeteur/shared/ui/input
import budgeteur/shared/ui/popover
import gleam/option.{type Option, None, Some}
import gleam/string
import gleam/time/calendar.{type Date}
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

pub type ValueError {
  ValueRequired
  NotANumber
  Negative
}

pub type AsOfError {
  AsOfRequired
  NotADate
}

pub type Form {
  Form(
    value: field.Field(Float, ValueError),
    as_of: field.Field(Date, AsOfError),
  )
}

pub type Msg {
  ValueChanged(value: String)
  AsOfChanged(value: String)
}

/// A blank value dated the client's today, when known.
pub fn empty(today: Option(Date)) -> Form {
  Form(value: field.Empty(""), as_of: today_field(today))
}

/// A value pre-filled with a magnitude, dated the client's today, when known.
pub fn prefilled(value: Float, today: Option(Date)) -> Form {
  Form(
    value: field.Valid(value:, input: money.to_string(value)),
    as_of: today_field(today),
  )
}

fn today_field(today: Option(Date)) -> field.Field(Date, AsOfError) {
  case today {
    Some(today) -> field.Valid(value: today, input: date.format(today))
    None -> field.Empty("")
  }
}

pub fn update(form: Form, msg: Msg) -> Form {
  case msg {
    ValueChanged(value:) ->
      Form(
        ..form,
        value: field.validate(
          money.clip_to_two_dp(value),
          validate_value,
          fn(error) { error == ValueRequired },
        ),
      )
    AsOfChanged(value:) ->
      Form(
        ..form,
        as_of: field.validate(value, validate_as_of, fn(error) {
          error == AsOfRequired
        }),
      )
  }
}

pub fn has_error(form: Form) -> Bool {
  field.has_error(form.value) || field.has_error(form.as_of)
}

/// Finalize the fields after a submit attempt. Both are required.
pub fn validate(form: Form) -> Result(#(ValueEntry, Form), Form) {
  let form =
    Form(
      value: field.finalize(form.value, fn() { ValueRequired }),
      as_of: field.finalize(form.as_of, fn() { AsOfRequired }),
    )
  case form.value, form.as_of {
    field.Valid(value:, ..), field.Valid(value: as_of, ..) ->
      Ok(#(ValueEntry(value:, as_of:), form))
    _, _ -> Error(form)
  }
}

fn validate_value(value: String) -> Result(Float, ValueError) {
  case string.trim(value) {
    "" -> Error(ValueRequired)
    trimmed ->
      case money.parse_decimal(trimmed) {
        Error(Nil) -> Error(NotANumber)
        Ok(amount) ->
          case amount <. 0.0 {
            True -> Error(Negative)
            False -> Ok(amount)
          }
      }
  }
}

fn validate_as_of(as_of: String) -> Result(Date, AsOfError) {
  case string.trim(as_of) {
    "" -> Error(AsOfRequired)
    trimmed ->
      case date.parse(trimmed) {
        Ok(as_of) -> Ok(as_of)
        Error(Nil) -> Error(NotADate)
      }
  }
}

// View

/// The value fields for an item on `side`, with `note` under the value for
/// what the parent form does with them. `autofocus` focuses the value when the
/// dialog opens, for a form with no field before it.
pub fn view(
  form: Form,
  side side: Side,
  submitting submitting: Bool,
  autofocus autofocus: Bool,
  note note: String,
) -> Element(Msg) {
  let Form(value:, as_of:) = form

  html.div([attribute.class("space-y-4")], [
    html.div([], [
      input.label_with_help(
        "Value",
        for: "value-amount-input",
        help: popover.help(id: "value-help", about: "Value", paragraphs: [
          value_help(side),
          note,
        ]),
      ),
      input.text([
        attribute.id("value-amount-input"),
        attribute.type_("text"),
        attribute.attribute("data-testid", "value-amount-input"),
        attribute.autofocus(autofocus),
        attribute.aria_describedby("value-help"),
        attribute.inputmode("decimal"),
        attribute.placeholder("0.00"),
        attribute.value(field.input(value)),
        attribute.disabled(submitting),
        event.on_input(ValueChanged),
        input.invalid(field.has_error(value)),
      ]),
      case field.error(value) {
        Some(ValueRequired) -> input.error_message("Value cannot be empty")
        Some(NotANumber) -> input.error_message("Not a valid number")
        Some(Negative) ->
          input.error_message(
            "Value cannot be negative. Record what is owed as a liability.",
          )
        None -> element.none()
      },
    ]),
    html.label([attribute.class("block")], [
      input.label("Value as of"),
      input.text([
        attribute.type_("date"),
        attribute.attribute("data-testid", "value-as-of-input"),
        attribute.value(field.input(as_of)),
        attribute.disabled(submitting),
        event.on_input(AsOfChanged),
        input.invalid(field.has_error(as_of)),
      ]),
      case field.error(as_of) {
        Some(AsOfRequired) -> input.error_message("Date cannot be empty")
        Some(NotADate) -> input.error_message("Not a valid date")
        None -> element.none()
      },
    ]),
  ])
}

fn value_help(side: Side) -> String {
  case side {
    Asset -> "Enter what it is worth. Use zero if it is worth nothing."
    Liability -> "Enter how much is owed. Use zero if nothing is outstanding."
  }
}
