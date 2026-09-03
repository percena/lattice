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

from __future__ import annotations

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


# Binder `updated` field-table row (spc-186 A4 / tkt-191). Bumped by each
# status-stamping script (stamp-pr-open, finish-ledger, ratify) atomically
# with the status flip, in the same locked read-modify-write transaction.
# The stamp is ISO-8601 UTC at seconds precision (YYYY-MM-DDTHH:MM:SSZ),
# matching the `datetime.now(utc).strftime(...)` the writers already emit.
# Lazy migration: a binder predating the row has no `| updated |` row; this
# helper is a no-op then (the validator warns — never fails). The row is
# only ever bumped, never inserted, so the writer cannot corrupt a binder
# that lacks the row; new binders carry it from the template.
UPDATED_ROW_RE = re.compile(r"(\| updated \|)\s*(.*?)\s*(\|)")


def stamp_updated(text: str, ts: str) -> str:
    """Bump the binder `| updated | <ts> |` field-table row in-place.

    Returns ``text`` unchanged when the row is absent (lazy migration) so a
    stamping script never corrupts a binder that predates the row. The caller
    gates the bump on ``s != orig`` (a real status mutation) so an idempotent
    re-run does not touch ``updated`` — preserving the no-change contract.
    """
    if not UPDATED_ROW_RE.search(text):
        return text
    return UPDATED_ROW_RE.sub(
        lambda m: f"{m.group(1)} {ts} {m.group(3)}", text, count=1
    )
