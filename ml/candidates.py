"""The candidates of decision 8 in docs/smart-tagging.md: features and logistic regression,
sentence embeddings with logistic regression or nearest neighbours, and both feature sets in one
linear model. Each is a candidate as `harness.Candidate` defines them.
"""

import time
from collections.abc import Callable
from pathlib import Path
from typing import Literal

import numpy as np
import pandas as pd
from sklearn.compose import ColumnTransformer
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.linear_model import LogisticRegression
from sklearn.pipeline import make_pipeline
from sklearn.preprocessing import FunctionTransformer, OneHotEncoder

import harness

# Inverse L2 strength, scikit-learn's default. The server's fit has to use the same.
C = 1.0

# Neighbours a nearest-neighbour candidate votes over.
K = 5

# The largest factor a capped balance scales a class's weight by.
BALANCE_CAP = 5.0

EMBEDDING_MODELS = {
    "minilm": "sentence-transformers/all-MiniLM-L6-v2",
    "bge-small": "BAAI/bge-small-en-v1.5",
}


def amount_features(rows: pd.DataFrame) -> pd.DataFrame:
    """The amount's sign, and the sign with a base 2 logarithmic bucket of its size, as
    categories. Sign separates income from expense tags; the bucket separates tags that share a
    payee."""
    amount = rows["amount"].astype(float)
    sign = pd.Series(np.where(amount < 0, "-", "+"), index=rows.index)
    bucket = np.floor(np.log2(amount.abs() + 1)).astype(int).astype(str)
    return pd.DataFrame({"sign": sign, "bucket": sign + bucket})


class Embedder:
    """Sentence embeddings of descriptions from one pretrained model, unit length. Each
    description is embedded once and cached in the data directory, which is gitignored because
    the cache is derived from the user's descriptions. The model loads only on a cache miss."""

    def __init__(self, model: str, cache: Path):
        self.model = model
        self.path = cache / f"embeddings-{model.replace('/', '--')}.npz"
        self.vectors: dict[str, np.ndarray] = {}
        # Seconds per description, measured when the cache was filled.
        self.seconds = float("nan")
        if self.path.exists():
            saved = np.load(self.path)
            self.vectors = dict(zip(saved["descriptions"], saved["vectors"]))
            self.seconds = float(saved["seconds"])

    def fill(self, descriptions: pd.Series) -> None:
        """Embed every description not already cached, and save the cache."""
        missing = sorted(set(descriptions) - self.vectors.keys())
        if not missing:
            return
        from sentence_transformers import SentenceTransformer

        encoder = SentenceTransformer(self.model, device="cpu")
        start = time.perf_counter()
        vectors = encoder.encode(missing, batch_size=64, normalize_embeddings=True)
        self.seconds = (time.perf_counter() - start) / len(missing)
        self.vectors |= dict(zip(missing, vectors))
        self.path.parent.mkdir(exist_ok=True)
        descriptions = list(self.vectors)
        np.savez(
            self.path,
            descriptions=np.array(descriptions),
            vectors=np.stack([self.vectors[d] for d in descriptions]),
            seconds=self.seconds,
        )

    def __call__(self, descriptions: pd.Series) -> np.ndarray:
        return np.stack([self.vectors[d] for d in descriptions])


Features = dict[str, Callable[[], object]]
"""Transformers by name, as ColumnTransformer takes them, each built fresh for every fit so the
vocabulary and IDF weights come from that fit's training set."""


def text_features(words: bool, amount: bool, account: bool) -> list[tuple]:
    """Character n-grams of the normalised description, and optionally its word tokens, the
    amount, and the account. The normalised description has case folded and digit runs
    replaced, so store and reference numbers do not split one merchant into many."""
    features = [
        (
            "chars",
            TfidfVectorizer(analyzer="char_wb", ngram_range=(3, 5), lowercase=False),
            "normalised",
        )
    ]
    if words:
        features.append(
            ("words", TfidfVectorizer(token_pattern=r"\S+", lowercase=False), "normalised")
        )
    if amount:
        features.append(
            (
                "amount",
                make_pipeline(
                    FunctionTransformer(amount_features),
                    OneHotEncoder(handle_unknown="ignore"),
                ),
                ["amount"],
            )
        )
    if account:
        features.append(("account", OneHotEncoder(handle_unknown="ignore"), ["account_id"]))
    return features


def embedding_feature(embedder: Embedder) -> tuple:
    return ("embedding", FunctionTransformer(embedder), "description")


def predict_single_class(training: pd.DataFrame, rows: pd.DataFrame) -> pd.DataFrame | None:
    """A model cannot be fitted to one class; it predicts that class with full confidence."""
    classes = training["label"].unique()
    if len(classes) > 1:
        return None
    return pd.DataFrame({"predicted": classes[0], "confidence": 1.0}, index=rows.index)


