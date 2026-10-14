import budgeteur/balance_sheet_page/balance_sheet_item.{
  type BalanceSheetItem, BalanceSheetItem,
}
import budgeteur/balance_sheet_page/observation_history_page.{
  Entry, ItemLine, ItemRef,
}
import budgeteur/balance_sheet_page/value_modal
import budgeteur/shared/api_error.{type ApiError, ApiError}
import budgeteur/shared/api_route
import budgeteur/shared/delete_modal
import budgeteur/shared/effect
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

fn loaded() -> observation_history_page.Model {
  let #(model, _) = observation_history_page.init(ItemRef(house().id))
  observation_history_page.Model(
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
  let #(model, effect) = observation_history_page.init(ItemRef(house().id))

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
    observation_history_page.update(
      loaded(),
      observation_history_page.UserRequestedDelete(newer),
    )
  let #(deleting, effect, _) =
    observation_history_page.update(
      confirming,
      observation_history_page.UserConfirmedDelete,
    )

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
    observation_history_page.update(
      deleting,
      observation_history_page.ServerDeletedEntry(newer, Ok(Nil)),
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

pub fn a_failed_delete_shows_inline_and_a_stale_one_is_ignored_test() {
  let model =
    observation_history_page.Model(
      ..loaded(),
      delete_modal: delete_modal.Deleting(target: older, context: Nil),
    )

  // The item's only value is kept: the server rejects the delete.
  let #(after, effect, out_msg) =
    observation_history_page.update(
      model,
      observation_history_page.ServerDeletedEntry(older, Error(api_error(400))),
    )

  let assert delete_modal.Errored(error: "boom", ..) = after.delete_modal
  let assert effect.LogError(_) = effect
  out_msg |> should.equal(None)

  // A response after the dialog was closed leaves the page alone.
  let closed =
    observation_history_page.Model(
      ..loaded(),
      delete_modal: delete_modal.empty(),
    )
  let #(after, effect, _) =
    observation_history_page.update(
      closed,
      observation_history_page.ServerDeletedEntry(older, Error(api_error(500))),
    )
  after |> should.equal(closed)
  effect |> should.equal(effect.none())
}

pub fn recording_opens_the_value_form_for_the_item_test() {
  let #(after, _, _) =
    observation_history_page.update(
      loaded(),
      observation_history_page.UserRequestedRecord,
    )

  let assert form_modal.Active(form: value_modal.Form(item:, ..), ..) =
    after.value_modal
  item |> should.equal(house())
}
