"""The evaluation harness for the smart tagging experiments, see decision 8 in
docs/smart-tagging.md.

A candidate is a function from a training set and the rows to predict for to a prediction per
row: a class, or none to abstain, and a confidence. The harness builds training sets under a
label policy, runs the candidate over a rolling-origin split, and scores only residual rows the
user labelled, so every candidate and policy is scored on the same rows.
"""

import re
from collections.abc import Callable
from dataclasses import dataclass
from pathlib import Path
from typing import Literal

import numpy as np
import pandas as pd

import rules

DATA_DIR = Path(__file__).parent / "data"

# The class of a transfer. Tags are their own ids.
TRANSFER = "transfer"

# Sources of labels the user chose. Only residual rows with one of these are scored.
SCORED_SOURCES = ("Manual", "Accepted")

# The columns a candidate sees for the rows it predicts for. Labels and sources are left out, so
# a candidate cannot read the answer.
FEATURES = ["id", "date", "amount", "description", "account_id", "normalised"]

Candidate = Callable[[pd.DataFrame, pd.DataFrame], pd.DataFrame]
"""Takes the training set (the feature columns plus `label` and `weight`) and the rows to
predict for (the feature columns), and returns a frame with the same index as the rows and the
columns `predicted` (a class, or None to abstain) and `confidence`."""


def normalise(description: str) -> str:
    """A description with case folded, digit runs replaced, and whitespace collapsed, so store
    and reference numbers do not split one merchant into many. Seen merchants, the lookup
    baseline, and the rule label cap compare descriptions by this."""
    return " ".join(re.sub(r"\d+", "#", rules.fold(description)).split())


@dataclass(frozen=True)
class Dataset:
    """One user's export. Transactions have the columns of `FEATURES` plus `label` (a class, or
    None for a dismissed or uncategorised row), `source`, and `residual` (no current rule
    matches the description)."""

    transactions: pd.DataFrame
    rules: list[rules.Rule]
    # Display names by class.
    class_names: dict[str, str]

    @property
    def scored(self) -> pd.Series:
        """The rows scored at some cutoff: residual, with a label the user chose."""
        t = self.transactions
        return t["residual"] & t["label"].notna() & t["source"].isin(SCORED_SOURCES)


def load(directory: Path = DATA_DIR) -> Dataset:
    """Read the CSV files `export.py` writes."""
    read = lambda name: pd.read_csv(directory / f"{name}.csv", dtype=str, keep_default_na=False)
    transactions, tags, rule_rows = read("transactions"), read("tags"), read("rules")

    found = [
        rules.Rule(row.id, row.pattern, row.tag_id if row.target == "Tag" else None)
        for row in rule_rows.itertuples()
    ]
    win = rules.winner(found)

    kind = transactions["kind"]
    label = pd.Series(None, index=transactions.index, dtype=object)
    label[kind == "Tagged"] = transactions["tag_id"]
    label[kind == "Transfer"] = TRANSFER
    transactions = transactions.assign(
        date=pd.to_datetime(transactions["date"]),
        amount=transactions["amount"].astype(float),
        normalised=transactions["description"].map(normalise),
        label=label,
        source=transactions["source"].replace("", None),
        residual=transactions["description"].map(lambda d: win(d) is None),
    )[[*FEATURES, "label", "source", "residual"]]

    class_names = dict(zip(tags["id"], tags["name"])) | {TRANSFER: "Transfer"}
    return Dataset(transactions, found, class_names)


@dataclass(frozen=True)
class LabelPolicy:
    """Which categorisations are labels, and at what weight. See decision 4 in
    docs/smart-tagging.md. `Manual` labels always have weight 1."""

    accepted_weight: float = 0.5
    detected: bool = True
    rule_labels: Literal["none", "capped", "uncapped"] = "none"
    # The total weight of each normalised description's rule labels when capped.
    rule_cap: float = 1.0

    @property
    def name(self) -> str:
        rule = f"capped {self.rule_cap:g}" if self.rule_labels == "capped" else self.rule_labels
        detected = "" if self.detected else ", no detected"
        return f"rule {rule}, accepted {self.accepted_weight:g}{detected}"


