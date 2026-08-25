# tkt-16-ego-browser-e2e-story

> **TL;DR:** ego-browser e2e-story reference layer — heredoc JS script template with assertion primitives + fail-loud auth
> **Kind:** feat · **Status:** open · **Priority:** P2
> **Path:** spc-12 → tkt-16 → (pr-…)

| Field | Value |
| --- | --- |
| kind | feat |
| priority | P2 |
| labels | enhancement, P2 |
| github | https://github.com/percena/lattice/issues/16 |
| status | open |
| adopted | false |
| summary | ego-browser e2e-story reference layer — heredoc JS + assert + fail-loud auth + JSON output |
| spec | spc-12 — Lattice skill-gap bridge (path: ../../specs/spc-12-skill-gap-bridge.md) |
| covers | A4 |
| blocked_by | (none) |
| parallel_group | G1 (parallel) |
| paths | skills/e2e-story/ or references/ (new) |
| solo_merge | yes |
| **primary_ticket** | tkt-16 (this issue) |
| **related_tickets** | (none) |
| **worktree_bind** | tkt-16-ego-browser-e2e-story |
| worktree | sibling …/lattice.worktrees/tkt-16-ego-browser-e2e-story/ |
| prs | (none) |

## Acceptance (this slice)

- [ ] **A4** `e2e-story` reference template exists (heredoc JS pattern for ego-browser) with goto/click/fill/select/press/screenshot/assert primitives, fail-loud auth check (expected auth but landed on login page → FAIL), structured JSON output via `console.log`, and at least one example story for weftd or flitro

## Notes

- Independent of all other tickets (G1 parallel, own PR, own worktree)
- ADR-002 §2: ego-browser is the approved foundation, NOT ERP's auto-playwright
- ego-browser v1.2.6 at `/Users/mxue/GitRepos/infra/ego-lite/skills/ego-browser/SKILL.md`
- Uses heredoc JS via `ego-browser nodejs <<'EOF'`, NOT a YAML runner
- Primitives map to ego-browser's page/locator API (goto→page.goto, click→locator.click, assert→page.evaluate)
- Fail-loud auth: if expected auth but landed on login page → story FAILS

## References

- GitHub issue body is SoT for long prose
- Spec: `spc-12` (path above)
- ADR: `ADR-002` → `docs/adr/002-lattice-skill-gap-bridge-adaptations.md`
- Review: `rev-20260825-072540Z` Finding 5
- ego-browser: `/Users/mxue/GitRepos/infra/ego-lite/skills/ego-browser/SKILL.md` (v1.2.6)
- ERP reference: `/Users/mxue/GitRepos/FlowDance/erp/.claude/skills/auto-playwright/SKILL.md` (story DSL concept, NOT runtime)

## Lineage

- Parent spec: **spc-12**
- Parent issue (GH sub-issue): **#12**
- Primary ticket: **tkt-16**
- Related / sub-tickets: (none)
- Covers: **A4**
- Blocked by: (none)
- Parallel group: **G1 (parallel)**
- Worktree bind: `tkt-16-ego-browser-e2e-story`
- Child PRs: (none yet)

## Assets

Local files in `./assets/`.

## Finish

- (none yet)
