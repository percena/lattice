"""Machine-readable transition schema — the source of truth for legal ticket
binder status transitions (spc-254 A3 / D2; rev-20260830-141357Z F3).

`status_vocab.py` owns the status *enum* + coupled-field policy; this module
owns the legal *edges* between those statuses (the `from/to/owner/guard/
reason/escape/trace/metric` table that `docs/workflow-fsm.md` §2 M2 describes
in prose). Per Decision D2, this schema is the SoT — the markdown FSM must
stay parity-equal (a bats test fails CI on drift), and the validator replays
the transition ledger against this table to reject an illegal edge between
two legal snapshots (the gap `docs/workflow-fsm.md` §5 explicitly left open).

Scope of this slice: M2 execution transitions (ticket binder `status`
flips performed by the three writers — reconcile-state.sh, finish-ledger.sh,
stamp-pr-open.sh). M1 planning and M3 knowledge transitions are documented in
`docs/workflow-fsm.md` but are not status-level edges the validator replays;
they remain prose for now. Illegal edges (e.g. direct `rework → pr-open`,
which must go `rework → in-progress → pr-open`) are simply *absent* from
`LEGAL_EDGES` — the validator flags any ledger (from, to) pair not present.

Each edge carries the ADR-007 five-piece contract shape:
  from   — source status ("init" for creation; no wildcard sources — spc-337 A2)
  to     — target status
  owner  — human | agent | system (who fires it)
  guard  — condition that must hold (the red line; None = none)
  reason — trigger description
  escape — operator-adjudicated override that lifts the guard (None = none)
  trace  — the durable artifact the flip journals (binder/ledger entry)
  metric — what is counted (None = not counted)
"""

from __future__ import annotations

from typing import NamedTuple, Optional, Tuple


class Transition(NamedTuple):
    from_: str          # "init" / a status value (no wildcard sources)
    to: str             # target status value
    owner: str          # human | agent | system (| for shared)
    guard: Optional[str]
    reason: str
    escape: Optional[str]
    trace: Optional[str]
    metric: Optional[str]
    # Structured flag (review F5): True when the edge is legal ONLY via an
    # operator-adjudicated escape (side-state guard). Discriminating on this
    # flag — not on substring prose in `guard` — keeps control flow robust
    # to rephrasing.
    escape_required: bool = False


