import budgeteur/balance_sheet_page/balance_sheet_item.{
  type BalanceSheetItem, BalanceSheetItem,
}
import budgeteur/balance_sheet_page/item_write_request.{ValueEntry}
import budgeteur/balance_sheet_page/value_form
import budgeteur/balance_sheet_page/value_modal
import budgeteur/shared/field
import budgeteur/shared/form_modal.{Active, Edit, NoChange, Put, Updated}
import budgeteur/shared/side.{Asset}
import budgeteur/shared/term.{NonCurrent}
import gleam/option.{None, Some}
import gleam/time/calendar.{Date, March}
import gleeunit/should
import youid/uuid

const today = Date(2026, March, 8)

fn run(state: value_modal.Modal, msg: value_modal.Msg) -> value_modal.Modal {
  let #(state, _, _) = value_modal.update(state, msg)
  state
}

fn house() -> BalanceSheetItem {
  let assert Ok(id) = uuid.from_string("00000000-0000-0000-0000-000000000003")
  BalanceSheetItem(
    id:,
    name: "House",
    side: Asset,
    term: NonCurrent,
    value: 400_000.0,
    as_of: Date(2026, March, 1),
    closed_on: None,
  )
}

fn open() -> value_modal.Modal {
  value_modal.hidden()
  |> run(value_modal.OpenRequested(item: house(), today: Some(today)))
}

pub fn opens_on_the_current_value_dated_today_test() {
  let assert Active(form:, mode: Edit(id)) = open()

  id |> should.equal(house().id)
  form.value.value
  |> should.equal(field.Valid(value: 400_000.0, input: "400000.00"))
  field.value(form.value.as_of) |> should.equal(Some(today))
}

pub fn recording_a_value_puts_it_for_the_item_test() {
  let state =
    open() |> run(value_modal.ValueMsg(value_form.ValueChanged("410000")))

  let assert #(submitting, Some(Put(id, entry)), NoChange) =
    value_modal.update(state, value_modal.SaveRequested)

  id |> should.equal(house().id)
  entry |> should.equal(ValueEntry(value: 410_000.0, as_of: today))

  let saved = BalanceSheetItem(..house(), value: 410_000.0, as_of: today)
  let #(_, _, outcome) =
    value_modal.update(submitting, value_modal.SaveCompleted(Ok(saved)))
  outcome |> should.equal(Updated(saved))
}

pub fn a_blank_value_is_reported_and_not_sent_test() {
  let state = open() |> run(value_modal.ValueMsg(value_form.ValueChanged("")))

  let assert #(
    Active(
      form: value_modal.Form(
        value: value_form.Form(
          value: field.Invalid(error: value_form.ValueRequired, ..),
          ..,
        ),
        ..,
      ),
      ..,
    ),
    None,
    NoChange,
  ) = value_modal.update(state, value_modal.SaveRequested)
}
