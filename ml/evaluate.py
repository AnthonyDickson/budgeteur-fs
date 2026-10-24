"""Evaluate every candidate under every label policy on the exported data and print a report.
See decision 8 in docs/smart-tagging.md.

Usage: python evaluate.py [--data DIR] [--over-matching PATTERN ...]
"""

import argparse
from pathlib import Path

import pandas as pd

import baselines
import harness
import rules
from harness import LabelPolicy

CANDIDATES: dict[str, harness.Candidate] = {
    "most common": baselines.most_common,
    "lookup": baselines.lookup,
}

POLICIES = [
    LabelPolicy(rule_labels="none"),
    LabelPolicy(rule_labels="uncapped"),
    LabelPolicy(rule_labels="capped"),
]

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


def summarise_comparisons(options: Options) -> None:
    precision = {
        key: harness.precision_at(results, COVERAGE)[1] for key, results in options.items()
    }
    reachable = {key: value for key, value in precision.items() if not pd.isna(value)}
    if reachable:
        best = max(reachable, key=reachable.get)
        section(f"Against the best at {COVERAGE:.0%} coverage, {best}, with 95% interval")
        for key in reachable:
            if key != best:
                comparison = harness.compare(options[key], options[best], COVERAGE)
                print(f"{key}: {format_comparison(comparison)}")

    section("Against the lookup at its own coverage, under the same policy")
    for (candidate, policy), results in options.items():
        lookup = options.get((LOOKUP, policy))
        if candidate == LOOKUP or lookup is None:
            continue
        coverage = harness.max_coverage(lookup)
        comparison = harness.compare(results, lookup, coverage)
        print(f"{(candidate, policy)} at {coverage:.0%}: {format_comparison(comparison)}")


def diagnose(dataset: harness.Dataset, options: Options, over_matching: list[str]) -> None:
    thresholds = {
        key: harness.threshold_for(results, COVERAGE) for key, results in options.items()
    }
    for key, results in options.items():
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
            for key, results in options.items()
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
    options = {
        (name, policy.name): harness.evaluate(dataset, candidate, policy)
        for name, candidate in CANDIDATES.items()
        for policy in POLICIES
    }
    summarise_options(options)
    summarise_comparisons(options)
    diagnose(dataset, options, args.over_matching)


if __name__ == "__main__":
    main()
