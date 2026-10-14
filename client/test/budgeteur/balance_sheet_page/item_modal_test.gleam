import budgeteur/balance_sheet_page/balance_sheet_item.{
  type BalanceSheetItem, BalanceSheetItem,
}
import budgeteur/balance_sheet_page/item_modal
import budgeteur/balance_sheet_page/item_write_request.{
  CreateItem, UpdateItem, ValueEntry,
}
import budgeteur/balance_sheet_page/value_form
import budgeteur/shared/field
import budgeteur/shared/form_modal.{
  Active, Create, Edit, Hidden, NoChange, Post, Put, Submitting,
}
import budgeteur/shared/side.{type Side, Asset, Liability}
import budgeteur/shared/term.{type Term, Current, NonCurrent}
import gleam/int
import gleam/option.{None, Some}
import gleam/string
import gleam/time/calendar.{Date, March}
import gleeunit/should
import youid/uuid.{type Uuid}

const today = Date(2026, March, 8)

fn item_id(n: Int) -> Uuid {
  let assert Ok(id) =
    uuid.from_string("00000000-0000-0000-0000-00000000000" <> int.to_string(n))
  id
}

fn item(
  name name: String,
  side side: Side,
  term term: Term,
  value value: Float,
) -> BalanceSheetItem {
  BalanceSheetItem(
    id: item_id(1),
    name: name,
    side: side,
    term: term,
    value: value,
    as_of: Date(2026, March, 1),
    closed_on: None,
  )
}

/// Apply a modal message, keeping only the resulting state.
fn run(
  state: item_modal.Modal,
  msg: item_modal.Msg,
  items: List(BalanceSheetItem),
) -> item_modal.Modal {
  let #(state, _, _) = item_modal.update(state, msg, items)
  state
}

fn value(msg: value_form.Msg) -> item_modal.Msg {
  item_modal.ValueMsg(msg)
}

fn create_modal(side: Side) -> item_modal.Modal {
  run(
    item_modal.hidden(),
    item_modal.CreateRequested(side:, today: Some(today)),
    [],
  )
}

/// The first value's fields of an open create form.
fn opening_value(state: item_modal.Modal) -> value_form.Form {
  let assert Active(form: item_modal.Form(opening_value: Some(form), ..), ..) =
    state
  form
}

pub fn blank_name_is_reported_on_submit_test() {
  let #(state, request, outcome) =
    item_modal.update(create_modal(Asset), item_modal.SaveRequested, [])

  let assert Active(
    form: item_modal.Form(
      name: field.Invalid(error: item_modal.NameRequired, ..),
      ..,
    ),
    ..,
  ) = state
  request |> should.equal(None)
  outcome |> should.equal(NoChange)
}

pub fn over_long_name_is_reported_while_typing_test() {
  let state =
    run(
      create_modal(Asset),
      item_modal.NameChanged(string.repeat("a", item_modal.max_name_length + 1)),
      [],
    )

  let assert Active(
    form: item_modal.Form(
      name: field.Invalid(error: item_modal.TooLong, ..),
      ..,
    ),
    ..,
  ) = state
}

pub fn duplicate_requires_the_name_side_and_term_to_all_match_test() {
  let existing =
    item(name: "Chequing", side: Asset, term: Current, value: 2000.0)

  // A second part of the sheet can reuse a name as long as the side or the
  // term differs, because the server's key is (name, side, term).
  let filled = fn(state, name, term) {
    state
    |> run(item_modal.NameChanged(name), [existing])
    |> run(value(value_form.ValueChanged("10")), [existing])
    |> run(item_modal.TermChanged(term), [existing])
  }

  let assert #(duplicate, None, NoChange) =
    item_modal.update(
      filled(create_modal(Asset), "Chequing", "Current"),
      item_modal.SaveRequested,
      [existing],
    )

  let assert Active(
    form: item_modal.Form(
      name: field.Invalid(error: item_modal.Duplicate, ..),
      ..,
    ),
    ..,
  ) = duplicate

  let assert #(_, Some(Post(_)), NoChange) =
    item_modal.update(
      filled(create_modal(Asset), "Chequing", "NonCurrent"),
      item_modal.SaveRequested,
      [existing],
    )

  let assert #(_, Some(Post(_)), NoChange) =
    item_modal.update(
      filled(create_modal(Liability), "Chequing", "Current"),
      item_modal.SaveRequested,
      [existing],
    )

  let assert #(_, Some(Post(_)), NoChange) =
    item_modal.update(
      filled(create_modal(Asset), "Savings", "Current"),
      item_modal.SaveRequested,
      [existing],
    )
}

