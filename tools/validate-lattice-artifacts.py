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

spc-254 A7/A8 additions: evidence proof for `pass` feature-map rows
(story header + result JSON; error-level), done-Spec PR-union check
(warning-level during the D3 migration window), and a one-way warning
baseline ratchet (`tools/.validator-warning-baseline.txt`; only-new
warnings fail CI separately).
"""

from __future__ import annotations

import argparse
import json
import os
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

# --- Vendored transition schema (spc-254 A3 / D2; mirror of
# skills/_lattice-lib/scripts/lib/transition_table.py LEGAL_EDGES). This file
# stays dependency-free so consumer repos can vendor the validator alone; a
# bats test (tools/tests/transition-parity.bats) asserts the two stay
# parity-equal. The lib is canonical -- edit there, then mirror here.
# Each entry is (from, to); there is NO wildcard source (spc-337 A2 removed
# `any -> closed`). An absent (from, to) pair is an illegal edge (e.g. direct
# rework -> pr-open, which must go rework -> in-progress -> pr-open).
LEGAL_TRANSITIONS: set[tuple[str, str]] = {
    ("init", "queued"), ("queued", "in-progress"), ("queued", "pr-open"),
    ("queued", "deferred"), ("in-progress", "deferred"), ("deferred", "queued"),
    ("deferred", "deferred"),
    ("in-progress", "pr-open"), ("in-progress", "parked"),
    ("in-progress", "stuck"), ("parked", "queued"), ("stuck", "queued"),
    ("pr-open", "rework"), ("rework", "in-progress"),
    ("pr-open", "pr-open"), ("pr-open", "closed"),
    # Explicit terminal edges (spc-337 A2 / ADR-012 sec.3): no wildcard source.
    ("queued", "closed"), ("in-progress", "closed"), ("parked", "closed"),
    ("stuck", "closed"), ("rework", "closed"), ("deferred", "closed"),
    ("open", "closed"),  # legacy coarse status, lazy migration
    # Side-state guard (ADR-007 sec.5b): legal ONLY with operator override.
    # All four SIDE_STATES get an escape edge (review F1): omitting
    # rework/deferred left --force-side-state flips on them undetected.
    ("parked", "pr-open"), ("stuck", "pr-open"),
    ("rework", "pr-open"), ("deferred", "pr-open"),
}
# Edges legal ONLY via an operator-adjudicated --force-side-state --reason
# escape; the ledger entry must carry force_side_state_reason.
ESCAPE_REQUIRED: set[tuple[str, str]] = {
    ("parked", "pr-open"), ("stuck", "pr-open"),
    ("rework", "pr-open"), ("deferred", "pr-open"),
}
# Vendored FULL edge contract (spc-270 A1.5): the ADR-007 five-piece shape
# (from/to/owner/guard/reason/escape/trace/metric/escape_required) mirrored
# field-for-field from lib/transition_table.py LEGAL_EDGES. LEGAL_TRANSITIONS
# and ESCAPE_REQUIRED above are the (from,to) + escape-flag projections of THIS
# table; the bats parity test (tools/tests/transition-parity.bats) asserts the
# full table stays field-equal with the lib so owner/guard/reason/escape/trace/
# metric cannot drift silently. Field order matches the lib's Transition
# NamedTuple. The lib is canonical -- edit there, then mirror here.
LEGAL_EDGES_FULL: tuple[tuple, ...] = (
    ("init", "queued", "system",
     None, "ticket created via create-tickets",
     None, "binder created", "ticket-count", False),
    ("queued", "in-progress", "system",
     "start-work bind / batch-work spawn", "spawn",
     None, "status stamp", "water-level", False),
    ("queued", "pr-open", "agent",
     "queued only (DIRECT_JUMP_SOURCES); WARN-journaled",
     "trivial direct PR (jump over in-progress)",
     None, "WARN journal entry", "direct-jumps", False),
    ("queued", "deferred", "system|human",
     "fuse-halt | blocked-by-failure | deliberate deschedule",
     "deschedule at trip time",
     None, "deferred + wait_reason stamp", "deferred-count", False),
    ("in-progress", "deferred", "system|human",
     "spec-supersede trip-time sweep | fuse-halt | deliberate deschedule",
     "deschedule at trip time (in-flight work obsoleted)",
     None, "deferred + wait_reason stamp", "deferred-count", False),
    # A deferred binder re-stamped by a spec-supersede sweep (its wait_reason
    # flips to spec-superseded, superseding the prior reason) is a reason-change
    # self-loop, analogous to the pr-open -> pr-open rebase-void self-loop.
    ("deferred", "deferred", "system",
     "spec-supersede re-stamp: wait_reason superseded (reason change)",
     "reason-supersede",
     None, "wait_reason rewrite + journal", "deferred-reason-change", False),
    ("deferred", "queued", "human",
     "re-scheduled into a later batch", "reschedule",
     None, "status flip", None, False),
    ("in-progress", "pr-open", "agent",
     "create-pr opens the PR", "open PR",
     None, "pr-open stamp", "pr-open-count", False),
    ("in-progress", "parked", "agent",
     "irreversible / cross-contract decision", "park & pivot",
     None, "park stamp", "parked-count", False),
    ("in-progress", "stuck", "agent|system",
     "fallback bounds hit OR watchdog-timeout/abandonment; "
     "wait_reason stamped (unblock | re-scope)",
     "block",
     None, "stuck + wait_reason stamp", "stuck-count", False),
    ("parked", "queued", "human",
     "ratify.sh single-commit (journal + flip)", "decision ratification",
     None, "journal entry + status flip", "ratify-count", False),
    ("stuck", "queued", "human",
     "wait_reason: unblock (answer/env fix) | re-scope (after Spec revision)",
     "unblock",
     None, "status flip", "unblock-count", False),
    ("pr-open", "rework", "system",
     "PR returned with findings; bump-fix-cycle stamps rework + fix_cycles",
     "review-hold",
     "--extend-budget --reason (one more cycle, operator-adjudicated)",
     "rework + fix_cycles stamp", "fix-cycles", False),
    ("rework", "in-progress", "system",
     "re-enter queue; fix_cycles stamps the round (cap <=2)",
     "requeue after fix",
     None, "status flip", "fix-cycles", False),
    ("pr-open", "pr-open", "system",
     "materially changed rebase -> verdict voided; clean rebase carries verdict",
     "rebase-void",
     None, "re-review trace", "re-review-count", False),
    ("pr-open", "closed", "human",
     "merge — day only; .batch-work-active marker gate | close without merge (cancel)",
     "merge|cancel",
     None, "Finish ledger mergedAt (no mergedAt on cancel)", "merge-count", False),
    # Explicit terminal edges (spc-337 A2 / ADR-012 sec.3) — mirror of the lib.
    ("queued", "closed", "human",
     "merge observed from queued (direct jump; stamps skipped) | cancel",
     "merge|cancel",
     None, "Finish ledger (+anomaly on direct-jump merge)", "direct-jump", False),
    ("in-progress", "closed", "human",
     "merge observed from in-progress (direct jump; pr-open skipped) | cancel",
     "merge|cancel",
     None, "Finish ledger (+anomaly on direct-jump merge)", "direct-jump", False),
    ("parked", "closed", "human",
     "cancel (finish-ledger --cancel --reason) | merge anomaly from side state",
     "cancel",
     None, "Finish ledger (no mergedAt on cancel; anomaly on merge)", "cancel-count", False),
    ("stuck", "closed", "human",
     "cancel (finish-ledger --cancel --reason) | merge anomaly from side state",
     "cancel",
     None, "Finish ledger (no mergedAt on cancel; anomaly on merge)", "cancel-count", False),
    ("rework", "closed", "human",
     "cancel (finish-ledger --cancel --reason) | merge anomaly from side state",
     "cancel",
     None, "Finish ledger (no mergedAt on cancel; anomaly on merge)", "cancel-count", False),
    ("deferred", "closed", "human",
     "cancel (finish-ledger --cancel --reason) | merge anomaly from side state",
     "cancel",
     None, "Finish ledger (no mergedAt on cancel; anomaly on merge)", "cancel-count", False),
    ("open", "closed", "human",
     "legacy coarse status (lazy migration): merge | cancel",
     "merge|cancel",
     None, "Finish ledger", "legacy-close", False),
    ("parked", "pr-open", "agent",
     "ILLEGAL unless --force-side-state --reason (operator-adjudicated)",
     "force-side-state crossing",
     "--force-side-state --reason", "operator-adjudicated trace",
     "side-state-crossings", True),
    ("stuck", "pr-open", "agent",
     "ILLEGAL unless --force-side-state --reason (operator-adjudicated)",
     "force-side-state crossing",
     "--force-side-state --reason", "operator-adjudicated trace",
     "side-state-crossings", True),
    ("rework", "pr-open", "agent",
     "ILLEGAL unless --force-side-state --reason (operator-adjudicated); "
     "normal path is rework -> in-progress -> pr-open",
     "force-side-state crossing",
     "--force-side-state --reason", "operator-adjudicated trace",
     "side-state-crossings", True),
    ("deferred", "pr-open", "agent",
     "ILLEGAL unless --force-side-state --reason (operator-adjudicated)",
     "force-side-state crossing",
     "--force-side-state --reason", "operator-adjudicated trace",
     "side-state-crossings", True),
)
TRANSITION_LEDGER_DIR = ".transition-ledger"
# spc-337 A1 / ADR-012 sec.4: terminal binders created on/after this instant
# must carry a transition ledger (error); earlier binders warn (baselined).
LEDGER_COVERAGE_CUTOFF = "2026-09-02T00:00:00Z"
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

# --- Evidence proof (spc-254 A7 / F6): story-header + result-JSON schema. ---
# A `pass` feature-map row must prove its story file exists, the story
# header's oracle/mutations are consistent with the row, and a `status=pass`
# result JSON exists. A destructive story needs an authorization trace. The
# story header is a fenced yaml block at the top of the story file
# (skills/run-e2e/SKILL.md "Story traceability header"); the result JSON is
# the run-e2e "Structured output" object saved as a sibling `.result.json`.
# Error-level: A7 says a `pass` row with no proof "fails the validator".
# First fenced ```yaml block at the top of the story file.
STORY_HEADER_RE = re.compile(r"^\s*```ya?ml\s*\n(.*?)\n\s*```", re.S | re.M)
STORY_HEADER_KEY_RE = re.compile(r"^([a-z_]+):\s*(.+?)\s*$", re.M | re.I)
# Story cell placeholder: em dash, "(none…)", or empty.
STORY_PLACEHOLDER_RE = re.compile(r"^(?:—|–|-|\(none.*\)|)$", re.I)
# Spec front-matter `prs:` row (spc-254 A7 done-Spec PR union).
SPEC_FM_PRS_RE = re.compile(r"^prs:\s*(\[.*\])\s*$", re.M)

# spc-270 A5.2: a pass result is fresh if last-verified is within this window.
EVIDENCE_FRESHNESS_DAYS = int(os.environ.get("LATTICE_EVIDENCE_FRESHNESS_DAYS", "30"))


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


def binder_for_ticket_id(home: Path, ticket: str) -> Path | None:
    """Resolve a ticket's binder README from its id (spc-270 A1.4 snapshot
    check). Mirrors transition-api._binder_for_ticket: glob
    home/tickets/tkt-<id>-*/README.md (one match). Returns None when no binder
    exists — the snapshot check is then skipped (a ticket with a ledger but no
    binder is not, by itself, drift; the ledger still must be edge-legal)."""
    td = home / "tickets"
    if not td.is_dir():
        return None
    pat = re.compile(rf"^{re.escape(ticket)}-[^\s/]+$")
    matches = [d for d in td.iterdir() if d.is_dir() and pat.match(d.name)]
    if len(matches) != 1:
        return None
    b = matches[0] / "README.md"
    return b if b.is_file() else None


def iter_reviews(home: Path) -> list[Path]:
    d = home / "reviews"
    if not d.is_dir():
        return []
    return sorted(p for p in d.glob("rev-*.md") if p.is_file())


def parse_story_header(text: str) -> dict[str, str]:
    """Parse the fenced yaml traceability header at the top of a story file.

    Returns a dict of field -> value (inline ``# comments`` stripped). The
    header is a docs convention (skills/run-e2e/SKILL.md); fields: ``feature``,
    ``oracle``, ``mutations``, and optional ``authorization`` /
    ``console_allow`` / ``http_allow`` / ``origins_allow``. Returns ``{}`` when
    no fenced yaml block is present (spc-254 A7 evidence proof).
    """
    m = STORY_HEADER_RE.search(text)
    if not m:
        return {}
    data: dict[str, str] = {}
    for line in m.group(1).splitlines():
        km = STORY_HEADER_KEY_RE.match(line)
        if km:
            val = km.group(2).split("#", 1)[0].strip()
            data[km.group(1).lower()] = val
    return data


def resolve_story_path(home: Path, story_cell: str) -> Path | None:
    """Resolve a feature-map story cell to a file path under ``home``.

    The cell may be ``.lattice/e2e/stories/x.story.md``, ``stories/x.story.md``,
    ``x.story.md``, or a placeholder (``—`` / ``(none…)``). Returns the first
    existing path, else the first candidate (for "missing" error messages), or
    ``None`` when the cell is a placeholder. Tries ``home/e2e/stories/<base>``
    and ``home/stories/<base>`` for bare names.
    """
    raw = story_cell.strip()
    if STORY_PLACEHOLDER_RE.fullmatch(raw):
        return None
    cleaned = re.sub(r"^(\./)?\.lattice/", "", raw)
    candidates: list[Path] = [home / cleaned]
    if "/" not in cleaned and "\\" not in cleaned:
        candidates.append(home / "e2e" / "stories" / cleaned)
        candidates.append(home / "stories" / cleaned)
    for c in candidates:
        if c.is_file():
            return c
    return candidates[0]


def result_json_path(story_path: Path) -> Path:
    """Sibling ``.result.json`` for a story file (``x.story.md`` -> ``x.result.json``)."""
    name = story_path.name
    if name.endswith(".story.md"):
        return story_path.with_name(name[: -len(".story.md")] + ".result.json")
    return story_path.with_name(story_path.stem + ".result.json")


def spec_prs(text: str) -> set[str]:
    """``prs`` ids parsed from a Spec's front-matter ``prs:`` row."""
    fm = parse_front_matter(text)
    raw = fm.get("prs", "")
    return set(re.findall(r"pr-[1-9][0-9]*", raw))


def binder_prs(text: str) -> set[str]:
    """``prs`` ids parsed from a binder card's ``| prs |`` row."""
    m = PRS_TABLE_RE.search(first_table_block(text))
    if not m:
        return set()
    return set(re.findall(r"pr-[1-9][0-9]*", m.group(1)))


def _evidence_v1_findings(spath, rpath, rdata, fmap, lineno, row_id, cells, header, findings):
    """spc-270 A5 v1 evidence proof: identity binding, freshness, assertions,
    screenshots, mutation round-trip + leftovers. v1 only (v0 skips — A5.5)."""
    h_feature = header.get("feature", "").strip()
    h_story = header.get("story", "").strip()
    if not h_feature or not h_story:
        findings.append({"code": "evidence_v1_identity_missing", "path": str(spath),
            "detail": f"story {spath.name} v1 header must carry feature + story identity"})
    r_feature = str(rdata.get("feature_id", "")).strip()
    r_story = str(rdata.get("story_id", "")).strip()
    r_run = str(rdata.get("run_id", "")).strip()
    if not r_run:
        findings.append({"code": "evidence_v1_run_id_missing", "path": str(rpath),
            "detail": f"result JSON {rpath.name} v1 must carry run_id"})
    r_sv = str(rdata.get("schema_version", "")).strip()
    if not r_sv or r_sv.lower() == "null":
        findings.append({"code": "evidence_v1_result_schema_missing", "path": str(rpath),
            "detail": f"result JSON {rpath.name} v1 must carry schema_version (matches the story header)"})
    if h_feature and r_feature and h_feature.lower() != r_feature.lower():
        findings.append({"code": "evidence_v1_identity_mismatch", "path": str(rpath),
            "detail": f"result JSON feature_id {r_feature!r} != story header feature {h_feature!r}"})
    if h_story and r_story and h_story.lower() != r_story.lower():
        findings.append({"code": "evidence_v1_identity_mismatch", "path": str(rpath),
            "detail": f"result JSON story_id {r_story!r} != story header story {h_story!r}"})
    lv_cell = cells[7].strip() if len(cells) > 7 else ""
    lv_m = re.match(r"\d{4}-\d{2}-\d{2}", lv_cell)
    if lv_m and not STORY_PLACEHOLDER_RE.fullmatch(lv_cell):
        try:
            from datetime import datetime, timezone
            lv_dt = datetime.strptime(lv_m.group(0), "%Y-%m-%d").replace(tzinfo=timezone.utc)
            age = (datetime.now(timezone.utc) - lv_dt).days
            if age > EVIDENCE_FRESHNESS_DAYS:
                findings.append({"code": "evidence_stale_run", "path": str(fmap),
                    "detail": f"line {lineno}: pass row {row_id!r} last-verified {lv_m.group(0)} is {age}d old (> {EVIDENCE_FRESHNESS_DAYS}d) — re-run the story"})
        except ValueError:
            pass
    assertions = rdata.get("assertions")
    if not isinstance(assertions, list) or not assertions:
        findings.append({"code": "evidence_no_assertions", "path": str(rpath),
            "detail": f"result JSON {rpath.name} v1 must carry a non-empty assertions[] list"})
    else:
        failed = [a for a in assertions if not (a.get("pass") if isinstance(a, dict) else False)]
        if failed:
            findings.append({"code": "evidence_failed_assertion", "path": str(rpath),
                "detail": f"result JSON {rpath.name} has {len(failed)} failing assertion(s); pass requires all-passing"})
    screenshots = rdata.get("screenshots")
    if not isinstance(screenshots, list) or not screenshots:
        findings.append({"code": "evidence_no_screenshot", "path": str(rpath),
            "detail": f"result JSON {rpath.name} v1 must carry a non-empty screenshots[] list"})
    else:
        for sc in screenshots:
            if not (spath.parent / str(sc)).is_file():
                findings.append({"code": "evidence_screenshot_missing", "path": str(rpath),
                    "detail": f"screenshot {sc!r} (resolved {spath.parent / str(sc)}) does not exist"})
    row_mut = cells[4].strip().lower() if len(cells) > 4 else ""
    if row_mut in ("safe", "destructive"):
        mtype = header.get("mutation_type", "").strip().lower()
        if mtype == "round-trip" and not rdata.get("round_trip"):
            findings.append({"code": "evidence_round_trip_not_proven", "path": str(rpath),
                "detail": f"story {spath.name} declares mutation_type: round-trip but result has no round_trip: true"})
    leftovers = rdata.get("leftovers")
    if not isinstance(leftovers, list):
        findings.append({"code": "evidence_leftovers_undeclared", "path": str(rpath),
            "detail": f"result JSON {rpath.name} v1 must declare leftovers: [] as a list (even if empty; null/absent is not disclosure)"})


def _evidence_proof_findings(
    home: Path,
    fmap: Path,
    lineno: int,
    cells: list[str],
    findings: list[dict[str, str]],
) -> None:
    """Append evidence-proof findings for a `pass` feature-map row (A7).

    A `pass` row must prove: story path exists, story header oracle/mutations
    are consistent, a `status=pass` result JSON exists. A destructive story
    needs an authorization trace. Findings are error-level (A7: "fails the
    validator").
    """
    row_id = cells[0]
    story_cell = cells[6]
    row_mut = cells[4].strip().lower()
    row_oracle = cells[3].strip()
    # 1. story path present + file exists.
    if STORY_PLACEHOLDER_RE.fullmatch(story_cell):
        findings.append(
            {
                "code": "evidence_proof_no_story",
                "path": str(fmap),
                "detail": (
                    f"line {lineno}: pass row {row_id!r} has no story path — "
                    "a pass row must point to a story file "
                    "(skills/run-e2e/SKILL.md traceability header)"
                ),
            }
        )
        return
    spath = resolve_story_path(home, story_cell)
    if spath is None or not spath.is_file():
        findings.append(
            {
                "code": "evidence_proof_story_missing",
                "path": str(fmap),
                "detail": (
                    f"line {lineno}: pass row {row_id!r} story {story_cell!r} "
                    f"does not exist (resolved to {spath}); create the story "
                    "or revert the row to `untested`/`fail`"
                ),
            }
        )
        return
    # 2. story header parsed + fields consistent.
    header = parse_story_header(load_text(spath))
    h_mut = header.get("mutations", "").strip().lower()
    if not h_mut:
        findings.append(
            {
                "code": "evidence_proof_header_missing",
                "path": str(spath),
                "detail": (
                    f"story {spath.name} has no traceability header (fenced "
                    "yaml with feature/oracle/mutations); see "
                    "skills/run-e2e/SKILL.md"
                ),
            }
        )
        return
    if h_mut != row_mut:
        findings.append(
            {
                "code": "evidence_proof_mutations_mismatch",
                "path": str(spath),
                "detail": (
                    f"story {spath.name} header mutations {h_mut!r} != "
                    f"feature-map row mutations {row_mut!r}; the header "
                    "must equal the map row's mutations class"
                ),
            }
        )
    h_oracle = header.get("oracle", "").strip()
    if not h_oracle:
        findings.append(
            {
                "code": "evidence_proof_oracle_missing",
                "path": str(spath),
                "detail": (
                    f"story {spath.name} header has no oracle citation "
                    "(spc-N A* | README §x | generic invariants)"
                ),
            }
        )
    elif h_oracle.lower() not in row_oracle.lower():
        findings.append(
            {
                "code": "evidence_proof_oracle_mismatch",
                "path": str(spath),
                "detail": (
                    f"story {spath.name} header oracle {h_oracle!r} not "
                    f"found in feature-map row oracle {row_oracle!r}; the "
                    "citations must agree"
                ),
            }
        )
    # 3. destructive authorization trace.
    if row_mut == "destructive":
        h_auth = header.get("authorization", "").strip()
        if not h_auth:
            findings.append(
                {
                    "code": "evidence_proof_destructive_no_auth",
                    "path": str(spath),
                    "detail": (
                        f"story {spath.name} is destructive but the header "
                        "has no `authorization:` trace; destructive stories "
                        "require written operator authorization"
                    ),
                }
            )
    # 4. result JSON exists with status=pass.
    # A5.5 migration: v0 artifacts (no schema_version in the story header) get
    # a lazy-migration WARNING (not error) and skip the v1 identity/freshness/
    # assertion/screenshot/round-trip/leftovers checks. v1 artifacts carry
    # schema_version and get the full spc-270 A5 proof.
    schema_v = header.get("schema_version", "").strip()
    is_v1 = bool(schema_v) and schema_v.lower() != "null"
    if not is_v1:
        findings.append(
            {
                "code": "evidence_legacy_v0",
                "level": "warning",
                "path": str(spath),
                "detail": (
                    f"story {spath.name} has no schema_version — v0 evidence "
                    "(lazy migration; add schema_version: 1 + story/run identity "
                    "for the full spc-270 A5 proof)"
                ),
            }
        )
    rpath = result_json_path(spath)
    if not rpath.is_file():
        findings.append(
            {
                "code": "evidence_proof_no_result",
                "path": str(fmap),
                "detail": (
                    f"line {lineno}: pass row {row_id!r} has no result JSON "
                    f"at {rpath} — a pass row must have a `status: pass` "
                    "result JSON sibling (<story>.result.json)"
                ),
            }
        )
    else:
        try:
            rdata = json.loads(rpath.read_text(encoding="utf-8"))
            if str(rdata.get("status", "")).lower() != "pass":
                findings.append(
                    {
                        "code": "evidence_proof_result_not_pass",
                        "path": str(rpath),
                        "detail": (
                            f"result JSON {rpath.name} status is "
                            f"{rdata.get('status')!r}, not 'pass'"
                        ),
                    }
                )
            # --- spc-270 A5 v1 evidence proof (only when schema_version present) ---
            if is_v1:
                _evidence_v1_findings(
                    spath, rpath, rdata, fmap, lineno, row_id, cells, header, findings
                )
        except (json.JSONDecodeError, OSError) as exc:
            findings.append(
                {
                    "code": "evidence_proof_result_malformed",
                    "path": str(rpath),
                    "detail": f"result JSON {rpath.name} is malformed: {exc}",
                }
            )


def validate_home(home: Path) -> list[dict[str, str]]:
    findings: list[dict[str, str]] = []
    specs: dict[str, Path] = {}
    spec_tickets: dict[str, set[str]] = {}
    spec_accept: dict[str, set[str]] = {}
    spec_prs_map: dict[str, set[str]] = {}
    spec_status_map: dict[str, str | None] = {}
    ticket_prs: dict[str, set[str]] = {}

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
            spec_prs_map[check_id] = spec_prs(text)

        # tkt-151 A1/A2: Spec status vocabulary + terminal guards.
        sp_st = spec_status(text)
        if check_id:
            spec_status_map[check_id] = sp_st
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
            ticket_prs.setdefault(tid, set())
            ticket_prs[tid] |= binder_prs(text)
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
        # tkt-381: binder field-table data rows should not carry more cells
        # than the header declares. A stray extra column (e.g.
        # `| status | closed | 2026-… |` in a 2-column table) caused the
        # queue_health parser to read `closed | 2026-…` as the value (fixed
        # in the parser, but the row itself is drift — ADR-012 §7 front-matter
        # migration will re-row these). Warning-level: legacy binders with stray
        # columns are baselined, not re-rowed here. Escaped pipes (`\|`) in
        # values are not counted as column separators. Header and separator
        # rows are skipped by content, not index (tkt-381 review F5/F6).
        _tb_lines = _tb.splitlines()
        _declared_cols = 0
        if _tb_lines:
            # Header row: count all cells (including empty) between outer pipes.
            _hdr_raw = [c.strip() for c in re.split(r'(?<!\\)\|', _tb_lines[0].strip().strip("|"))]
            _declared_cols = len(_hdr_raw)
        for _row in _tb_lines:
            _cells_raw = [c.strip() for c in re.split(r'(?<!\\)\|', _row.strip().strip("|"))]
            # Skip separator rows (---|---) by content.
            if _cells_raw and all(re.fullmatch(r'-+:?', c) for c in _cells_raw if c):
                continue
            # Skip header rows by content (first cell is 'Field').
            if _cells_raw and _cells_raw[0].lower() == 'field':
                continue
            # Count ALL cells (including empty) vs declared column count.
            # Not filtering empty cells: `| wait_reason | | 2026-… |` has
            # 3 cells (empty value + stray column) — must be flagged (F5).
            if _declared_cols and len(_cells_raw) > _declared_cols:
                findings.append(
                    {
                        "code": "binder_row_extra_columns",
                        "level": "warning",
                        "path": str(path),
                        "detail": (
                            f"field-table row has a stray extra column: "
                            f"{_row.strip()!r} — table declares "
                            f"{_declared_cols} column(s); row has "
                            f"{len(_cells_raw)} (ADR-012 §7 front-matter migration)"
                        ),
                    }
                )
                break  # one warning per binder is enough for triage
        if st in STATUS_TERMINAL and not has_finish_ledger(text):
            findings.append(
                {
                    "code": "closed_without_finish",
                    "path": str(path),
                    "detail": f"status {st!r} but ## Finish ledger is missing or placeholder-only",
                }
            )
        # Ledger coverage (spc-337 A1 / ADR-012 sec.4): a terminal binder must
        # have a per-ticket transition ledger — otherwise the status flip was a
        # hand edit or a stamp whose ledger landed outside the repo (the cwd
        # bug fixed in spc-337). Binders created on/after the cutoff error;
        # legacy binders (created before it, or with no created row) warn and
        # sit in the ratchet baseline. Legacy slug-named ledger files
        # (`tkt-N-<slug>.jsonl`) count as coverage.
        if st in STATUS_TERMINAL:
            _tkt = re.match(r"^(tkt-\d+)", path.parent.name)
            if _tkt:
                _tid = _tkt.group(1)
                _ldir = home / TRANSITION_LEDGER_DIR
                _has_ledger = (_ldir / f"{_tid}.jsonl").is_file() or any(
                    _ldir.glob(f"{_tid}-*.jsonl")
                )
                if not _has_ledger:
                    _cm = CREATED_TABLE_RE.search(first_table_block(text))
                    _created = _cm.group(1).strip() if _cm else ""
                    _post_cutoff = bool(
                        BINDER_TS_RE.fullmatch(_created) and _created >= LEDGER_COVERAGE_CUTOFF
                    )
                    findings.append(
                        {
                            # Post-cutoff: hard error. Pre-cutoff / undated:
                            # `closed_without_ledger_legacy` — a lazy-migration
                            # warning class (ratchet-exempt like
                            # evidence_legacy_v0, and snapshotted in the
                            # baseline so the count can only shrink).
                            "code": "closed_without_ledger" if _post_cutoff else "closed_without_ledger_legacy",
                            "level": "error" if _post_cutoff else "warning",
                            "path": str(path),
                            "detail": (
                                f"status {st!r} but no transition ledger "
                                f"{TRANSITION_LEDGER_DIR}/{_tid}.jsonl "
                                f"(created {_created or 'unknown'}; "
                                f"{'post' if _post_cutoff else 'pre'}-cutoff "
                                f"{LEDGER_COVERAGE_CUTOFF}) — status flips go through "
                                "transition-api.py commit (ADR-012 sec.1); legacy "
                                "binders are baselined, never hand-rewritten"
                            ),
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

    # Done-Spec PR union (spc-254 A7 / F6): a `done` Spec's front-matter
    # `prs` must contain the union of its child binders' prs rows. Warning-
    # level during the D3 migration window (new check; ratcheted via the
    # warning baseline so only-new warnings fail CI). Backfilling the spec
    # prs row from the child binders makes a done Spec clean.
    for sid, sp_st in spec_status_map.items():
        if sp_st != "done" or sid not in specs:
            continue
        child_prs: set[str] = set()
        for tid in spec_tickets.get(sid, set()):
            child_prs |= ticket_prs.get(tid, set())
        spec_p = spec_prs_map.get(sid, set())
        missing = child_prs - spec_p
        if missing:
            spec_path = specs[sid]
            findings.append(
                {
                    "code": "spec_prs_missing_child_union",
                    "level": "warning",
                    "path": str(spec_path.relative_to(home.parent)) if home.parent in spec_path.parents else str(spec_path),
                    "detail": (
                        f"status is done but prs {sorted(spec_p, key=lambda p: int(p[3:]))} "
                        f"omits child binder PR union {sorted(child_prs, key=lambda p: int(p[3:]))} "
                        f"(missing: {sorted(missing, key=lambda p: int(p[3:]))}); "
                        "backfill the spec front-matter `prs:` row from the child binders"
                    ),
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
            # Evidence proof (spc-254 A7 / F6): a `pass` row must prove its
            # story file exists, the story header's oracle/mutations are
            # consistent with the row, and a `status=pass` result JSON
            # exists. A destructive story needs an authorization trace.
            # Error-level: A7 says a `pass` row with no proof "fails the
            # validator". Only `pass` rows are proof-gated; `fail`/`blocked`/
            # `untested` carry no proof obligation.
            if st_cell == "pass":
                _evidence_proof_findings(home, fmap, lineno, cells, findings)

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

    # Transition ledger replay (spc-254 A3 / spc-270 A1.4). The transition API
    # (skills/_lattice-lib/scripts/transition-api.py) appends a JSONL entry per
    # status flip; the validator replays it and rejects an illegal edge between
    # two legal snapshots -- the gap docs/workflow-fsm.md sec.5 explicitly left
    # open. Per-ticket files under home/.transition-ledger/ are COMMITTED
    # (review F2) so CI accumulates real history and enforces edge legality for
    # real. Missing dir = nothing to replay (not an error).
    #
    # spc-270 A1.4/A1.5: replay now enforces the three continuity invariants the
    # append-only `record` primitive left to trust (mirroring transition-api
    # replay-ledger): identity (entry ticket == ledger file ticket), continuity
    # (entry.from == prior entry.to), and snapshot (the ledger's final `to` ==
    # the binder's current `status`). This is the check that catches the
    # finish-ledger close-without-ledger-entry drift class in CI. The 6 dev-base
    # drift cases (tkt-256/261/284/285/286/287) were backfilled with their
    # missing pr-open→closed entry so CI stays green going forward.
    ledger_dir = home / TRANSITION_LEDGER_DIR
    if ledger_dir.is_dir():
        for ledger in sorted(ledger_dir.glob("*.jsonl")):
            file_ticket = ledger.stem  # full stem (tkt-N or tkt-N-<slug>)
            # tkt-363: slug-named ledgers (tkt-N-<slug>.jsonl) must still
            # resolve their binder. Derive the ticket id (tkt-N) from the
            # stem so the binder glob `tkt-N-*` matches; the full stem is
            # kept for the identity check.
            id_match = re.match(r'^(tkt-\d+|spc-\d+)', ledger.stem)
            ticket_id = id_match.group(1) if id_match else ledger.stem
            prev_to: str | None = None
            last_to: str | None = None
            for lineno, line in enumerate(
                ledger.read_text(encoding="utf-8").splitlines(), 1
            ):
                line = line.strip()
                if not line:
                    continue
                try:
                    entry = json.loads(line)
                except json.JSONDecodeError as exc:
                    findings.append(
                        {
                            "code": "transition_ledger_malformed",
                            "path": str(ledger),
                            "detail": f"line {lineno}: malformed JSON: {exc}",
                        }
                    )
                    continue
                frm = str(entry.get("from", ""))
                to = str(entry.get("to", ""))
                eticket = str(entry.get("ticket", ""))
                # Identity: the entry must belong to this ledger's ticket.
                if eticket and eticket != file_ticket:
                    findings.append(
                        {
                            "code": "transition_ledger_identity_mismatch",
                            "path": str(ledger),
                            "detail": (
                                f"line {lineno}: identity mismatch: entry ticket "
                                f"{eticket!r} != ledger {file_ticket!r}"
                            ),
                        }
                    )
                # no wildcard source (spc-337 A2): the pair itself must be listed
                pair_legal = (frm, to) in LEGAL_TRANSITIONS
                if not pair_legal:
                    findings.append(
                        {
                            "code": "illegal_transition_edge",
                            "path": str(ledger),
                            "detail": (
                                f"line {lineno}: illegal edge {frm!r} -> "
                                f"{to!r} (ticket {eticket or '?'})"
                                f"; not in transition schema"
                            ),
                        }
                    )
                    prev_to = to
                    last_to = to
                    continue
                if (frm, to) in ESCAPE_REQUIRED and not entry.get(
                    "force_side_state_reason"
                ):
                    findings.append(
                        {
                            "code": "illegal_transition_edge",
                            "path": str(ledger),
                            "detail": (
                                f"line {lineno}: edge {frm!r} -> {to!r} "
                                f"(ticket {eticket or '?'}) requires"
                                f" an operator-adjudicated --force-side-state-"
                                f"reason (side-state guard; no agent self-"
                                f"adjudication)"
                            ),
                        }
                    )
                # Continuity: each entry's `from` must equal the prior `to`.
                if prev_to is not None and frm != prev_to:
                    findings.append(
                        {
                            "code": "transition_ledger_discontinuity",
                            "path": str(ledger),
                            "detail": (
                                f"line {lineno}: discontinuity: entry from="
                                f"{frm!r} but prior to={prev_to!r}"
                            ),
                        }
                    )
                prev_to = to
                last_to = to
            # Final snapshot: the ledger's last `to` must equal the binder status.
            if last_to is not None:
                binder = binder_for_ticket_id(home, ticket_id)
                if binder is not None:
                    bstatus = ticket_status(binder.read_text(encoding="utf-8"))
                    if bstatus is not None and bstatus != last_to:
                        findings.append(
                            {
                                "code": "transition_ledger_snapshot_mismatch",
                                "path": str(ledger),
                                "detail": (
                                    f"snapshot mismatch: ledger final to="
                                    f"{last_to!r} but binder status="
                                    f"{bstatus!r}"
                                ),
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
    parser.add_argument(
        "--migration-version",
        default="1",
        help="spc-270 A6.4 migration version; warnings scheduled to error at "
        "<= this version (tools/.warning-migration-schedule.txt) become errors.",
    )
    parser.add_argument(
        "--baseline",
        default=None,
        help=(
            "Warning-baseline file (one 'code\\tpath' per line; # comments "
            "allowed). Warnings whose signature is not in the baseline fail "
            "the run (one-way ratchet; spc-254 A8/D3). Default: "
            "<validator_dir>/.validator-warning-baseline.txt when --home is "
            "not passed; off when --home is custom."
        ),
    )
    args = parser.parse_args(argv)

    root = Path(args.root).resolve() if args.root else Path.cwd()
    homes = [Path(h).resolve() for h in (args.homes or [])]
    default_home_used = not args.homes
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

    # Warnings surface but never fail the run (lazy migration) — UNLESS the
    # warning is new relative to the baseline ratchet (spc-254 A8/D3). The
    # baseline is a one-way ratchet (only-decrease): warnings present in the
    # baseline stay non-fatal; warnings NOT in the baseline fail CI
    # separately. Auto-active for the default home (repo .lattice) so CI
    # (which runs the validator with no --home) gets the ratchet for free;
    # off for custom --home (fixture tests) unless --baseline is explicit.
    baseline_path = Path(args.baseline) if args.baseline else None
    if baseline_path is None and default_home_used:
        baseline_path = Path(__file__).resolve().parent / ".validator-warning-baseline.txt"
    baseline_sigs: set[str] = set()
    baseline_corrupt = False
    # spc-270 A6.1: baseline entries are 2-column (code\tpath → legacy wildcard
    # occurrence_key="*") or 3-column (code\tpath\toccurrence_key). A 2-column
    # entry matches ANY occurrence of that code+path (preserves existing debt).
    if baseline_path is not None and baseline_path.is_file():
        for line in baseline_path.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            parts = line.split("\t")
            if len(parts) == 2:
                baseline_sigs.add(f"{parts[0]}\t{parts[1]}\t*")  # legacy wildcard
            elif len(parts) >= 3:
                baseline_sigs.add(f"{parts[0]}\t{parts[1]}\t{parts[2]}")
            else:
                baseline_corrupt = True  # malformed entry (A6.2 fail-closed)
    elif baseline_path is not None and not baseline_path.is_file():
        baseline_corrupt = True  # baseline configured but missing (A6.2)

    def _occurrence_key(f: dict[str, str]) -> str:
        # spc-270 A6.1: same-code+path findings stay DISTINCT by their detail
        # (incl. line number — two malformed rows at line 5 vs 6 are distinct
        # occurrences; stripping the line number collapsed them, defeating A6.1).
        # Truncate only for baseline-file readability; the discriminator is kept.
        return f.get("detail", "")[:80]

    def _sig(f: dict[str, str]) -> str:
        # Normalize to repo-root-relative so the baseline is portable across
        # checkouts (CI vs local). Falls back to the raw path when the finding
        # path is not under the repo root (e.g. an absolute path outside it).
        p = f.get("path", "")
        try:
            p = str(Path(p).resolve().relative_to(root))
        except (ValueError, TypeError):
            pass
        # A6.1: 3-column signature (code, path, occurrence_key). 2-column legacy
        # baseline entries get occurrence_key="*" (wildcard — match any occurrence).
        return f"{f.get('code', '')}\t{p}\t{_occurrence_key(f)}"

    # spc-270 A6.4: versioned warning→error migration runs BEFORE the ratchet
    # computation so migrated warnings are NOT double-counted (they leave the
    # warnings list + join errors; new_warnings only sees unmigrated warnings).
    try:
        mig_ver = int(getattr(args, "migration_version", "1") or "1")
    except (ValueError, TypeError):
        print("Error: --migration-version must be an integer", file=sys.stderr)
        return 2
    mig_path = Path(__file__).resolve().parent / ".warning-migration-schedule.txt"
    mig_schedule: dict[str, int] = {}
    if mig_path.is_file():
        for line in mig_path.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            parts = line.split("\t")
            if len(parts) == 2:
                try:
                    mig_schedule[parts[0]] = int(parts[1])
                except ValueError:
                    pass
    migrated = [f for f in all_findings if mig_schedule.get(f.get("code", ""), 999) <= mig_ver]
    for w in migrated:
        w["level"] = "error"
        w["migrated_from_warning"] = True
    errors = [f for f in all_findings if f.get("level", "error") != "warning"]
    warnings = [f for f in all_findings if f.get("level", "error") == "warning"]
    # spc-270 A5.5: evidence_legacy_v0 is a lazy-migration warning (v0 artifacts
    # accepted during the v0→v1 transition) — never ratcheted fatal, so the
    # first v0 pass row in .lattice does not break CI. Exempt it only when a
    # baseline is present (ratchet mode); no baseline ⇒ no ratchet (else []).
    # spc-337 A1 / D4: closed_without_ledger_legacy marks terminal binders
    # that predate the ledger contract (created before LEDGER_COVERAGE_CUTOFF
    # or undated). They are baselined for the record but ratchet-exempt: the
    # PR-vs-base-baseline comparison (artifacts.yml, spc-270 A6.3) would
    # otherwise refuse the very PR that introduces the check. Lifting the
    # exemption is the documented migration step (.warning-migration-schedule).
    RATCHET_EXEMPT_CODES = {"evidence_legacy_v0", "closed_without_ledger_legacy"}

    def _is_baselined(w: dict[str, str]) -> bool:
        # A6.1: a warning is baselined if its exact 3-col sig matches OR the
        # legacy 2-col wildcard (code\tpath\*) matches (preserves existing debt).
        sig = _sig(w)
        if sig in baseline_sigs:
            return True
        p = sig.rsplit("\t", 1)[0]  # code\tpath
        return f"{p}\t*" in baseline_sigs

    new_warnings = (
        [w for w in warnings if not _is_baselined(w) and w.get("code", "") not in RATCHET_EXEMPT_CODES]
        if baseline_sigs
        else []
    )
    new_sigs = {_sig(w) for w in new_warnings}
    # spc-270 A6.2: a corrupt/missing baseline (when ratchet is active — i.e. a
    # baseline path was resolved) fails closed rather than silently passing.
    ratchet_fail = bool(new_warnings) or (baseline_corrupt and baseline_path is not None)

    if args.json:
        print(
            json.dumps(
                {
                    "ok": not errors and not ratchet_fail,
                    "count": len(errors),
                    "warning_count": len(warnings),
                    "new_warning_count": len(new_warnings),
                    "ratchet_new_warnings": new_warnings,
                    "findings": all_findings,
                },
                indent=2,
            )
        )
    else:
        if not errors and not ratchet_fail:
            bits = []
            if warnings:
                bits.append(f"{len(warnings)} warning(s)")
            if new_warnings:
                bits.append(f"{len(new_warnings)} new warning(s) (ratchet)")
            suffix = f" ({', '.join(bits)})" if bits else ""
            print(f"validate-lattice-artifacts: OK{suffix}")
        else:
            parts = [f"{len(errors)} finding(s)"]
            if ratchet_fail:
                parts.append(f"{len(new_warnings)} new warning(s) (ratchet)")
            baselined = len(warnings) - len(new_warnings)
            parts.append(f"{baselined} baselined warning(s)")
            print(f"validate-lattice-artifacts: FAILED (" + ", ".join(parts) + ")")
        for f in all_findings:
            level = f.get("level", "error")
            if level == "warning":
                tag = "NEW warn " if _sig(f) in new_sigs else "warn "
            else:
                tag = ""
            print(f"  [{tag}{f['code']}] {f['path']}: {f['detail']}")

    return 1 if (errors or ratchet_fail) else 0


if __name__ == "__main__":
    raise SystemExit(main())
