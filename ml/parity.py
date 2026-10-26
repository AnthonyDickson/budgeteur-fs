"""Write the parity fixtures of decision 10 in docs/smart-tagging.md: the anonymised import
fixtures, labelled, with the features and predicted probabilities of the shipped model fitted on
them in scikit-learn. The server's parity tests fit the F# model on the same transactions and
compare. CI does not run Python, so the outputs are committed; rerun this when the shipped model
or the import fixtures change.

The fit runs to a tight tolerance and the gradient of its objective is checked at the result, so
the fixtures hold the unique optimum rather than wherever the optimiser stopped. It uses Newton
conjugate gradient rather than the experiments' L-BFGS: the optimum is the same, but
scikit-learn's L-BFGS also stops on a relative decrease of the objective, which it does not
expose, and halts with a gradient around 1e-6. Coefficients are not written: unpenalised
intercepts are only unique up to a constant, while probabilities are.

Usage: python parity.py
"""

from pathlib import Path

import numpy as np
import pandas as pd
from scipy.special import softmax
from sklearn.compose import ColumnTransformer
from sklearn.linear_model import LogisticRegression

import candidates
import harness

ROOT = Path(__file__).parent.parent
IMPORT_FIXTURES = ROOT / "server/tests/Budgeteur.Tests/Import/Fixtures"
OUTPUT = ROOT / "server/tests/Budgeteur.Tests/Domain/Fixtures/SmartTagging"

# Label weights by source, as decision 4 settles them.
WEIGHTS = {"Manual": 1.0, "Accepted": 0.5, "Detected": 1.0}

# Labels by a pattern in the description, first match wins, as (pattern, class, source). They
# give every source, classes from one label to dozens, and both signs. The rows none matches
# are only predicted for, and with the card statement, whose account is not in the training
# set, exercise terms and categories the fit has not seen.
LABELS = [
    ("FRESH MART", "groceries", "Manual"),
    ("HARBOUR CAFE", "eating-out", "Manual"),
    ("THE LOCAL", "eating-out", "Accepted"),
    ("Pizza", "eating-out", "Manual"),
    ("RIDESHARE *EATS", "eating-out", "Manual"),
    ("RIDESHARE *TRIP", "transport", "Accepted"),
    ("CITY TRANSPORT", "transport", "Manual"),
    ("CITY APPLIANCES", "household", "Accepted"),
    ("Rent", "rent", "Manual"),
    ("Electricity", "utilities", "Manual"),
    ("MOBILENET", "phone", "Manual"),
    ("CLOUDSTOR", "subscriptions", "Manual"),
    ("NETWORKHUB", "subscriptions", "Manual"),
    ("WEBFAST", "subscriptions", "Accepted"),
    ("GAMESTORE", "games", "Manual"),
    ("DONATION", "donations", "Manual"),
    ("CIVIC SOCIETY", "donations", "Accepted"),
    ("Salary", "salary", "Manual"),
    ("INTEREST CREDIT", "interest", "Manual"),
    ("WITHHOLDING TAX", "tax", "Manual"),
    ("TRANSFER", harness.TRANSFER, "Detected"),
    ("Credit Card", harness.TRANSFER, "Manual"),
]

# Convergence: the solver stops at a gradient below `TOLERANCE`, scaled as scikit-learn scales
# its objective, and the largest gradient component of the unscaled objective at the result has
# to be below `MAX_GRADIENT`.
TOLERANCE = 1e-12
MAX_GRADIENT = 1e-8


def kiwibank(name: str) -> pd.DataFrame:
    rows = pd.read_csv(IMPORT_FIXTURES / f"{name}.csv", dtype=str, keep_default_na=False)
    return pd.DataFrame({"description": rows["Description"], "amount": rows["Amount"]})


def asb_card(name: str) -> pd.DataFrame:
    """The card statement lists purchases as positive, so amounts are negated as import does."""
    rows = pd.read_csv(IMPORT_FIXTURES / f"{name}.csv", dtype=str, skiprows=4)
    amount = rows["Amount"].map(lambda a: a[1:] if a.startswith("-") else f"-{a}")
    return pd.DataFrame({"description": rows["Description"], "amount": amount})