pub fn editing_sends_only_the_name_and_term_test() {
  // The page passes the other items only, so keeping an item's own name is
  // not a collision. The edit form has no value: later values are recorded
  // with the value form.
  let existing =
    item(name: "Chequing", side: Asset, term: Current, value: 2000.0)
  let state =
    run(item_modal.hidden(), item_modal.EditRequested(existing), [existing])

  let assert Active(form: item_modal.Form(opening_value: None, ..), ..) = state

  let assert #(submitting, Some(request), NoChange) =
    item_modal.update(
      run(state, item_modal.TermChanged("NonCurrent"), []),
      item_modal.SaveRequested,
      [],
    )

  let assert Submitting(mode: Edit(id), ..) = submitting
  id |> should.equal(existing.id)

  request
  |> should.equal(Put(
    existing.id,
    UpdateItem(name: "Chequing", term: NonCurrent),
  ))
}

pub fn value_is_required_numeric_and_non_negative_test() {
  let value_error = fn(input) {
    let state =
      create_modal(Asset)
      |> run(item_modal.NameChanged("Chequing"), [])
      |> run(value(value_form.ValueChanged(input)), [])

    opening_value(state).value
  }

  let assert field.Empty("") = value_error("")
  let assert field.Invalid(error: value_form.NotANumber, ..) =
    value_error("twelve")
  let assert field.Invalid(error: value_form.Negative, ..) = value_error("-1")
  let assert field.Valid(value: 12.5, ..) = value_error("12.50")
  let assert field.Valid(value: 12.34, input: "12.34") = value_error("12.3456")

  // A blank value is only reported once the user submits.
  let state =
    create_modal(Asset)
    |> run(item_modal.NameChanged("Chequing"), [])
    |> run(item_modal.SaveRequested, [])

  let assert field.Invalid(error: value_form.ValueRequired, ..) =
    opening_value(state).value
}

pub fn create_builds_a_post_with_the_chosen_side_and_first_value_test() {
  let state =
    create_modal(Liability)
    |> run(item_modal.NameChanged("  Mortgage  "), [])
    |> run(value(value_form.ValueChanged("300000")), [])
    |> run(item_modal.TermChanged("NonCurrent"), [])

  let assert #(Submitting(mode: Create, ..), Some(request), NoChange) =
    item_modal.update(state, item_modal.SaveRequested, [])

  request
  |> should.equal(
    Post(CreateItem(
      name: "Mortgage",
      side: Liability,
      term: NonCurrent,
      first: ValueEntry(value: 300_000.0, as_of: today),
    )),
  )
}

pub fn cancelling_hides_the_modal_test() {
  let filled =
    create_modal(Asset) |> run(item_modal.NameChanged("Chequing"), [])

  let assert #(Hidden, None, NoChange) =
    item_modal.update(filled, item_modal.CancelRequested, [])
}

pub fn opening_the_form_always_starts_fresh_test() {
  let filled =
    create_modal(Asset) |> run(item_modal.NameChanged("Chequing"), [])

  let assert Active(
    form: item_modal.Form(
      name: field.Empty(""),
      side: Liability,
      term: Current,
      opening_value: Some(value_form.Form(
        value: field.Empty(""),
        as_of: field.Valid(value: Date(2026, March, 8), input: "2026-03-08"),
      )),
    ),
    mode: Create,
  ) =
    run(
      filled,
      item_modal.CreateRequested(side: Liability, today: Some(today)),
      [],
    )
}

pub fn the_as_of_date_is_required_and_must_be_a_date_test() {
  // Before the page knows today the date starts blank, and a blank date is
  // only reported once the user submits.
  let state =
    item_modal.hidden()
    |> run(item_modal.CreateRequested(side: Asset, today: None), [])
    |> run(item_modal.NameChanged("Chequing"), [])
    |> run(value(value_form.ValueChanged("10")), [])

  let assert field.Empty("") = opening_value(state).as_of

  let assert #(submitted, None, NoChange) =
    item_modal.update(state, item_modal.SaveRequested, [])
  let assert field.Invalid(error: value_form.AsOfRequired, ..) =
    opening_value(submitted).as_of

  let assert field.Invalid(error: value_form.NotADate, ..) =
    opening_value(run(state, value(value_form.AsOfChanged("yesterday")), [])).as_of

  let assert #(_, Some(Post(CreateItem(first:, ..))), NoChange) =
    item_modal.update(
      run(state, value(value_form.AsOfChanged("2026-02-28")), []),
      item_modal.SaveRequested,
      [],
    )
  first.as_of |> should.equal(Date(2026, calendar.February, 28))
}
