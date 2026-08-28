# ADR 006: Worktree discipline via PreToolUse hard enforcement (location gate + interactive-confirmation escape)

- **Status:** Accepted
- **Date:** 2026-08-28
- **Deciders:** maintainers
- **Related:** `spc-145`
- **Related ADRs:** (none)

## Context

Agents repeatedly drift to plain temp branches on the main clone (or direct base commits) instead of the Ticket → worktree procedure. The enforcement audit (`spc-145`) found:

- `assert-shippable-cwd.sh` (the only HARD gate) blocks writes on team-base (`main`/`dev`) but **deliberately passes** a non-base branch on the main clone — the documented `--mode branch` escape. This is exactly the drift path recorded in memory `strict-profile-sibling-worktree-default`.
- `ensure-workspace.sh` enforces bound names + worktree default, but is **consultative**: a bare `git checkout -b` bypasses it with zero friction.
- No PreToolUse hook intercepts `git checkout -b` / `git switch -c`; `hooks.json` only matches `gh pr create` / `gh pr merge`.
- Soft guidance (memory / CLAUDE.md / `policy.md`) consistently loses to the zero-friction bypass — it is a reminder, not a guardrail.

The user requires: **default strict execution; non-standard flows only with explicit user authorization, and the agent must ask for a second confirmation before routing through the audited escape.**

## Decision Drivers

- Drift, not adversarial behavior, is the failure mode — the gate must make the wrong path *impossible by default*, not merely discouraged.
- Explicit user authorization must still work, but leave an audit trail and require a confirmation step so drift (no authorization) cannot masquerade as "the user wanted it".
- The gate must cover the recorded drift exactly: a **bound** name (`tkt-N-foo`) created in the main clone is still drift, so name-based gating is insufficient.
- Compliant path (`ensure-workspace --mode worktree`) must not be self-blocked by the new gate.

## Considered Options

- **Option A — Name-based gate** (deny only unbound branch names). Good: simple. Bad: a bound name on the main clone still drifts — this is the exact recorded bypass. **Rejected.**
- **Option B — Location-based gate + interactive escape** (deny raw branch ops in the main clone; route everything through `ensure-workspace`; non-standard flows require user confirmation + `--reason`). Good: covers all bypass shapes; honors explicit authorization with an audit trail. Bad: needs a sentinel contract so the compliant path is not self-blocked; sentinel spoofable by a determined agent. **Chosen.**
- **Option C — Fully frictionless "user said so" sentinel** (agent sets a bypass flag when it believes the user authorized). Bad: the gate cannot distinguish drift from authorization, so drift re-enters through the same flag. **Rejected.**

## Decision

We will enforce worktree discipline with a **three-layer physical stack**, gating on **location** (main clone vs worktree), not branch name:

1. **L1 — PreToolUse Bash hook:** deny raw `git checkout -b` / `git switch -c/-C` / `git branch <create>` / `git switch <existing-to-non-base>` in the main clone unless the `ensure-workspace` sentinel is set. Switching to a base branch is always allowed. CWD inside a worktree is always allowed.
2. **L2 — Strengthen `assert-shippable-cwd.sh`:** under `profile: strict`, fail non-base-on-main-clone (require worktree OR `--allow-base-write --reason`). Light profile unchanged.
3. **L3 — PreToolUse Write/Edit hook:** run `assert-shippable-cwd.sh` before shippable writes (`.lattice/**` + product code); deny on fail, with the `--reason` escape available.

`ensure-workspace.sh` exports a sentinel before its own git branch/checkout so L1 does not self-block the compliant path.

For non-standard flows, the agent must **ask the user and receive explicit confirmation**, then route through `ensure-workspace --allow-unbound --reason "user-authorized …"` or `assert --allow-base-write --reason "user-authorized …"`. Drift (no confirmation) is blocked at L1/L3.

## Consequences

- **Positive:** Drift to temp branches / base commits becomes physically impossible by default; the main clone stays parked on `dev`; workspace isolation becomes a machine-checked invariant; explicit authorization still works but is audited and confirmation-gated.
- **Negative / trade-offs:** Hook latency on every shippable Write (mitigated: assert is fast, classifier scoped to `.lattice/**` + product code). The sentinel env var is spoofable by a determined agent (accepted — problem is drift, not adversarial; L3 Write hook does not trust the sentinel and is the spoof backstop). Agents must discover the interactive-confirmation escape (mitigated: denial messages name the escape and instruct "ask the user").
- **Follow-ups:** `spc-145` splits delivery tickets; implementation via `start-work` in a spc-145 worktree.
- **Verification:** L1/L3 hooks live in `plugins/lattice/hooks/` + `hooks.json`; L2 gate verified by `assert-shippable-cwd.bats`; new bats cover location gate, sentinel passthrough, strict flip, Write hook, interactive escape.

## Status history

- 2026-08-28: Proposed → Accepted (deciders confirmed in spc-145 alignment)

## Notes

Rejected: name-based gating (Option A) — insufficient because the recorded drift was a bound name on the main clone. Rejected: frictionless self-set sentinel (Option C) — cannot distinguish drift from authorization.

Residual risk (out of scope for `spc-145`): adversarial sentinel spoofing. If this materializes, harden the sentinel to a file marker written by `ensure-workspace` and checked by the hook, or a process-tree parent check.

---

_Not a Lattice bloodline/graph node. Cite from Spec/PR/Review with `ADR-006` or this path._
