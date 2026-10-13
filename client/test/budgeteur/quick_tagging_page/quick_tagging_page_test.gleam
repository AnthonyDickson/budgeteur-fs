import budgeteur/quick_tagging_page/queue.{Queue, QueuedTransaction}
import budgeteur/quick_tagging_page/quick_tagging_page.{
  ClientFetchedQueue, ClientFetchedTags, Dismiss, Saved, Saving, ServerSaved,
  TagWith, Transfer, UserChose, UserRequestedNextBatch, UserRetried,
}
import budgeteur/shared/api_error.{type ApiError, ApiError}
import budgeteur/shared/api_route
import budgeteur/shared/effect
import budgeteur/shared/http_effect
import budgeteur/shared/out_msg
import budgeteur/shared/remote.{Failed, Loaded, Loading}
import budgeteur/shared/tag.{Expense, Income, Tag}
import budgeteur/shared/toast
import gleam/dict
import gleam/list
import gleam/option.{None, Some}
import gleam/time/calendar.{Date, October}
import gleeunit/should
import youid/uuid

fn transaction(description: String) -> queue.QueuedTransaction {
  QueuedTransaction(
    id: uuid.v7(),
    amount: -42.5,
    description:,
    date: Date(2026, October, 1),
    account_name: None,
  )
}

fn queue() -> queue.Queue {
  Queue(transactions: [transaction("Countdown")], total: 1)
}

fn tag(name: String, kind: tag.TagKind) -> tag.Tag {
  Tag(id: uuid.v7(), name:, color: "#22C55E", kind:)
}

fn api_error() -> ApiError {
  ApiError(
    error: "Error",
    details: "boom",
    status_code: Some(500),
    request_id: None,
  )
}

fn update(model: quick_tagging_page.Model, msg: quick_tagging_page.Msg) {
  let #(model, effect, out_msg) = quick_tagging_page.update(model, msg)
  out_msg |> should.equal(None)
  #(model, effect)
}

fn queue_url() -> String {
  api_route.to_string(api_route.GetQuickTagQueue)
}

fn tags_url() -> String {
  api_route.to_string(api_route.GetAllTags)
}

/// A page that has loaded the queue and tags.
fn loaded_model(queue: queue.Queue) -> quick_tagging_page.Model {
  let #(model, _) = quick_tagging_page.init()
  let #(model, _) = update(model, ClientFetchedQueue(Ok(queue)))
  let #(model, _) = update(model, ClientFetchedTags(Ok([])))
  model
}

/// The id of the queue's first transaction.
fn first_id(queue: queue.Queue) -> uuid.Uuid {
  let assert [first, ..] = queue.transactions
  first.id
}

pub fn init_fetches_the_queue_and_the_tags_test() {
  let #(model, effect) = quick_tagging_page.init()

  model.queue |> should.equal(Loading)
  model.tags |> should.equal(Loading)
  let assert effect.Batch([
    effect.HttpRequest(url: first, ..),
    effect.HttpRequest(url: second, ..),
  ]) = effect
  first |> should.equal(queue_url())
  second |> should.equal(tags_url())
}

pub fn retry_fetches_both_again_after_a_failure_test() {
  let #(model, _) = quick_tagging_page.init()
  let #(model, _) = update(model, ClientFetchedQueue(Error(api_error())))
  let #(model, _) = update(model, ClientFetchedTags(Ok([])))
  model.queue |> should.equal(Failed)

  let #(model, effect) = update(model, UserRetried)

  model.queue |> should.equal(Loading)
  model.tags |> should.equal(Loading)
  let assert effect.Batch([
    effect.HttpRequest(url: first, ..),
    effect.HttpRequest(url: second, ..),
  ]) = effect
  first |> should.equal(queue_url())
  second |> should.equal(tags_url())
}

pub fn choosing_a_tag_saves_it_and_keeps_the_row_test() {
  let queue = queue()
  let id = first_id(queue)
  let tag_id = uuid.v7()
  let model = loaded_model(queue)

  let #(model, effect) = update(model, UserChose(id, TagWith(tag_id)))

  dict.get(model.rows, id)
  |> should.equal(Ok(Saving(choice: TagWith(tag_id), previous: None)))
  let assert effect.HttpRequest(method: http_effect.Put, url:, body:, ..) =
    effect
  url |> should.equal(api_route.to_string(api_route.QuickTagTransaction(id)))
  body |> should.equal("{\"tagId\":\"" <> uuid.to_string(tag_id) <> "\"}")
  quick_tagging_page.waiting(model) |> should.equal(Some(1))

  let #(model, _) = update(model, ServerSaved(id, TagWith(tag_id), Ok(Nil)))

  dict.get(model.rows, id) |> should.equal(Ok(Saved(TagWith(tag_id))))
  model.queue |> should.equal(Loaded(queue))
  quick_tagging_page.waiting(model) |> should.equal(Some(0))
}

