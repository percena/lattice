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
  from   — source status ("init" for creation, "any" for cancel)
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
    from_: str          # "init" / "any" / a status value
    to: str             # target status value
    owner: str          # human | agent | system (| for shared)
    guard: Optional[str]
    reason: str
    escape: Optional[str]
    trace: Optional[str]
    metric: Optional[str]


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
               "fuse-halt | blocked-by-failure | deliberate deschedule",
               "deschedule at trip time",
               None, "deferred + wait_reason stamp", "deferred-count"),
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
               "merge — day only; .batch-work-active marker gate",
               "merge",
               None, "Finish ledger mergedAt", "merge-count"),
    Transition("any", "closed", "human",
               "cancel", "cancel",
               None, "Finish ledger (no mergedAt)", "cancel-count"),
    # Side-state guard (ADR-007 sec.5b): a pr-open stamp crossing a side state
    # is refused without an explicit operator-adjudicated --force-side-state
    # --reason override that journals a structured trace. These edges are legal
    # ONLY with the escape; the validator requires the ledger entry's trace
    # field to carry the override reason.
    Transition("parked", "pr-open", "agent",
               "ILLEGAL unless --force-side-state --reason (operator-adjudicated)",
               "force-side-state crossing",
               "--force-side-state --reason", "operator-adjudicated trace",
               "side-state-crossings"),
    Transition("stuck", "pr-open", "agent",
               "ILLEGAL unless --force-side-state --reason (operator-adjudicated)",
               "force-side-state crossing",
               "--force-side-state --reason", "operator-adjudicated trace",
               "side-state-crossings"),
    # NOTE: direct `rework -> pr-open` is intentionally ABSENT — the doc states
    # "there is no direct rework -> pr-open"; it must go rework -> in-progress
    # -> pr-open. Any ledger (rework, pr-open) pair is flagged illegal.
)

# Edge lookup keyed by (from, to). "any" matches any source for cancel.
_EDGE_INDEX = {(e.from_, e.to): e for e in LEGAL_EDGES}


def is_legal_edge(frm: str, to: str) -> bool:
    """True if the (frm, to) pair is a legal transition per the schema.

    `frm` may be "any" (cancel accepts any source); a literal source is also
    matched against the "any" edge so cancel is legal from any status.
    """
    if (frm, to) in _EDGE_INDEX:
        return True
    if ("any", to) in _EDGE_INDEX:
        return True
    return False


def edge_for(frm: str, to: str) -> Optional[Transition]:
    """Return the Transition for (frm, to), preferring the literal edge over
    the "any" wildcard. None if illegal."""
    e = _EDGE_INDEX.get((frm, to))
    if e is not None:
        return e
    return _EDGE_INDEX.get(("any", to))


def requires_escape(frm: str, to: str) -> bool:
    """True if the (frm, to) edge is legal ONLY via an operator-adjudicated
    escape (side-state guard). The ledger entry must carry the override trace."""
    e = edge_for(frm, to)
    return e is not None and e.escape is not None and e.guard is not None \
        and "ILLEGAL unless" in (e.guard or "")


def legal_from_status(frm: str) -> list:
    """All legal target statuses reachable from `frm`."""
    return sorted({e.to for e in LEGAL_EDGES
                   if e.from_ == frm or e.from_ == "any"})
