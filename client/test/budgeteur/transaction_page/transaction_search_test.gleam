import budgeteur/transaction_page/transaction_search.{Search}
import gleam/list
import gleeunit/should
import youid/uuid

pub fn blank_text_sets_no_criterion_test() {
  Search(..transaction_search.new(), text: "  ")
  |> transaction_search.is_set
  |> should.be_false
}

pub fn a_preset_counts_as_a_filter_test() {
  Search(..transaction_search.new(), preset: transaction_search.ThisYear)
  |> transaction_search.filter_count
  |> should.equal(1)
}

pub fn custom_dates_count_once_a_day_is_given_test() {
  let custom =
    Search(..transaction_search.new(), preset: transaction_search.Custom)
  custom |> transaction_search.filter_count |> should.equal(0)

  Search(..custom, to: "2026-02-01")
  |> transaction_search.filter_count
  |> should.equal(1)
}

pub fn custom_days_can_be_equal_test() {
  let search =
    Search(
      ..transaction_search.new(),
      preset: transaction_search.Custom,
      from: "2026-02-01",
      to: "2026-02-01",
    )
  let assert Ok(_) = transaction_search.validate(search)
}

pub fn account_and_tag_count_as_filters_test() {
  Search(
    ..transaction_search.new(),
    account: transaction_search.NoAccount,
    tag: transaction_search.Untagged,
  )
  |> transaction_search.filter_count
  |> should.equal(2)
}

pub fn select_values_round_trip_test() {
  let assert Ok(id) = uuid.from_string("00000000-0000-0000-0000-0000000000aa")
  [
    transaction_search.AnyAccount,
    transaction_search.NoAccount,
    transaction_search.OneAccount(id),
  ]
  |> list.each(fn(filter) {
    filter
    |> transaction_search.account_to_value
    |> transaction_search.parse_account
    |> should.equal(filter)
  })
  [
    transaction_search.AnyTag,
    transaction_search.WithoutTag,
    transaction_search.Untagged,
    transaction_search.Dismissed,
    transaction_search.Transfer,
    transaction_search.OneTag(id),
  ]
  |> list.each(fn(filter) {
    filter
    |> transaction_search.tag_to_value
    |> transaction_search.parse_tag
    |> should.equal(filter)
  })
}