pub fn dismissing_sends_a_delete_test() {
  let queue = queue()
  let id = first_id(queue)

  let #(_, effect) = update(loaded_model(queue), UserChose(id, Dismiss))

  let assert effect.HttpRequest(method: http_effect.Delete, url:, ..) = effect
  url |> should.equal(api_route.to_string(api_route.DismissTransaction(id)))
}

pub fn a_row_ignores_choices_while_saving_test() {
  let queue = queue()
  let id = first_id(queue)
  let #(model, _) = update(loaded_model(queue), UserChose(id, Dismiss))

  let #(after, effect) = update(model, UserChose(id, TagWith(uuid.v7())))

  after |> should.equal(model)
  effect |> should.equal(effect.none())
}

pub fn choosing_the_saved_choice_again_sends_nothing_test() {
  let queue = queue()
  let id = first_id(queue)
  let #(model, _) = update(loaded_model(queue), UserChose(id, Dismiss))
  let #(model, _) = update(model, ServerSaved(id, Dismiss, Ok(Nil)))

  let #(after, effect) = update(model, UserChose(id, Dismiss))

  after |> should.equal(model)
  effect |> should.equal(effect.none())
}

pub fn a_failed_save_restores_the_previous_choice_test() {
  let queue = queue()
  let id = first_id(queue)
  let tag_id = uuid.v7()
  let #(model, _) = update(loaded_model(queue), UserChose(id, TagWith(tag_id)))
  let #(model, _) = update(model, ServerSaved(id, TagWith(tag_id), Ok(Nil)))
  let #(model, _) = update(model, UserChose(id, Dismiss))

  let #(model, effect, out_msg) =
    quick_tagging_page.update(
      model,
      ServerSaved(id, Dismiss, Error(api_error())),
    )

  dict.get(model.rows, id) |> should.equal(Ok(Saved(TagWith(tag_id))))
  let assert effect.LogError(_) = effect
  let assert Some(out_msg.PageRequestedToast(title:, level: toast.Error, ..)) =
    out_msg
  title |> should.equal("Could not dismiss the transaction")
}

pub fn a_failed_first_save_leaves_the_row_waiting_test() {
  let queue = queue()
  let id = first_id(queue)
  let #(model, _) = update(loaded_model(queue), UserChose(id, Dismiss))

  let #(model, _, _) =
    quick_tagging_page.update(
      model,
      ServerSaved(id, Dismiss, Error(api_error())),
    )

  dict.get(model.rows, id) |> should.equal(Error(Nil))
  quick_tagging_page.waiting(model) |> should.equal(Some(1))
}

pub fn next_batch_fetches_the_queue_again_test() {
  let queue = queue()
  let id = first_id(queue)
  let #(model, _) = update(loaded_model(queue), UserChose(id, Dismiss))
  let #(model, _) = update(model, ServerSaved(id, Dismiss, Ok(Nil)))

  let #(model, effect) = update(model, UserRequestedNextBatch)

  model.queue |> should.equal(Loading)
  model.tags |> should.equal(Loaded([]))
  model.rows |> should.equal(dict.new())
  let assert effect.HttpRequest(url:, ..) = effect
  url |> should.equal(queue_url())
}

pub fn next_batch_waits_for_saves_in_flight_test() {
  let queue = queue()
  let id = first_id(queue)
  let #(model, _) = update(loaded_model(queue), UserChose(id, Dismiss))

  let #(after, effect) = update(model, UserRequestedNextBatch)

  after |> should.equal(model)
  effect |> should.equal(effect.none())
}

pub fn tags_are_ordered_expenses_first_then_by_name_test() {
  let salary = tag("Salary", Income)
  let rent = tag("Rent", Expense)
  let bonus = tag("Bonus", Income)
  let groceries = tag("Groceries", Expense)

  quick_tagging_page.ordered_tags([salary, rent, bonus, groceries])
  |> list.map(fn(tag) { tag.name })
  |> should.equal(["Groceries", "Rent", "Bonus", "Salary"])
}

pub fn marking_a_transfer_sends_a_put_to_the_transfer_route_test() {
  let queue = queue()
  let id = first_id(queue)

  let #(model, effect) = update(loaded_model(queue), UserChose(id, Transfer))

  let assert effect.HttpRequest(method: http_effect.Put, url:, ..) = effect
  url |> should.equal(api_route.to_string(api_route.MarkTransfer(id)))

  let #(model, _) = update(model, ServerSaved(id, Transfer, Ok(Nil)))

  dict.get(model.rows, id) |> should.equal(Ok(Saved(Transfer)))
  quick_tagging_page.waiting(model) |> should.equal(Some(0))
}
