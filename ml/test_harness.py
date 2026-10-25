import tempfile
import unittest
from pathlib import Path

import pandas as pd

import baselines
import harness
from harness import LabelPolicy

TAG = "tag-groceries"
OTHER = "tag-rent"

TRANSACTION_COLUMNS = [
    "id", "date", "amount", "description", "account_id", "kind", "tag_id", "source"
]


def transaction(id, date, description, kind="", tag_id="", source="", amount="-10.00"):
    return [id, date, amount, description, "account", kind, tag_id, source]


def load(transactions: list[list[str]], rules: list[list[str]] | None = None) -> harness.Dataset:
    with tempfile.TemporaryDirectory() as directory:
        path = Path(directory)
        transactions = pd.DataFrame(transactions, columns=TRANSACTION_COLUMNS)
        transactions.to_csv(path / "transactions.csv", index=False)
        pd.DataFrame(
            [[TAG, "Groceries", "Expense"], [OTHER, "Rent", "Expense"]],
            columns=["id", "name", "kind"],
        ).to_csv(path / "tags.csv", index=False)
        pd.DataFrame(rules or [], columns=["id", "pattern", "target", "tag_id"]).to_csv(
            path / "rules.csv", index=False
        )
        return harness.load(path)


def results(predicted: list[str | None], confidence: list[float], label: list[str]) -> pd.DataFrame:
    frame = pd.DataFrame(
        {
            "id": [str(i) for i in range(len(label))],
            "label": label,
            "predicted": pd.Series(predicted, dtype=object),
            "confidence": confidence,
            "seen": True,
        }
    )
    frame["correct"] = frame["predicted"] == frame["label"]
    return frame


class NormaliseTests(unittest.TestCase):
    def test_folds_case_replaces_digit_runs_and_collapses_whitespace(self):
        self.assertEqual(harness.normalise(" Pak n Save  4021 "), "PAK N SAVE #")


class TrainingSetTests(unittest.TestCase):
    dataset = load(
        [
            transaction("m", "2026-01-01", "MANUAL", "Tagged", TAG, "Manual"),
            transaction("a", "2026-01-01", "ACCEPTED", "Tagged", TAG, "Accepted"),
            transaction("d", "2026-01-01", "DETECTED", "Transfer", "", "Detected"),
            transaction("x", "2026-01-01", "DISMISSED", "Dismissed", "", "Manual"),
            transaction("u", "2026-01-01", "UNTAGGED"),
            transaction("r1", "2026-01-01", "PAK 1", "Tagged", TAG, "Rule"),
            transaction("r2", "2026-01-01", "PAK 22", "Tagged", TAG, "Rule"),
            transaction("r3", "2026-01-01", "PAK 333", "Tagged", TAG, "Rule"),
            transaction("r4", "2026-01-01", "RENT", "Tagged", OTHER, "Rule"),
        ]
    )

    def weights(self, policy: LabelPolicy) -> dict[str, float]:
        training = harness.training_set(self.dataset.transactions, policy)
        return dict(zip(training["id"], training["weight"]))

    def test_default_policy_leaves_out_rule_labels(self):
        weights = self.weights(LabelPolicy(accepted_weight=0.25))
        self.assertEqual(weights, {"m": 1, "a": 0.25, "d": 1})

    def test_detected_transfers_can_be_left_out(self):
        self.assertNotIn("d", self.weights(LabelPolicy(detected=False)))

    def test_uncapped_rule_labels_have_full_weight(self):
        weights = self.weights(LabelPolicy(rule_labels="uncapped"))
        self.assertEqual([weights[id] for id in ["r1", "r2", "r3", "r4"]], [1, 1, 1, 1])

    def test_capped_rule_labels_share_the_cap_per_normalised_description(self):
        weights = self.weights(LabelPolicy(rule_labels="capped", rule_cap=1.5))
        self.assertEqual([weights[id] for id in ["r1", "r2", "r3", "r4"]], [0.5, 0.5, 0.5, 1])


