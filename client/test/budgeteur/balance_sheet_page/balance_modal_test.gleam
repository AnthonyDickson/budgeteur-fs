import budgeteur/balance_sheet_page/account.{type Account, Account}
import budgeteur/balance_sheet_page/account_write_request.{BalanceEntry}
import budgeteur/balance_sheet_page/balance_form
import budgeteur/balance_sheet_page/balance_modal.{CurrentBalance}
import budgeteur/shared/field
import budgeteur/shared/form_modal.{Active, Edit, NoChange, Put, Updated}
import budgeteur/shared/side.{Asset, Liability}
import budgeteur/shared/term.{Current}
import gleam/option.{None, Some}
import gleam/time/calendar.{Date, March}
import gleeunit/should
import youid/uuid

const today = Date(2026, March, 8)

fn run(
  state: balance_modal.Modal,
  msg: balance_modal.Msg,
) -> balance_modal.Modal {
  let #(state, _, _) = balance_modal.update(state, msg)
  state
}

fn balance(msg: balance_form.Msg) -> balance_modal.Msg {
  balance_modal.BalanceMsg(msg)
}

fn everyday() -> Account {
  let assert Ok(id) = uuid.from_string("00000000-0000-0000-0000-000000000007")
  Account(id:, name: "Everyday", number: None, term: Current, closed_on: None)
}

fn open(current: option.Option(balance_modal.CurrentBalance)) {
  balance_modal.hidden()
  |> run(balance_modal.OpenRequested(
    account: everyday(),
    current:,
    today: Some(today),
  ))
}

pub fn opens_on_the_current_balance_dated_today_test() {
  let state =
    open(
      Some(CurrentBalance(
        side: Asset,
        amount: 1000.0,
        as_of: Date(2026, March, 1),
      )),
    )

  let assert Active(form:, mode: Edit(id)) = state
  id |> should.equal(everyday().id)
  form.balance.side |> should.equal(Asset)
  form.balance.amount
  |> should.equal(field.Valid(value: 1000.0, input: "1000.00"))
  field.value(form.balance.as_of) |> should.equal(Some(today))
}

pub fn an_overdrawn_account_records_a_negative_balance_test() {
  // Recording a liability on an account shown as an asset flips its sign, so
  // the line moves sides once the sheet is refetched.
  let state =
    open(Some(CurrentBalance(side: Asset, amount: 1000.0, as_of: today)))
    |> run(balance(balance_form.SideChanged(Liability)))
    |> run(balance(balance_form.AmountChanged("250.5")))

  let assert #(_, Some(Put(id, entry)), NoChange) =
    balance_modal.update(state, balance_modal.SaveRequested)

  id |> should.equal(everyday().id)
  entry |> should.equal(BalanceEntry(balance: -250.5, as_of: today))

  let #(_, _, outcome) =
    balance_modal.update(
      run(state, balance_modal.SaveRequested),
      balance_modal.SaveCompleted(Ok(everyday())),
    )
  outcome |> should.equal(Updated(everyday()))
}

pub fn an_unknown_balance_starts_blank_and_is_required_test() {
  let state = open(None)

  let assert Active(form:, ..) = state
  form.balance.amount |> should.equal(field.Empty(""))

  let assert #(
    Active(
      form: balance_modal.Form(
        balance: balance_form.Form(
          amount: field.Invalid(error: balance_form.AmountRequired, ..),
          ..,
        ),
        ..,
      ),
      ..,
    ),
    None,
    NoChange,
  ) = balance_modal.update(state, balance_modal.SaveRequested)
}

pub fn a_balance_needs_a_date_and_no_sign_test() {
  let state =
    open(None)
    |> run(balance(balance_form.AmountChanged("10")))
    |> run(balance(balance_form.AsOfChanged("")))

  let assert #(
    Active(
      form: balance_modal.Form(
        balance: balance_form.Form(
          as_of: field.Invalid(error: balance_form.AsOfRequired, ..),
          ..,
        ),
        ..,
      ),
      ..,
    ),
    None,
    NoChange,
  ) = balance_modal.update(state, balance_modal.SaveRequested)

  let assert Active(
    form: balance_modal.Form(
      balance: balance_form.Form(
        amount: field.Invalid(error: balance_form.Negative, ..),
        ..,
      ),
      ..,
    ),
    ..,
  ) = run(state, balance(balance_form.AmountChanged("-10")))
}
