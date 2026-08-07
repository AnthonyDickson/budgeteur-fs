import budgeteur/transactions/pages/view_all
import gleam/list
import gleeunit/should

// ── Dummy test ────────────────────────────────────────────────────────────────
// This test exists solely to keep gleeunit happy: it fails when zero tests are
// found. It exercises the pure `update` branch of the transactions
// "view all" page by feeding it an empty fetch result. It is deliberately
// trivial and should be replaced by real behaviour tests.
pub fn view_all_accepts_empty_transactions_test() {
  // Given a freshly initialised view-all page
  let #(model, _effect) = view_all.init()

  // When the client reports an empty fetch result
  let #(new_model, _effect, _out_msgs) =
    view_all.update(model, view_all.ClientFetchedTransactions(Ok([])))

  // Then the model records the empty list
  new_model.transactions
  |> list.length
  |> should.equal(0)
}
