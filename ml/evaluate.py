"""Evaluate every candidate under every label policy on the exported data, choose a winner as
decision 8 in docs/smart-tagging.md fixes, and print a report.

Usage: python evaluate.py [--data DIR] [--over-matching PATTERN ...]
"""

import argparse
from pathlib import Path

import pandas as pd

import baselines
import candidates
import harness
import rules
from harness import LabelPolicy

# The rule label variants of decision 4, simplest first, the order the choice breaks ties by.
POLICIES = [
    LabelPolicy(rule_labels="none"),
    LabelPolicy(rule_labels="uncapped"),
    LabelPolicy(rule_labels="capped"),
]

# The `Accepted` weights and `Detected` choices tried for the winner, under its rule variant.
ACCEPTED_WEIGHTS = [0.25, 0.5, 1.0]

# The coverage every option is compared at, fixed before the first run.
COVERAGE = 0.5

LOOKUP = "lookup"

# Results by candidate name and policy name.
Options = dict[tuple[str, str], pd.DataFrame]


def section(title: str) -> None:
    print(f"\n## {title}\n")


def table(frame: pd.DataFrame) -> str:
    return frame.to_string(float_format="{:.3f}".format, na_rep="-")


def summarise_data(dataset: harness.Dataset) -> None:
    t = dataset.transactions
    scored = dataset.scored
    section("Data")
    print(f"{len(t)} transactions, {t['residual'].sum()} residual, {scored.sum()} scored")
    print(f"{len(dataset.rules)} rules, {len(dataset.class_names)} classes\n")
    by_source = t.groupby(["source", "residual"], dropna=False).size()
    print(by_source.unstack(fill_value=0).to_string())
    print()
    per_cutoff = {
        cutoff.strftime("%Y-%m"): {
            "labels before": (t["label"].notna() & (t["date"] < cutoff)).sum(),
            "scored in month": (
                scored & (t["date"] >= cutoff) & (t["date"] < cutoff + pd.DateOffset(months=1))
            ).sum(),
        }
        for cutoff in harness.cutoffs(dataset)
    }
    print(pd.DataFrame.from_dict(per_cutoff, orient="index").to_string())


def summarise_embeddings(embedders: dict[str, candidates.Embedder]) -> None:
    section("Embeddings")
    for name, embedder in embedders.items():
        print(
            f"{name} ({embedder.model}): {len(embedder.vectors)} descriptions, "
            f"{embedder.seconds * 1000:.2f} ms each when cached"
        )


def summarise_options(options: Options) -> None:
    rows = {}
    for key, results in options.items():
        accuracy = harness.accuracy(results)["accuracy"]
        threshold, precision = harness.precision_at(results, COVERAGE)
        rows[key] = {
            "accuracy": accuracy["all"],
            "seen": accuracy["seen"],
            "unseen": accuracy["unseen"],
            "max coverage": harness.max_coverage(results),
            f"threshold @{COVERAGE:.0%}": threshold,
            f"precision @{COVERAGE:.0%}": precision,
        }
    counts = harness.accuracy(next(iter(options.values())))["rows"]
    section("Top-1 accuracy, and precision at the comparison's coverage")
    print(
        f"{counts['all']} scored rows: {counts['seen']} seen and {counts['unseen']} unseen "
        "without rule labels\n"
    )
    print(table(pd.DataFrame.from_dict(rows, orient="index")))

    section("Precision against coverage")
    levels = [level / 10 for level in range(1, 11)]
    curve = {
        key: {f"{level:.0%}": harness.precision_at(results, level)[1] for level in levels}
        for key, results in options.items()
    }
    print(table(pd.DataFrame.from_dict(curve, orient="index")))


def format_comparison(c: dict[str, float]) -> str:
    return (
        f"{c['a']:.3f} vs {c['b']:.3f}: "
        f"{c['difference']:+.3f} [{c['low']:+.3f}, {c['high']:+.3f}]"
    )


def within_noise(c: dict[str, float]) -> bool:
    return c["low"] <= 0 <= c["high"]


def choose(options: Options, order: list[tuple[str, str]]) -> tuple[str, str] | None:
    """The winner of decision 8 among the candidates: the best precision at the comparison's
    coverage, unless a simpler option is within noise of it, in which case the simplest such
    option. `order` lists the candidates' options simplest first; the baselines are not among
    them. Prints each option against the best."""
    precision = {key: harness.precision_at(options[key], COVERAGE)[1] for key in order}
    reachable = {key: value for key, value in precision.items() if not pd.isna(value)}
    if not reachable:
        section(f"No candidate reaches {COVERAGE:.0%} coverage")
        return None
    best = max(reachable, key=reachable.get)
    section(f"Against the best at {COVERAGE:.0%} coverage, {best}, with 95% interval")
    tied = [best]
    for key in reachable:
        if key != best:
            comparison = harness.compare(options[key], options[best], COVERAGE)
            print(f"{key}: {format_comparison(comparison)}")
            if within_noise(comparison):
                tied.append(key)
    winner = min(tied, key=order.index)
    print(f"\nWinner, the simplest within noise of the best: {winner}")
    return winner


def check_lookup(options: Options, winner: tuple[str, str]) -> None:
    """The winner has to beat the lookup on precision at the lookup's own coverage, by more
    than noise, or the lookup ships instead."""
    section("Against the lookup at its own coverage, under the same policy")
    for (candidate, policy), results in options.items():
        lookup = options.get((LOOKUP, policy))
        if candidate == LOOKUP or lookup is None:
            continue
        coverage = harness.max_coverage(lookup)
        comparison = harness.compare(results, lookup, coverage)
        mark = " (winner)" if (candidate, policy) == winner else ""
        print(f"{(candidate, policy)}{mark} at {coverage:.0%}: {format_comparison(comparison)}")
    lookup = options[(LOOKUP, winner[1])]
    comparison = harness.compare(options[winner], lookup, harness.max_coverage(lookup))
    if comparison["low"] > 0:
        print(f"\nThe winner beats the lookup by more than noise, so {winner} ships")
    else:
        print("\nThe winner does not beat the lookup by more than noise, so the lookup ships")