Balance = Literal["full", "capped", "sqrt"]
"""How far a fit evens out its classes' weights, as `balance` describes."""


def balance(training: pd.DataFrame, how: Balance = "full") -> pd.Series:
    """Row weights scaled by a factor per class, so small classes count for more in the fit.
    The full factor gives every class the mean class total, as scikit-learn's balanced class
    weights but from label weights rather than row counts. A class with one or two labels then
    carries a large share of the fit, so the capped factor is at most `BALANCE_CAP` and the
    sqrt factor is the full factor's square root. Rows within a class keep their relative
    weights, and the total weight is unchanged, so C means the same."""
    totals = training.groupby("label")["weight"].transform("sum")
    factor = training["weight"].sum() / (training["label"].nunique() * totals)
    if how == "capped":
        factor = factor.clip(upper=BALANCE_CAP)
    elif how == "sqrt":
        factor = np.sqrt(factor)
    weight = training["weight"] * factor
    return weight * training["weight"].sum() / weight.sum()


def logistic_regression(
    features: Callable[[], list[tuple]], balanced: Balance | None = None
) -> harness.Candidate:
    """Weighted multinomial logistic regression with L2 regularisation, fitted with L-BFGS, over
    the given features, optionally with balanced class weights. Confidence is the top class's
    probability."""

    def candidate(training: pd.DataFrame, rows: pd.DataFrame) -> pd.DataFrame:
        single = predict_single_class(training, rows)
        if single is not None:
            return single
        model = make_pipeline(
            ColumnTransformer(features()),
            LogisticRegression(C=C, solver="lbfgs", max_iter=2000),
        )
        weight = training["weight"] if balanced is None else balance(training, balanced)
        model.fit(training, training["label"], logisticregression__sample_weight=weight)
        probabilities = model.predict_proba(rows)
        classes = model.classes_
        return pd.DataFrame(
            {
                "predicted": classes[probabilities.argmax(axis=1)],
                "confidence": probabilities.max(axis=1),
            },
            index=rows.index,
        )

    return candidate


def nearest_neighbours(embedder: Embedder, k: int = K) -> harness.Candidate:
    """A vote of the k most similar training descriptions by cosine similarity, each weighted by
    its similarity and label weight. Confidence is the top class's share of the neighbours'
    total label weight, scaled by similarity, so it falls when even the nearest neighbours are
    far away."""

    def candidate(training: pd.DataFrame, rows: pd.DataFrame) -> pd.DataFrame:
        similarity = embedder(rows["description"]) @ embedder(training["description"]).T
        nearest = np.argsort(-similarity, axis=1, kind="stable")[:, :k]
        labels = training["label"].to_numpy()
        weights = training["weight"].to_numpy()
        predicted, confidence = [], []
        for row, neighbours in enumerate(nearest):
            votes: dict[str, float] = {}
            for n in neighbours:
                votes[labels[n]] = votes.get(labels[n], 0.0) + weights[n] * max(similarity[row, n], 0)
            # Ties go to the first class by id, so the result does not depend on row order.
            top = min(votes, key=lambda cls: (-votes[cls], cls))
            predicted.append(top)
            confidence.append(votes[top] / weights[neighbours].sum())
        return pd.DataFrame({"predicted": predicted, "confidence": confidence}, index=rows.index)

    return candidate


def embedders(data: Path, descriptions: pd.Series) -> dict[str, Embedder]:
    """An embedder per model, with every description embedded."""
    found = {name: Embedder(model, data) for name, model in EMBEDDING_MODELS.items()}
    for embedder in found.values():
        embedder.fill(descriptions)
    return found


def candidates(embedders: dict[str, Embedder]) -> dict[str, harness.Candidate]:
    """Every candidate, simplest first, the order the choice in decision 8 breaks ties by: the
    feature subsets from fewest features, then embeddings alone, then both concatenated. Each
    logistic regression is followed by its balanced variants, from full to softest."""
    found: dict[str, harness.Candidate] = {}

    def regression(name: str, features: Callable[[], list[tuple]]) -> None:
        found[name] = logistic_regression(features)
        found[f"{name}, balanced"] = logistic_regression(features, "full")
        found[f"{name}, balanced capped"] = logistic_regression(features, "capped")
        found[f"{name}, balanced sqrt"] = logistic_regression(features, "sqrt")

    regression("chars", lambda: text_features(False, False, False))
    regression("chars, words", lambda: text_features(True, False, False))
    regression("chars, words, amount", lambda: text_features(True, True, False))
    regression("features", lambda: text_features(True, True, True))
    for name, embedder in embedders.items():
        regression(f"{name} lr", lambda e=embedder: [embedding_feature(e)])
        found[f"{name} knn"] = nearest_neighbours(embedder)
    for name, embedder in embedders.items():
        regression(
            f"features, {name}",
            lambda e=embedder: [*text_features(True, True, True), embedding_feature(e)],
        )
    return found
