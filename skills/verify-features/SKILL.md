---
name: verify-features
description: "Full-feature runtime verification against a living feature map: mine Spec/ticket lineage (and a bounded UI crawl) into .lattice/feature-map.md with cited expected behavior, design e2e stories per feature (run-e2e/ego-browser substrate), execute bounded waves, triage failures into bug tickets with reproduction steps, stamp coverage. Use when the user wants full-functionality testing, a bug hunt across an app's features, verification that vibe-coded changes actually work end to end, or a coverage picture of what has and hasn't been verified. Not for authoring a single e2e story (run-e2e), PR change-set review (review-code), artifact chain review (review-delivery), or fixing the bugs found (start-work)."
allowed-tools: Bash Read Grep Glob AskUserQuestion
metadata:
  agents: "claude-code,codex"
  domain: quality-side-path
---

# Verify Features

**Runtime quality side-path.** Runs the product, feature by feature, against **explicit expected behavior** — and keeps the coverage ledger honest. The oracle problem (what features exist, what should each do) is answered from **lineage**: Spec `A*` criteria and ticket acceptance are a feature inventory with expectations attached; the committed **feature map** (`.lattice/feature-map.md`) makes coverage diffable and staleness visible. Stories execute on the `run-e2e` pattern (ego-browser); bugs become tickets, never in-pass fixes. (spc-104; design `rev-20260827-042618Z`)

**Runtime path:** before executing skill-owned files, set `LATTICE_SKILL_ROOT` to the absolute directory containing this loaded `SKILL.md` (Claude may already provide `CLAUDE_SKILL_DIR`). Never infer it from consumer cwd.

## Load on demand

| When | Read |
| --- | --- |
| Feature inventory: lineage mining, surface scan, bounded crawl, map diff | `references/inventory.md` |
| Story design: oracle hierarchy, invariant bundle, mutation policy | `references/story-design.md` |
| Failure triage, minimal repro, bug filing, escape tracing | `references/triage.md` |
| Verification report shape + map stamping | `references/report.md` |
| Feature-map file shape | `../_lattice-lib/references/templates/feature-map.md` |
| Story heredoc mechanics (substrate — do not fork) | `../run-e2e/SKILL.md` |
| Delegation and accountable ownership | `../_lattice-lib/references/orchestration-patterns.md` |

## When to use / When NOT

| Use | Not — use instead |
| --- | --- |
| Full-functionality verification of an app (all features, or a risk-ranked subset) | Author/debug one e2e story → `run-e2e` |
| Post-delivery bug hunt: did the vibe-coded changes actually work? | PR change-set bugs → `review-code` |
| Build/refresh the feature map and its coverage picture | Artifact chain review + digest → `review-delivery` |
| Verify the feature set touched by a night's PRs (post-triage, pre- or post-merge) | Fix a found bug → `start-work` (bug-class, Phase 0c repro) |
| Turn "it seems to work" into per-feature pass/fail with evidence | Production-readiness checklist → `review-production` |

## Core rules

### INVARIANT (fail closed)

1. **Oracle-cited pass.** A feature is marked `pass` only when an executed story's JSON evidence exists AND the story asserted that feature's recorded oracle. A pass with no oracle, or from reading code/screenshots without an executed story, is forbidden.
2. **Mutation policy.** Every feature row declares `mutations: none | safe | destructive`. `destructive` (delete / payment / send / external side-effects) is NEVER exercised without per-feature operator authorization recorded in the map. `safe` mutations run only in an operator-designated e2e environment (`.lattice/config.yaml` `e2e_env` allowlist). Default posture: read-only. The browser carries the operator's real login state — treat every unmapped button as loaded.
3. **Fail-loud preflight.** App unreachable, ego-browser missing, or no e2e environment designated for a mutation wave → the affected features are stamped `blocked` with the reason; never a silent skip, never "pass by default". (Same law as run-e2e's auth check and check-duplicate-work's coverage gaps.)
4. **Bounded.** Crawl ≤ 20 same-origin pages; ≤ 12 stories per wave; ≤ 2 waves per invocation; flaky retry ≤ 1. Tunables live in `.lattice/config.yaml` (documented defaults); exceeding a bound stops the pass and reports.
5. **Single-writer map.** Only this skill writes `.lattice/feature-map.md`. Other skills read it; a human edits it like any reviewed artifact.
6. **Files bugs, never fixes.** Product code is never edited in a verification pass. A real bug becomes an issue + binder with Reproduction Steps and evidence (`references/triage.md`); the fix is `start-work`'s job.

### DEFAULT