# M2 execution — legal ticket binder status transitions.
# Mirror of docs/workflow-fsm.md §2 "M2 execution" table. The bats parity test
# (tests/transition-parity.bats) asserts the two stay in sync.
LEGAL_EDGES: Tuple[Transition, ...] = (
    Transition("init", "queued", "system",
               None, "ticket created via create-tickets",
               None, "binder created", "ticket-count"),
    Transition("queued", "in-progress", "system",
               "start-work bind / batch-work spawn", "spawn",
               None, "status stamp", "water-level"),
    Transition("queued", "pr-open", "agent",
               "queued only (DIRECT_JUMP_SOURCES); WARN-journaled",
               "trivial direct PR (jump over in-progress)",
               None, "WARN journal entry", "direct-jumps"),
    Transition("queued", "deferred", "system|human",
               "fuse-halt | blocked-by-failure | budget-exhausted | deliberate deschedule",
               "deschedule at trip time",
               None, "deferred + wait_reason stamp", "deferred-count"),
    Transition("in-progress", "deferred", "system|human",
               "spec-supersede trip-time sweep | fuse-halt | deliberate deschedule",
               "deschedule at trip time (in-flight work obsoleted)",
               None, "deferred + wait_reason stamp", "deferred-count"),
    # A deferred binder re-stamped by a spec-supersede sweep (its wait_reason
    # flips to spec-superseded, superseding the prior reason) is a reason-change
    # self-loop, analogous to the pr-open → pr-open rebase-void self-loop: the
    # status does not change but the coupled wait_reason does, and the ledger
    # records the reason supersede (spc-270 A1.3 routes spec-supersede through
    # commit, so the edge must be legal).
    Transition("deferred", "deferred", "system",
               "spec-supersede re-stamp: wait_reason superseded (reason change)",
               "reason-supersede",
               None, "wait_reason rewrite + journal", "deferred-reason-change"),
    Transition("deferred", "queued", "human",
               "re-scheduled into a later batch", "reschedule",
               None, "status flip", None),
    Transition("in-progress", "pr-open", "agent",
               "create-pr opens the PR", "open PR",
               None, "pr-open stamp", "pr-open-count"),
    Transition("in-progress", "parked", "agent",
               "irreversible / cross-contract decision", "park & pivot",
               None, "park stamp", "parked-count"),
    Transition("in-progress", "stuck", "agent|system",
               "fallback bounds hit OR watchdog-timeout/abandonment; "
               "wait_reason stamped (unblock | re-scope)",
               "block",
               None, "stuck + wait_reason stamp", "stuck-count"),
    Transition("parked", "queued", "human",
               "ratify.sh single-commit (journal + flip)", "decision ratification",
               None, "journal entry + status flip", "ratify-count"),
    Transition("stuck", "queued", "human",
               "wait_reason: unblock (answer/env fix) | re-scope (after Spec revision)",
               "unblock",
               None, "status flip", "unblock-count"),
    Transition("pr-open", "rework", "system",
               "PR returned with findings; bump-fix-cycle stamps rework + fix_cycles",
               "review-hold",
               "--extend-budget --reason (one more cycle, operator-adjudicated)",
               "rework + fix_cycles stamp", "fix-cycles"),
    Transition("rework", "in-progress", "system",
               "re-enter queue; fix_cycles stamps the round (cap <=2)",
               "requeue after fix",
               None, "status flip", "fix-cycles"),
    Transition("pr-open", "pr-open", "system",
               "materially changed rebase -> verdict voided; clean rebase carries verdict",
               "rebase-void",
               None, "re-review trace", "re-review-count"),
    Transition("pr-open", "closed", "human",
               "merge — day only; .batch-work-active marker gate | close without merge (cancel)",
               "merge|cancel",
               None, "Finish ledger mergedAt (no mergedAt on cancel)", "merge-count"),
    # Explicit terminal edges (spc-337 A2 / ADR-012 §3). The former
    # `any -> closed` wildcard let a merged ticket that skipped in-progress /
    # pr-open replay as a clean "cancel"; now each source has its own edge so
    # the ledger distinguishes merge from cancel from a skipped lifecycle.
    #   queued|in-progress -> closed: a MERGED PR observed from a pre-PR state
    #   (metric `direct-jump`; finish-ledger journals an `anomaly:` line) OR a
    #   cancel (finish-ledger --cancel --reason).
    #   parked|stuck|rework|deferred -> closed: cancel (reason required) OR a
    #   MERGED PR from a side state (finish-ledger `anomaly:` line).
    Transition("queued", "closed", "human",
               "merge observed from queued (direct jump; stamps skipped) | cancel",
               "merge|cancel",
               None, "Finish ledger (+anomaly on direct-jump merge)", "direct-jump"),
    Transition("in-progress", "closed", "human",
               "merge observed from in-progress (direct jump; pr-open skipped) | cancel",
               "merge|cancel",
               None, "Finish ledger (+anomaly on direct-jump merge)", "direct-jump"),
    Transition("parked", "closed", "human",
               "cancel (finish-ledger --cancel --reason) | merge anomaly from side state",
               "cancel",
               None, "Finish ledger (no mergedAt on cancel; anomaly on merge)", "cancel-count"),
    Transition("stuck", "closed", "human",
               "cancel (finish-ledger --cancel --reason) | merge anomaly from side state",
               "cancel",
               None, "Finish ledger (no mergedAt on cancel; anomaly on merge)", "cancel-count"),
    Transition("rework", "closed", "human",
               "cancel (finish-ledger --cancel --reason) | merge anomaly from side state",
               "cancel",
               None, "Finish ledger (no mergedAt on cancel; anomaly on merge)", "cancel-count"),
    Transition("deferred", "closed", "human",
               "cancel (finish-ledger --cancel --reason) | merge anomaly from side state",
               "cancel",
               None, "Finish ledger (no mergedAt on cancel; anomaly on merge)", "cancel-count"),
    # Legacy coarse `open` (pre-FSM binders; validator warns `legacy_open_status`)
    # may still be closed by finish-ledger during lazy migration.
    Transition("open", "closed", "human",
               "legacy coarse status (lazy migration): merge | cancel",
               "merge|cancel",
               None, "Finish ledger", "legacy-close"),
    # Side-state guard (ADR-007 sec.5b): a pr-open stamp crossing a side
    # state is refused without an explicit operator-adjudicated --force-side-
    # state --reason override that journals a structured trace. These edges
    # are legal ONLY with the escape; the validator requires the ledger
    # entry's trace field to carry the override reason. SIDE_STATES (status
    # _vocab.py) is {parked, stuck, rework, deferred} — so ALL FOUR side
    # states get an escape edge here (review F1: the prior slice omitted
    # rework/deferred, so --force-side-state flips on them were recorded as
    # illegal and swallowed by stamp-pr-open's `|| echo WARN`, shipping an
    # illegal binder state undetected).
    Transition("parked", "pr-open", "agent",
               "ILLEGAL unless --force-side-state --reason (operator-adjudicated)",
               "force-side-state crossing",
               "--force-side-state --reason", "operator-adjudicated trace",
               "side-state-crossings", True),
    Transition("stuck", "pr-open", "agent",
               "ILLEGAL unless --force-side-state --reason (operator-adjudicated)",
               "force-side-state crossing",
               "--force-side-state --reason", "operator-adjudicated trace",
               "side-state-crossings", True),
    Transition("rework", "pr-open", "agent",
               "ILLEGAL unless --force-side-state --reason (operator-adjudicated); "
               "normal path is rework -> in-progress -> pr-open",
               "force-side-state crossing",
               "--force-side-state --reason", "operator-adjudicated trace",
               "side-state-crossings", True),
    Transition("deferred", "pr-open", "agent",
               "ILLEGAL unless --force-side-state --reason (operator-adjudicated)",
               "force-side-state crossing",
               "--force-side-state --reason", "operator-adjudicated trace",
               "side-state-crossings", True),
    # NOTE: the normal (non-force) `rework -> pr-open` is intentionally
    # absent — the doc states "there is no direct rework -> pr-open"; it must
    # go rework -> in-progress -> pr-open. Any ledger (rework, pr-open) pair
    # WITHOUT a force_side_state_reason is flagged illegal by the validator.
)

