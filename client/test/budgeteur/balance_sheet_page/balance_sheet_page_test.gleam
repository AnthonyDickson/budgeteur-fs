import budgeteur/balance_sheet_page/balance_sheet.{
  type BalanceSheet, BalanceSheet,
}
import budgeteur/balance_sheet_page/balance_sheet_item.{
  type BalanceSheetItem, BalanceSheetItem,
}
import budgeteur/balance_sheet_page/balance_sheet_page
import budgeteur/balance_sheet_page/item_delete_modal
import budgeteur/balance_sheet_page/item_kind.{type ItemKind, Asset, Liability}
import budgeteur/balance_sheet_page/item_modal
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
import gleam/time/timestamp
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
  kind kind: ItemKind,
  term term: Term,
  balance balance: Float,
) -> BalanceSheetItem {
  BalanceSheetItem(id: item_id(id), name:, kind:, term:, balance:)
}

fn empty_model() -> balance_sheet_page.Model {
  balance_sheet_page.Model(
    sheet: balance_sheet_page.Loading,
    item_modal: item_modal.hidden(),
    item_delete_modal: item_delete_modal.empty(),
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
      kind: Asset,
      term: Current,
      balance: field.Empty(""),
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
    statement_date: timestamp.from_unix_seconds(1_772_000_000),
    total_assets: 402_000.0,
    total_liabilities: 301_500.0,
    net_worth: 999.0,
    total_current_assets: 2000.0,
    total_non_current_assets: 400_000.0,
    total_current_liabilities: 1500.0,
    total_non_current_liabilities: 300_000.0,
    working_capital: 500.0,
    items: [
      item(id: 1, name: "Chequing", kind: Asset, term: Current, balance: 2000.0),
      item(
        id: 2,
        name: "Mortgage",
        kind: Liability,
        term: NonCurrent,
        balance: 300_000.0,
      ),
    ],
  )
}

pub fn init_fetches_the_sheet_test() {
  let #(model, effect) = balance_sheet_page.init()

  model.sheet |> should.equal(balance_sheet_page.Loading)

  let assert effect.HttpRequest(method: method, url: url, ..) = effect
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

pub fn not_found_is_the_empty_state_test() {
  let #(model, effect, out_msg) =
    balance_sheet_page.update(
      empty_model(),
      balance_sheet_page.ClientFetchedSheet(Error(api_error(404))),
    )

  // A user with no sheet yet is an expected state, not an error.
  model.sheet |> should.equal(balance_sheet_page.Empty)
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
    item(id: 3, name: "Savings", kind: Asset, term: Current, balance: 500.0)

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
    item(id: 1, name: "Chequing", kind: Asset, term: Current, balance: 2500.0)

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
    item(id: 1, name: "Chequing", kind: Asset, term: Current, balance: 2000.0)

  let #(opened, _, _) =
    balance_sheet_page.update(
      loaded_model(sample_sheet()),
      balance_sheet_page.UserRequestedItemDelete(target),
    )

  let assert delete_modal.Confirming(..) = opened.item_delete_modal

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
    item(id: 1, name: "Chequing", kind: Asset, term: Current, balance: 2000.0)

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
    item(id: 1, name: "Chequing", kind: Asset, term: Current, balance: 2000.0)

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
            kind: Asset,
            term: Current,
            balance: field.Empty(""),
          ),
          form_modal.Create,
        )),
      balance_sheet_page.ItemModalMsg(item_modal.CancelRequested),
    )

  after.item_modal |> should.equal(item_modal.hidden())
  effect |> should.equal(effect.none())
  out_msg |> should.equal(None)
}
