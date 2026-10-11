import budgeteur/balance_sheet_page/account.{Account}
import budgeteur/balance_sheet_page/account_modal.{Held, Owed}
import budgeteur/balance_sheet_page/account_write_request.{
  AccountWriteRequest, BalanceEntry,
}
import budgeteur/balance_sheet_page/term.{Current, NonCurrent}
import budgeteur/shared/field
import budgeteur/shared/form_modal.{Active, Edit, NoChange, Post, Put}
import gleam/option.{None, Some}
import gleam/time/calendar.{Date, March}
import gleeunit/should
import youid/uuid

const today = Date(2026, March, 8)

fn run(
  state: account_modal.Modal,
  msg: account_modal.Msg,
) -> account_modal.Modal {
  let #(state, _, _) = account_modal.update(state, msg)
  state
}

fn new_account() -> account_modal.Modal {
  account_modal.hidden()
  |> run(account_modal.CreateRequested(today: Some(today)))
  |> run(account_modal.NameChanged("Credit card"))
}

pub fn signed_balance_negates_owed_amounts_test() {
  account_modal.signed_balance(Held, 120.5) |> should.equal(120.5)
  account_modal.signed_balance(Owed, 120.5) |> should.equal(-120.5)
  account_modal.signed_balance(Owed, 0.0) |> should.equal(0.0)
}

pub fn an_owed_balance_is_sent_as_a_negative_balance_test() {
  let state =
    new_account()
    |> run(account_modal.SideChanged(Owed))
    |> run(account_modal.BalanceChanged("400"))
    |> run(account_modal.NumberChanged("  XXXX-XXXX-XXXX-1234 "))

  let assert #(_, Some(Post(request)), NoChange) =
    account_modal.update(state, account_modal.SaveRequested)

  request
  |> should.equal(AccountWriteRequest(
    name: "Credit card",
    number: Some("XXXX-XXXX-XXXX-1234"),
    term: Current,
    balance: Some(BalanceEntry(balance: -400.0, as_of: today)),
  ))
}

pub fn a_blank_balance_records_none_and_needs_no_date_test() {
  // An account may be created before its balance is known; the as-of date is
  // ignored without a balance.
  let state =
    new_account()
    |> run(account_modal.AsOfChanged(""))
    |> run(account_modal.TermChanged("NonCurrent"))

  let assert #(_, Some(Post(request)), NoChange) =
    account_modal.update(state, account_modal.SaveRequested)

  request
  |> should.equal(AccountWriteRequest(
    name: "Credit card",
    number: None,
    term: NonCurrent,
    balance: None,
  ))
}

pub fn a_balance_needs_a_date_and_a_magnitude_test() {
  let state =
    new_account()
    |> run(account_modal.BalanceChanged("10"))
    |> run(account_modal.AsOfChanged(""))

  let assert #(
    Active(
      form: account_modal.Form(
        as_of: field.Invalid(error: account_modal.AsOfRequired, ..),
        ..,
      ),
      ..,
    ),
    None,
    NoChange,
  ) = account_modal.update(state, account_modal.SaveRequested)

  let assert Active(
    form: account_modal.Form(
      balance: field.Invalid(error: account_modal.Negative, ..),
      ..,
    ),
    ..,
  ) = run(state, account_modal.BalanceChanged("-10"))
}

pub fn editing_keeps_the_balance_unless_one_is_entered_test() {
  let assert Ok(id) = uuid.from_string("00000000-0000-0000-0000-000000000007")
  let account =
    Account(
      id:,
      name: "Everyday",
      number: Some("12-3456-0789012-000"),
      term: Current,
    )

  let state =
    account_modal.hidden()
    |> run(account_modal.EditRequested(account:, today: Some(today)))

  let assert Active(form:, mode: Edit(_)) = state
  form.balance |> should.equal(field.Empty(""))
  form.number |> should.equal("12-3456-0789012-000")

  let assert #(_, Some(Put(put_id, request)), NoChange) =
    account_modal.update(
      run(state, account_modal.NameChanged("Bills")),
      account_modal.SaveRequested,
    )

  put_id |> should.equal(id)
  request
  |> should.equal(AccountWriteRequest(
    name: "Bills",
    number: Some("12-3456-0789012-000"),
    term: Current,
    balance: None,
  ))
}