# Edge lookup keyed by (from, to). No wildcard sources (spc-337 A2): every
# legal edge names its literal source, so a ledger pair is legal iff it is
# listed here.
_EDGE_INDEX = {(e.from_, e.to): e for e in LEGAL_EDGES}

# Terminal edges that are a `direct-jump` when the PR was MERGED: the ticket
# reached `closed` without passing pr-open (spc-337 A2). finish-ledger journals
# an `anomaly:` line and the ledger carries metric `direct-jump`.
DIRECT_JUMP_TERMINAL_SOURCES = frozenset({"queued", "in-progress"})


def is_legal_edge(frm: str, to: str) -> bool:
    """True if the (frm, to) pair is a legal transition per the schema."""
    return (frm, to) in _EDGE_INDEX


def edge_for(frm: str, to: str) -> Optional[Transition]:
    """Return the Transition for (frm, to). None if illegal."""
    return _EDGE_INDEX.get((frm, to))


def requires_escape(frm: str, to: str) -> bool:
    """True if the (frm, to) edge is legal ONLY via an operator-adjudicated
    escape (side-state guard). Discriminates on the structured `escape_
    required` flag (review F5), not on substring prose in `guard`, so
    rephrasing the guard text cannot silently disable the override check."""
    e = edge_for(frm, to)
    return e is not None and e.escape_required


def legal_from_status(frm: str) -> list:
    """All legal target statuses reachable from `frm`."""
    return sorted({e.to for e in LEGAL_EDGES if e.from_ == frm})
