import unittest

import numpy as np
import pandas as pd

import candidates
import harness


def frame(rows: list[tuple[str, str, str]]) -> pd.DataFrame:
    """Rows of description, amount, and label, with weight 1."""
    descriptions, amounts, labels = zip(*rows)
    return pd.DataFrame(
        {
            "id": [str(i) for i in range(len(rows))],
            "date": pd.Timestamp("2026-01-01"),
            "amount": [float(a) for a in amounts],
            "description": descriptions,
            "account_id": "account",
            "normalised": [harness.normalise(d) for d in descriptions],
            "label": labels,
            "weight": 1.0,
        }
    )


TRAINING = frame(
    [
        ("PAK N SAVE 4021", "-80.00", "groceries"),
        ("PAK N SAVE 1187", "-95.00", "groceries"),
        ("COUNTDOWN 22", "-40.00", "groceries"),
        ("LANDLORD RENT", "-600.00", "rent"),
        ("LANDLORD RENT", "-600.00", "rent"),
        ("ACME PAYROLL", "3000.00", "salary"),
    ]
)


class AmountFeatureTests(unittest.TestCase):
    def test_buckets_by_sign_and_base_2_logarithm(self):
        rows = pd.DataFrame({"amount": [-80.0, -95.0, 600.0, 0.0]})
        features = candidates.amount_features(rows)
        self.assertEqual(list(features["sign"]), ["-", "-", "+", "+"])
        self.assertEqual(list(features["bucket"]), ["-6", "-6", "+9", "+0"])


class LogisticRegressionTests(unittest.TestCase):
    candidate = staticmethod(
        candidates.logistic_regression(lambda: candidates.text_features(True, True, True))
    )

    def test_predicts_a_new_store_of_a_seen_merchant(self):
        rows = frame([("PAK N SAVE 9999", "-70.00", "")]).drop(columns=["label", "weight"])
        predicted = self.candidate(TRAINING, rows).iloc[0]
        self.assertEqual(predicted["predicted"], "groceries")
        self.assertGreater(predicted["confidence"], 1 / 3)

    def test_a_single_class_is_predicted_with_full_confidence(self):
        training = TRAINING[TRAINING["label"] == "rent"]
        predicted = self.candidate(training, TRAINING).iloc[0]
        self.assertEqual(predicted.tolist(), ["rent", 1.0])

    def test_row_weights_change_the_fit(self):
        rows = frame([("PAK N SAVE 9999", "-70.00", "")])
        heavier = TRAINING.assign(weight=np.where(TRAINING["label"] == "groceries", 5.0, 1.0))
        light = self.candidate(TRAINING, rows).iloc[0]["confidence"]
        heavy = self.candidate(heavier, rows).iloc[0]["confidence"]
        self.assertGreater(heavy, light)


class NearestNeighbourTests(unittest.TestCase):
    # Unit vectors by description: two near each other, one orthogonal.
    vectors = {
        "A": np.array([1.0, 0.0]),
        "A2": np.array([0.8, 0.6]),
        "B": np.array([0.0, 1.0]),
    }

    def embed(self, descriptions: pd.Series) -> np.ndarray:
        return np.stack([self.vectors[d] for d in descriptions])

    def test_votes_by_similarity_and_scales_confidence_by_it(self):
        training = frame([("A", "-1", "a"), ("B", "-1", "b")])
        rows = frame([("A2", "-1", "")])
        predicted = candidates.nearest_neighbours(self.embed, k=2)(training, rows).iloc[0]
        self.assertEqual(predicted["predicted"], "a")
        self.assertAlmostEqual(predicted["confidence"], 0.8 / 2)

    def test_label_weights_scale_votes(self):
        training = frame([("A", "-1", "a"), ("B", "-1", "b")]).assign(weight=[0.25, 1.0])
        rows = frame([("A2", "-1", "")])
        predicted = candidates.nearest_neighbours(self.embed, k=2)(training, rows).iloc[0]
        # a scores 0.25 * 0.8 = 0.2, b scores 1 * 0.6.
        self.assertEqual(predicted["predicted"], "b")
        self.assertAlmostEqual(predicted["confidence"], 0.6 / 1.25)


if __name__ == "__main__":
    unittest.main()
