import budgeteur/shared/api_error
import budgeteur/shared/delete_modal
import gleam/option.{None}
import gleeunit/should

fn failing(error: String) -> api_error.ApiError {
  api_error.ApiError(
    error: "boom",
    details: error,
    status_code: None,
    request_id: None,
  )
}

pub fn confirm_from_confirming_transitions_to_deleting_test() {
  let assert Ok(#(state, target)) =
    delete_modal.confirm(delete_modal.open(1, "context"))

  state |> should.equal(delete_modal.Deleting(target: 1, context: "context"))
  target |> should.equal(1)
}

pub fn confirm_from_errored_retries_in_place_test() {
  let state = delete_modal.Errored(target: 1, context: "context", error: "boom")

  let assert Ok(#(state, target)) = delete_modal.confirm(state)

  state |> should.equal(delete_modal.Deleting(target: 1, context: "context"))
  target |> should.equal(1)
}

pub fn confirm_is_a_no_op_when_hidden_test() {
  let state: delete_modal.State(Int, String) = delete_modal.empty()
  let result: Result(#(delete_modal.State(Int, String), Int), Nil) =
    delete_modal.confirm(state)

  result |> should.equal(Error(Nil))
}

pub fn confirm_is_a_no_op_while_deleting_test() {
  let state = delete_modal.Deleting(target: 1, context: "context")
  let result: Result(#(delete_modal.State(Int, String), Int), Nil) =
    delete_modal.confirm(state)

  result |> should.equal(Error(Nil))
}

pub fn fail_moves_a_deleting_state_to_errored_test() {
  let state = delete_modal.Deleting(target: 1, context: "context")

  let state = delete_modal.fail(state, failing("boom"))

  state
  |> should.equal(delete_modal.Errored(
    target: 1,
    context: "context",
    error: "boom",
  ))
}
