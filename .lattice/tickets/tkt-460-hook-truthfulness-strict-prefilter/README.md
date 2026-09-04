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
| status | pr-open |
| fix_cycles | 0 |
| wait_reason | (none) |
| created | 2026-09-03T16:51:19Z |
| updated | 2026-09-04T01:31:22Z |
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
| prs | pr-467 — https://github.com/percena/lattice/pull/467 |

## Acceptance (this slice)

- [x] **A5** `tools/hooks/pretooluse-bats-check.py` exits 2 on a banned form; docstring and `tools/README.md` state the exit contract and how to register it (settings.json snippet).
- [x] **A6** `plugins/lattice/hooks/README.md`, `plugins/lattice/README.md`, `CLAUDE.md`, `skills/finish-work/SKILL.md` (rationalization row), `plugin.json`, `marketplace.json` state: default is strict (block); `LATTICE_HOOK_MODE=advisory` downgrades only the three `gh` intercepts; L1/L3 always block.
- [x] **A7** `intercept-gh-pr-common.sh` strict mode skips the python passes when the jq-decoded `tool_input.command` has no `gh` token; bats proves a `gh pr create` payload is still classified; existing `intercept-gh-pr-*.bats` green; measured cost on `ls -la` < 50 ms per hook.

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
- 2026-09-03 registration of `pretooluse-bats-check.py` → document-only in `tools/README.md` (settings.json snippet); not added to plugin hooks.json (source: pre-resolved spc-458 Out of scope — maintainer tool, not a plugin hook).
- 2026-09-03 strict pre-filter design → two tiers: tier-1 raw-payload check `no "gh" bytes AND no "\u" escape` (sound because `\uXXXX` is JSON's only letter-producing escape) exits in ~14 ms without jq; tier-2 jq-decoded `tool_input.command` check before the metadata pass. Measured strict non-gh cost 150 ms → 22–28 ms per hook; the ticket's < 50 ms bar needed tier-1 because jq alone costs ~53 ms on this host (source: agent-judgment, reversible; chain source `intercept-gh-pr-common.sh` comment block lines 44-51).
- 2026-09-03 `pretooluse-bats-check.py` `os.system(f"python3 {checker} {tmp}")` → `subprocess.run([...])` while touching the exit code (source: agent-judgment; removes a shell round-trip on an agent-derived path, same class the repo fixed in #453).

## Pending decisions

- Extend the jq pre-filter to the branch-create hook? · context: same ~100 ms cost class · default-if-unanswered: no (separate ticket).

## Attempts

- attempt 1 · 2026-09-03 · direct fix per Approach · suites: intercept-gh-pr-create 83/83, intercept-gh-pr-merge 39/39, intercept-gh-issue-create 15/15, intercept-git-branch-create 21/21, intercept-shippable-write 14/14, pretooluse-bats-check 4/4, validate-skills OK, validate-plugin-versions OK · timing strict non-gh: 154 → 22–28 ms/hook

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
