//// The close date field the item and account forms share when editing: blank
//// while the line is open, the date it was sold, repaid, or closed otherwise.
//// See decision 4 in docs/reports.md.

import budgeteur/shared/date
import budgeteur/shared/field
import budgeteur/shared/modal_ui
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

pub type CloseDateError {
  NotADate
}

/// Blank (`Empty`) while the line is open.
pub type Field =
  field.Field(Date, CloseDateError)

/// The field for a line's close date, if any.
pub fn from(closed_on: Option(Date)) -> Field {
  case closed_on {
    Some(closed_on) ->
      field.Valid(value: closed_on, input: date.format(closed_on))
    None -> field.Empty("")
  }
}

pub fn update(input: String) -> Field {
  field.validate(string.trim(input), parse, fn(_) { False })
}

/// The close date to send: `Ok(None)` while blank, or `Error(Nil)` when the
/// input is not a date.
pub fn value(field: Field) -> Result(Option(Date), Nil) {
  case field {
    field.Empty(..) -> Ok(None)
    field.Valid(value:, ..) -> Ok(Some(value))
    field.Invalid(..) -> Error(Nil)
  }
}

fn parse(input: String) -> Result(Date, CloseDateError) {
  case date.parse(input) {
    Ok(closed_on) -> Ok(closed_on)
    Error(Nil) -> Error(NotADate)
  }
}

/// The field with its `help` text, which names what closing means for the
/// line.
pub fn view(
  closed_on: Field,
  testid testid: String,
  help help: String,
  submitting submitting: Bool,
  on_input on_input: fn(String) -> msg,
) -> Element(msg) {
  html.label([attribute.class("block")], [
    html.span(
      [attribute.class("mb-1 block text-sm font-medium text-gray-700")],
      [html.text("Closed on")],
    ),
    html.input([
      attribute.type_("date"),
      attribute.attribute("data-testid", testid),
      attribute.class(input_class),
      attribute.classes([
        #(modal_ui.error_border_style, field.has_error(closed_on)),
      ]),
      attribute.value(field.input(closed_on)),
      attribute.disabled(submitting),
      event.on_input(on_input),
    ]),
    case field.error(closed_on) {
      Some(NotADate) -> modal_ui.form_error_message("Not a valid date")
      None -> element.none()
    },
    html.p([attribute.class("mt-1 text-xs text-gray-500")], [html.text(help)]),
  ])
}
