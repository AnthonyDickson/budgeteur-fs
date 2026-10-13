import budgeteur/balance_sheet_page/account.{Account}
import budgeteur/balance_sheet_page/account_modal
import budgeteur/balance_sheet_page/account_write_request.{
  AccountWriteRequest, BalanceEntry,
}
import budgeteur/balance_sheet_page/balance_form
import budgeteur/balance_sheet_page/item_kind.{Liability}
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

fn balance(msg: balance_form.Msg) -> account_modal.Msg {
  account_modal.BalanceMsg(msg)
}

fn new_account() -> account_modal.Modal {
  account_modal.hidden()
  |> run(account_modal.CreateRequested(today: Some(today)))
  |> run(account_modal.NameChanged("Credit card"))
}

pub fn a_liability_opening_balance_is_sent_negative_test() {
  let state =
    new_account()
    |> run(balance(balance_form.SideChanged(Liability)))
    |> run(balance(balance_form.AmountChanged("400")))
    |> run(account_modal.NumberChanged("  XXXX-XXXX-XXXX-1234 "))

  let assert #(_, Some(Post(request)), NoChange) =
    account_modal.update(state, account_modal.SaveRequested)

  request
  |> should.equal(AccountWriteRequest(
    name: "Credit card",
    number: Some("XXXX-XXXX-XXXX-1234"),
    term: Current,
    opening_balance: Some(BalanceEntry(balance: -400.0, as_of: today)),
  ))
}

pub fn a_blank_opening_balance_records_none_and_needs_no_date_test() {
  // An account may be created before its balance is known; the as-of date is
  // ignored without an amount.
  let state =
    new_account()
    |> run(balance(balance_form.AsOfChanged("")))
    |> run(account_modal.TermChanged("NonCurrent"))

  let assert #(_, Some(Post(request)), NoChange) =
    account_modal.update(state, account_modal.SaveRequested)

  request
  |> should.equal(AccountWriteRequest(
    name: "Credit card",
    number: None,
    term: NonCurrent,
    opening_balance: None,
  ))
}

pub fn an_opening_balance_needs_a_date_test() {
  let state =
    new_account()
    |> run(balance(balance_form.AmountChanged("10")))
    |> run(balance(balance_form.AsOfChanged("")))

  let assert #(
    Active(
      form: account_modal.Form(
        opening_balance: Some(balance_form.Form(
          as_of: field.Invalid(error: balance_form.AsOfRequired, ..),
          ..,
        )),
        ..,
      ),
      ..,
    ),
    None,
    NoChange,
  ) = account_modal.update(state, account_modal.SaveRequested)
}

pub fn editing_changes_only_the_details_test() {
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
    |> run(account_modal.EditRequested(account:))

  let assert Active(form:, mode: Edit(_)) = state
  form.opening_balance |> should.equal(None)
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
    opening_balance: None,
  ))
}