def training_set(transactions: pd.DataFrame, policy: LabelPolicy) -> pd.DataFrame:
    """The labelled rows of `transactions` the policy keeps, with a `weight` column."""
    labelled = transactions[transactions["label"].notna()]
    source = labelled["source"]
    weight = pd.Series(0.0, index=labelled.index)
    weight[source == "Manual"] = 1.0
    weight[source == "Accepted"] = policy.accepted_weight
    if policy.detected:
        weight[source == "Detected"] = 1.0
    is_rule = source == "Rule"
    if policy.rule_labels == "uncapped":
        weight[is_rule] = 1.0
    elif policy.rule_labels == "capped":
        count = labelled[is_rule].groupby("normalised")["id"].transform("size")
        weight[is_rule] = np.minimum(1.0, policy.rule_cap / count)
    training = labelled.assign(weight=weight)
    return training[training["weight"] > 0][[*FEATURES, "label", "weight"]]


def cutoffs(dataset: Dataset) -> list[pd.Timestamp]:
    """The first day of each month after the first labelled month, through the last month with
    a transaction. Each is trained on everything before it and tested on the month it starts."""
    t = dataset.transactions
    first = t.loc[t["label"].notna(), "date"].min().to_period("M") + 1
    last = t["date"].max().to_period("M")
    return [period.to_timestamp() for period in pd.period_range(first, last, freq="M")]


def evaluate(dataset: Dataset, candidate: Candidate, policy: LabelPolicy) -> pd.DataFrame:
    """Run the candidate at every cutoff. One row per scored transaction, with its `cutoff`,
    true `label`, `predicted` class, `confidence`, whether it is `correct`, and whether its
    merchant was `seen` in the training set."""
    t = dataset.transactions
    scored = dataset.scored
    results = []
    for cutoff in cutoffs(dataset):
        test = t[scored & (t["date"] >= cutoff) & (t["date"] < cutoff + pd.DateOffset(months=1))]
        if test.empty:
            continue
        training = training_set(t[t["date"] < cutoff], policy)
        if training.empty:
            predictions = pd.DataFrame({"predicted": None, "confidence": np.nan}, index=test.index)
        else:
            predictions = candidate(training, test[FEATURES].copy())
        results.append(
            pd.DataFrame(
                {
                    "id": test["id"],
                    "cutoff": cutoff,
                    "label": test["label"],
                    "predicted": predictions["predicted"].astype(object),
                    "confidence": predictions["confidence"].astype(float),
                    "seen": test["normalised"].isin(training["normalised"]),
                }
            )
        )
    results = pd.concat(results).sort_values("id", ignore_index=True)
    results["predicted"] = results["predicted"].where(results["predicted"].notna(), None)
    results["correct"] = results["predicted"] == results["label"]
    return results


# Metrics


def accuracy(results: pd.DataFrame) -> pd.DataFrame:
    """Top-1 accuracy for all, seen, and unseen merchants. Abstaining counts as wrong."""
    groups = {
        "all": results,
        "seen": results[results["seen"]],
        "unseen": results[~results["seen"]],
    }
    return pd.DataFrame(
        {
            "rows": {name: len(group) for name, group in groups.items()},
            "accuracy": {name: group["correct"].mean() for name, group in groups.items()},
        }
    )


def precision_coverage(results: pd.DataFrame) -> pd.DataFrame:
    """Precision against coverage at every distinct confidence used as the threshold, highest
    first. A row is suggested when it has a prediction with at least the threshold's
    confidence."""
    predicted = results[results["predicted"].notna()]
    by_confidence = (
        predicted.groupby("confidence")["correct"]
        .agg(["size", "sum"])
        .sort_index(ascending=False)
    )
    suggested = by_confidence["size"].cumsum()
    return pd.DataFrame(
        {
            "threshold": by_confidence.index,
            "coverage": (suggested / len(results)).to_numpy(),
            "precision": (by_confidence["sum"].cumsum() / suggested).to_numpy(),
        }
    )


