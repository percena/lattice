# Triage — from failed story to filed bug

Every `fail` gets exactly one class before the report. Never leave a fail unclassified, never fix product code (INVARIANT 6).

## Classes

| Class | Signature | Disposition |
| --- | --- | --- |
| `product-bug` | Oracle or invariant violated by app behavior; reproduces | Minimize → file (below); map row `fail` |
| `test-defect` | Story asserted the wrong thing / brittle locator / bad wait | Fix the STORY (stories are in-scope files), re-run once; map row keeps prior status until a clean run |
| `environment` | App down mid-run, seed data missing, env not allowlisted | Map row `blocked` + reason; no bug filed |
| `auth` | Landed on login unexpectedly (run-e2e fail-loud) | Map row `blocked (auth)`; surface to operator — session/task-space issue, not a product verdict |

Flaky (pass on the single allowed retry): record `flaky` in the report with both JSONs; a flake twice across runs is a `product-bug` candidate (timing bugs are bugs).

## Minimal repro (bound: ≤ 2 cycles)

Strip the failing story to the shortest sequence that still violates the oracle; capture the final JSON + screenshot. If it stops reproducing during minimization, keep the last reproducing version — do not chase further (bound), file with it.

## Filing (bug-class ticket, existing loop)

1. `bash <lib>/check-duplicate-work.sh --title "<bug title>"` — advisory; link overlaps instead of duplicating.
2. `gh issue create` — label `bug` + priority; body carries **Reproduction Steps** (the minimized sequence, numbered), expected (oracle text + citation), actual (JSON `reason` + evidence), environment.
3. Binder `.lattice/tickets/tkt-<issue#>-<slug>/README.md` — standard template plus:
   - `| found_by | verify-features rev-<this pass's rev id> |`
   - `| escaped_from | pr-N — digest rev-… (auto-pass) |` when tracing succeeds (below); omit the row when it doesn't.
   - Reproduction Steps section + evidence path — this is what `start-work` Phase 0c replays.
4. The verification rev lists every filed ticket; the map row's `status` cell references it (`fail (tkt-N)`).

## Escape tracing (spc-104 A4 — feeds spc-42's trust calibration)

1. Locate the defective behavior's code: `git log -S '<distinctive string>'` or blame the implicated lines → the merge PR.
2. `grep -rln 'pr-N' .lattice/reviews/` → the digest that triaged it; read its per-PR class.
3. `auto-pass` → `escaped_from: pr-N — digest rev-… (auto-pass)`. `ratify-then-pass` → same row, class noted (counted separately by the digest metric). `deep-review` or pre-digest history → no escape; omit.
4. Tracing is best-effort with a bound of one attempt per bug — an untraceable bug is filed without the row, never guessed.
