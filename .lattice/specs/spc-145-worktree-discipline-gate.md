---
# status: draft | locked | done | superseded
id: spc-145
slug: worktree-discipline-gate
title: PreToolUse hard-enforcement stack for worktree discipline
kind: feat
status: done
mode: C
priority: P1
summary: "Three-layer physical enforcement (git hook + assert hardening + Write hook) so agents cannot drift to temp branches / base commits; interactive-confirmation escape for explicit user authorization."
created: 2026-08-28
updated: 2026-08-28
tickets: [tkt-146, tkt-147, tkt-148]
prs: [pr-154]
reviews: []
supersedes: []
superseded_by: null
---

# Spec: PreToolUse hard-enforcement stack for worktree discipline

> **TL;DR:** Make worktree-vs-branch a machine-enforced gate (not self-enforced): PreToolUse hooks block raw branch creation / shippable writes on the main clone; non-standard flows require user authorization + an agent second confirmation, routed through the audited `--reason` escape.
> **Kind:** feat · **Status:** locked · **Mode:** C · **Priority:** P1
> **Path:** spc-145 → ADR-006 → tkt-… → pr-…

## Why

AI agents repeatedly drift to plain temp branches on the main clone (or direct base commits) instead of following the Ticket → worktree procedure. Root cause, verified against the enforcement surface:

- The existing HARD gate `assert-shippable-cwd.sh` only blocks writes on team-base (`main`/`dev`). It **deliberately passes** "non-base branch on the main clone" (its `--mode branch` escape hatch) — which is *exactly* the recorded drift path in memory `strict-profile-sibling-worktree-default` ("I did `git checkout -b <branch>` in the main clone").
- `ensure-workspace.sh` enforces bound names (`tkt-N`/`spc-N`) and worktree default, but it is **consultative** — only effective when an agent chooses to call it. A bare `git checkout -b` bypasses it with zero friction.
- No PreToolUse hook intercepts `git checkout -b` / `git switch -c` (hooks.json only matches `gh pr create` / `gh pr merge`).
- Downstream skills (`alignment-check`, `finish-work`) do not front-load a worktree check; failures surface late or are sidesteppable.

Soft guidance (memory / CLAUDE.md / `policy.md`) consistently loses to the zero-friction bypass because guidance is a **reminder**, not a **guardrail**. User value: agents stop drifting, the main clone stays parked on `dev`, workspace isolation becomes an invariant rather than a hope — and the user retains an audited escape for legitimate non-standard flows.

## In scope

- **L1 — PreToolUse Bash hook (prevention):** intercept raw git branch-create / branch-switch commands (`git checkout -b`, `git switch -c/-C`, `git branch <create>`, `git switch <existing>` to non-base) when run in the **main clone**. Deny unless the ensure-workspace sentinel is set. **Gate on location (main clone vs worktree), NOT branch name** — a bound name like `tkt-8-foo` created in the main clone is also blocked.
- **L1 sentinel contract:** `ensure-workspace.sh` exports a sentinel env var before its own `git checkout -b` / `git branch` so the compliant path is not self-blocked.
- **L2 — Strengthen `assert-shippable-cwd.sh`:** under `profile: strict`, fail non-base-on-main-clone (require worktree OR authorized escape). `--allow-base-write --reason` preserved. Light profile unchanged.
- **L3 — PreToolUse Write/Edit hook (asset protection):** before shippable writes (`.lattice/` + product code), run `assert-shippable-cwd.sh`; deny on fail. Escape via `--allow-base-write --reason` / `--allow-unbound --reason`.
- **Interactive-confirmation escape:** when the agent needs a non-standard flow, it must ask the user first and wait for explicit confirmation; on confirm, route through `ensure-workspace --allow-unbound --reason "user-authorized …"` or `assert --allow-base-write --reason "user-authorized …"`. Drift (no user confirmation) stays blocked.
- New tests (bats) covering the location-based gate, sentinel passthrough, strict-profile assert flip, Write hook, and the interactive escape.
- `references/policy.md` + project CLAUDE.md update documenting the machine-enforced default and the interactive-confirmation escape.

## Out of scope

- Removing the `--mode branch` / `--allow-unbound` escape hatch entirely (kept as the audited escape for legitimate rescue).
- Non-strict (`light`) profile behavior changes.
- Adversarial sentinel spoofing (agent deliberately `export`-ing the sentinel to bypass). Documented as residual; this Spec targets drift, not adversarial agents.
- Retiring the existing `gh pr create` / `gh pr merge` intercept hooks.

