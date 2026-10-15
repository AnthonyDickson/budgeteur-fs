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
import budgeteur/shared/ui/dialog
import gleam/option.{type Option, None, Some}
import gleam/string
import gleam/time/calendar.{type Date}
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

const input_class = "block w-full rounded-md border border-gray-300 px-3 py-2 text-sm text-gray-900 shadow-sm "
  <> "focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500 "
  <> "disabled:cursor-not-allowed disabled:bg-gray-100 disabled:text-gray-400"

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
/// what the parent form does with them.
pub fn view(
  form: Form,
  side side: Side,
  submitting submitting: Bool,
  note note: String,
) -> Element(Msg) {
  let Form(value:, as_of:) = form

  html.div([attribute.class("space-y-4")], [
    html.label([attribute.class("block")], [
      html.span(
        [attribute.class("mb-1 block text-sm font-medium text-gray-700")],
        [html.text("Value")],
      ),
      html.input([
        attribute.type_("text"),
        attribute.attribute("data-testid", "value-amount-input"),
        attribute.inputmode("decimal"),
        attribute.placeholder("0.00"),
        attribute.class(input_class),
        attribute.classes([
          #(dialog.error_border_style, field.has_error(value)),
        ]),
        attribute.value(field.input(value)),
        attribute.disabled(submitting),
        event.on_input(ValueChanged),
      ]),
      case field.error(value) {
        Some(ValueRequired) ->
          dialog.form_error_message("Value cannot be empty")
        Some(NotANumber) -> dialog.form_error_message("Not a valid number")
        Some(Negative) ->
          dialog.form_error_message(
            "Value cannot be negative. Record what is owed as a liability.",
          )
        None -> element.none()
      },
      html.p([attribute.class("mt-1 text-xs text-gray-500")], [
        html.text(value_help(side) <> " " <> note),
      ]),
    ]),
    html.label([attribute.class("block")], [
      html.span(
        [attribute.class("mb-1 block text-sm font-medium text-gray-700")],
        [html.text("Value as of")],
      ),
      html.input([
        attribute.type_("date"),
        attribute.attribute("data-testid", "value-as-of-input"),
        attribute.class(input_class),
        attribute.classes([
          #(dialog.error_border_style, field.has_error(as_of)),
        ]),
        attribute.value(field.input(as_of)),
        attribute.disabled(submitting),
        event.on_input(AsOfChanged),
      ]),
      case field.error(as_of) {
        Some(AsOfRequired) -> dialog.form_error_message("Date cannot be empty")
        Some(NotADate) -> dialog.form_error_message("Not a valid date")
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
