---
id: spc-458
slug: review-followup
title: "Review follow-up — finish-stamp/transition-api correctness, hook truthfulness, spc-433 closure, docs drift"
kind: chore
status: locked
mode: C
priority: P1
summary: "Fix verified defects from the 2026-09-03 full-repo review not covered by spc-441: stamp-path bugs, hook doc/code drift, spc-433 mechanism gap, docs drift"
created: 2026-09-03
updated: 2026-09-03
tickets: [tkt-459, tkt-460, tkt-461, tkt-462, tkt-463]
prs: [pr-464, pr-465, pr-466]
reviews: []
supersedes: []
superseded_by: null
---

# Spec: Review follow-up — finish-stamp/transition-api correctness, hook truthfulness, spc-433 closure, docs drift

> **TL;DR:** A five-way parallel audit of the repo (dev @ 80f3701, re-verified at 046144d) confirmed 30+ defects. spc-441 already owns the security/CI/test sweep (tkt-442..449); this Spec owns everything else that survived manual re-verification — two HIGH stamp-path bugs, hook docs that contradict the code, spc-433 acceptance criteria that shipped as prose only, and documentation drift.
> **Kind:** chore · **Status:** locked · **Mode:** C · **Priority:** P1
> **Path:** spc-458 → tkt-459..463 → (prs pending)

## Why

