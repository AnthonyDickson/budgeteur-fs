import budgeteur/shared/number
import gleeunit/should

pub fn format_int_groups_digits_test() {
  number.format_int(1_234_567) |> should.equal("1,234,567")
  number.format_int(999) |> should.equal("999")
  number.format_int(0) |> should.equal("0")
}
