import budgeteur/balance_sheet_page/balance_sheet_item.{
  type BalanceSheetItem, BalanceSheetItem,
}
import budgeteur/balance_sheet_page/close_modal
import budgeteur/balance_sheet_page/item_modal
import budgeteur/balance_sheet_page/line_details_page.{
  Earliest, Entry, HasEarlier, ItemLine, ItemRef, Only,
}
import budgeteur/balance_sheet_page/value_modal
import budgeteur/shared/api_error.{type ApiError, ApiError}
import budgeteur/shared/api_route
import budgeteur/shared/delete_modal
import budgeteur/shared/effect
import budgeteur/shared/field
import budgeteur/shared/form_modal
import budgeteur/shared/http_effect
import budgeteur/shared/out_msg
import budgeteur/shared/remote.{Loaded, Loading}
import budgeteur/shared/side.{Asset}
import budgeteur/shared/term.{NonCurrent}
import gleam/list
import gleam/option.{None, Some}
import gleam/time/calendar.{Date, February, March}
import gleeunit/should
import youid/uuid

fn house() -> BalanceSheetItem {
  let assert Ok(id) = uuid.from_string("00000000-0000-0000-0000-000000000003")
  BalanceSheetItem(
    id:,
    name: "House",
    side: Asset,
    term: NonCurrent,
    value: 410_000.0,
    as_of: Date(2026, March, 1),
    closed_on: None,
  )
}

const newer = Entry(as_of: Date(2026, March, 1), amount: 410_000.0)

const older = Entry(as_of: Date(2026, February, 1), amount: 400_000.0)