7. **Universal invariant bundle** on every story regardless of oracle strength: zero `pageErrors`; zero non-allowlisted `consoleErrors`; no unexpected first-party 4xx/5xx (`httpErrors`); no dead-end navigation. Mutation stories additionally assert the **round-trip**: create → reload → verify persisted (the top vibe-code bug class — UI success without persistence).
8. **Oracle hierarchy:** spec-derived (`spc-N A*` citation) > doc-derived (README/docs claim) > generic invariants only. Crawl-discovered features get generic oracles — and their undocumented existence is itself recorded as a lineage-gap finding.
9. **Risk-ranked execution:** waves run highest risk tier first (recently-changed features, mutation surfaces, auth boundaries), so a stopped pass still verified what matters most.
10. **Scoped runs:** with a ticket set / PR set as input, verify only features whose `paths`/entry intersect the change set (plus their map-declared dependents); full sweeps are explicit.
11. Out-of-paths defects noticed while driving the app follow the **Observation duty** (`../_lattice-lib/references/decision-policy.md`) — `NOTICED:` line, keep moving.

### HINT

12. Prefer refreshing an existing map over regenerating it — history (`last-verified`, prior statuses) is the value.
13. A feature failing its story twice with the same signature is a bug candidate even when the oracle is generic; file it with the invariant violated as the expected behavior.

## Flow

0. **Preflight.** Resolve `LATTICE_SKILL_ROOT` → `ensure-lattice.sh`. Confirm ego-browser present and the target app reachable (one probe request); read `.lattice/config.yaml` for `e2e_env` + bounds. Missing → INVARIANT 3.
1. **INVENTORY** (`references/inventory.md`). Mine specs/binders (strong oracles), docs/README (medium), route/nav scan, then a bounded crawl for the unmapped rest. Diff against the existing map; add/update rows (single-writer); set `mutations` conservatively (unknown → `destructive` until classified).
2. **PLAN** (`references/story-design.md`). Per feature in scope: happy-path story + edge/negative where the oracle defines them; attach the invariant bundle; rank by risk tier; respect bounds.
3. **EXECUTE.** Each story = one `run-e2e` heredoc invocation (one Bash call, JSON out, screenshot evidence). Store stories under `.lattice/e2e/stories/` with the traceability header (feature id, oracle citation, mutations class). Flaky (pass-on-retry) → note, retry once max.
4. **TRIAGE** (`references/triage.md`). Classify each fail: `product-bug | test-defect | environment | auth`. Product bugs: minimize the repro (≤ 2 cycles), file issue + binder (Reproduction Steps, evidence path, `found_by`), trace `escaped_from` when the defective change merged through a digest-triaged PR.
5. **REPORT** (`references/report.md`). Stamp the map (`status`, `last-verified`, story ref). Persist a verification rev (`kind: verification`, create-review id conventions): coverage stats (pass/fail/blocked/untested), bug list, map diff, bounds hit.

## Anti-patterns

| Don't | Why |
| --- | --- |
| Mark `pass` from code reading or a screenshot glance | Only an executed story asserting the oracle counts (INVARIANT 1) |
| Explore mutations on a production account "carefully" | The map's mutation class + e2e env allowlist decide, not care (INVARIANT 2) |
| Regenerate the map from scratch each run | Destroys verification history; refresh + diff instead |
| Fix the obvious one-line bug while you're in there | Tester and implementer accountability collapse; file it (INVARIANT 6) |
| Verify only features that have specs | The crawl exists precisely for the undocumented rest; weak oracles beat no coverage |
| Pile every feature into one giant story | One feature-flow per story (run-e2e law); triage needs per-feature evidence |

## Common Rationalizations

| Rationalization | Reality |
| --- | --- |
| "The feature obviously works, the code is right there" | The class of bug this skill exists for is exactly "the code looks right and the feature is broken" — execute the story |
| "No spec for this feature, so nothing to check" | Generic invariants (no errors, no dead ends, persistence round-trip) catch most vibe-code bugs; and the missing spec is itself a finding |
| "It's a test env, deleting is fine" | Only if the env is in the operator's `e2e_env` allowlist AND the row says so — the map is the authority, not the vibe |
| "I'll just re-run until it passes" | Retry bound is 1; a flake is a finding about the story or the app, not noise to grind away |
| "The digest already reviewed these PRs" | review-delivery reads artifacts; it never ran the product. The two are complementary by design |

## Red Flags

- A `pass` row with no story reference or no oracle citation
- A mutation story targeting an origin not in the e2e allowlist
- The map rewritten wholesale in one commit (history destroyed)
- Bug "filed" only in the report prose — no issue, no binder, no repro steps
- A verification pass that edited product code
- More stories executed than the declared bounds allow

## Verification

Before claiming a pass is done:

- [ ] Preflight recorded (app probe, ego-browser, env allowlist) or the pass stopped loud
- [ ] Map refreshed via diff (not regenerated); every new row has oracle + source + mutations class
- [ ] Every executed story: one heredoc invocation, JSON + screenshot evidence, traceability header
- [ ] Every `pass` cites its oracle; every `fail` is triaged into a class; every skipped feature is `blocked` or `untested`, never silently absent
- [ ] Product bugs each have issue + binder with Reproduction Steps + evidence + `found_by` (and `escaped_from` when traceable)
- [ ] Bounds respected and reported; verification rev persisted under `.lattice/reviews/` and map stamped

# References:
- [Inventory recipe](references/inventory.md)
- [Story design + oracle policy](references/story-design.md)
- [Triage + bug filing](references/triage.md)
- [Report + map stamping](references/report.md)