## Acceptance

- [x] **A1** Raw `git checkout -b <name>` and `git switch -c <name>` in the main clone (any name, bound or unbound) is **denied** by the L1 PreToolUse hook with a message pointing to `ensure-workspace --mode worktree` / `/start-work`.
- [x] **A2** `git branch <create>` + `git switch <existing>` (the two-step bypass) is also denied by L1 in the main clone.
- [x] **A3** The compliant path still works: `ensure-workspace --mode worktree --bind tkt|spc …` runs its internal `git branch` / `git worktree add` / `git checkout -b` without being self-blocked (sentinel passthrough); the worktree is created and the agent can `cd` and write.
- [x] **A4** `assert-shippable-cwd.sh` under `profile: strict` **fails** non-base-on-main-clone; `--allow-base-write --reason` still passes. Light profile keeps the legacy pass behavior.
- [x] **A5** The L3 PreToolUse Write/Edit hook denies shippable writes (`.lattice/**`, product code) when `assert-shippable-cwd.sh` fails, with the same `--reason` escape available.
- [x] **A6** A non-standard flow requires the agent to ask the user and receive explicit confirmation before routing through the `--reason` escape; a drift attempt (no user confirmation) is blocked at L1/L3. The reason string records "user-authorized".
- [x] **A7** New bats tests pass; existing `ensure-workspace.bats` and `assert-shippable-cwd.bats` still pass (no compliant-path regression).
- [x] **A8** Switching **to** a base branch (`main`/`dev`/`master`) in the main clone is never blocked (allow returning to base).

## Non-goals

- A general-purpose "agent jailbreak prevention" framework. Scope is worktree-discipline only.

## Decisions (principal, user-confirmed)

1. **Gate on location, not branch name.** A bound name (`tkt-N-foo`) created in the main clone is still blocked, because the recorded drift was exactly a bound-name branch on the main clone. The gate distinguishes main-clone vs worktree, not bound vs unbound. (User-confirmed in review.)
2. **Three-layer hard stack.** L1 (git create) prevents; L2 (assert) makes the consultative gate real; L3 (Write/Edit) protects assets at write time. Each covers a bypass the others miss (e.g. a pre-existing branch, a two-step create, a write after evading L1).
3. **Interactive confirmation for non-standard flows.** Explicit user authorization is honored, but the agent must ask first and the escape is routed through the audited `--reason` path. Drift (no authorization) stays blocked. This makes drift and explicit authorization asymmetric in friction. (User-confirmed: "非标准流程的话，授权的话再给我确认一下 … 否则默认按严格执行".)
4. **Residual escape preserved, sentinel spoofing out of scope.** `--allow-unbound --reason` / `--allow-base-write --reason` remain for legitimate rescue; the sentinel is an env var (spoofable by a determined agent), accepted because the problem is drift, not adversarial. L3 Write hook does not trust the sentinel, providing the spoof-resistant backstop.

## Risks / open questions

- **Hook latency / false positives:** PreToolUse Write/Edit hook runs on every write; must keep `assert-shippable-cwd.sh` fast (it already is) and the path-classifier cheap. Mitigation: only assert on `.lattice/**` + tracked product code, not every file.
- **Edge: agent sets sentinel to self-bypass.** Accepted residual (D4); L3 backstops.
- **Edge: legitimate `git checkout -b` inside an already-open worktree.** L1 allows it (CWD is a worktree, `show-toplevel != MAIN_ROOT`).
- **Escape-hatch discoverability:** if the interactive-confirmation escape is too hidden, agents may stall instead of asking. Mitigation: the L1/L3 denial message must name the escape and instruct "ask the user".

## References

- ADR: `ADR-006` → `docs/adr/006-worktree-discipline-hard-enforcement.md` (to be written, same worktree)
- Memory: `strict-profile-sibling-worktree-default` (records the drift this Spec fixes)
- Memory: `merge-target-integration-branch`
- Scripts: `skills/_lattice-lib/scripts/assert-shippable-cwd.sh`, `ensure-workspace.sh`; `plugins/lattice/hooks/hooks.json`

## Links / bloodline (L0)

- Tickets: bare ids in front matter (`tkt-N`) — to be split by `create-tickets`.
- PRs: prefer GitHub `Fixes`/`Refs`; Spec.prs is recovery.
- Reviews: (none yet)
