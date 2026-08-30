#!/usr/bin/env python3
"""Read-only Lattice L0 contract checks.

Detects selected current-law drift over distributed Spec/ticket/Review files
without introducing a lineage database or rewriting artifacts.

Checks (selected, not exhaustive):
  - ticket binder ``status`` FSM vocabulary: working
    queued|in-progress|parked|stuck|pr-open|rework|deferred, terminal closed
    (requires a real ``## Finish`` ledger), legacy open (warning, lazy migration)
  - coupled ticket fields (tkt-151 A3): ``stuck`` requires
    ``wait_reason: unblock|re-scope``; ``deferred`` requires a valid
    machine-readable reason (``fuse-halt|blocked-by-failure|spec-superseded``);
    contradictory values fail
  - Spec status vocabulary (tkt-151 A1/A2): ``draft|locked|done|superseded``;
    ``done`` with open non-deferred A* or a contradicting display status fails;
    ``superseded`` requires a valid ``superseded_by`` spc-N link
  - Review status/outcome vocabulary (tkt-151 A1): unknown status/outcome
    fails; a concluded Review without exactly one valid outcome fails
  - Finish-evidence terminal guard (tkt-151 A4): a merged OR cancel
    ``## Finish`` stamp requires terminal ``closed`` when provable from one
    snapshot
  - header ``**Status:**`` copy (TL;DR blockquote) contradicting the field-table
    status (warning; legacy-coarse ``open`` headers are exempt — lazy migration)
  - binder ``prs`` row format: a filled row must be canonical ``pr-N — <URL>``
    entries, comma-separated for multi-PR tickets; ``(none…)`` placeholders are
    exempt (warning permanently — adopt flows may reintroduce legacy rows)
  - binder ``github`` field vs directory ``tkt-N``: a real issue URL's issue
    number must match the N in ``tkt-N-<slug>`` (error on mismatch); a
    placeholder/empty value on a numeric dir emits the phantom-binder smell
    warning (guessed dir number without ``gh issue create``)
  - Spec/ticket id shape for current files (spc-N / tkt-N bare decimal;
    `tkt-pending-<slug>` dirs are a recognized transient state — exempt
    from `malformed_ticket_id`)
  - ``covers`` A* ids that do not exist on the parent Spec Acceptance
  - one-sided local edges: ticket lists Spec but Spec.tickets omits the ticket
    (when both files exist under the scanned homes)

Exit 0 = clean, 1 = findings, 2 = usage/io error.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any

# Binder status FSM vocabulary + coupled-field transition policy (ADR-004 sec.6
# / spc-42 A4, extended by ADR-007 sec.4 for the side-state guard). Vendored
# copy of skills/_lattice-lib/scripts/lib/status_vocab.py (tkt-189 / spc-186
# A2): this file stays dependency-free so consumer repos can vendor the
# validator alone. A bats test asserts the two stay parity-equal (constants +
# compiled regex pattern); the lib is the canonical source -- edit there,
# then mirror here. `open` is legacy-coarse: accepted with a warning (lazy
# migration). `closed` is finish-ledger's terminal stamp; merged vs
# closed-without-merge is read from the ## Finish ledger's mergedAt.
STATUS_WORKING_ORDER = (
    "queued", "in-progress", "parked", "stuck", "pr-open", "rework", "deferred",
)
STATUS_WORKING = frozenset(STATUS_WORKING_ORDER)
STATUS_TERMINAL = frozenset({"closed"})
STATUS_LEGACY = frozenset({"open"})
STATUS_OK = STATUS_WORKING | STATUS_TERMINAL | STATUS_LEGACY
# Side states hold an external signal a pr-open stamp must not silently
# overwrite (parked/stuck/rework/deferred); stamp-pr-open refuses the flip
# without an explicit --force-side-state --reason override (ADR-007 sec.5b).
# tkt-237 M3: deferred added (was missing — silent flip to pr-open lost the
# deferred signal). MUST stay parity-equal with lib/status_vocab.py.
SIDE_STATES = frozenset({"parked", "stuck", "rework", "deferred"})
# queued -> pr-open is allowed but WARN-journaled (in-progress is the default).
DIRECT_JUMP_SOURCES = frozenset({"queued"})
_NONTERMINAL_VALUES = sorted(
    STATUS_WORKING | STATUS_LEGACY, key=lambda s: (-len(s), s)
)
NONTERMINAL_ALT = "|".join(_NONTERMINAL_VALUES)
NONTERMINAL_RE = re.compile(rf"(?:{NONTERMINAL_ALT})")


def is_terminal(status: str) -> bool:
    return status in STATUS_TERMINAL


def is_nonterminal(status: str) -> bool:
    return status in STATUS_WORKING or status in STATUS_LEGACY


def is_side_state(status: str) -> bool:
    return status in SIDE_STATES
SPEC_ID_RE = re.compile(r"^spc-([1-9][0-9]*)$")
TKT_ID_RE = re.compile(r"^tkt-([1-9][0-9]*)$")
# tkt-pending-<slug> dirs are a valid transient state before gh issue create
# (flow.md §3.5: "Rename tkt-pending-<slug> → tkt-N-<slug> if needed"). The
# validator must not error on them (tkt-174: the phantom_binder_smell warning
# recommended tkt-pending-* but malformed_ticket_id rejected it — contradiction).
TKT_PENDING_DIR_RE = re.compile(r"^tkt-pending-([a-z0-9][a-z0-9-]*)$", re.I)
REV_ID_RE = re.compile(
    r"^rev-(?:[1-9][0-9]*|[0-9]{8}-[0-9]{6}Z(?:-[a-z0-9]{2,4})?)$"
)
COVERS_RE = re.compile(r"\bA([1-9][0-9]*)\b")
A_HEADING_RE = re.compile(r"\*\*A([1-9][0-9]*)\*\*")
FM_RE = re.compile(r"^---\s*\n(.*?)\n---\s*\n", re.S)
STATUS_TABLE_RE = re.compile(r"^\|\s*status\s*\|\s*([^|]+?)\s*\|", re.I | re.M)
STATUS_TLDR_RE = re.compile(r"\*\*Status:\*\*\s*([a-zA-Z0-9_-]+)", re.I)
SPEC_REF_RE = re.compile(r"\|\s*spec\s*\|\s*(spc-[1-9][0-9]*)\b", re.I)
PRS_TABLE_RE = re.compile(r"^\|\s*prs\s*\|\s*([^|]+?)\s*\|", re.I | re.M)
# Binder github field row (tkt-155). The value is a GitHub issue URL whose
# trailing number must match the N in the directory name tkt-N-<slug>, or a
# placeholder when the issue has not been created yet.
GITHUB_TABLE_RE = re.compile(r"^\|\s*github\s*\|\s*([^|]+?)\s*\|", re.I | re.M)
# A github field value that is a placeholder — not a real issue URL. Matches:
# empty, `(to be created)`, `pending`, `(none…)`, `(none yet)`, etc. The
# `(none…)` family shares grammar with PRS_PLACEHOLDER_RE (binder_rows.py).
GITHUB_PLACEHOLDER_RE = re.compile(
    r"^(?:\(none.*\)|\(to be created\)|pending|)$", re.I
)
# Extract the trailing issue number from a GitHub issue URL.
GITHUB_ISSUE_URL_RE = re.compile(r"/issues/([1-9][0-9]*)\b")
# A row that is entirely a `(none…)` parenthetical is a placeholder, not a
# filled ledger entry (e.g. `(none)`, `(none yet)`, `(none — rides tkt-5 PR)`).
# Grammar single-sourced with the writers in
# skills/_lattice-lib/scripts/lib/binder_rows.py — this file keeps standalone
# copies (consumer repos vendor the validator alone); a bats test asserts the
# two stay byte-identical (tkt-91).
PRS_PLACEHOLDER_RE = re.compile(r"^\(none.*\)$", re.I)
# Canonical filled row: `pr-N — <URL>` (single spaces around the em dash),
# comma-separated for multi-PR tickets (`pr-52 — <URL>, pr-53 — <URL>`).
_PRS_ENTRY = r"pr-[1-9][0-9]* — https?://[^\s,]+"
PRS_ROW_CANON_RE = re.compile(rf"^{_PRS_ENTRY}(?:,\s*{_PRS_ENTRY})*$")
TICKETS_LIST_RE = re.compile(r"^tickets:\s*\[(.*?)\]\s*$", re.M)
# Binder fix_cycles field-table row (ADR-004 §5 / tkt-123). Missing row is OK
# (lazy migration — never fails); an explicit value >2 exceeds the review-fix
# cap and warns (mirror legacy_open_status posture).
FIX_CYCLES_RE = re.compile(r"^\|\s*fix_cycles\s*\|\s*([0-9]+)\s*\|", re.I | re.M)

# Binder created/updated timestamps (spc-186 A4 / tkt-191). Field-table rows,
# ISO-8601 UTC at seconds precision (YYYY-MM-DDTHH:MM:SSZ) — the stamp format
# the three status-stamping scripts emit (datetime.now(utc).strftime(
# "%Y-%m-%dT%H:%M:%SZ")). `created` is stamped once at creation; `updated` is
# bumped atomically with each status flip. Missing rows are a lazy-migration
# warning (historical binders predate the rows; never fails); a present-but-
# malformed value is an error. Validator-local grammar (writers emit, never
# validate; mirrors FIX_CYCLES_RE's posture) — not vendored from lib/.
BINDER_TS_RE = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$")
CREATED_TABLE_RE = re.compile(r"^\|\s*created\s*\|\s*([^|]+?)\s*\|", re.I | re.M)
UPDATED_TABLE_RE = re.compile(r"^\|\s*updated\s*\|\s*([^|]+?)\s*\|", re.I | re.M)
# A timestamp value that is a placeholder (not yet stamped): the template's
# `<YYYY-MM-DDTHH:MM:SSZ>` fill-in hint, `(pending)`, `(none)`, empty. These
# are treated as MISSING (warning), not malformed — an agent who has not yet
# stamped gets a nudge, not a hard fail. Only a non-placeholder value that
# fails the ISO-8601 canon is a malformed error.
TS_PLACEHOLDER_RE = re.compile(r"^(?:\(none.*\)|\(pending.*\)|\(to be.*\)|pending|<[^|]*>|)$", re.I)

# tkt-151: Spec status vocabulary (front-matter `status:` line, commented
# template `# status: draft | locked | done | superseded`). `done` and
# `superseded` are terminal — they carry terminal guards (A2). `draft`/`locked`
# are non-terminal.
SPEC_STATUS_OK = {"draft", "locked", "done", "superseded"}
SPEC_STATUS_TERMINAL = {"done", "superseded"}
# `superseded_by` validity is checked via SPEC_FM_SUPERSEDED_BY_RE in the helper.
# Review status/outcome vocabulary (create-review template front matter).
# status: open | concluded; outcome: null | inform_only | needs_decision |
# spawn_spec | spawn_tickets | spawn_fix | needs_grill.
REVIEW_STATUS_OK = {"open", "concluded"}
REVIEW_OUTCOME_OK = {
    "inform_only",
    "needs_decision",
    "spawn_spec",
    "spawn_tickets",
    "spawn_fix",
    "needs_grill",
}
# Coupled ticket field: wait_reason (binder field-table row). The row carries
# the reason for BOTH stuck and deferred statuses (tkt-151 anticipated decision
# — reuse wait_reason semantics extended to deferred; grep-able single row).
# stuck: unblock | re-scope (FSM-2b / tkt-132). deferred: fuse-halt |
# blocked-by-failure (ADR-004 amd tkt-136 Option B — batch-work stamps these)
# | spec-superseded (spc-186 A3 — spec-supersede trip-time sweep stamps a
# superseded Spec's still-active child binders at supersede time). Vendored
# copy of lib/status_vocab.py STUCK_REASONS / DEFERRED_REASONS (tkt-190): edit
# there, then mirror here (bats parity test asserts equality).
WAIT_REASON_RE = re.compile(r"^\|\s*wait_reason\s*\|\s*([^|]+?)\s*\|", re.I | re.M)
STUCK_REASONS = frozenset({"unblock", "re-scope"})
DEFERRED_REASONS = frozenset({"fuse-halt", "blocked-by-failure", "spec-superseded"})
# Terminal Finish-evidence stamps (## Finish ledger). A merged ledger records
# `pr-P merged:`; a cancel ledger records `issue #N closed:` without a merge.
# Both are provable-from-one-snapshot terminal evidence (A4): a non-terminal
# binder status contradicting either stamp is drift.
#
# Anchored to the canonical emitted bullet form (finish-ledger.sh writes
# `- pr-N merged:`, `- issue #N closed:`, `- cancelled:`) with re.MULTILINE so
# body prose that merely *mentions* `merged:` / `closed:` (e.g. a note line
# `- note: PR was merged: … but reverted` or a placeholder
# `- (none — not yet merged: waiting on CI)`) cannot masquerade as a stamp
# (tkt-238 H1). The cancel stamp permits leading indentation (`  - cancelled:`)
# so an indented cancel is still detected (tkt-238 M2); the merged/closed
# stamps share the same `^\s*-\s+` bullet anchor for consistency.
FINISH_MERGED_RE = re.compile(r"^\s*-\s+pr-\d+\s+merged:\s", re.M)
FINISH_CLOSED_RE = re.compile(r"^\s*-\s+issue\s+#\d+\s+closed:\s", re.M | re.I)
FINISH_CANCELLED_RE = re.compile(r"^\s*-\s+cancelled:", re.M)


def parse_front_matter(text: str) -> dict[str, Any]:
    m = FM_RE.match(text)
    if not m:
        return {}
    data: dict[str, Any] = {}
    for line in m.group(1).splitlines():
        if ":" not in line:
            continue
        key, val = line.split(":", 1)
        data[key.strip()] = val.strip()
    return data


def load_text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def first_table_block(text: str) -> str:
    """Return the first markdown table block (consecutive ``|``-prefixed lines).

    Binder field rows (``| status | … |``, ``| covers | … |``, ``| spec | … |``)
    are read only from the binder card, which is always the first table in the
    file; a later docs/example table must not shadow it.
    """
    lines = text.splitlines()
    start = None
    for index, line in enumerate(lines):
        if line.lstrip().startswith("|"):
            start = index
            break
    if start is None:
        return ""
    end = start
    while end < len(lines) and lines[end].lstrip().startswith("|"):
        end += 1
    return "\n".join(lines[start:end])


def tldr_header_status(text: str) -> str | None:
    """Header ``**Status:**`` from TL;DR blockquote lines before the binder card.

    Scoped to ``>`` lines above the first table so prose that merely mentions
    the literal ``**Status:**`` marker (e.g. an acceptance criterion about it)
    can never masquerade as a header status. The template dropped this copy
    (field table is SoT); legacy binders may still carry it.
    """
    for line in text.splitlines():
        stripped = line.lstrip()
        if stripped.startswith("|"):
            break
        if stripped.startswith(">"):
            m = STATUS_TLDR_RE.search(line)
            if m:
                return m.group(1).strip().lower()
    return None


def ticket_status(text: str) -> str | None:
    m = STATUS_TABLE_RE.search(first_table_block(text))
    if m:
        return m.group(1).strip().lower()
    # Fallback when the binder card (first table) has no | status | row: use
    # the scoped TL;DR header (blockquote lines before the first table), not a
    # whole-text search — body prose that merely mentions the literal
    # **Status:** marker (e.g. an acceptance criterion) must not masquerade as
    # the ticket status. Mirrors tldr_header_status()'s scoping rationale.
    hs = tldr_header_status(text)
    if hs is not None:
        return hs
    fm = parse_front_matter(text)
    if "status" in fm:
        return str(fm["status"]).strip().lower().strip("'\"")
    return None


ACCEPT_HEADING_RE = re.compile(r"^(#{2,6})\s+.*acceptance", re.I)
HEADING_RE = re.compile(r"^(#{2,6})\s")
FINISH_SECTION_RE = re.compile(r"^##\s+Finish\b.*?\n(.*?)(?=^##\s|\Z)", re.S | re.M)
HTML_COMMENT_RE = re.compile(r"<!--.*?-->", re.S)


def has_finish_ledger(text: str) -> bool:
    """True when a ``## Finish`` section carries real ledger content.

    Placeholder bodies — the ``(none…)`` family (e.g. ``(none yet)``,
    ``(none — rides tkt-5 PR)``), bullets of them, HTML comments, blank
    lines — do not count. finish-ledger.sh replaces the placeholder with dated
    ``pr-P merged: …`` / ``issue #N closed: …`` lines, which do. The placeholder
    grammar is shared with the prs row (``PRS_PLACEHOLDER_RE``) — single-sourced.
    """
    m = FINISH_SECTION_RE.search(text)
    if not m:
        return False
    body = HTML_COMMENT_RE.sub("", m.group(1))
    for line in body.splitlines():
        content = line.strip().lstrip("-").strip()
        if content and PRS_PLACEHOLDER_RE.fullmatch(content) is None:
            return True
    return False


def finish_ledger_merged(text: str) -> bool:
    """True when the ``## Finish`` ledger records at least one PR merge.

    finish-ledger.sh writes ``pr-P merged: <ISO date> — <URL>`` lines; a
    closed-without-merge ledger (cancel path) has no ``merged:`` line and is
    exempt from the terminal-status requirement.
    """
    m = FINISH_SECTION_RE.search(text)
    if not m:
        return False
    body = HTML_COMMENT_RE.sub("", m.group(1))
    return FINISH_MERGED_RE.search(body) is not None


def finish_ledger_terminal(text: str) -> bool:
    """True when the ``## Finish`` ledger records a provable terminal event.

    A merged ledger carries ``pr-P merged:``; a cancel ledger carries
    ``issue #N closed:`` without a merge; a no-issue cancel carries
    ``- cancelled:``. Any of these stamps is terminal evidence provable from
    one snapshot (tkt-151 A4): a non-terminal binder status contradicting
    either is drift. Whole-document prose is not consulted — only the
    ``## Finish`` section body.

    Shares the content model of ``has_finish_ledger``: iterate lines, strip
    HTML comments, and skip ``(none…)`` placeholder lines
    (``PRS_PLACEHOLDER_RE``) so a placeholder body that merely *mentions*
    ``merged:`` (e.g. ``(none — not yet merged: waiting on CI)``) cannot
    masquerade as a terminal stamp (tkt-238 H1). The stamp regexes are
    anchored to the canonical bullet form, so prose note lines like
    `- note: PR was merged: … but reverted` are not matched either.
    """
    m = FINISH_SECTION_RE.search(text)
    if not m:
        return False
    body = HTML_COMMENT_RE.sub("", m.group(1))
    for line in body.splitlines():
        content = line.strip().lstrip("-").strip()
        if not content or PRS_PLACEHOLDER_RE.fullmatch(content) is not None:
            continue
        if (FINISH_MERGED_RE.search(line) is not None or
                FINISH_CLOSED_RE.search(line) is not None or
                FINISH_CANCELLED_RE.search(line) is not None):
            return True
    return False


SPEC_FM_STATUS_RE = re.compile(r"^status:\s*([a-zA-Z0-9_-]+)\s*$", re.M)
SPEC_FM_SUPERSEDED_BY_RE = re.compile(
    r"^superseded_by:\s*(\S.*?)\s*$", re.M
)
SPEC_HEADER_BLOCKQUOTE_RE = re.compile(r"^\s*>", re.M)
# Deferred marker on an acceptance line (per-A*, explicit, same-line).
ACCEPT_DEFERRED_RE = re.compile(r"\(deferred\)", re.I)
# Strikethrough wrapping a bold A-id (`~~**A2**~~`) — an explicit per-A*
# deferred marker. Only the A-id itself being struck counts as deferred;
# `~~` wrapping unrelated prose (e.g. `- [ ] **A2** ~~deprecated approach~~
# — actually still open`) must NOT defer the open A-id (tkt-238 M3).
STRIKE_AID_RE = re.compile(r"~~\*\*A\d+\*\*~~")


def spec_status(text: str) -> str | None:
    """Spec front-matter ``status:`` value (authoritative SoT).

    Scoped to front matter only — the commented template line
    ``# status: draft | locked | …`` and TL;DR ``**Status:**`` copy are not
    consulted here (the header is checked separately for contradiction).
    """
    fm = parse_front_matter(text)
    if not fm:
        return None
    val = fm.get("status")
    if not val:
        return None
    return val.strip().strip("'\"").lower()


def spec_header_status(text: str) -> str | None:
    """TL;DR ``**Status:**`` copy from blockquote lines before the first ``##`` heading.

    Specs do not carry a binder card table at the top; their display status
    lives in a ``>`` blockquote line (``> **Kind:** … · **Status:** locked · …``).
    Scoped to blockquote lines before the first ``##`` heading so body prose
    that merely mentions the literal ``**Status:**`` marker cannot masquerade.
    """
    for line in text.splitlines():
        if HEADING_RE.match(line):
            break
        if SPEC_HEADER_BLOCKQUOTE_RE.match(line):
            m = STATUS_TLDR_RE.search(line)
            if m:
                return m.group(1).strip().lower()
    return None


def spec_done_open_acceptance(text: str) -> list[str]:
    """Open, non-deferred A-ids in the Acceptance section (tkt-151 A2).

    A `done` Spec must have every Acceptance item either checked ``- [x]`` or
    explicitly deferred with an inline ``(deferred)`` marker on the same line.
    A bare ``- [ ]`` (open, non-deferred) A* is a fictional-done drift. Only
    lines inside an Acceptance section are consulted (reuses the
    acceptance-section scoping of spec_acceptance_ids).
    """
    open_ids: list[str] = []
    in_section = False
    level = 0
    for line in text.splitlines():
        hm = HEADING_RE.match(line)
        if hm:
            if ACCEPT_HEADING_RE.match(line):
                in_section = True
                level = len(hm.group(1))
                # An open checkbox on the heading line itself counts too.
                open_ids.extend(_open_non_deferred_aids(line))
                continue
            if in_section and len(hm.group(1)) <= level:
                in_section = False
                continue
        if in_section:
            open_ids.extend(_open_non_deferred_aids(line))
    return open_ids


def _open_non_deferred_aids(line: str) -> list[str]:
    # A markdown checkbox line: `- [ ]` (open) vs `- [x]`/`- [X]` (closed).
    # Deferred when the line carries an inline `(deferred)` marker OR the
    # A-id itself is struck through (`~~**A2**~~`). Strikethrough wrapping
    # *unrelated* prose (e.g. `**A2** ~~deprecated~~ — still open`) must NOT
    # defer the open A-id (tkt-238 M3): previously any `~~` on the line was
    # treated as deferred, masking a fictional-done Spec.
    if not re.match(r"^\s*-\s*\[\s\]", line):
        return []
    if ACCEPT_DEFERRED_RE.search(line) or STRIKE_AID_RE.search(line):
        return []
    return [f"A{n}" for n in A_HEADING_RE.findall(line)]


def spec_superseded_by(text: str) -> str | None:
    """Spec front-matter ``superseded_by:`` value (raw, unvalidated)."""
    m = SPEC_FM_SUPERSEDED_BY_RE.search(text)
    if not m:
        return None
    val = m.group(1).strip().strip("'\"")
    return val if val and val.lower() != "null" else None


def review_status(text: str) -> str | None:
    fm = parse_front_matter(text)
    if "status" not in fm:
        return None
    return str(fm["status"]).strip().strip("'\"").lower()


def review_outcome(text: str) -> str | None:
    fm = parse_front_matter(text)
    if "outcome" not in fm:
        return None
    val = str(fm["outcome"]).strip().strip("'\"")
    return val if val and val.lower() != "null" else None


def binder_wait_reason(text: str) -> str | None:
    """``wait_reason`` value from the binder card (first table block only).

    ``(none)`` / empty / missing → None (the unstated sentinel). Stripped of
    surrounding whitespace. The template's third description cell is not
    consulted (the value is the second cell only).
    """
    m = WAIT_REASON_RE.search(first_table_block(text))
    if not m:
        return None
    val = m.group(1).strip()
    if not val or PRS_PLACEHOLDER_RE.fullmatch(val):
        return None
    return val.lower()


def spec_acceptance_ids(text: str) -> set[str]:
    """Collect **A-N** ids only from Acceptance section(s).

    A bold A-id in prose outside an Acceptance section must not count as
    coverable. A section runs from a heading matching /^##+ .*Acceptance/i to
    the next heading at the same or a higher level.
    """
    ids: set[str] = set()
    in_section = False
    level = 0
    for line in text.splitlines():
        hm = HEADING_RE.match(line)
        if hm:
            if ACCEPT_HEADING_RE.match(line):
                in_section = True
                level = len(hm.group(1))
                # A-ids may appear inline on the heading line itself (e.g.
                # "## Acceptance — **A1**, **A2**"); collect them before the
                # continue so they register as coverable.
                ids.update(f"A{n}" for n in A_HEADING_RE.findall(line))
                continue
            if in_section and len(hm.group(1)) <= level:
                in_section = False
                continue
        if in_section:
            ids.update(f"A{n}" for n in A_HEADING_RE.findall(line))
    return ids


def binder_covers(text: str) -> set[str]:
    # Prefer table covers row (binder card only — first table block)
    m = re.search(r"^\|\s*covers\s*\|\s*([^|]+)\|", first_table_block(text), re.I | re.M)
    blob = m.group(1) if m else ""
    # Also acceptance headings owned by the ticket
    blob += "\n" + "\n".join(
        line for line in text.splitlines() if line.strip().startswith("- [")
    )
    return {f"A{n}" for n in COVERS_RE.findall(blob)}


def spec_ticket_ids(text: str) -> set[str]:
    """Tickets declared in the **authoritative** tickets: front-matter / list row.

    Prose backtick mentions (`` `tkt-N` ``) are intentionally excluded. A one-sided
    ticket↔spec edge is a real drift only when the authoritative list omits the
    ticket; a casual prose reference must not mask that.
    """
    fm = parse_front_matter(text)
    raw = fm.get("tickets", "")
    ids = set(re.findall(r"tkt-([1-9][0-9]*)", raw))
    m = TICKETS_LIST_RE.search(text)
    if m:
        ids.update(re.findall(r"tkt-([1-9][0-9]*)", m.group(1)))
    return {f"tkt-{n}" for n in ids}


def iter_specs(home: Path) -> list[Path]:
    d = home / "specs"
    if not d.is_dir():
        return []
    return sorted(p for p in d.glob("spc-*.md") if p.is_file())


def iter_tickets(home: Path) -> list[Path]:
    out: list[Path] = []
    for base in (home / "tickets", home / "tickets" / "archive"):
        if not base.is_dir():
            continue
        for readme in base.glob("tkt-*/README.md"):
            out.append(readme)
    return sorted(out)


def iter_reviews(home: Path) -> list[Path]:
    d = home / "reviews"
    if not d.is_dir():
        return []
    return sorted(p for p in d.glob("rev-*.md") if p.is_file())


def validate_home(home: Path) -> list[dict[str, str]]:
    findings: list[dict[str, str]] = []
    specs: dict[str, Path] = {}
    spec_tickets: dict[str, set[str]] = {}
    spec_accept: dict[str, set[str]] = {}

    for path in iter_specs(home):
        text = load_text(path)
        fm = parse_front_matter(text)
        # Slugless fallback derives from the stem so `spc-12.md` yields
        # `spc-12`, not `spc-12.md`.
        sid = str(fm.get("id", "")).strip() or path.stem.split("-", 2)[0] + "-" + path.stem.split("-")[1]
        # id from filename spc-N-slug
        m = re.match(r"(spc-[1-9][0-9]*)-", path.name)
        file_id = m.group(1) if m else ""
        check_id = sid if sid.startswith("spc-") else file_id
        if check_id and not SPEC_ID_RE.fullmatch(check_id):
            findings.append(
                {
                    "code": "malformed_spec_id",
                    "path": str(path.relative_to(home.parent)) if home.parent in path.parents else str(path),
                    "detail": f"id {check_id!r} is not spc-N bare decimal",
                }
            )
        if check_id:
            specs[check_id] = path
            spec_tickets[check_id] = spec_ticket_ids(text)
            spec_accept[check_id] = spec_acceptance_ids(text)

        # tkt-151 A1/A2: Spec status vocabulary + terminal guards.
        sp_st = spec_status(text)
        if sp_st is not None and sp_st not in SPEC_STATUS_OK:
            findings.append(
                {
                    "code": "invalid_spec_status",
                    "path": str(path.relative_to(home.parent)) if home.parent in path.parents else str(path),
                    "detail": f"status {sp_st!r} not in {sorted(SPEC_STATUS_OK)}",
                }
            )
        # TL;DR **Status:** header vs front-matter status. A terminal Spec
        # (done/superseded) with a contradicting display status is a
        # fictional-done drift — error (A2). For draft/locked the mismatch is
        # a warning (display drift; lazy migration).
        sp_header_st = spec_header_status(text)
        if sp_st is not None and sp_header_st is not None and sp_header_st != sp_st:
            is_terminal = sp_st in SPEC_STATUS_TERMINAL
            findings.append(
                {
                    "code": "spec_header_status_mismatch",
                    "level": "error" if is_terminal else "warning",
                    "path": str(path.relative_to(home.parent)) if home.parent in path.parents else str(path),
                    "detail": (
                        f"TL;DR header status {sp_header_st!r} contradicts "
                        f"front-matter status {sp_st!r} (front matter is SoT)"
                        + ("; a terminal Spec's display must match" if is_terminal else "")
                    ),
                }
            )
        # `done` with open non-deferred A* is fictional-done (A2).
        if sp_st == "done":
            open_a = spec_done_open_acceptance(text)
            if open_a:
                findings.append(
                    {
                        "code": "spec_done_open_acceptance",
                        "path": str(path.relative_to(home.parent)) if home.parent in path.parents else str(path),
                        "detail": (
                            f"status is done but Acceptance has open non-deferred "
                            f"items: {sorted(open_a, key=lambda x: int(x[1:]))} "
                            "(check off with proof, mark (deferred), or revert to locked)"
                        ),
                    }
                )
        # `superseded` requires a valid superseded_by link (A2).
        if sp_st == "superseded":
            by = spec_superseded_by(text)
            if not by or not SPEC_ID_RE.fullmatch(by):
                findings.append(
                    {
                        "code": "spec_superseded_no_link",
                        "path": str(path.relative_to(home.parent)) if home.parent in path.parents else str(path),
                        "detail": (
                            f"status is superseded but superseded_by is {by!r} "
                            "(must be a real spc-N)"
                        ),
                    }
                )

    for path in iter_reviews(home):
        text = load_text(path)
        fm = parse_front_matter(text)
        rid = str(fm.get("id", "")).strip()
        if rid and not REV_ID_RE.fullmatch(rid):
            findings.append(
                {
                    "code": "malformed_review_id",
                    "path": str(path),
                    "detail": f"id {rid!r} is not a valid R1/legacy Review id",
                }
            )

        # tkt-151 A1: Review status/outcome vocabulary + concluded-with-outcome guard.
        rv_st = review_status(text)
        if rv_st is not None and rv_st not in REVIEW_STATUS_OK:
            findings.append(
                {
                    "code": "invalid_review_status",
                    "path": str(path),
                    "detail": f"status {rv_st!r} not in {sorted(REVIEW_STATUS_OK)}",
                }
            )
        rv_out = review_outcome(text)
        if rv_out is not None and rv_out not in REVIEW_OUTCOME_OK:
            findings.append(
                {
                    "code": "invalid_review_outcome",
                    "path": str(path),
                    "detail": f"outcome {rv_out!r} not in {sorted(REVIEW_OUTCOME_OK)}",
                }
            )
        # A concluded Review must carry exactly one valid outcome (A1).
        if rv_st == "concluded" and not rv_out:
            findings.append(
                {
                    "code": "concluded_review_no_outcome",
                    "path": str(path),
                    "detail": (
                        f"status is concluded but outcome is {rv_out!r} "
                        "(exactly one of inform_only | needs_decision | "
                        "spawn_spec | spawn_tickets | spawn_fix | needs_grill required)"
                    ),
                }
            )

    ticket_dirs_by_id: dict[str, list[Path]] = {}
    for path in iter_tickets(home):
        text = load_text(path)
        # id from directory tkt-N-slug
        m = re.match(r"(tkt-[1-9][0-9]*)-", path.parent.name)
        tid = m.group(1) if m else ""
        if tid:
            ticket_dirs_by_id.setdefault(tid, []).append(path)
        if not tid or not TKT_ID_RE.fullmatch(tid):
            # tkt-pending-<slug> is a recognized transient dir (flow.md §3.5)
            # — not malformed. Exempt from the error so binder_github_pending
            # can fire as a standalone warning (tkt-174).
            if not TKT_PENDING_DIR_RE.fullmatch(path.parent.name):
                findings.append(
                    {
                        "code": "malformed_ticket_id",
                        "path": str(path),
                        "detail": f"directory {path.parent.name!r} is not tkt-N-… or tkt-pending-<slug>",
                    }
                )

        st = ticket_status(text)
        if st is not None and st not in STATUS_OK:
            findings.append(
                {
                    "code": "invalid_ticket_status",
                    "path": str(path),
                    "detail": f"status {st!r} not in {sorted(STATUS_OK)}",
                }
            )
        if st in STATUS_LEGACY:
            findings.append(
                {
                    "code": "legacy_open_status",
                    "level": "warning",
                    "path": str(path),
                    "detail": f"status {st!r} is legacy-coarse; migrate to the FSM enum ({' | '.join(STATUS_WORKING_ORDER)} | closed)",
                }
            )
        # tkt-151 A3: coupled ticket fields. `stuck` requires a valid
        # wait_reason in {unblock, re-scope}; `deferred` requires a valid
        # machine-readable reason in {fuse-halt, blocked-by-failure,
        # spec-superseded}. A contradictory value (e.g. stuck + fuse-halt,
        # deferred + unblock) fails
        # — the reason must match the status. Missing/(none) for either fails.
        wr = binder_wait_reason(text)
        if st == "stuck" and wr not in STUCK_REASONS:
            findings.append(
                {
                    "code": "stuck_without_valid_wait_reason",
                    "path": str(path),
                    "detail": (
                        f"status is stuck but wait_reason is {wr!r}; "
                        f"must be one of {sorted(STUCK_REASONS)} (FSM-2b)"
                    ),
                }
            )
        if st == "deferred" and wr not in DEFERRED_REASONS:
            findings.append(
                {
                    "code": "deferred_without_valid_reason",
                    "path": str(path),
                    "detail": (
                        f"status is deferred but wait_reason is {wr!r}; "
                        f"must be one of {sorted(DEFERRED_REASONS)} "
                        "(ADR-004 amd tkt-136 Option B; spc-186 A3 adds "
                        "spec-superseded)"
                    ),
                }
            )
        # Bounded-loop invariant (ADR-004 §5 / tkt-123 / spc-186 A6): the
        # binder field-table `fix_cycles` row records review-fix rounds; cap is
        # ≤2. An explicit value >2 exceeds the bound — WARNING, not error.
        # Why warn (not error): the cap-exit is a CLASS-FORCING transition, not
        # a hard stop. `bump-fix-cycle.sh` owns the counter + cap-exit: on the
        # third rework it holds fix_cycles at 2 and journals a CAP-HIT trace
        # that forces the `deep-review` triage class (human) before any further
        # fix cycle — no auto-retry (ADR-007 §4 five-piece). A value >2 means a
        # human authorized the --extend-budget escape (operator-adjudicated,
        # journaled in ## Decision journal); the warning surfaces that the cap
        # was exceeded so morning triage can read the escape trace, not block
        # the run. Lazy-migration posture: missing row = 0, never fails.
        fc_m = FIX_CYCLES_RE.search(first_table_block(text))
        if fc_m:
            fc_val = int(fc_m.group(1))
            if fc_val > 2:
                findings.append(
                    {
                        "code": "fix_cycles_exceeded",
                        "level": "warning",
                        "path": str(path),
                        "detail": (
                            f"fix_cycles {fc_val} exceeds the review-fix cap "
                            "of 2 (ADR-004 §5); the bound is declared law — "
                            "either resolve the findings (deep-review) or "
                            "file a Spec/ticket revision"
                        ),
                    }
                )
        # Binder created/updated timestamps (spc-186 A4 / tkt-191). Missing
        # rows (or unfilled placeholders) warn — lazy migration; historical
        # binders predate the rows and never fail. A present, non-placeholder
        # value that is not ISO-8601 UTC seconds-precision is a malformed
        # error. `created` is stamped once; `updated` is bumped by each
        # status-stamping script; both gate A5 staleness (now − updated).
        _tb = first_table_block(text)
        missing_ts: list[str] = []
        for _name, _re in (("created", CREATED_TABLE_RE), ("updated", UPDATED_TABLE_RE)):
            _m = _re.search(_tb)
            if not _m:
                missing_ts.append(_name)
                continue
            _val = _m.group(1).strip()
            if not _val or TS_PLACEHOLDER_RE.fullmatch(_val):
                missing_ts.append(_name)
            elif BINDER_TS_RE.fullmatch(_val) is None:
                findings.append(
                    {
                        "code": "malformed_binder_timestamp",
                        "path": str(path),
                        "detail": (
                            f"{_name} row {_val!r} is not ISO-8601 UTC "
                            "seconds-precision (YYYY-MM-DDTHH:MM:SSZ)"
                        ),
                    }
                )
        if missing_ts:
            findings.append(
                {
                    "code": "missing_binder_timestamp",
                    "level": "warning",
                    "path": str(path),
                    "detail": (
                        f"binder lacks created/updated timestamp row(s): "
                        f"{', '.join(missing_ts)} (lazy migration — stamp "
                        "created at creation, updated on each status flip; "
                        "spc-186 A4)"
                    ),
                }
            )
        # Header **Status:** copy vs field-table status. The template dropped
        # the header copy (field table is SoT); a stale survivor that
        # contradicts the table is dual-maintenance drift. Legacy-coarse
        # `open` headers predate the FSM migration and stay exempt (the
        # lazy-migration path owns those).
        table_status_m = STATUS_TABLE_RE.search(first_table_block(text))
        header_st = tldr_header_status(text)
        if (
            table_status_m
            and header_st is not None
            and header_st not in STATUS_LEGACY
            and header_st != table_status_m.group(1).strip().lower()
        ):
            findings.append(
                {
                    "code": "header_status_mismatch",
                    "level": "warning",
                    "path": str(path),
                    "detail": (
                        f"TL;DR header status {header_st!r} contradicts field-table "
                        f"status {table_status_m.group(1).strip().lower()!r} "
                        "(field table is SoT; drop the header copy)"
                    ),
                }
            )
        # Binder prs row: canonical filled format is `pr-N — <URL>` (em dash),
        # comma-separated for multi-PR tickets; `(none…)` placeholders are
        # exempt. Warning-level PERMANENTLY: the historical ledger migrates
        # lazily and adopt flows may reintroduce legacy rows, so this must
        # never fail a run regardless of merge order.
        prs_m = PRS_TABLE_RE.search(first_table_block(text))
        if prs_m:
            prs_val = prs_m.group(1).strip()
            if (
                prs_val
                and not PRS_PLACEHOLDER_RE.fullmatch(prs_val)
                and not PRS_ROW_CANON_RE.fullmatch(prs_val)
            ):
                findings.append(
                    {
                        "code": "prs_row_format",
                        "level": "warning",
                        "path": str(path),
                        "detail": (
                            f"prs row {prs_val!r} is not canonical "
                            "`pr-N — <URL>` (em dash; comma-separated for "
                            "multiples; `(none…)` placeholders exempt)"
                        ),
                    }
                )
        # Binder github field vs directory tkt-N (tkt-155): the github row
        # names the GH issue that owns this binder. A real URL's issue number
        # must match the N in tkt-N-<slug> (error on mismatch — lineage key
        # fork); a placeholder/empty value on a numeric dir is the phantom
        # smell (warning — likely a guessed dir number without gh issue
        # create). Absent row is OK (lazy migration — mirrors fix_cycles).
        gh_m = GITHUB_TABLE_RE.search(first_table_block(text))
        if gh_m:
            gh_val = gh_m.group(1).strip()
            if GITHUB_PLACEHOLDER_RE.fullmatch(gh_val):
                # Placeholder/empty github value. On a numeric dir this is
                # the phantom-binder smell (binder_github_pending is
                # subsumed — the phantom signal is the actionable one); on
                # a non-numeric dir it is just pending.
                dir_n_m = re.match(r"tkt-([1-9][0-9]*)$", tid) if tid else None
                if dir_n_m:
                    findings.append(
                        {
                            "code": "phantom_binder_smell",
                            "level": "warning",
                            "path": str(path),
                            "detail": (
                                f"numeric dir {tid} but github field is "
                                f"placeholder ({gh_val!r}) — likely a guessed "
                                "dir number without gh issue create; use "
                                "`tkt-pending-<slug>` until the issue exists"
                            ),
                        }
                    )
                else:
                    findings.append(
                        {
                            "code": "binder_github_pending",
                            "level": "warning",
                            "path": str(path),
                            "detail": (
                                f"github field is pending/placeholder "
                                f"({gh_val!r}) — create the issue and update"
                            ),
                        }
                    )
            else:
                url_m = GITHUB_ISSUE_URL_RE.search(gh_val)
                if url_m:
                    gh_issue_n = url_m.group(1)
                    dir_n_m = re.match(r"tkt-([1-9][0-9]*)$", tid) if tid else None
                    if dir_n_m and gh_issue_n != dir_n_m.group(1):
                        findings.append(
                            {
                                "code": "binder_dir_github_mismatch",
                                "path": str(path),
                                "detail": (
                                    f"dir {tid} but github issue #{gh_issue_n} "
                                    "— lineage key fork (dir N must match "
                                    "issue N)"
                                ),
                            }
                        )
                else:
                    findings.append(
                        {
                            "code": "binder_github_malformed",
                            "level": "warning",
                            "path": str(path),
                            "detail": (
                                f"github row {gh_val!r} is neither a real "
                                "issue URL nor a recognized placeholder"
                            ),
                        }
                    )
        if st in STATUS_TERMINAL and not has_finish_ledger(text):
            findings.append(
                {
                    "code": "closed_without_finish",
                    "path": str(path),
                    "detail": f"status {st!r} but ## Finish ledger is missing or placeholder-only",
                }
            )
        # Inverse of closed_without_finish: a merged OR cancel ## Finish ledger
        # is terminal evidence provable from one snapshot (tkt-151 A4), so a
        # working/legacy status contradicts the binder's own single source of
        # truth (spc-42:76). Error-level — this is exactly the breach that
        # stranded 19 binders at `pr-open` (tkt-90; audit rev-20260827-033352Z
        # F1/F2). A cancel ledger (`issue #N closed:` without a merge) is now
        # terminal evidence too (A4); previously only `merged:` was.
        if st is not None and st not in STATUS_TERMINAL and finish_ledger_terminal(text):
            findings.append(
                {
                    "code": "finish_without_terminal_status",
                    "path": str(path),
                    "detail": (
                        f"## Finish records a terminal event (merge or cancel) "
                        f"but status is {st!r}; a Finish ledger with a `merged:` "
                        "or `issue #N closed:` stamp requires terminal status "
                        "(finish-ledger stamps `closed`)"
                    ),
                }
            )

        # covers vs Spec Acceptance (spec row from the binder card only)
        sm = SPEC_REF_RE.search(first_table_block(text))
        if sm:
            sid = sm.group(1)
            covers = binder_covers(text)
            accept = spec_accept.get(sid)
            if accept is not None and covers:
                missing = sorted(covers - accept, key=lambda x: int(x[1:]))
                if missing:
                    findings.append(
                        {
                            "code": "covers_not_on_spec",
                            "path": str(path),
                            "detail": f"{tid} covers {missing} but {sid} Acceptance lacks them",
                        }
                    )
            # one-sided: active ticket claims Spec but Spec.tickets omits ticket.
            # Active = legacy open + any working FSM state; terminal binders are
            # historical ledger and stay exempt, as does the archive.
            under_archive = "tickets/archive" in path.as_posix()
            if (
                not under_archive
                and st in (STATUS_LEGACY | STATUS_WORKING)
                and sid in spec_tickets
                and tid
                and tid not in spec_tickets[sid]
            ):
                findings.append(
                    {
                        "code": "onesided_spec_ticket_edge",
                        "path": str(path),
                        "detail": f"{tid} references {sid} but {sid}.tickets does not list {tid}",
                    }
                )

    # Feature map (spc-104 A1): when `.lattice/feature-map.md` exists, its rows
    # must be well-formed and use the status vocabulary. Unknown status = error
    # (same posture as invalid_ticket_status); malformed row = warning (lazy
    # migration precedent). Template:
    # skills/_lattice-lib/references/templates/feature-map.md
    fmap = home / "feature-map.md"
    if fmap.is_file():
        FMAP_STATUS_OK = {"untested", "pass", "fail", "blocked"}
        for lineno, line in enumerate(load_text(fmap).splitlines(), 1):
            if not line.startswith("| ftr-"):
                continue
            cells = [c.strip() for c in line.strip().strip("|").split("|")]
            if len(cells) != 9 or not cells[3]:
                findings.append(
                    {
                        "code": "feature_map_row_format",
                        "level": "warning",
                        "path": str(fmap),
                        "detail": (
                            f"line {lineno}: row needs 9 cells "
                            "(id|feature|entry|oracle|mutations|risk|story|last-verified|status) "
                            "with a non-empty oracle"
                        ),
                    }
                )
                continue
            st_cell = re.sub(r"\s*\(.*\)$", "", cells[8]).strip()
            if st_cell not in FMAP_STATUS_OK:
                findings.append(
                    {
                        "code": "feature_map_status",
                        "path": str(fmap),
                        "detail": (
                            f"line {lineno}: status {cells[8]!r} not in "
                            f"{sorted(FMAP_STATUS_OK)} (parenthetical qualifier allowed)"
                        ),
                    }
                )

    # One binder directory per ticket id: `tkt-N` is the lineage key, so two
    # dirs sharing it fork the chain (tkt-90; the historical tkt-35 collision
    # went unnoticed for four rounds without this check).
    for dup_tid, dup_paths in sorted(ticket_dirs_by_id.items()):
        if len(dup_paths) > 1:
            dirs = ", ".join(sorted(p.parent.name for p in dup_paths))
            findings.append(
                {
                    "code": "duplicate_ticket_id",
                    "path": str(dup_paths[0]),
                    "detail": f"{dup_tid} is claimed by {len(dup_paths)} binder dirs: {dirs}",
                }
            )

    return findings


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--home",
        action="append",
        dest="homes",
        help="Lattice home (.lattice). Repeatable. Default: <repo>/.lattice",
    )
    parser.add_argument("--json", action="store_true", help="JSON findings on stdout")
    parser.add_argument(
        "--root",
        default=None,
        help="Repo root for default home (default: cwd show-toplevel or .)",
    )
    args = parser.parse_args(argv)

    root = Path(args.root).resolve() if args.root else Path.cwd()
    homes = [Path(h).resolve() for h in (args.homes or [])]
    if not homes:
        homes = [root / ".lattice"]

    all_findings: list[dict[str, str]] = []
    for home in homes:
        if not home.is_dir():
            print(f"Error: lattice home not found: {home}", file=sys.stderr)
            return 2
        all_findings.extend(validate_home(home))

    # Stable order
    all_findings.sort(key=lambda f: (f.get("code", ""), f.get("path", ""), f.get("detail", "")))

    # Warnings surface but never fail the run (lazy migration).
    errors = [f for f in all_findings if f.get("level", "error") != "warning"]
    warnings = [f for f in all_findings if f.get("level", "error") == "warning"]

    if args.json:
        print(
            json.dumps(
                {
                    "ok": not errors,
                    "count": len(errors),
                    "warning_count": len(warnings),
                    "findings": all_findings,
                },
                indent=2,
            )
        )
    else:
        if not errors:
            suffix = f" ({len(warnings)} warning(s))" if warnings else ""
            print(f"validate-lattice-artifacts: OK{suffix}")
        else:
            print(f"validate-lattice-artifacts: FAILED ({len(errors)} finding(s), {len(warnings)} warning(s))")
        for f in all_findings:
            level = f.get("level", "error")
            prefix = "warn " if level == "warning" else ""
            print(f"  [{prefix}{f['code']}] {f['path']}: {f['detail']}")

    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