fn loaded() -> line_details_page.Model {
  let #(model, _) = line_details_page.init(ItemRef(house().id))
  line_details_page.Model(
    ..model,
    today: Some(Date(2026, March, 8)),
    line: Loaded(ItemLine(house())),
    entries: Loaded([newer, older]),
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

/// The URLs an effect requests, in order.
fn urls(effect: effect.Effect(msg)) -> List(String) {
  case effect {
    effect.HttpRequest(url:, ..) -> [url]
    effect.Batch(effects) -> list.flat_map(effects, urls)
    _ -> []
  }
}

pub fn init_fetches_the_line_and_its_history_test() {
  let #(model, effect) = line_details_page.init(ItemRef(house().id))

  model.line |> should.equal(Loading)
  model.entries |> should.equal(Loading)
  urls(effect)
  |> should.equal([
    api_route.to_string(api_route.GetBalanceSheetItem(house().id)),
    api_route.to_string(api_route.GetItemObservations(house().id)),
  ])
}

pub fn deleting_an_entry_refetches_and_toasts_test() {
  let #(confirming, _, _) =
    line_details_page.update(
      loaded(),
      line_details_page.UserRequestedDelete(newer),
    )
  let #(deleting, effect, _) =
    line_details_page.update(confirming, line_details_page.UserConfirmedDelete)

  let assert delete_modal.Deleting(..) = deleting.delete_modal
  let assert effect.HttpRequest(method:, url:, ..) = effect
  method |> should.equal(http_effect.Delete)
  url
  |> should.equal(
    api_route.to_string(api_route.DeleteItemObservation(
      house().id,
      Date(2026, March, 1),
    )),
  )

  // The previous value may now be current, so the header is refetched too.
  let #(after, effect, out_msg) =
    line_details_page.update(
      deleting,
      line_details_page.ServerDeletedEntry(newer, Ok(Nil)),
    )

  after.delete_modal |> should.equal(delete_modal.empty())
  urls(effect)
  |> should.equal([
    api_route.to_string(api_route.GetBalanceSheetItem(house().id)),
    api_route.to_string(api_route.GetItemObservations(house().id)),
  ])
  let assert Some(out_msg.PageRequestedToast(body:, ..)) = out_msg
  body |> should.equal("Deleted the value on 2026-03-01")
}

pub fn the_delete_dialog_knows_where_the_entry_sits_test() {
  let place = fn(model, entry) {
    let #(after, _, _) =
      line_details_page.update(
        model,
        line_details_page.UserRequestedDelete(entry),
      )
    let assert delete_modal.Confirming(context:, ..) = after.delete_modal
    context
  }

  place(loaded(), newer) |> should.equal(HasEarlier)
  place(loaded(), older) |> should.equal(Earliest)
  place(line_details_page.Model(..loaded(), entries: Loaded([older])), older)
  |> should.equal(Only)
}

pub fn a_failed_delete_shows_inline_and_a_stale_one_is_ignored_test() {
  let model =
    line_details_page.Model(
      ..loaded(),
      delete_modal: delete_modal.Deleting(target: older, context: Earliest),
    )

  // The server rejects the delete.
  let #(after, effect, out_msg) =
    line_details_page.update(
      model,
      line_details_page.ServerDeletedEntry(older, Error(api_error(400))),
    )

  let assert delete_modal.Errored(error: "boom", ..) = after.delete_modal
  let assert effect.LogError(_) = effect
  out_msg |> should.equal(None)

  // A response after the dialog was closed leaves the page alone.
  let closed =
    line_details_page.Model(..loaded(), delete_modal: delete_modal.empty())
  let #(after, effect, _) =
    line_details_page.update(
      closed,
      line_details_page.ServerDeletedEntry(older, Error(api_error(500))),
    )
  after |> should.equal(closed)
  effect |> should.equal(effect.none())
}

pub fn recording_opens_the_value_form_for_the_item_test() {
  let #(after, _, _) =
    line_details_page.update(loaded(), line_details_page.UserRequestedRecord)

  let assert form_modal.Active(form: value_modal.Form(item:, ..), ..) =
    after.value_modal
  item |> should.equal(house())
}

pub fn closing_puts_the_close_date_and_refetches_test() {
  let #(opened, _, _) =
    line_details_page.update(loaded(), line_details_page.UserRequestedClose)

  // The form opens on today.
  let assert form_modal.Active(form:, ..) = opened.close_modal
  form.closed_on
  |> should.equal(field.Valid(value: Date(2026, March, 8), input: "2026-03-08"))

  let #(submitting, effect, _) =
    line_details_page.update(
      opened,
      line_details_page.CloseModalMsg(close_modal.SaveRequested),
    )

  let assert effect.Batch([effect.HttpRequest(method:, url:, body:, ..), _]) =
    effect
  method |> should.equal(http_effect.Put)
  url |> should.equal(api_route.to_string(api_route.CloseItem(house().id)))
  body |> should.equal("{\"closedOn\":\"2026-03-08\"}")

  // Once closed, the line is refetched to show its close date.
  let #(after, effect, out_msg) =
    line_details_page.update(
      submitting,
      line_details_page.CloseModalMsg(close_modal.SaveCompleted(Ok(Nil))),
    )

  after.close_modal |> should.equal(form_modal.Hidden)
  urls(effect)
  |> should.equal([
    api_route.to_string(api_route.GetBalanceSheetItem(house().id)),
    api_route.to_string(api_route.GetItemObservations(house().id)),
  ])
  let assert Some(out_msg.PageRequestedToast(body: "Closed", ..)) = out_msg
}

pub fn reopening_deletes_the_close_date_and_refetches_test() {
  let #(_, effect, _) =
    line_details_page.update(loaded(), line_details_page.UserRequestedReopen)

  let assert effect.HttpRequest(method:, url:, ..) = effect
  method |> should.equal(http_effect.Delete)
  url |> should.equal(api_route.to_string(api_route.ReopenItem(house().id)))

  let #(_, effect, out_msg) =
    line_details_page.update(
      loaded(),
      line_details_page.ServerReopened(Ok(Nil)),
    )
  urls(effect) |> list.length |> should.equal(2)
  let assert Some(out_msg.PageRequestedToast(body: "Reopened", ..)) = out_msg

  // A failure leaves the page as it is and says so.
  let #(after, _, out_msg) =
    line_details_page.update(
      loaded(),
      line_details_page.ServerReopened(Error(api_error(500))),
    )
  after |> should.equal(loaded())
  let assert Some(out_msg.PageRequestedToast(title: "Could not reopen", ..)) =
    out_msg
}

pub fn editing_saves_the_details_and_deleting_returns_to_the_sheet_test() {
  let #(editing, _, _) =
    line_details_page.update(loaded(), line_details_page.UserRequestedEdit)
  let assert form_modal.Active(mode: form_modal.Edit(id), ..) =
    editing.item_modal
  id |> should.equal(house().id)

  // Saving puts the details.
  let #(_, effect, _) =
    line_details_page.update(
      editing,
      line_details_page.ItemModalMsg(item_modal.SaveRequested),
    )
  let assert effect.Batch([effect.HttpRequest(method:, url:, ..), _]) = effect
  method |> should.equal(http_effect.Put)
  url
  |> should.equal(
    api_route.to_string(api_route.UpdateBalanceSheetItem(house().id)),
  )

  // Delete swaps the form for the confirmation, which deletes the item.
  let #(confirming, _, _) =
    line_details_page.update(
      editing,
      line_details_page.ItemModalMsg(item_modal.DeleteRequested),
    )
  confirming.item_modal |> should.equal(form_modal.Hidden)
  let assert delete_modal.Confirming(target:, ..) = confirming.item_delete_modal
  target |> should.equal(house())

  let #(deleting, effect, _) =
    line_details_page.update(
      confirming,
      line_details_page.UserConfirmedLineDelete,
    )
  let assert effect.HttpRequest(method: http_effect.Delete, url:, ..) = effect
  url
  |> should.equal(
    api_route.to_string(api_route.DeleteBalanceSheetItem(house().id)),
  )

  // Once deleted, the page returns to the balance sheet.
  let #(_, effect, out_msg) =
    line_details_page.update(
      deleting,
      line_details_page.ServerDeletedLine(Ok(Nil)),
    )
  effect |> should.equal(effect.push_url("/balance-sheet"))
  let assert Some(out_msg.PageRequestedToast(body: "Deleted 'House'", ..)) =
    out_msg
}