class EvaluateTests(unittest.TestCase):
    dataset = load(
        [
            transaction("jan-rule", "2026-01-05", "PAK N SAVE", "Tagged", TAG, "Rule"),
            transaction("jan", "2026-01-10", "COUNTDOWN", "Tagged", TAG, "Manual"),
            transaction("feb", "2026-02-03", "COUNTDOWN", "Tagged", TAG, "Accepted"),
            transaction("feb-matched", "2026-02-04", "PAK N SAVE", "Tagged", TAG, "Manual"),
            transaction("feb-detected", "2026-02-05", "TRANSFER", "Transfer", "", "Detected"),
            transaction("feb-untagged", "2026-02-06", "NEW WORLD"),
            transaction("mar", "2026-03-01", "LANDLORD", "Tagged", OTHER, "Manual"),
        ],
        rules=[["rule", "pak", "Tag", TAG]],
    )

    def test_scores_only_residual_rows_the_user_labelled_after_the_first_month(self):
        evaluated = harness.evaluate(self.dataset, baselines.lookup, LabelPolicy())
        self.assertEqual(list(evaluated["id"]), ["feb", "mar"])

    def test_trains_only_on_labels_before_the_cutoff_and_hides_test_labels(self):
        calls = []

        def spy(training, rows):
            calls.append((set(training["id"]), set(rows["id"]), set(rows.columns)))
            return baselines.most_common(training, rows)

        harness.evaluate(self.dataset, spy, LabelPolicy(rule_labels="uncapped"))
        self.assertEqual(
            [(training, rows) for training, rows, _ in calls],
            [
                ({"jan-rule", "jan"}, {"feb"}),
                ({"jan-rule", "jan", "feb", "feb-matched", "feb-detected"}, {"mar"}),
            ],
        )
        self.assertTrue(all(columns == set(harness.FEATURES) for _, _, columns in calls))

    def test_marks_seen_merchants_and_correct_predictions(self):
        evaluated = harness.evaluate(self.dataset, baselines.lookup, LabelPolicy()).set_index("id")
        self.assertEqual(evaluated.loc["feb", ["seen", "correct"]].tolist(), [True, True])
        self.assertEqual(evaluated.loc["mar", ["seen", "correct"]].tolist(), [False, False])

    def test_abstains_when_the_policy_leaves_no_labels(self):
        dataset = load(
            [
                transaction("jan", "2026-01-05", "PAK N SAVE", "Tagged", TAG, "Rule"),
                transaction("feb", "2026-02-03", "COUNTDOWN", "Tagged", TAG, "Manual"),
            ],
            rules=[["rule", "pak", "Tag", TAG]],
        )
        evaluated = harness.evaluate(dataset, baselines.most_common, LabelPolicy())
        self.assertIsNone(evaluated.loc[0, "predicted"])


class MetricTests(unittest.TestCase):
    def test_threshold_is_the_highest_reaching_the_coverage(self):
        r = results(["a", "a", "b", "b"], [0.9, 0.8, 0.8, 0.5], ["a", "b", "b", "b"])
        # 0.8 is shared by two rows, so it suggests for 75%, not 50%.
        self.assertEqual(harness.precision_at(r, 0.5), (0.8, 2 / 3))

    def test_abstentions_count_against_coverage_not_precision(self):
        nan = float("nan")
        r = results(["a", None, None, None], [0.9, nan, nan, nan], ["a"] * 4)
        self.assertEqual(harness.max_coverage(r), 0.25)
        self.assertEqual(harness.precision_at(r, 0.25), (0.9, 1.0))
        threshold, precision = harness.precision_at(r, 0.5)
        self.assertIsNone(threshold)
        self.assertTrue(pd.isna(precision))

    def test_class_recall_counts_only_correct_suggestions_at_the_threshold(self):
        r = results(["a", "a", "b", "a"], [0.9, 0.5, 0.9, 0.9], ["a", "a", "b", "b"])
        recall = harness.class_recall(r, 0.8)
        self.assertEqual(recall.to_dict(), {"a": 0.5, "b": 0.5})

    def test_confusion_counts_suggestions_by_true_and_suggested_class(self):
        r = results(["a", "c", "b", "a"], [0.9, 0.9, 0.9, 0.5], ["a", "a", "b", "b"])
        confusion = harness.confusion(r, 0.8)
        self.assertEqual(confusion.to_dict("list"), {"a": [1, 0, 0], "b": [0, 1, 0], "c": [1, 0, 0]})

    def test_compare_is_paired(self):
        r = results(["a", "b", "a", "b"], [0.9, 0.8, 0.7, 0.6], ["a", "a", "a", "b"])
        comparison = harness.compare(r, r.copy(), coverage=0.5)
        interval = [comparison[key] for key in ["difference", "low", "high"]]
        self.assertEqual(interval, [0, 0, 0])

    def test_compare_rejects_different_rows(self):
        r = results(["a"], [0.9], ["a"])
        with self.assertRaises(ValueError):
            harness.compare(r, r.assign(id=["other"]))


if __name__ == "__main__":
    unittest.main()
