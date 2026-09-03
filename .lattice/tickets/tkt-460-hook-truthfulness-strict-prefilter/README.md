# tkt-460-hook-truthfulness-strict-prefilter

> **TL;DR:** Make the enforcement layer's docs, description, exit codes and strict-mode cost match the code.
> **Kind:** fix · **Priority:** P2
> **Path:** spc-458 → tkt-460 → (pr-…)

| Field | Value |
| --- | --- |
| kind | fix |
| priority | P2 |
| labels | bug, P2 |
| github | https://github.com/percena/lattice/issues/460 |
| status | queued |
| fix_cycles | 0 |
| wait_reason | (none) |
| created | 2026-09-03T16:51:19Z |
| updated | 2026-09-03T16:51:19Z |
| adopted | false |
| summary | Hook docs/description match code; pretooluse hook exits 2; strict-mode jq pre-filter removes ~1s/Bash-call tax |
| spec | spc-458 — Review follow-up (path: ../../specs/spc-458-review-followup.md) |
| covers | A5, A6, A7 |
| blocked_by | (none) |
| merge_blocked_by | (none) |
| parallel_group | (serial) |
| paths | plugins/lattice/hooks/lib/intercept-gh-pr-common.sh, plugins/lattice/hooks/README.md, plugins/lattice/README.md, plugins/lattice/.claude-plugin/plugin.json, .claude-plugin/marketplace.json, CLAUDE.md, skills/finish-work/SKILL.md, tools/hooks/pretooluse-bats-check.py, tools/README.md, plugins/lattice/scripts/tests/** |
| solo_merge | yes |
| autonomy | 3 |
| **primary_ticket** | tkt-460 (this issue) |
| **related_tickets** | (none) |
| **worktree_bind** | `tkt-460-hook-truthfulness-strict-prefilter` |
| worktree | sibling `…/lattice.worktrees/tkt-460-hook-truthfulness-strict-prefilter/` |
| prs | (none) |

## Acceptance (this slice)

- [ ] **A5** `tools/hooks/pretooluse-bats-check.py` exits 2 on a banned form; docstring and `tools/README.md` state the exit contract and how to register it (settings.json snippet).
- [ ] **A6** `plugins/lattice/hooks/README.md`, `plugins/lattice/README.md`, `CLAUDE.md`, `skills/finish-work/SKILL.md` (rationalization row), `plugin.json`, `marketplace.json` state: default is strict (block); `LATTICE_HOOK_MODE=advisory` downgrades only the three `gh` intercepts; L1/L3 always block.
- [ ] **A7** `intercept-gh-pr-common.sh` strict mode skips the python passes when the jq-decoded `tool_input.command` has no `gh` token; bats proves a `gh pr create` payload is still classified; existing `intercept-gh-pr-*.bats` green; measured cost on `ls -la` < 50 ms per hook.

## Approach

1. `sys.exit(1)` → `sys.exit(2)`; update docstring; add a "Registering" subsection to `tools/README.md`.
2. Doc edits: hooks README line 6-7, plugins README § Hooks, CLAUDE.md line 54-55, finish-work SKILL.md rationalization "hooks advise by default…" → "hooks block by default (strict)…", plugin.json/marketplace.json description tail.
3. `intercept-gh-pr-common.sh`: after mode resolution, `cmd=$(printf '%s' "$hook_data" | jq -r '.tool_input.command // empty' 2>/dev/null)`; if jq succeeded and `$cmd` does not match `(^|[^[:alnum:]_])gh([^[:alnum:]_]|$)` → exit 0 in BOTH modes (jq decodes `\uXXXX`, so the documented advisory-only concern no longer applies); jq failure → fall through to the full path (fail-safe toward the guard). Keep the existing advisory raw-string shortcut as a first, cheaper tier.
4. bats: new test in `intercept-gh-pr-create.bats` for the escaped payload; timing assertion optional (document the measurement in the PR).
Touch-set: see `paths` row.

## Anticipated decisions

- Whether the pre-filter should also cover `intercept-git-branch-create.sh` — disposition: must-ask → parked (different classifier; out of this ticket's paths).
- Register `pretooluse-bats-check.py` in `plugins/lattice/hooks/hooks.json` vs document-only — disposition: pre-resolved(spc-458 Decisions 3/Out of scope): document-only; it is a maintainer tool, not a plugin hook.

## Decision journal

<!-- Append-only during execution. -->

## Pending decisions

- Extend the jq pre-filter to the branch-create hook? · context: same ~100 ms cost class · default-if-unanswered: no (separate ticket).

## Attempts

- (none)

## Notes

- Skill-marker session-long TTL (`Stop`-hook clear) NOTICED — follow-up.

## References

- Spec: `spc-458` · `rev-20260902-015425Z` (advisory gap first recorded) · Claude Code hooks exit-code contract (exit 2 = block)

## Lineage

- Parent spec: **spc-458** · Parent issue: **#458** · Primary ticket: **tkt-460** · Covers: **A5, A6, A7** · Blocked by: none · Worktree bind: `tkt-460-hook-truthfulness-strict-prefilter`

## Assets

Local files in `./assets/`.

## Finish

- (none yet)
