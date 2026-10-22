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
import gleam/string
import gleam/time/calendar.{Date, October}
import gleeunit/should
import lustre/element
import youid/uuid

fn transaction(description: String) -> queue.QueuedTransaction {
  QueuedTransaction(
    id: uuid.v7(),
    amount: -42.5,
    description:,
    date: Date(2026, October, 1),
    account_name: None,
    suggestion: None,
  )
}

fn queue() -> queue.Queue {
  Queue(transactions: [transaction("Countdown")], total: 1)
}

fn tag(name: String, kind: tag.TagKind) -> tag.Tag {
  Tag(id: uuid.v7(), name:, color: tag.Green, kind:)
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
  body
  |> should.equal(
    "{\"tagId\":\"" <> uuid.to_string(tag_id) <> "\",\"suggested\":false}",
  )
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

fn suggested_transfer_queue() -> queue.Queue {
  let suggestion =
    queue.Suggestion(target: queue.TransferTarget, pattern: "TO SAVINGS")
  Queue(
    transactions: [
      QueuedTransaction(
        ..transaction("Transfer to savings"),
        suggestion: Some(suggestion),
      ),
    ],
    total: 1,
  )
}

pub fn choosing_the_suggestion_sends_the_suggestion_flag_test() {
  let queue = suggested_transfer_queue()
  let id = first_id(queue)
  let groceries = tag("Groceries", Expense)
  let #(model, _) =
    update(loaded_model(queue), ClientFetchedTags(Ok([groceries])))

  let #(_, effect) = update(model, UserChose(id, Transfer))
  let assert effect.HttpRequest(body:, ..) = effect
  body |> should.equal("{\"suggested\":true}")

  let #(_, effect) = update(model, UserChose(id, TagWith(groceries.id)))
  let assert effect.HttpRequest(body:, ..) = effect
  body
  |> should.equal(
    "{\"tagId\":\"" <> uuid.to_string(groceries.id) <> "\",\"suggested\":false}",
  )
}

pub fn the_suggested_button_is_marked_without_moving_test() {
  let queue = suggested_transfer_queue()
  let groceries = tag("Groceries", Expense)
  let #(model, _) =
    update(loaded_model(queue), ClientFetchedTags(Ok([groceries])))
  let html = element.to_string(quick_tagging_page.view(model))

  // The buttons keep their order: the tag, then Transfer, then Dismiss.
  let assert [_, after_tag] =
    string.split(html, "data-testid=\"quick-tag-button\"")
  let assert [_, after_transfer] =
    string.split(after_tag, "data-testid=\"quick-tag-transfer\"")
  after_transfer
  |> string.contains("data-testid=\"quick-tag-dismiss\"")
  |> should.be_true

  // Only Transfer is marked, and the label names the rule's pattern.
  string.split(html, "data-suggested=\"true\"")
  |> list.length
  |> should.equal(2)
  html |> string.contains("TO SAVINGS") |> should.be_true
}
