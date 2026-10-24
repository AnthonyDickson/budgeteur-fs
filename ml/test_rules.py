import unittest

from rules import Rule, winner


def rule(pattern: str, tag_id: str | None = "tag") -> Rule:
    return Rule(id=pattern, pattern=pattern, tag_id=tag_id)


class WinnerTests(unittest.TestCase):
    def test_matches_a_substring_ignoring_case(self):
        self.assertEqual(winner([rule("pak")])("POS W/D PAK N SAVE").pattern, "pak")

    def test_no_match(self):
        self.assertIsNone(winner([rule("COUNTDOWN")])("PAK N SAVE"))

    def test_longest_pattern_wins_whatever_its_target(self):
        rules = [rule("PAK", "groceries"), rule("PAK N SAVE FUEL", None)]
        self.assertIsNone(winner(rules)("PAK N SAVE FUEL").tag_id)

    def test_equal_lengths_ordered_by_the_comparison(self):
        rules = [rule("save", "b"), rule("PAK ", "a")]
        self.assertEqual(winner(rules)("PAK N SAVE").tag_id, "a")

    def test_case_folding_keeps_lengths(self):
        # .NET's OrdinalIgnoreCase does not fold ß to SS, as Python's upper() does.
        self.assertIsNone(winner([rule("SS")])("STRAßE"))


if __name__ == "__main__":
    unittest.main()
