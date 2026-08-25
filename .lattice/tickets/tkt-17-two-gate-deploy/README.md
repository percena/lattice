# tkt-17-two-gate-deploy

> **TL;DR:** Two-gate deploy quality sub-pipeline for deploy-weftd-flitro — diff classify + review-code + tests + Gate 1/2
> **Kind:** feat · **Status:** open · **Priority:** P2
> **Path:** spc-12 → tkt-17 → (pr-…)

| Field | Value |
| --- | --- |
| kind | feat |
| priority | P2 |
| labels | enhancement, P2 |
| github | https://github.com/percena/lattice/issues/17 |
| status | open |
| adopted | false |
| summary | two-gate deploy quality sub-pipeline for deploy-weftd-flitro (diff classify + review + tests + gates) |
| spec | spc-12 — Lattice skill-gap bridge (path: ../../specs/spc-12-skill-gap-bridge.md) |
| covers | A4 |
| blocked_by | (none) |
| parallel_group | G1 (parallel, cross-repo) |
| paths | deploy-weftd-flitro/SKILL.md (weftd repo), possibly _lattice-lib/scripts/ |
| solo_merge | yes |
| **primary_ticket** | tkt-17 (this issue) |
| **related_tickets** | (none) |
| **worktree_bind** | tkt-17-two-gate-deploy |
| worktree | sibling (in weftd repo, not lattice repo) |
| prs | (none) |

## Acceptance (this slice)

- [ ] **A4** deploy-weftd-flitro has a pre-deploy quality sub-pipeline: diff classification (changed files → weftd frontend / flitro+agentd / docs-only → skip deploy), review-code scan on the diff (advice-only), available test run, Gate 1 (scope + classification confirm, user present, fast-fail), Gate 2 (review findings + test results + deploy plan → final approval), post-deploy health check

## Notes

- Cross-repo ticket: deploy-weftd-flitro lives in weftd repo (`/Users/mxue/GitRepos/MVP/weftd/.claude/skills/deploy-weftd-flitro/`)
- Also mirrored at `/Users/mxue/.claude/skills/deploy-weftd-flitro/`
- ADR-002 §4: reuses Lattice review-code contract (advice-only), NOT ERP guard.sh or verify-code
- Existing WS-5 schema gate (DB precondition) stays as-is — this ticket adds quality gates, not DB gates
- Existing SERVICE selector (manual all/weftd/agentd) stays — this ticket adds automatic diff classification
- Two-gate pattern borrowed from ERP's fast-deploy in shape only

## References

- GitHub issue body is SoT for long prose
- Spec: `spc-12` (path above)
- ADR: `ADR-002` → `docs/adr/002-lattice-skill-gap-bridge-adaptations.md`
- Review: `rev-20260825-072540Z` Finding 4
- ERP reference: `/Users/mxue/GitRepos/FlowDance/erp/.claude/skills/fast-deploy/SKILL.md` (two-gate pattern)
- Current deploy skill: `/Users/mxue/.claude/skills/deploy-weftd-flitro/SKILL.md`

## Lineage

- Parent spec: **spc-12**
- Parent issue (GH sub-issue): **#12**
- Primary ticket: **tkt-17**
- Related / sub-tickets: (none)
- Covers: **A4**
- Blocked by: (none)
- Parallel group: **G1 (parallel, cross-repo)**
- Worktree bind: `tkt-17-two-gate-deploy`
- Child PRs: (none yet)

## Assets

Local files in `./assets/`.

## Finish

- (none yet)
