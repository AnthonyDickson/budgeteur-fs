"""Rule matching as auto-tagging defines it: a pattern matches when it occurs anywhere in the
description, ignoring case ordinally, and the longest matching pattern wins. See decisions 1 and
2 in docs/auto-tagging.md. Mirrors the server's Domain/Rule.fs, so the residual rows found here
are the ones the server's queue would give to the model.
"""

from dataclasses import dataclass


def fold(text: str) -> str:
    """Case folding as .NET's OrdinalIgnoreCase does it: each character maps to its simple
    uppercase form, so lengths never change. Python's upper() maps some characters to several
    (ß to SS), which .NET does not, so those are kept as they are."""
    return "".join(upper if len(upper := c.upper()) == 1 else c for c in text)


@dataclass(frozen=True)
class Rule:
    id: str
    pattern: str
    # A tag id, or None for a transfer rule.
    tag_id: str | None


def _precedence(rule: Rule) -> tuple[int, str, str]:
    """Longer patterns first, then equal lengths by the comparison, then ordinally. The last
    step only separates patterns that differ by case, which uniqueness rules out."""
    return (-len(rule.pattern), fold(rule.pattern), rule.pattern)


def winner(rules: list[Rule]):
    """The winning rule for a description, or None when no rule matches. Apply it to the rules
    once and reuse the result for many descriptions, so the rules are sorted once."""
    ordered = [(fold(rule.pattern), rule) for rule in sorted(rules, key=_precedence)]

    def win(description: str) -> Rule | None:
        folded = fold(description)
        return next((rule for pattern, rule in ordered if pattern in folded), None)

    return win
