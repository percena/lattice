# tkt-163 reproduction evidence

## Bug A — build-review-context.sh FETCH_HEAD TOCTOU

**Mechanism (manual minimal repro, 2026-08-28):** after `git fetch origin <branch>` lands, overwrite `.git/FETCH_HEAD` with a baseline OID (simulating a concurrent batch-work fetch from another worktree — FETCH_HEAD lives in the shared common git dir). A subsequent `git show FETCH_HEAD:<path>` returns the **baseline** content, not the fetched head:

```text
poisoned FETCH_HEAD -> 49b43a4 (baseline=49b43a4)
git show FETCH_HEAD:f  →  v1   (expected v2 from the fetched head)
```

**Against the real fixture (pre-fix script):** a git wrapper that poisons FETCH_HEAD to baseline after every fetch yields a manifest labeled `binder source: head:pr-22` whose `- status: in-progress` comes from the poisoned baseline — wrong content under a head label, indistinguishable from correct output.

Post-fix: fetch lands in per-process ref `refs/lattice-review-ctx/<pid>/pr-N`, show reads that ref, ref deleted after; poisoned FETCH_HEAD is never consulted. Same poison fixture → `- status: pr-open` (correct head content).

## Bug B — stamp-pr-open.sh dedup fail-open

Pre-fix: `COMMENTS_JSON=$(gh issue view ... || true)` — on gh failure the empty value skips the `-n` dedup guard and the script posts anyway (duplicate comment), and unparseable JSON took the same path. Reproduced via fake gh returning exit 1 / `not-json{`: pre-fix posts a comment; post-fix skips with a loud WARNING and exits 0 (PR flow unblocked per decision-policy).

## Regression tests (all fail pre-fix, pass post-fix)

- `build-review-context.bats` › "--from-heads is immune to a concurrently-swapped FETCH_HEAD (per-process ref)"
- `stamp-pr-open.bats` › "adopted binder: dedup read failure skips comment post (fail-closed)"
- `stamp-pr-open.bats` › "adopted binder: unparseable comments JSON skips comment post (fail-closed)"

## Side discovery (filed separately)

While validating the race test, found that **bash `set -e` never fires on failing `[[ ]]` or `! cmd`** (POSIX compound-command / negation exemptions; verified raw bash + bats 1.13.0). In bats test bodies this makes mid-body `[[ … ]]` and `! grep …` assertions toothless — only the final command gates the result. This initially masked the race test (it passed on the pre-fix script). ~660 `[[ ]]` assertions across 39 bats files / 744 tests are suspect. Tracked in its own ticket (see issue list); this ticket's new tests use errexit-effective `grep -q` forms.