def sweep_weights(
    dataset: harness.Dataset,
    candidate: harness.Candidate,
    winner: tuple[str, str],
    winning: LabelPolicy,
    options: Options,
) -> None:
    """The winner under each `Accepted` weight, with `Detected` transfers in and out, against
    the winner's own policy."""
    section(f"Label weights for {winner[0]}, against {winner[1]}")
    for detected in (True, False):
        for weight in ACCEPTED_WEIGHTS:
            policy = LabelPolicy(
                accepted_weight=weight,
                detected=detected,
                rule_labels=winning.rule_labels,
                rule_cap=winning.rule_cap,
            )
            if policy == winning:
                continue
            results = harness.evaluate(dataset, candidate, policy)
            comparison = harness.compare(results, options[winner], COVERAGE)
            print(f"{policy.name}: {format_comparison(comparison)}")


def summarise_threshold(results: pd.DataFrame, winner: tuple[str, str]) -> None:
    """Coverage and precision at fixed thresholds, for choosing the shipped threshold."""
    section(f"Threshold for {winner}")
    rows = {}
    for level in range(1, 10):
        threshold = level / 10
        mask = harness.suggested(results, threshold)
        rows[f"{threshold:.1f}"] = {
            "coverage": mask.mean(),
            "precision": results.loc[mask, "correct"].mean(),
            "seen precision": results.loc[mask & results["seen"], "correct"].mean(),
            "unseen precision": results.loc[mask & ~results["seen"], "correct"].mean(),
        }
    print(table(pd.DataFrame.from_dict(rows, orient="index")))


def by_bucket(results: pd.DataFrame, mask: pd.Series, column: str, bins: list[float]) -> str:
    """Rows, suggestions, and precision of the suggestions, by bucket of `column`."""
    bucket = pd.cut(results[column], bins=bins, right=False)
    frame = pd.DataFrame(
        {
            "rows": results.groupby(bucket, observed=False).size(),
            "suggested": mask.groupby(bucket, observed=False).sum(),
            "precision": results.loc[mask, "correct"].groupby(bucket[mask], observed=False).mean(),
        }
    )
    return table(frame)


def summarise_minimums(results: pd.DataFrame, winner: tuple[str, str]) -> None:
    """Precision at the comparison's threshold by how many labels the fit had, for the overall
    minimum, and by how many the predicted class had, for the per-class minimum."""
    threshold = harness.threshold_for(results, COVERAGE)
    if threshold is None:
        return
    mask = harness.suggested(results, threshold)
    inf = float("inf")
    section(f"Label minimums for {winner} at threshold {threshold:.3f}")
    print("By labels in the training set\n")
    print(by_bucket(results, mask, "labels", [0, 25, 50, 100, 200, 400, 800, inf]))
    print("\nBy labels of the predicted class\n")
    print(by_bucket(results, mask, "class labels", [0, 1, 2, 3, 5, 10, 20, 50, inf]))


def diagnose(
    dataset: harness.Dataset, options: Options, candidate: str, over_matching: list[str]
) -> None:
    """Distribution shift and over-matching rules for one candidate under each rule variant."""
    shown = {key: results for key, results in options.items() if key[0] == candidate}
    thresholds = {key: harness.threshold_for(results, COVERAGE) for key, results in shown.items()}
    for key, results in shown.items():
        section(f"Class distribution on scored rows at {COVERAGE:.0%} coverage: {key}")
        print(harness.class_distribution(results, dataset.class_names, thresholds[key]).to_string())

    for pattern in over_matching:
        rule = next(
            (r for r in dataset.rules if rules.fold(r.pattern) == rules.fold(pattern.strip())),
            None,
        )
        if rule is None:
            print(f"\nNo rule has the pattern {pattern!r}")
            continue
        cls = rule.tag_id or harness.TRANSFER
        name = dataset.class_names.get(cls, cls)
        section(f"Scored rows for {name}, the target of {rule.pattern!r}")
        precision = {
            key: harness.class_precision(results, cls, thresholds[key])
            for key, results in shown.items()
        }
        print(table(pd.DataFrame.from_dict(precision, orient="index")))


def main() -> None:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("--data", type=Path, default=harness.DATA_DIR)
    parser.add_argument(
        "--over-matching",
        action="append",
        default=[],
        metavar="PATTERN",
        help="a rule pattern known to over-match, for the diagnostics; repeatable",
    )
    args = parser.parse_args()

    dataset = harness.load(args.data)
    summarise_data(dataset)
    embedders = candidates.embedders(args.data, dataset.transactions["description"])
    summarise_embeddings(embedders)

    found = {
        "most common": baselines.most_common,
        LOOKUP: baselines.lookup,
        **candidates.candidates(embedders),
    }
    policies = {policy.name: policy for policy in POLICIES}
    options = {
        (name, policy): harness.evaluate(dataset, candidate, policies[policy])
        for name, candidate in found.items()
        for policy in policies
    }
    summarise_options(options)
    order = [key for key in options if key[0] not in ("most common", LOOKUP)]
    winner = choose(options, order)
    if winner is None:
        return
    check_lookup(options, winner)
    sweep_weights(dataset, found[winner[0]], winner, policies[winner[1]], options)
    summarise_threshold(options[winner], winner)
    summarise_minimums(options[winner], winner)
    diagnose(dataset, options, winner[0], args.over_matching)


if __name__ == "__main__":
    main()
