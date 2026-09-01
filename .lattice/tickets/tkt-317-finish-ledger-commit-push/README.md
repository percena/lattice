# tkt-317 — finish-ledger.sh writes binder but never commits/pushes; finish-work SKILL.md step 10 overclaims

| Field | Value |
| --- | --- |
| id | tkt-317 |
| issue | #317 |
| slug | finish-ledger-commit-push |
| adopted | false |
| kind | bug |
| priority | P2 |
| status | in-progress |
| github | https://github.com/percena/lattice/issues/317 |
| paths | `skills/_lattice-lib/scripts/finish-ledger.sh`, `skills/finish-work/SKILL.md` |
| ship | one-PR |
| created | 2026-09-01T12:48:52Z |
| updated | 2026-09-01T12:48:52Z |

## Why

`finish-ledger.sh` writes the `## Finish` ledger into the binder and stages only the `.transition-ledger/<tkt>.jsonl` — but never `git add`s the binder, never commits, never pushes. `finish-work/SKILL.md` step 10 claims the helper "then commit + push the base branch." This doc/impl mismatch leaves the working tree dirty after every finish, forcing manual `git add`/`commit`/`push` (observed live during PR #313: 4 binders stamped → 3 manual cleanup commits + idempotent `(reason: completed)` refinements re-dirtied the tree).

## Scope (In)

- `finish-ledger.sh`: `git add` the binder README alongside the transition-ledger JSONL; remove duplicate trailing `exit 0`.
- `finish-work/SKILL.md` step 10: correct the overclaim — finish-ledger.sh writes + stages; the finish-work flow commits + pushes once after the per-binder loop.
- `finish-work` short path: add an explicit commit + push step after the finish-ledger loop.
- Idempotency: re-running finish-ledger.sh on an already-stamped binder must not re-dirty committed lines (`(reason: completed)` refinement no-op when a reason is already present).

## Out

- Re-architecting finish-ledger.sh to commit per-binder (keep the one-invocation-per-binder → one-commit design).
- The spc-277/tkt-278 parallel-operator drift from PR #313 (not this bug — verified scripts scope to `--binder`).
- transition-api.py (pure file I/O, no git ops — out of scope).

## Acceptance (from issue)

- [ ] finish-ledger.sh stages the binder README (`git add <binder>`) alongside the transition-ledger JSONL; duplicate trailing `exit 0` removed.
- [ ] finish-work/SKILL.md step 10 corrected: finish-ledger.sh writes + stages; the finish-work flow commits + pushes once after the per-binder loop (no overclaim).
- [ ] finish-work short path has an explicit commit + push step after the finish-ledger loop.
- [ ] Re-running finish-ledger.sh on an already-stamped binder does not re-dirty committed lines (reason refinement is a no-op when a reason is already present).
- [ ] One fresh finish-work cycle (local or observed) lands clean with no manual `git add`/`git commit`/`git push` intervention.

## Approach

1. Read `finish-ledger.sh` tail (the post-Python bash section, ~line 614+): the `git add "$LEDGER_FILE"` line. Add `git add "$BINDER"` next to it so the binder is staged for the caller's commit.
2. Remove the duplicate trailing `exit 0` (dead code).
3. In the idempotency path (the `elif s != orig` branch that re-writes via `os.replace`), guard the `(reason: completed)` refinement so it does not mutate a line that already carries a parenthesized reason — make it a no-op `s == orig` when the only change would be that refinement.
4. `finish-work/SKILL.md` step 10: replace "then commit + push the base branch" (attributed to the script) with "finish-ledger.sh writes + stages; the finish-work flow then commits + pushes once after the per-binder loop." Add a short-path bullet: after the finish-ledger loop, `git add` (if not already) + `git commit -m "finish(tkt-…): stamp Finish ledger — pr-N merged"` + `git push`.
5. Verify: re-read edited sections; run `bash skills/_lattice-lib/scripts/tests/finish-ledger.bats` (if present) + `tools/ci-local.sh --fast` lattice-artifacts step.

## Anticipated decisions

| Decision | Disposition | Note |
| --- | --- | --- |
| Should finish-ledger.sh itself `git commit`/`push` (vs. just staging)? | pre-resolved | No — keep one-commit-per-loop design; script stages, flow commits once. Avoids N commits for N-ticket batches. |
| Where to stage the binder — inside the Python `commit_transaction` or the bash tail? | pre-resolved | Bash tail (`git add "$BINDER"` next to the existing `git add "$LEDGER_FILE"`) — the Python is locked-file-IO; git ops stay in bash. |
| Should the `(reason: completed)` refinement be removed entirely vs. guarded? | agent-decides | Guarding (no-op when reason present) is lower-risk than removing; confirm during EXECUTE by reading the prepare_commit_text logic. |
| finish-work short-path commit message format | pre-resolved | Match the existing convention: `finish(tkt-…): stamp Finish ledger — pr-N merged, #M closed`. |

## Notes

- Root-caused during PR #313 finish (tkt-307..310). The spc-277/tkt-278 working-tree drift seen there was parallel operator activity (user M1n9X committed 638184d + ran finish-ledger on dev in parallel), NOT this bug — verified stamp-pr-open.sh / transition-api.py / finish-ledger.sh all scope to the single `--binder` + its own ledger.