The 2026-09-03 review ran five independent audits (spc-433 implementation, core scripts, hooks/CI, skill docs, tests) and then re-verified every actionable claim by hand against the tree. Two claims were retracted (the finish-stamp.yml expression-injection claim: inputs already route through env; the "dev bats red" claim: fixed in transit by #450). The rest are real and fall into four groups that spc-441 does not cover:

1. **Stamp-path correctness (ADR-013 class).** `finish-stamp-ci.py` matches `pr-N` as a substring (pr-44 hits pr-440) and reports push failures as success; `finish-stamp.py` renames the binder before the ledger edge is validated; `transition-api.py` has an arity crash, a silent rollback no-op, and a non-gitignored temp file; `finish-commit.sh` fails on untracked files.
2. **Hook truthfulness.** The docs say `LATTICE_HOOK_MODE=advisory` relaxes all blocks (it relaxes only the `gh` intercepts); the marketplace description says hooks advise by default (default is strict); one PreToolUse hook exits 1 (cannot block) and is unregistered; strict mode costs ≈1 s per Bash call because three hooks each re-run the same strip passes.
3. **spc-433 closure.** A2/A3/A6 shipped with no parser, writer, or validator; the binder template claims a validator warning that does not exist; `lattice-init.sh` does not emit the new `snapshots/` ignore; `--budget` has two contradictory semantics; `budget-exhausted` is absent from the FSM docs.
4. **Docs drift + test plumbing.** Three different skill counts, an incomplete co-install list, ~35 dangling relative links, a phantom `deep-review` state, CHANGELOG missing 0.4.0/0.5.0, an 8-test suite CI never discovers, two root-hostile tests with a guard that cannot fire, and an unpinned `sudo`-executed bats install.

Source: review session 2026-09-03 (this conversation; findings recorded in the ticket bodies). Complements `spc-441` — no ticket here touches a file owned by an open spc-441 PR except tkt-463, which is explicitly stacked after #451.

## In scope

- tkt-459: finish-stamp-ci / finish-stamp / transition-api / finish-commit correctness + tests + validator step in `finish-stamp.yml`
- tkt-460: hook docs/description truth, pretooluse hook exit code + registration note, strict-mode jq pre-filter
- tkt-461: validator `autonomy` check, `lattice-init.sh` gitignore generator, `autonomy-filter.py`, budget semantics reconciliation, FSM docs (`budget-exhausted`, side-state list), English-only shipped prose
- tkt-462: skill counts, co-install list, script table, `deep-review` wording, broken links, CHANGELOG backfill, orphan bats suite relocation, root guards
- tkt-463 (stacked after #451): bats commit-SHA pin, ci-local base-baseline parity

## Out of scope

- Anything owned by spc-441 (GHA env routing, eval elimination, macOS matrix, issue-create hook tests, CODEOWNERS, resolver extraction, L3 guard split, evals README)
- Making L1/L3 hooks honour `LATTICE_HOOK_MODE` (policy change; operator decision)
- Lock timeouts / directory-flock portability; a shared `lib/binder_fields.py` + `lib/locking.py` extraction (follow-up Spec)
- Scripting start-work `--budget` timing or snapshot writing (start-work has no scripts; these remain instruction-shaped and are labelled so)
- Gating `.lattice/blocked/` writes in the L3 hook (file owned by #456)
- Shrinking the validator warning baseline; backfilling git tags

## Acceptance

- [ ] **A1** `finish-stamp-ci.py` discovers binders by `\bpr-N\b`, exits non-zero on push/fetch failure, commits the staged set; `finish-stamp-ci.bats` covers pr-44 vs pr-440 and the return codes.
- [ ] **A2** `finish-stamp.py` writes the ledger edge before the binder rename and rolls it back on rename failure; `finish-stamp.bats` + `finish-ledger.bats` green.
- [ ] **A3** `transition-api.py commit` arity guard (usage + exit 3); `_rollback_ledger` searches the whole file and warns when absent; temp file `.transition-api.*.tmp`, unlinked on failure; `transition-api.bats` green.
- [ ] **A4** `finish-commit.sh` clean assertion ignores untracked files; `finish-stamp.yml` runs the artifact validator before pushing.
- [ ] **A5** `tools/hooks/pretooluse-bats-check.py` exits 2 on a banned form; docstring + `tools/README.md` state exit contract and registration.
- [ ] **A6** hooks README, plugin README, `CLAUDE.md`, finish-work SKILL row, `plugin.json`, `marketplace.json` state the true default (strict) and the true scope of `LATTICE_HOOK_MODE=advisory`.
- [ ] **A7** strict mode pre-filters on the jq-decoded command; escaped-`gh` bats case still classified; non-gh Bash call costs < 50 ms per hook.
- [ ] **A8** validator: `autonomy` out of 0–4 → error; absent on C-mode tickets → warning; fixtures both ways; template claim true.
- [ ] **A9** `lattice-init.sh` emits `snapshots/`; bats asserts.
- [ ] **A10** `skills/batch-work/scripts/autonomy-filter.py` + tests; flow.md RESOLVE TICKETS calls it.
- [ ] **A11** budget semantics stated once per skill without contradiction; `budget-exhausted` in `docs/workflow-fsm.md` + `workflow-fsm-reference.md`; no Chinese prose in shipped skill files; `full-flow.md` §7 updated.
- [ ] **A12** one skill count; co-install list + script table complete; `deep-review` documented as a triage class.
- [ ] **A13** every relative link in shipped SKILL/reference files resolves; CHANGELOG 0.4.0/0.5.0 sections + `[Unreleased]` bullets.
- [ ] **A14** `docs-truth.bats` under CI discovery; chmod-000 tests skip for uid 0.
- [ ] **A15** bats-core pinned by commit SHA in both workflows; `ci-local.sh` mirrors the base-baseline comparison.

## Non-goals

- Replacing the model-driven parts of start-work/batch-work with scripts wholesale
- A global enforcement wrapper (README §Philosophy already documents per-call-path strength)

## Decisions (principal, user-confirmed)

1. **Scope = confirmed findings only, delivered through the standard pipeline** (create-spec → create-tickets → start-work → create-pr → review-code → finish-work), serial single-worktree per ticket. — user-stated ("确认之后…create tickets…start work…review code…finish work")
2. **Budget semantics:** batch-work `--budget` is the per-batch ceiling (never-spawned → `deferred` + `budget-exhausted`); start-work `--budget` is the per-ticket outer bound over the timebox (trip → `stuck` + `unblock`, the existing watchdog edge). Both documented explicitly; spc-433's open question closed by dated amendment. — recommended (matches `status_vocab.py`: `budget-exhausted` ∈ DEFERRED_REASONS, `unblock` ∈ STUCK_REASONS)
3. **Advisory scope stays gh-only in code; docs are corrected to match** rather than widening the escape to L1/L3. — recommended (narrowest change; L1/L3 relaxation is a policy call)
4. **Orphan suite is moved, not the CI glob** — workflow files are owned by open PR #451. — recommended
5. **tkt-463 is stacked after #451** (`merge_blocked_by: #444`); if #451 has not landed when the rest ships, tkt-463 stays `queued` and is reported. — recommended

## Agent-assumed (secondary)

- Validator `autonomy_missing` is a warning (lazy migration like `missing_binder_timestamp`), baselined for existing binders; `autonomy_out_of_range` is an error.
- `autonomy-filter.py` is python3 stdlib, reads the binder field table via the same regex family as `queue_health._parse_field_rows`.
- The strict pre-filter uses `jq -r '.tool_input.command // empty'` then a literal `gh` word test; the python classifiers still run whenever the decoded string contains `gh`.
- Spec + binders land via one docs PR first; each ticket then branches from dev (precedent: #427 / spc-441).

## Risks / open questions

- The other active session may merge spc-441 PRs while this Spec is in flight; each start-work re-bases on current dev (`update-pr-base.sh`).
- The main clone carries another session's staged finish-ledger for tkt-442; this Spec's finish-commit steps must not sweep it silently (check `git diff --cached` before each `finish-commit.sh`).
- Follow-up Spec candidates recorded, not delivered: lock timeout/portability; `lib/binder_fields.py` + `lib/locking.py` extraction (8 status parsers, 4 lock copies); L1/L3 advisory policy; skill-marker TTL; warning-baseline ratchet; git tag backfill.

## References

- Prior Spec: `spc-441` (hardening sweep, parallel), `spc-433` (closure target), `spc-416` / ADR-013 (finish-ledger write separation), ADR-012, ADR-011, ADR-005
- Review note: `rev-20260902-015425Z` (advisory-mode gap first recorded)

## Links / bloodline (L0)

- Primary: [#458](https://github.com/percena/lattice/issues/458)
- Tickets: tkt-459, tkt-460, tkt-461, tkt-462, tkt-463
- PRs: pr-464 (spec + binders), pr-465 (tkt-459), pr-466 (tkt-463); tkt-460/461/462 PRs added at their open time
- Reviews: (none)
