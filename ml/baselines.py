"""The baselines of decision 8 in docs/smart-tagging.md. A candidate has to beat the lookup to
justify itself. Both are candidates as `harness.Candidate` defines them."""

import pandas as pd


def _shares(training: pd.DataFrame, by: list[str]) -> pd.DataFrame:
    """Each group's most common label by weight, and its share of the group's weight. Ties go
    to the first class by id, so the result does not depend on row order."""
    weights = training.groupby([*by, "label"])["weight"].sum().reset_index()
    weights["share"] = weights["weight"] / weights.groupby(by)["weight"].transform("sum")
    top = weights.sort_values([*by, "weight", "label"], ascending=[True] * len(by) + [False, True])
    return top.drop_duplicates(by)[[*by, "label", "share"]]


def most_common(training: pd.DataFrame, rows: pd.DataFrame) -> pd.DataFrame:
    """The most common class in the training set, for every row."""
    top = _shares(training.assign(all=0), ["all"]).iloc[0]
    return pd.DataFrame({"predicted": top["label"], "confidence": top["share"]}, index=rows.index)


def lookup(training: pd.DataFrame, rows: pd.DataFrame) -> pd.DataFrame:
    """The most common label for the row's exact normalised description in the training set.
    Abstains for unseen merchants."""
    top = _shares(training, ["normalised"]).set_index("normalised")
    found = rows["normalised"].map(top["label"])
    return pd.DataFrame(
        {
            "predicted": found.where(found.notna(), None),
            "confidence": rows["normalised"].map(top["share"]),
        },
        index=rows.index,
    )
