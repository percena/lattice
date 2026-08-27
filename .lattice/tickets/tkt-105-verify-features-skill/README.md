# tkt-105-verify-features-skill

> **TL;DR:** Ship the 14th user-facing skill — verify-features: lineage-mined feature map with cited oracles, bounded inventory→plan→execute→triage→report loop on run-e2e stories, bugs filed into the existing repro loop — plus the feature-map template and its validator check
> **Kind:** feat · **Priority:** P1
> **Path:** spc-104 → tkt-105 → (pr-…)

| Field | Value |
| --- | --- |
| kind | feat |
| priority | P1 |
| labels | enhancement, P1 |
| github | https://github.com/percena/lattice/issues/105 |
| status | queued |
| adopted | false |
| summary | verify-features SKILL.md + 4 references + feature-map template + validator format check + full surface registration + 0.3.0 cut |
| spec | spc-104 — runtime verification loop |
| covers | A1, A2, A5 |
| blocked_by | spc-104 planning PR |
| parallel_group | (serial — wave 1 of the spc-104 train) |
| paths | skills/verify-features/** (new), skills/_lattice-lib/references/templates/feature-map.md (new), tools/validate-lattice-artifacts.py, tools/tests/**, .claude-plugin/marketplace.json, plugins/lattice/.claude-plugin/plugin.json, plugins/lattice/README.md, plugins/lattice/skills/, README.md, README.zh-CN.md, llms.txt, tools/run-routing-evals.py, evals/routing/**, docs/getting-started.md, CHANGELOG.md |
| solo_merge | yes (after planning PR) |
| **primary_ticket** | tkt-105 (this issue) |
| **related_tickets** | tkt-106/tkt-107 (train siblings), tkt-16/tkt-31 (run-e2e substrate), tkt-14 (bug-repro loop this feeds) |
| **worktree_bind** | tkt-105-verify-features-skill |
| worktree | sibling …/lattice.worktrees/tkt-105-verify-features-skill/ |
| prs | (none yet) |

## Acceptance (this slice)

- [ ] **A1** feature-map template + conventions (columns: id, feature, entry, oracle + source, mutations, risk, story, last-verified, status ∈ untested|pass|fail|blocked); `validate-lattice-artifacts.py` format check when the file exists, fixture-backed tests
- [ ] **A2** verify-features SKILL.md + references (inventory, story/oracle policy incl. invariant bundle, triage + bug filing, report shape) carrying spc-104 Decisions 1/3/4 as INVARIANTs; registered on every enforced surface incl. routing cases
- [ ] **A3** full ci-local green; owns the 0.3.0 cut + CHANGELOG entry

## Approach

New `skills/verify-features/` in the house anatomy (frontmatter with agents + allowed-tools; When to use/NOT; Core rules by severity; Flow; Anti-patterns; Common Rationalizations; Red Flags; Verification checklist; references/). Four references: `inventory.md` (lineage mining recipe: specs A* + binder acceptance + README/docs scan + route grep + bounded ego-browser crawl ≤N pages; map diff + single-writer law), `story-design.md` (oracle hierarchy, per-feature happy/edge/negative, universal invariant bundle, mutation policy table), `triage.md` (failure classes, minimal-repro loop ≤2, bug issue+binder recipe with Reproduction Steps + evidence path, escaped_from tracing pointer to review-delivery), `report.md` (verification rev shape `kind: verification`, coverage stats block, feature-map stamping). Feature-map template lives in `_lattice-lib/references/templates/` (single-source; verify-features cites it). Validator: `feature_map_format` finding (warning-level for rows, error for unknown status vocabulary) gated on file existence. Registration: the #98 validator enforces manifests/plugin README; also README tables (en+zh), llms.txt, getting-started, routing CATALOG + `evals/routing/verify-features.json` (2–3 realistic prompts). Version: 0.3.0 (new skill = minor); canonical cut authored here, shared bytes to 106/107/108.

## Anticipated decisions

- Skill name — pre-resolved: `verify-features` (verb-noun house pattern; "runtime" family name rejected as vague)
- Feature id scheme — agent-decides: `ftr-<kebab-slug>` (stable, human-readable, no counter infra; collision = validator finding); journal
- Validator severity split — agent-decides: unknown status = error, malformed row = warning (lazy migration precedent); journal
- Crawl bound default — agent-decides: ≤20 pages, same-origin only; journal

## Decision journal

## Pending decisions

## Attempts

## Notes

- The skill must NOT require Lattice lineage to function (consumer repos without specs get doc-derived + generic oracles) — degrade documented, never silently
- ego-browser is externally installed (same posture as run-e2e); preflight fail-loud

## References

- spc-104 (Decisions 1–6) · rev-20260827-042618Z · run-e2e SKILL.md (substrate contract) · #98 registration enforcement

## Lineage

- Parent spec: **spc-104** (#104) · Primary ticket: **tkt-105** · Parallel group: **(serial, wave 1)** · Worktree bind: `tkt-105-verify-features-skill`

## Finish