def transactions() -> pd.DataFrame:
    """Every fixture row, with the account named after its file, and a label and weight where
    `LABELS` gives one."""
    statements = [
        ("KiwibankChequing", kiwibank),
        ("KiwibankSavings", kiwibank),
        ("AsbCard", asb_card),
    ]
    frames = []
    for account, read in statements:
        rows = read(account)
        frames.append(
            rows.assign(
                id=[f"{account}-{i + 1}" for i in range(len(rows))],
                account_id=account,
            )
        )
    rows = pd.concat(frames, ignore_index=True)

    def label(description: str) -> tuple[str, float]:
        return next(
            ((cls, WEIGHTS[source]) for pattern, cls, source in LABELS if pattern in description),
            ("", 0.0),
        )

    labels = rows["description"].map(label)
    return rows.assign(
        label=labels.map(lambda pair: pair[0]),
        weight=labels.map(lambda pair: pair[1]),
    )[["id", "account_id", "amount", "description", "label", "weight"]]


def features(columns: ColumnTransformer, rows: pd.DataFrame) -> pd.DataFrame:
    """Each row's non-zero features as (id, block, term, value). Terms are named without the
    column order, so the server can compare them however it orders its own."""
    matrix = columns.transform(rows).tocoo()
    terms = []
    for block, transformer, _ in columns.transformers_:
        if block == "remainder":
            continue
        if block == "amount":
            names = transformer[-1].get_feature_names_out(["sign", "bucket"])
        elif block == "account":
            names = transformer.categories_[0]
        else:
            names = transformer.get_feature_names_out()
        terms.extend((block, name) for name in names)
    found = pd.DataFrame(
        {
            "id": rows["id"].to_numpy()[matrix.row],
            "block": [terms[c][0] for c in matrix.col],
            "term": [terms[c][1] for c in matrix.col],
            "value": matrix.data,
        }
    )
    return found.sort_values(["id", "block", "term"], kind="stable")


def max_gradient(model: LogisticRegression, x, y: pd.Series, weight: pd.Series) -> float:
    """The largest gradient component of the summed, weighted cross entropy plus the L2 penalty
    over the coefficients, which scikit-learn minimises up to a constant factor."""
    probabilities = softmax(x @ model.coef_.T + model.intercept_, axis=1)
    onehot = y.to_numpy()[:, None] == model.classes_
    residual = (probabilities - onehot) * weight.to_numpy()[:, None]
    coef = x.T @ residual + model.coef_.T / candidates.C
    intercept = residual.sum(axis=0)
    return float(max(np.abs(coef).max(), np.abs(intercept).max()))


def main() -> None:
    rows = transactions()
    rows = rows.assign(
        amount=rows["amount"].astype(float),
        normalised=rows["description"].map(harness.normalise),
    )
    training = rows[rows["label"] != ""]
    weight = candidates.balance(training, "sqrt")

    columns = ColumnTransformer(candidates.text_features(True, True, True))
    x = columns.fit_transform(training)
    model = LogisticRegression(C=candidates.C, solver="newton-cg", tol=TOLERANCE, max_iter=100_000)
    model.fit(x, training["label"], sample_weight=weight)
    gradient = max_gradient(model, x, training["label"], weight)
    if gradient > MAX_GRADIENT:
        raise SystemExit(f"The fit did not converge: gradient {gradient:.3g} > {MAX_GRADIENT:g}")

    probabilities = pd.DataFrame(
        model.predict_proba(columns.transform(rows)), columns=model.classes_
    )
    probabilities.insert(0, "id", rows["id"])
    # Rows that repeat an account and description differ only in the amount's categories, so
    # features are written for the first of each, which keeps the fixture small.
    distinct = rows.drop_duplicates(["account_id", "description"])
    outputs = {
        "transactions": rows.drop(columns="normalised").assign(
            amount=rows["amount"].map("{:.2f}".format)
        ),
        "features": features(columns, distinct),
        "probabilities": probabilities,
    }

    OUTPUT.mkdir(parents=True, exist_ok=True)
    for name, frame in outputs.items():
        frame.to_csv(OUTPUT / f"{name}.csv", index=False)
    print(
        f"{len(training)} labels, {len(model.classes_)} classes, {x.shape[1]} features, "
        f"{len(rows) - len(training)} unlabelled rows; {model.n_iter_[0]} iterations, "
        f"largest gradient {gradient:.3g}. Written to {OUTPUT.relative_to(ROOT)}."
    )


if __name__ == "__main__":
    main()
