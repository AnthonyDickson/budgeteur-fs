//// The balance fields the account and balance forms share: the side, the
//// amount without a sign, and the as-of date. The form is plain data in its
//// modal's form; the modal forwards these fields' messages to `update`. See
//// decision 13 in docs/csv-import.md.

import budgeteur/balance_sheet_page/account_write_request.{
  type BalanceEntry, BalanceEntry,
}
import budgeteur/shared/date
import budgeteur/shared/field
import budgeteur/shared/money
import budgeteur/shared/side.{type Side, Asset, Liability}
import budgeteur/shared/ui/input
import gleam/option.{type Option, None, Some}
import gleam/string
import gleam/time/calendar.{type Date}
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

pub type AmountError {
  AmountRequired
  NotANumber
  Negative
}

pub type AsOfError {
  AsOfRequired
  NotADate
}

pub type Form {
  Form(
    // Which side of the sheet the balance puts the account on. The amount is
    // a magnitude, so the user never types a sign.
    side: Side,
    amount: field.Field(Float, AmountError),
    as_of: field.Field(Date, AsOfError),
  )
}

pub type Msg {
  SideChanged(side: Side)
  AmountChanged(value: String)
  AsOfChanged(value: String)
}

/// A blank balance dated the client's today, when known.
pub fn empty(today: Option(Date)) -> Form {
  Form(side: Asset, amount: field.Empty(""), as_of: today_field(today))
}

/// A balance pre-filled with a side and magnitude, dated the client's today,
/// when known.
pub fn prefilled(side: Side, amount: Float, today: Option(Date)) -> Form {
  Form(
    side:,
    amount: field.Valid(value: amount, input: money.to_string(amount)),
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
    SideChanged(side:) -> Form(..form, side:)
    AmountChanged(value:) ->
      Form(
        ..form,
        amount: field.validate(
          money.clip_to_two_dp(value),
          validate_amount,
          fn(_) { False },
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

/// The signed balance for a magnitude on a side: a liability is negative.
pub fn signed_balance(side: Side, magnitude: Float) -> Float {
  case side {
    Asset -> magnitude
    Liability -> 0.0 -. magnitude
  }
}

pub fn has_error(form: Form) -> Bool {
  field.has_error(form.amount) || field.has_error(form.as_of)
}

/// Finalize the fields after a submit attempt. A blank amount is no entry
/// when `optional`, and an error otherwise. The as-of date is required with an
/// amount.
pub fn validate(
  form: Form,
  optional optional: Bool,
) -> Result(#(Option(BalanceEntry), Form), Form) {
  case form.amount, optional {
    field.Empty(..), True -> Ok(#(None, form))
    _, _ -> {
      let form =
        Form(
          ..form,
          amount: field.finalize(form.amount, fn() { AmountRequired }),
          as_of: field.finalize(form.as_of, fn() { AsOfRequired }),
        )
      case form.amount, form.as_of {
        field.Valid(value: magnitude, ..), field.Valid(value: as_of, ..) ->
          Ok(#(
            Some(BalanceEntry(
              balance: signed_balance(form.side, magnitude),
              as_of:,
            )),
            form,
          ))
        _, _ -> Error(form)
      }
    }
  }
}

fn validate_amount(amount: String) -> Result(Float, AmountError) {
  case money.parse_decimal(string.trim(amount)) {
    Error(Nil) -> Error(NotANumber)
    Ok(amount) ->
      case amount <. 0.0 {
        True -> Error(Negative)
        False -> Ok(amount)
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

/// The balance fields, with `note` under the amount for what the parent form
/// does with them.
pub fn view(
  form: Form,
  submitting submitting: Bool,
  note note: String,
) -> Element(Msg) {
  let Form(side:, amount:, as_of:) = form

  html.div([attribute.class("space-y-4")], [
    html.div([attribute.class("space-y-2")], [
      input.radio_group(
        legend: "Balance",
        testid: "balance-side",
        disabled: submitting,
        options: [
          #("Asset", "Asset", side == Asset, fn(_) { SideChanged(Asset) }),
          #("Liability", "Liability", side == Liability, fn(_) {
            SideChanged(Liability)
          }),
        ],
      ),
      html.p([attribute.class("text-xs text-fg-muted")], [
        html.text(
          "Liability when the account is overdrawn or a card balance is owing. The line moves sides when the balance changes sign.",
        ),
      ]),
      input.text([
        attribute.type_("text"),
        attribute.attribute("data-testid", "balance-amount-input"),
        attribute.attribute("aria-label", "Amount"),
        attribute.inputmode("decimal"),
        attribute.placeholder("0.00"),
        attribute.value(field.input(amount)),
        attribute.disabled(submitting),
        event.on_input(AmountChanged),
        input.invalid(field.has_error(amount)),
      ]),
      case field.error(amount) {
        Some(AmountRequired) -> input.error_message("Amount cannot be empty")
        Some(NotANumber) -> input.error_message("Not a valid number")
        Some(Negative) ->
          input.error_message(
            "Enter the amount without a sign. Choose asset or liability instead.",
          )
        None -> element.none()
      },
      html.p([attribute.class("text-xs text-fg-muted")], [html.text(note)]),
    ]),
    html.label([attribute.class("block")], [
      input.label("Balance as of"),
      input.text([
        attribute.type_("date"),
        attribute.attribute("data-testid", "balance-as-of-input"),
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
