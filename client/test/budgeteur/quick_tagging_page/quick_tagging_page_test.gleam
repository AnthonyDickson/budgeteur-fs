import budgeteur/quick_tagging_page/queue.{Queue, QueuedTransaction}
import budgeteur/quick_tagging_page/quick_tagging_page.{
  ClientFetchedQueue, ClientFetchedTags, UserRequestedNextBatch, UserRetried,
}
import budgeteur/shared/api_error.{type ApiError, ApiError}
import budgeteur/shared/api_route
import budgeteur/shared/effect
import budgeteur/shared/remote.{Failed, Loaded, Loading}
import gleam/option.{None, Some}
import gleam/time/calendar.{Date, October}
import gleeunit/should
import youid/uuid

fn queue() -> queue.Queue {
  Queue(
    transactions: [
      QueuedTransaction(
        id: uuid.v7(),
        amount: -42.5,
        description: "Countdown",
        date: Date(2026, October, 1),
        account_name: None,
      ),
    ],
    total: 1,
  )
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

/// A page that has loaded its queue and tags.
fn loaded_model(queue: queue.Queue) -> quick_tagging_page.Model {
  let #(model, _) = quick_tagging_page.init()
  let #(model, _) = update(model, ClientFetchedQueue(Ok(queue)))
  let #(model, _) = update(model, ClientFetchedTags(Ok([])))
  model
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

pub fn next_batch_fetches_the_queue_again_test() {
  let queue = queue()
  let model = loaded_model(queue)
  model.queue |> should.equal(Loaded(queue))

  let #(model, effect) = update(model, UserRequestedNextBatch)

  model.queue |> should.equal(Loading)
  model.tags |> should.equal(Loaded([]))
  let assert effect.HttpRequest(url:, ..) = effect
  url |> should.equal(queue_url())
}
