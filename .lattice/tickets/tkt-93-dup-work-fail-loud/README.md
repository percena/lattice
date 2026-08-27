# tkt-93-dup-work-fail-loud

> **TL;DR:** check-duplicate-work stops failing open — dependency/query failures report as coverage gaps (never "OK"), the documented CJK match branch actually exists, args are guarded, and the script gets its first bats suite
> **Kind:** fix · **Priority:** P1
> **Path:** (ticket-only) → tkt-93 → (pr-…)

| Field | Value |
| --- | --- |
| kind | fix |
| priority | P1 |
| labels | bug, P1 |
| github | https://github.com/percena/lattice/issues/93 |
| status | in-progress |
| adopted | false |
| summary | fail-loud coverage-gap reporting + pipefail + CJK OR-branch + arg guards + bats |
| spec | none — audit rev-20260827-033352Z F5; original contract spc-12 A1 |
| covers | audit F5 |
| blocked_by | (none) |
| parallel_group | G1 (wave 1) |
| paths | skills/_lattice-lib/scripts/check-duplicate-work.sh, skills/_lattice-lib/scripts/tests/** |
| solo_merge | yes |
| **primary_ticket** | tkt-93 (this issue) |
| **related_tickets** | tkt-13/tkt-32 (script origin + earlier json fix) |
| **worktree_bind** | tkt-93-dup-work-fail-loud |
| worktree | sibling …/lattice.worktrees/tkt-93-dup-work-fail-loud/ |
| prs | (none yet) |

## Acceptance (this slice)

- [x] **A1** jq/gh preflight + per-surface query failure → explicit "coverage gap" line, never "OK no possible overlap"; still exit 0 (advisory)
- [x] **A2** `set -euo pipefail`; `${2:-}` guards; bad usage follows the documented advisory behavior
- [x] **A3** CJK OR-branch implemented (shared CJK run ≥3 chars, character-count); ASCII behavior unchanged
- [x] **A4** new bats suite (token match, CJK match, missing-jq gap, gh-failure gap, arg edges); full `ci-local` green

## Approach

Preflight `command -v jq`/`gh` → per-surface `COVERAGE_GAPS+=("issues: jq missing")`; replace `|| echo ""` swallows with explicit capture of the exit status so a failed query marks the surface degraded instead of empty-clean. Final summary prints OK only when all three surfaces actually ran. CJK: extract CJK runs per title (existing tokenizer), add an OR site comparing run substrings ≥3 chars (python3 one-shot for character-aware comparison — the script already requires python3-adjacent tooling via gh/jq? verify; if not, do byte-triples on UTF-8 with the 3-char = 9-byte convention documented). Tests use a stub `gh`/`jq` on PATH (fixture pattern from sibling suites).

## Anticipated decisions

- CJK comparison mechanism (python3 vs pure-bash byte math) — disposition: agent-decides (prefer python3 if already a hard dep of sibling lib scripts; journal the choice)
- Whether a coverage gap changes the exit code — pre-resolved: no; advisory exit 0 is the spc-12 A1 contract, the *text* must stop lying

## Decision journal

- **CJK comparison mechanism → python3 heredoc** (2026-08-27). python3 is already embedded by sibling lib scripts (stamp-pr-open.sh, finish-ledger.sh), so it adds no new dependency class. Implementation: `cjk_shared_run()` collects the CJK-run tokens from both token strings and intersects their character-level trigram sets — any shared CJK substring ≥3 chars implies a shared 3-char substring, so trigram intersection is exact for the ≥3 rule and character-aware (not bytes). Pure-ASCII inputs short-circuit via a byte-level `LC_ALL=C grep` gate before any python3 spawn, so ASCII behavior (and cost) is unchanged. If python3 is missing AND the title contains CJK, that is reported as its own coverage gap (`cjk-matching unavailable (python3 missing)`) rather than silently degrading to token-only matching.
- **Gap taxonomy details** (2026-08-27). (a) jq missing gaps ALL three surfaces, including worktrees — overlap records are jq-built, so the worktree surface cannot report matches without it; honest gap beats a half-running surface. (b) `--skip-remote` is a deliberate caller skip, not a coverage gap; the OK line now counts surfaces actually run ("(2 surfaces checked)" under --skip-remote — the all-green full run keeps the exact legacy "(3 surfaces checked)" string). (c) unknown repository is a gap for both remote surfaces (was a silent skip). (d) gapped-but-no-overlap verdict is a new `INCONCLUSIVE N coverage gap(s)` line; JSON reuses the existing `coverage_gap` status vocab and adds `coverage_gaps` + `surfaces_checked` keys while keeping all legacy keys (loose parsers unaffected). (e) missing option values route through `need_value()` → usage + exit 0, per the pre-resolved advisory contract.

## Pending decisions

## Attempts

## Notes

- The script's own header (line 27) states the principle the implementation violates — fix converges implementation to stated contract, no contract change

## References

- rev-20260827-033352Z F5 · spc-12 A1 · `.lattice/specs/spc-12-skill-gap-bridge.md`

## Lineage

- Parent spec: none (ticket-only) · Primary ticket: **tkt-93** · Parallel group: **G1 (wave 1)** · Worktree bind: `tkt-93-dup-work-fail-loud`

## Finish
