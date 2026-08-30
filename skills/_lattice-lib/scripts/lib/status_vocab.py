"""Single source for the ticket binder status vocabulary + coupled-field
transition policy (tkt-189 / spc-186 A2).

Owns the FSM status enum, the side-state set (external signals that must not
be silently overwritten by a pr-open stamp), and the direct-jump policy
(queued -> pr-open allowed but warned). Consumed by the three writers
(reconcile-state.sh, finish-ledger.sh, stamp-pr-open.sh -- their embedded
python imports this module) and asserted parity-equal against the vendored
copy in tools/validate-lattice-artifacts.py by a bats test (the validator
stays dependency-free so consumer repos can vendor it alone).

Canon (ADR-004 sec.6 / spc-42 A4, extended by ADR-007 sec.4 for the side-state
guard): working = queued | in-progress | parked | stuck | pr-open | rework |
deferred, legacy = open (lazy migration), terminal = closed. merged vs
closed-without-merge is read from the ## Finish ledger's mergedAt, not a
separate status value. Side states (parked/stuck/rework/deferred) hold an
external signal; a pr-open stamp crossing them is a red-line (ADR-007 sec.5b):
refused without an explicit operator-adjudicated override that journals a
structured trace; no default break-glass.
"""

from __future__ import annotations

import re

# FSM working vocabulary in canonical order. The order is load-bearing: the
# validator's legacy-migration message lists it, and the morning digest water
# levels surface states in this sequence.
STATUS_WORKING_ORDER = (
    "queued", "in-progress", "parked", "stuck", "pr-open", "rework", "deferred",
)
STATUS_WORKING = frozenset(STATUS_WORKING_ORDER)
STATUS_TERMINAL = frozenset({"closed"})
STATUS_LEGACY = frozenset({"open"})
STATUS_OK = STATUS_WORKING | STATUS_TERMINAL | STATUS_LEGACY

# Side states hold an external signal (parked = irreversible / cross-contract
# decision pending; stuck = needs human investigation; rework = PR returned
# with findings; deferred = a deferral reason — spec-superseded /
# blocked-by-failure / fuse-halt — that the morning digest must surface). A
# pr-open stamp from these is a red-line crossing (ADR-007 sec.5b): the
# signal must not be silently lost. stamp-pr-open refuses the flip without
# an explicit --force-side-state --reason override that journals a
# structured trace; the override is operator-adjudicated
# (double-confirm), no agent self-adjudication. (tkt-237 M3: `deferred` was
# missing from this set — a deferred binder hit stamp-pr-open's else branch
# and silently flipped to pr-open with no journal trace, losing the
# deferred signal. finish-ledger.sh:442 already lists deferred as anomalous.)
SIDE_STATES = frozenset({"parked", "stuck", "rework", "deferred"})

# Direct-jump policy: queued -> pr-open is allowed (an agent may open a PR
# without an in-progress stamp when work is trivial), but the jump is
# WARN-journaled so the "started" signal is logged rather than silently lost.
# The in-progress stamp remains the DEFAULT path; a jump is an exception, not
# the rule. in-progress -> pr-open is the ungated default and emits no trace.
DIRECT_JUMP_SOURCES = frozenset({"queued"})

# Regex matching any nonterminal status value (working U legacy) -- used by
# finish-ledger to flip any working/legacy status -> closed on terminal
# evidence (cancel / issue-closed / merged-without-linked-issue). The
# alternation is built with a total order (length desc, then lexicographic)
# so the compiled pattern is byte-stable across processes regardless of
# frozenset iteration order, and a multi-word status (in-progress) is not
# shadowed by a prefix.
_NONTERMINAL_VALUES = sorted(
    STATUS_WORKING | STATUS_LEGACY, key=lambda s: (-len(s), s)
)
NONTERMINAL_ALT = "|".join(_NONTERMINAL_VALUES)
# `(?:...)` group, embedded-ready: consumers interpolate NONTERMINAL_ALT into
# their own anchored status-row regex (finish-ledger) or use this compiled
# form to test a bare value.
NONTERMINAL_RE = re.compile(rf"(?:{NONTERMINAL_ALT})")

# Coupled-field wait_reason vocabulary (tkt-190 / spc-186 A3). The wait_reason
# binder field-table row carries the reason for BOTH stuck and deferred
# statuses (tkt-151 anticipated decision -- one grep-able row). Single-sourced
# here so the validator's vendored copy stays parity-equal (bats test).
# stuck: unblock | re-scope (FSM-2b / tkt-132).
# deferred: fuse-halt | blocked-by-failure (ADR-004 amd tkt-136 Option B --
# batch-work stamps these at trip time) | spec-superseded (spc-186 A3 --
# spec-supersede trip-time sweep stamps a superseded Spec's still-active child
# binders at supersede time, generalizing the tkt-136/137 trip-time honesty
# principle to spec supersede). A contradictory value (stuck + fuse-halt,
# deferred + unblock) fails -- the reason must match the status.
STUCK_REASONS = frozenset({"unblock", "re-scope"})
DEFERRED_REASONS = frozenset({"fuse-halt", "blocked-by-failure", "spec-superseded"})


def is_terminal(status: str) -> bool:
    """True for closed (the only terminal status)."""
    return status in STATUS_TERMINAL


def is_nonterminal(status: str) -> bool:
    """True for any working or legacy-coarse status (open is lazy-migration)."""
    return status in STATUS_WORKING or status in STATUS_LEGACY


def is_side_state(status: str) -> bool:
    """True for statuses that hold an external signal a pr-open stamp must
    not silently overwrite (parked / stuck / rework)."""
    return status in SIDE_STATES
