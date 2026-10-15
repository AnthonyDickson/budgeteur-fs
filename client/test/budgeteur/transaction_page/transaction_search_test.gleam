import budgeteur/transaction_page/transaction_search.{Search}
import gleeunit/should

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
