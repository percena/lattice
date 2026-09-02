| field | value |
| status | pr-open |
| priority | P1 |
| labels | feat, P1 |
| github | https://github.com/percena/lattice/issues/419 |
| spec | spc-416 |
| covers | A6 |
| prs | pr-421 — https://github.com/percena/lattice/pull/421 |
| created | 2026-09-02T13:44:22Z |
| updated | 2026-09-02T15:49:47Z |
| wait_reason | (none) |

## Summary

GHA on pull_request:closed — verifies local stamp landed, repairs Mode C (ledger continuity), catches local stamp failures. CI-dependent safety net (local stamp is primary, CI-independent).

## Scope

- .github/workflows/finish-stamp.yml — pull_request: closed (merged) trigger
- Verifies binder + ledger consistency on merged dev branch
- Invokes finish-stamp.py in CI if stamp missing (idempotent)
- Mode C repair: insert missing intermediate ledger edges
- Commits as github-actions[bot] with contents:write
- Race with local stamp: benign (both idempotent)

## Acceptance

- [x] A6: GHA verifies local stamp + repairs missing ledger entries (Mode C safety net)

## Notes

- Blocked by #418 (finish-stamp.py must exist) — resolved; #418 closed, PR #420 merged.
- CI billing risk: local stamp is primary; GHA is safety net. If billing exhausted, local stamp still works.
- Layer 3 (daily sweep) deferred to follow-up if needed.
- NOTICED: finish-stamp.bats (tkt-418 A9 test suite) is absent — #418 shipped without it. Out-of-paths (tkt-418 scope); follow-up ticket needed if test coverage is required. (out-of-paths, 2026-09-02)
- NOTICED: finish-stamp.py A3 idempotency violated — `stamp_updated` was applied unconditionally before the `written` check, so already-closed binders always staged a timestamp bump (GHA would push noise commits). Fixed in tkt-419 because A6 (GHA safety net) requires a truly idempotent stamp (A3) to avoid noise on every `pull_request:closed`. Fix: compute `content_changed` before the updated-stamp bump; only apply `stamp_updated` when the binder content actually changed. 30/30 existing bats tests pass. (cross-ticket fix, 2026-09-02)
- Verification: dry-run + real idempotent run against PR #420 (tkt-418, already closed) → true no-op (no staged changes, no commit). actionlint clean on finish-stamp.yml + all existing workflows.
