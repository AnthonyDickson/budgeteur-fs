import budgeteur/balance_sheet_page/balance_sheet_item.{
  type BalanceSheetItem, BalanceSheetItem,
}
import budgeteur/balance_sheet_page/item_kind.{type ItemKind, Asset, Liability}
import budgeteur/balance_sheet_page/item_modal
import budgeteur/balance_sheet_page/term.{type Term, Current, NonCurrent}
import budgeteur/balance_sheet_page/write_item_request.{
  WriteBalanceSheetItemRequest,
}
import budgeteur/shared/field
import budgeteur/shared/form_modal.{
  Active, Create, Edit, Hidden, NoChange, Post, Put, Submitting,
}
import gleam/int
import gleam/string
import gleeunit/should
import youid/uuid.{type Uuid}

fn item_id(n: Int) -> Uuid {
  let assert Ok(id) =
    uuid.from_string("00000000-0000-0000-0000-00000000000" <> int.to_string(n))
  id
}

fn item(
  name name: String,
  kind kind: ItemKind,
  term term: Term,
  balance balance: Float,
) -> BalanceSheetItem {
  BalanceSheetItem(
    id: item_id(1),
    name: name,
    kind: kind,
    term: term,
    balance: balance,
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

fn create_modal(kind: ItemKind) -> item_modal.Modal {
  run(item_modal.hidden(), item_modal.CreateRequested(kind), [])
}

fn active_form(state: item_modal.Modal) -> item_modal.Form {
  let assert Active(form: form, ..) = state
  form
}

pub fn blank_name_is_reported_on_submit_test() {
  let #(state, requests, outcome) =
    item_modal.update(create_modal(Asset), item_modal.SaveRequested, [])

  let assert Active(
    form: item_modal.Form(
      name: field.Invalid(error: item_modal.NameRequired, ..),
      ..,
    ),
    ..,
  ) = state
  requests |> should.equal([])
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

pub fn duplicate_requires_the_name_kind_and_term_to_all_match_test() {
  let existing =
    item(name: "Chequing", kind: Asset, term: Current, balance: 2000.0)

  // A second part of the sheet can reuse a name as long as the kind or the
  // term differs, because the server's key is (name, kind, term).
  let filled = fn(state, name, term) {
    state
    |> run(item_modal.NameChanged(name), [existing])
    |> run(item_modal.BalanceChanged("10"), [existing])
    |> run(item_modal.TermChanged(term), [existing])
  }

  let assert #(duplicate, [], NoChange) =
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

  let assert #(_, [Post(_)], NoChange) =
    item_modal.update(
      filled(create_modal(Asset), "Chequing", "NonCurrent"),
      item_modal.SaveRequested,
      [existing],
    )

  let assert #(_, [Post(_)], NoChange) =
    item_modal.update(
      filled(create_modal(Liability), "Chequing", "Current"),
      item_modal.SaveRequested,
      [existing],
    )

  let assert #(_, [Post(_)], NoChange) =
    item_modal.update(
      filled(create_modal(Asset), "Savings", "Current"),
      item_modal.SaveRequested,
      [existing],
    )
}

pub fn editing_an_item_does_not_count_it_as_its_own_duplicate_test() {
  // The page passes the other items only, so renaming an item back to its own
  // name is not a collision.
  let existing =
    item(name: "Chequing", kind: Asset, term: Current, balance: 2000.0)
  let state =
    run(item_modal.hidden(), item_modal.EditRequested(existing), [existing])

  let assert #(submitting, [request], NoChange) =
    item_modal.update(state, item_modal.SaveRequested, [])

  let assert Submitting(mode: Edit(id), ..) = submitting

  id |> should.equal(existing.id)

  request
  |> should.equal(Put(
    existing.id,
    WriteBalanceSheetItemRequest(
      name: "Chequing",
      kind: Asset,
      term: Current,
      balance: 2000.0,
    ),
  ))
}

pub fn balance_is_required_numeric_and_non_negative_test() {
  let balance_error = fn(input) {
    let state =
      create_modal(Asset)
      |> run(item_modal.NameChanged("Chequing"), [])
      |> run(item_modal.BalanceChanged(input), [])

    active_form(state).balance
  }

  let assert field.Empty("") = balance_error("")
  let assert field.Invalid(error: item_modal.NotANumber, ..) =
    balance_error("twelve")
  let assert field.Invalid(error: item_modal.Negative, ..) = balance_error("-1")
  let assert field.Valid(value: 12.5, ..) = balance_error("12.50")

  // A blank balance is only reported once the user submits.
  let state =
    create_modal(Asset)
    |> run(item_modal.NameChanged("Chequing"), [])
    |> run(item_modal.SaveRequested, [])

  let assert Active(
    form: item_modal.Form(
      balance: field.Invalid(error: item_modal.BalanceRequired, ..),
      ..,
    ),
    ..,
  ) = state
}

pub fn balance_input_is_clipped_to_two_decimal_places_test() {
  let state =
    create_modal(Asset)
    |> run(item_modal.BalanceChanged("12.3456"), [])

  let assert field.Valid(value: 12.34, input: "12.34") =
    active_form(state).balance
}

pub fn create_builds_a_post_with_the_chosen_kind_test() {
  let state =
    create_modal(Liability)
    |> run(item_modal.NameChanged("  Mortgage  "), [])
    |> run(item_modal.BalanceChanged("300000"), [])
    |> run(item_modal.TermChanged("NonCurrent"), [])

  let assert #(Submitting(mode: Create, ..), [request], NoChange) =
    item_modal.update(state, item_modal.SaveRequested, [])

  request
  |> should.equal(
    Post(WriteBalanceSheetItemRequest(
      name: "Mortgage",
      kind: Liability,
      term: NonCurrent,
      balance: 300_000.0,
    )),
  )
}

pub fn cancelling_and_dismissing_both_close_the_dialog_test() {
  let filled =
    create_modal(Asset) |> run(item_modal.NameChanged("Chequing"), [])

  let assert #(Hidden, [_], NoChange) =
    item_modal.update(filled, item_modal.CancelRequested, [])

  // A browser dismissal (Esc or the backdrop) is already closed on screen, so
  // no close effect is needed.
  let assert #(Hidden, [], NoChange) =
    item_modal.update(filled, item_modal.DialogDismissed, [])
}

pub fn opening_the_form_always_starts_fresh_test() {
  let filled =
    create_modal(Asset) |> run(item_modal.NameChanged("Chequing"), [])

  let assert Active(
    form: item_modal.Form(
      name: field.Empty(""),
      kind: Liability,
      term: Current,
      balance: field.Empty(""),
    ),
    mode: Create,
  ) = run(filled, item_modal.CreateRequested(Liability), [])
}
