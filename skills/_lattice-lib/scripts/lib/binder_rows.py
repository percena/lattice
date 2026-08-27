"""Single source for the binder `prs` field-row grammar (tkt-91).

Owns the placeholder predicate, the canonical entry format, and the multi-PR
joiner. Consumed by the two writers (stamp-pr-open.sh, finish-ledger.sh — their
embedded python imports this module) and asserted byte-equal against the
standalone copies in tools/validate-lattice-artifacts.py by a bats test
(the validator stays dependency-free so consumer repos can vendor it alone).

Canon (tkt-74): `pr-N — <URL>` with single spaces around the em dash,
comma-joined for multi-PR tickets. The ` · ` joiner is the legacy shape
tkt-73/tkt-80 canonicalized away; writers must never emit it.
"""

import re

# Any row that is entirely a `(none…)` parenthetical is a placeholder —
# `(none)`, `(none yet)`, `(none — rides tkt-5 PR)` — and is REPLACED by the
# first real entry, never appended beside.
PRS_PLACEHOLDER_RE = re.compile(r"^\(none.*\)$", re.I)

PRS_ENTRY = r"pr-[1-9][0-9]* — https?://[^\s,]+"
PRS_ROW_CANON_RE = re.compile(rf"^{PRS_ENTRY}(?:,\s*{PRS_ENTRY})*$")

PRS_JOINER = ", "


def is_placeholder(value: str) -> bool:
    return bool(PRS_PLACEHOLDER_RE.fullmatch(value.strip()))


def format_entry(pr_n: int | str, pr_url: str) -> str:
    """Canonical single entry. A URL is required — bare `pr-N` is off-canon;
    callers must resolve the URL (or derive it from the repo slug) first."""
    if not pr_url:
        raise ValueError("prs entry requires a URL (bare pr-N is off-canon)")
    return f"pr-{pr_n} — {pr_url}"


def merge_row(current: str, pr_n: int | str, pr_url: str) -> str:
    """Return the row value after recording pr_n: placeholder/empty rows are
    replaced, an already-recorded pr_n is idempotent, anything else appends
    with the canonical comma joiner."""
    cur = current.strip()
    if re.search(rf"\bpr-{pr_n}\b", cur):
        return cur
    entry = format_entry(pr_n, pr_url)
    if not cur or is_placeholder(cur):
        return entry
    return f"{cur}{PRS_JOINER}{entry}"