def threshold_for(results: pd.DataFrame, coverage: float) -> float | None:
    """The highest threshold that suggests for at least `coverage` of the rows, or None when no
    threshold does."""
    curve = precision_coverage(results)
    reached = curve[curve["coverage"] >= coverage - 1e-12]
    return None if reached.empty else float(reached["threshold"].iloc[0])


def suggested(results: pd.DataFrame, threshold: float) -> pd.Series:
    return results["predicted"].notna() & (results["confidence"] >= threshold)


def max_coverage(results: pd.DataFrame) -> float:
    """The share of rows with any prediction: the coverage at the lowest threshold."""
    return results["predicted"].notna().mean()


def precision_at(results: pd.DataFrame, coverage: float) -> tuple[float | None, float]:
    """The threshold for `coverage` and the precision at it: correct suggestions over
    suggestions made. NaN when the coverage cannot be reached."""
    threshold = threshold_for(results, coverage)
    if threshold is None:
        return None, np.nan
    mask = suggested(results, threshold)
    return threshold, results.loc[mask, "correct"].mean()


def compare(
    a: pd.DataFrame,
    b: pd.DataFrame,
    coverage: float = 0.5,
    resamples: int = 1000,
    seed: int = 0,
) -> dict[str, float]:
    """The difference in precision (a minus b), each at its own threshold for `coverage`, with
    a 95% interval from a paired bootstrap over the scored rows. Both must be results for the
    same rows. The thresholds stay fixed across resamples."""
    if not a["id"].equals(b["id"]):
        raise ValueError("Results are for different rows")
    masks, correct = [], []
    for results in (a, b):
        threshold = threshold_for(results, coverage)
        if threshold is None:
            return {"a": np.nan, "b": np.nan, "difference": np.nan, "low": np.nan, "high": np.nan}
        masks.append(suggested(results, threshold).to_numpy())
        correct.append(results["correct"].to_numpy())

    def precision(index):
        return [
            (mask[index] & right[index]).sum(axis=-1) / mask[index].sum(axis=-1)
            for mask, right in zip(masks, correct)
        ]

    index = np.random.default_rng(seed).integers(0, len(a), size=(resamples, len(a)))
    with np.errstate(invalid="ignore", divide="ignore"):
        pa, pb = precision(np.arange(len(a)))
        ra, rb = precision(index)
    low, high = np.nanpercentile(ra - rb, [2.5, 97.5])
    return {"a": pa, "b": pb, "difference": pa - pb, "low": low, "high": high}


# Diagnostics


def class_distribution(
    results: pd.DataFrame, class_names: dict[str, str], threshold: float | None
) -> pd.DataFrame:
    """For each class, how many scored rows have it as their true label, how many the
    candidate predicts it for, and how many it suggests it for at the threshold. Classes
    suggested far more often than they occur show distribution shift."""
    true = results["label"].value_counts()
    predicted = results["predicted"].value_counts()
    at_threshold = (
        results.loc[suggested(results, threshold), "predicted"].value_counts()
        if threshold is not None
        else pd.Series(dtype=int)
    )
    table = pd.DataFrame({"true": true, "predicted": predicted, "suggested": at_threshold})
    table = table.fillna(0).astype(int).sort_values("true", ascending=False)
    table.index = table.index.map(lambda c: class_names.get(c, c))
    return table


def class_precision(results: pd.DataFrame, cls: str, threshold: float | None) -> dict[str, float]:
    """How the candidate does on residual rows for one class at the threshold: how often it
    suggests the class, how often that is right, and how many of the class's rows it finds. For
    a rule known to over-match, run on its target with and without rule labels: if its tags
    teach spurious tokens, the model suggests the target for residual rows that are not it."""
    mask = suggested(results, threshold) if threshold is not None else results["predicted"].notna()
    suggestions = mask & (results["predicted"] == cls)
    hits = suggestions & results["correct"]
    true = (results["label"] == cls).sum()
    return {
        "true": int(true),
        "suggested": int(suggestions.sum()),
        "precision": hits.sum() / suggestions.sum() if suggestions.any() else np.nan,
        "recall": hits.sum() / true if true else np.nan,
    }
