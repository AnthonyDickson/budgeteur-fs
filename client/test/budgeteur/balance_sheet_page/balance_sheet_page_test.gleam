import budgeteur/balance_sheet_page/account.{type Account, Account}
import budgeteur/balance_sheet_page/account_delete_modal
import budgeteur/balance_sheet_page/account_modal
import budgeteur/balance_sheet_page/balance_form
import budgeteur/balance_sheet_page/balance_modal
import budgeteur/balance_sheet_page/balance_sheet.{
  type BalanceSheet, BalanceSheet,
}
import budgeteur/balance_sheet_page/balance_sheet_item.{
  type BalanceSheetItem, BalanceSheetItem,
}
import budgeteur/balance_sheet_page/balance_sheet_page
import budgeteur/balance_sheet_page/item_delete_modal
import budgeteur/balance_sheet_page/item_modal
import budgeteur/balance_sheet_page/side.{type Side, Asset, Liability}
import budgeteur/balance_sheet_page/term.{type Term, Current, NonCurrent}
import budgeteur/shared/api_error.{type ApiError, ApiError}
import budgeteur/shared/api_route
import budgeteur/shared/delete_modal
import budgeteur/shared/effect
import budgeteur/shared/field
import budgeteur/shared/form_modal
import budgeteur/shared/http_effect
import budgeteur/shared/out_msg
import budgeteur/shared/toast
import gleam/int
import gleam/option.{None, Some}
import gleam/time/calendar.{Date, March}
import gleeunit/should
import youid/uuid.{type Uuid}

fn item_id(n: Int) -> Uuid {
  let assert Ok(id) =
    uuid.from_string("00000000-0000-0000-0000-00000000000" <> int.to_string(n))
  id
}

fn item(
  id id: Int,
  name name: String,
  side side: Side,
  term term: Term,
  value value: Float,
) -> BalanceSheetItem {
  BalanceSheetItem(
    id: item_id(id),
    name:,
    side:,
    term:,
    value:,
    as_of: Date(2026, March, 1),
  )
}

fn empty_model() -> balance_sheet_page.Model {
  balance_sheet_page.Model(
    sheet: balance_sheet_page.Loading,
    today: None,
    item_modal: item_modal.hidden(),
    item_delete_modal: item_delete_modal.empty(),
    account_modal: account_modal.hidden(),
    account_delete_modal: account_delete_modal.empty(),
    balance_modal: balance_modal.hidden(),
  )
}

fn loaded_model(sheet: BalanceSheet) -> balance_sheet_page.Model {
  balance_sheet_page.Model(
    ..empty_model(),
    sheet: balance_sheet_page.Loaded(sheet),
  )
}

fn with_modal(
  model: balance_sheet_page.Model,
  modal: item_modal.Modal,
) -> balance_sheet_page.Model {
  balance_sheet_page.Model(..model, item_modal: modal)
}

/// A model whose delete dialog is mid-request for `item`.
fn deleting_model(
  model: balance_sheet_page.Model,
  target: BalanceSheetItem,
) -> balance_sheet_page.Model {
  let assert Ok(#(state, _)) =
    delete_modal.confirm(item_delete_modal.open(target))

  balance_sheet_page.Model(..model, item_delete_modal: state)
}

fn submitting_modal(mode: form_modal.Mode) -> item_modal.Modal {
  form_modal.Submitting(
    item_modal.Form(
      name: field.Empty(""),
      side: Asset,
      term: Current,
      value: field.Empty(""),
      as_of: field.Empty(""),
    ),
    mode,
  )
}

fn api_error(status_code: Int) -> ApiError {
  ApiError(
    error: "Error",
    details: "boom",
    status_code: Some(status_code),
    request_id: None,
  )
}

/// A sheet whose totals deliberately disagree with its items, so a page that
/// recomputed them locally would be caught.
fn sample_sheet() -> BalanceSheet {
  BalanceSheet(
    total_assets: 402_000.0,
    total_liabilities: 301_500.0,
    net_worth: 999.0,
    total_current_assets: 2000.0,
    total_non_current_assets: 400_000.0,
    total_current_liabilities: 1500.0,
    total_non_current_liabilities: 300_000.0,
    working_capital: 500.0,
    items: [
      item(id: 1, name: "Chequing", side: Asset, term: Current, value: 2000.0),
      item(
        id: 2,
        name: "Mortgage",
        side: Liability,
        term: NonCurrent,
        value: 300_000.0,
      ),
    ],
    accounts: [],
    unknown_balances: [],
  )
}

pub fn init_asks_for_today_and_fetches_the_sheet_test() {
  let #(model, effect) = balance_sheet_page.init()

  model.sheet |> should.equal(balance_sheet_page.Loading)

  let assert effect.Batch([
    effect.GetLocalDate(_),
    effect.HttpRequest(method: method, url: url, ..),
  ]) = effect
  method |> should.equal(http_effect.Get)
  url |> should.equal(api_route.to_string(api_route.GetBalanceSheet))
}

pub fn a_fetched_sheet_is_loaded_verbatim_test() {
  let #(model, effect, out_msg) =
    balance_sheet_page.update(
      empty_model(),
      balance_sheet_page.ClientFetchedSheet(Ok(sample_sheet())),
    )

  // The server owns the totals, so they are kept as received.
  model.sheet |> should.equal(balance_sheet_page.Loaded(sample_sheet()))
  out_msg |> should.equal(None)
  effect |> should.equal(effect.none())
}

pub fn a_failed_fetch_retries_or_keeps_the_loaded_sheet_test() {
  // With nothing loaded there is nothing to show, so the page offers a retry.
  let #(failed, failed_effect, failed_out_msg) =
    balance_sheet_page.update(
      empty_model(),
      balance_sheet_page.ClientFetchedSheet(Error(api_error(500))),
    )

  failed.sheet |> should.equal(balance_sheet_page.Failed)
  failed_out_msg |> should.equal(None)
  let assert effect.LogError(_) = failed_effect

  // With a sheet loaded earlier (e.g. a refetch after a write), the data must
  // not appear to vanish.
  let loaded = loaded_model(sample_sheet())

  let #(kept, kept_effect, kept_out_msg) =
    balance_sheet_page.update(
      loaded,
      balance_sheet_page.ClientFetchedSheet(Error(api_error(500))),
    )

  kept |> should.equal(loaded)
  let assert effect.LogError(_) = kept_effect
  let assert Some(out_msg.PageRequestedToast(level: level, ..)) = kept_out_msg
  level |> should.equal(toast.Error)
}

pub fn saving_an_item_closes_the_dialog_refetches_and_toasts_test() {
  let created =
    item(id: 3, name: "Savings", side: Asset, term: Current, value: 500.0)

  let #(after, effect, out_msg) =
    balance_sheet_page.update(
      loaded_model(sample_sheet())
        |> with_modal(submitting_modal(form_modal.Create)),
      balance_sheet_page.ItemModalMsg(item_modal.SaveCompleted(Ok(created))),
    )

  after.item_modal |> should.equal(item_modal.hidden())
  let assert Some(out_msg.PageRequestedToast(level: level, body: body, ..)) =
    out_msg
  level |> should.equal(toast.Success)
  body |> should.equal("Created item 'Savings'")

  // The save response carries only the item, so the page refetches the sheet
  // rather than recomputing the totals.
  let assert effect.HttpRequest(method: method, url: url, ..) = effect
  method |> should.equal(http_effect.Get)
  url |> should.equal(api_route.to_string(api_route.GetBalanceSheet))
}

pub fn updating_an_item_reports_the_updated_item_test() {
  let existing =
    item(id: 1, name: "Chequing", side: Asset, term: Current, value: 2500.0)

  let #(after, _, out_msg) =
    balance_sheet_page.update(
      loaded_model(sample_sheet())
        |> with_modal(submitting_modal(form_modal.Edit(existing.id))),
      balance_sheet_page.ItemModalMsg(item_modal.SaveCompleted(Ok(existing))),
    )

  after.item_modal |> should.equal(item_modal.hidden())
  let assert Some(out_msg.PageRequestedToast(level: level, body: body, ..)) =
    out_msg
  level |> should.equal(toast.Success)
  body |> should.equal("Updated item 'Chequing'")
}

pub fn confirming_a_delete_arms_a_delete_request_test() {
  let target =
    item(id: 1, name: "Chequing", side: Asset, term: Current, value: 2000.0)

  // Delete in the item's edit dialog swaps the dialog for the confirmation.
  let #(editing, _, _) =
    balance_sheet_page.update(
      loaded_model(sample_sheet()),
      balance_sheet_page.UserRequestedItemEdit(target.id),
    )
  let #(opened, _, _) =
    balance_sheet_page.update(
      editing,
      balance_sheet_page.ItemModalMsg(item_modal.DeleteRequested),
    )

  opened.item_modal |> should.equal(item_modal.hidden())
  opened.item_delete_modal |> should.equal(item_delete_modal.open(target))

  let #(deleting, effect, _) =
    balance_sheet_page.update(
      opened,
      balance_sheet_page.UserConfirmedItemDelete,
    )

  let assert delete_modal.Deleting(..) = deleting.item_delete_modal

  let assert effect.HttpRequest(method: method, url: url, timeout: timeout, ..) =
    effect
  method |> should.equal(http_effect.Delete)
  url
  |> should.equal(
    api_route.to_string(api_route.DeleteBalanceSheetItem(target.id)),
  )
  timeout |> should.equal(Some(delete_modal.delete_timeout_ms))
}

pub fn a_deleted_item_hides_the_dialog_refetches_and_toasts_test() {
  let target =
    item(id: 1, name: "Chequing", side: Asset, term: Current, value: 2000.0)

  let model = loaded_model(sample_sheet()) |> deleting_model(target)

  let #(after, effect, out_msg) =
    balance_sheet_page.update(
      model,
      balance_sheet_page.ServerDeletedItem(target, Ok(Nil)),
    )

  after.item_delete_modal |> should.equal(item_delete_modal.empty())

  let assert effect.HttpRequest(method: method, url: url, ..) = effect
  method |> should.equal(http_effect.Get)
  url |> should.equal(api_route.to_string(api_route.GetBalanceSheet))

  let assert Some(out_msg.PageRequestedToast(level: level, body: body, ..)) =
    out_msg
  level |> should.equal(toast.Success)
  body |> should.equal("Deleted item 'Chequing'")

  // An item that is already gone matches the user's intent, so a 404 is
  // reported as a successful delete.
  let #(already_gone, _, already_gone_out_msg) =
    balance_sheet_page.update(
      model,
      balance_sheet_page.ServerDeletedItem(target, Error(api_error(404))),
    )

  already_gone.item_delete_modal |> should.equal(item_delete_modal.empty())
  let assert Some(out_msg.PageRequestedToast(level: gone_level, ..)) =
    already_gone_out_msg
  gone_level |> should.equal(toast.Success)
}

pub fn a_delete_failure_shows_inline_and_logs_test() {
  let target =
    item(id: 1, name: "Chequing", side: Asset, term: Current, value: 2000.0)

  let #(after, effect, out_msg) =
    balance_sheet_page.update(
      loaded_model(sample_sheet()) |> deleting_model(target),
      balance_sheet_page.ServerDeletedItem(target, Error(api_error(500))),
    )

  let assert delete_modal.Errored(error: details, ..) = after.item_delete_modal
  details |> should.equal("boom")
  let assert effect.LogError(_) = effect
  out_msg |> should.equal(None)
}

pub fn cancelling_the_item_form_hides_it_test() {
  let #(after, effect, out_msg) =
    balance_sheet_page.update(
      loaded_model(sample_sheet())
        |> with_modal(form_modal.Active(
          item_modal.Form(
            name: field.Empty(""),
            side: Asset,
            term: Current,
            value: field.Empty(""),
            as_of: field.Empty(""),
          ),
          form_modal.Create,
        )),
      balance_sheet_page.ItemModalMsg(item_modal.CancelRequested),
    )

  after.item_modal |> should.equal(item_modal.hidden())
  effect |> should.equal(effect.none())
  out_msg |> should.equal(None)
}

fn sample_account() -> Account {
  Account(id: item_id(5), name: "Everyday", number: None, term: Current)
}

pub fn recording_a_balance_posts_it_and_refetches_the_sheet_test() {
  let model =
    balance_sheet_page.Model(
      ..loaded_model(sample_sheet()),
      today: Some(Date(2026, March, 8)),
    )

  // "Record balance" on an unknown balance opens the balance form, dated
  // today.
  let #(opened, _, _) =
    balance_sheet_page.update(
      model,
      balance_sheet_page.UserRequestedBalanceRecord(sample_account(), None),
    )

  let assert form_modal.Active(form:, mode: form_modal.Edit(id)) =
    opened.balance_modal
  id |> should.equal(sample_account().id)
  form.balance.as_of
  |> should.equal(field.Valid(value: Date(2026, March, 8), input: "2026-03-08"))

  let #(filled, _, _) =
    balance_sheet_page.update(
      opened,
      balance_sheet_page.BalanceModalMsg(
        balance_modal.BalanceMsg(balance_form.AmountChanged("12.50")),
      ),
    )
  let #(submitting, effect, _) =
    balance_sheet_page.update(
      filled,
      balance_sheet_page.BalanceModalMsg(balance_modal.SaveRequested),
    )

  let assert effect.HttpRequest(method:, url:, ..) = effect
  method |> should.equal(http_effect.Post)
  url
  |> should.equal(
    api_route.to_string(api_route.RecordBalance(sample_account().id)),
  )

  let #(after, effect, out_msg) =
    balance_sheet_page.update(
      submitting,
      balance_sheet_page.BalanceModalMsg(
        balance_modal.SaveCompleted(Ok(sample_account())),
      ),
    )

  after.balance_modal |> should.equal(balance_modal.hidden())
  let assert Some(out_msg.PageRequestedToast(body:, ..)) = out_msg
  body |> should.equal("Recorded a balance for 'Everyday'")
  let assert effect.HttpRequest(url:, ..) = effect
  url |> should.equal(api_route.to_string(api_route.GetBalanceSheet))
}

pub fn saving_an_account_refetches_the_sheet_and_toasts_test() {
  let submitting =
    account_modal.update(
      account_modal.hidden(),
      account_modal.CreateRequested(today: None),
    )
  let #(active, _, _) = submitting
  let #(active, _, _) =
    account_modal.update(active, account_modal.NameChanged("Everyday"))
  let #(submitting, _, _) =
    account_modal.update(active, account_modal.SaveRequested)

  let #(after, effect, out_msg) =
    balance_sheet_page.update(
      balance_sheet_page.Model(
        ..loaded_model(sample_sheet()),
        account_modal: submitting,
      ),
      balance_sheet_page.AccountModalMsg(
        account_modal.SaveCompleted(Ok(sample_account())),
      ),
    )

  after.account_modal |> should.equal(account_modal.hidden())
  let assert Some(out_msg.PageRequestedToast(level: level, body: body, ..)) =
    out_msg
  level |> should.equal(toast.Success)
  body |> should.equal("Created account 'Everyday'")

  // The save may have recorded a balance, so the server's totals are fetched
  // again.
  let assert effect.HttpRequest(method: method, url: url, ..) = effect
  method |> should.equal(http_effect.Get)
  url |> should.equal(api_route.to_string(api_route.GetBalanceSheet))
}

pub fn deleting_an_account_sends_a_delete_and_refetches_test() {
  let account = sample_account()
  let model =
    loaded_model(BalanceSheet(..sample_sheet(), unknown_balances: [account]))

  // The account opens on its balance form; "Edit account" swaps it for the
  // account form, and Delete there swaps that for the confirmation.
  let #(recording, _, _) =
    balance_sheet_page.update(
      model,
      balance_sheet_page.UserRequestedBalanceRecord(account, None),
    )
  let #(editing, _, _) =
    balance_sheet_page.update(
      recording,
      balance_sheet_page.BalanceModalMsg(balance_modal.EditAccountRequested),
    )

  editing.balance_modal |> should.equal(balance_modal.hidden())
  let assert form_modal.Active(mode: form_modal.Edit(id), ..) =
    editing.account_modal
  id |> should.equal(account.id)

  let #(opened, _, _) =
    balance_sheet_page.update(
      editing,
      balance_sheet_page.AccountModalMsg(account_modal.DeleteRequested),
    )

  opened.account_modal |> should.equal(account_modal.hidden())
  opened.account_delete_modal
  |> should.equal(account_delete_modal.open(account))

  let #(deleting, effect, _) =
    balance_sheet_page.update(
      opened,
      balance_sheet_page.UserConfirmedAccountDelete,
    )

  let assert delete_modal.Deleting(..) = deleting.account_delete_modal
  let assert effect.HttpRequest(method: method, url: url, ..) = effect
  method |> should.equal(http_effect.Delete)
  url |> should.equal(api_route.to_string(api_route.DeleteAccount(account.id)))

  let #(after, effect, out_msg) =
    balance_sheet_page.update(
      deleting,
      balance_sheet_page.ServerDeletedAccount(account, Ok(Nil)),
    )

  after.account_delete_modal |> should.equal(account_delete_modal.empty())
  let assert effect.HttpRequest(url: url, ..) = effect
  url |> should.equal(api_route.to_string(api_route.GetBalanceSheet))
  let assert Some(out_msg.PageRequestedToast(body: body, ..)) = out_msg
  body |> should.equal("Deleted account 'Everyday'")
}
