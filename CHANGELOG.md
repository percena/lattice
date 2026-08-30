# Changelog

All notable changes to the **Lattice** toolkit (portable Agent Skills + the `lattice@percena` Claude Code plugin) are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). The packaged plugin adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html); the version in `plugins/lattice/.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` is the canonical release number, and portable skills under `skills/` ship with the same git history.

## [Unreleased]

## [0.3.0] - 2026-08-27

Runtime verification loop (spc-104, rev-20260827-042618Z; #105–#108): released as a shared train cut — #105 owns the bump and this entry; the round's other bundled PRs carry byte-identical version files. Stacked on the 0.2.4 round (#97–#103). This is the first dev→main promotion (main was 0.1.9); the merge-time bullets below — including the release-train retirement — land with 0.3.0 on main.

### Added

- **`verify-features` skill (tkt-105, #105)** — the 14th user-facing skill: full-feature runtime verification. Mines Spec `A*`/ticket lineage into a committed `.lattice/feature-map.md` (features + cited expected behavior + mutation class + verification stamps; single-writer), designs per-feature e2e stories with an oracle hierarchy (spec-derived > doc-derived > generic invariants) and a universal invariant bundle (page/console/http errors, dead ends, mutation round-trip), executes bounded waves on the `run-e2e`/ego-browser substrate, triages failures, and files real bugs as tickets with Reproduction Steps that feed start-work's Phase 0c repro loop. Mutation-safety INVARIANT: destructive surfaces are never exercised without per-feature written operator authorization; safe mutations only in the operator's e2e env allowlist.
- **Feature-map template + validator checks (tkt-105, #105)** — `_lattice-lib/references/templates/feature-map.md`; `validate-lattice-artifacts.py` gains `feature_map_status` (error) and `feature_map_row_format` (warning) when `.lattice/feature-map.md` exists.


### Changed

- **Release-train retirement (spc-116, ADR-005, #117–#120)** — the strict per-landing version-bump law ("bundled content changed without a version increment") now fires only at the dev→main **release boundary** (`--release-check` flag, base-ref = `origin/main`); dev landings enforce only the non-decrease hard bottom. This retires the entire train compensation mechanism: `train_cut_shared()`, `--no-train`, the linear-push guard, the batch-work orchestrator unified-cut step, and spawn-brief contract item 6 are all deleted. `finish-work` gains a dev→main pre-merge version-bump check step. `ci-local` defaults to lenient dev-mode; `--release-check` simulates the main-boundary strict pass. The train mechanism (tkt-60, tkt-114) existed solely to suppress false-positive reds on an integration branch with no cache consumers.

### Also in 0.3.0 (merge-time bullets, train members)

- **run-e2e upgrades (tkt-106, #113)** — `httpErrors` capture (first-party 4xx/5xx + requestfailed, allowlist filters assertions never evidence), story traceability header (feature/oracle/mutations), mutation round-trip recipe (reload → assert persisted; `leftovers` reporting), story catalog `.lattice/e2e/stories/`.
- **Escaped-defect metric (tkt-107, #111)** — bug binders carry `found_by`/`escaped_from` lineage; every digest counts escapes per triage class; spc-42's risk-tiered auto-merge revisit trigger armed.
- **Audit recipe (tkt-108, #112)** — the verified-audit method becomes create-review law (`kind: audit`): fan-out, verify-then-report, enforcement coverage, claim reconciliation, history archaeology, mechanism pairing; review-code docs-sync gains claim reconciliation.

## [0.2.4] - 2026-08-27

Post-round-4 verified audit batch (rev-20260827-033352Z, #90–#96): released as a shared train cut — #90 owns the bump and this entry; the other bundled PRs of the round carry byte-identical version files (canonical manifest blobs owned by #94). Merge-time bullets for the train's other tickets are appended below their PR merges.

### Fixed

- **Binder lifecycle closure (tkt-90, #90)** — `finish-ledger.sh` now flips any working status (`open`, `queued`, `in-progress`, `pr-open`, `rework`) to `closed` at ledger time; previously only the legacy `open` literal matched, so every binder stamped `pr-open` by `stamp-pr-open.sh` stayed stranded after merge — 19 binders restamped `closed`, `spc-12` land-stamped retroactively, and the historical `tkt-35` id collision resolved by renaming the impostor to its true id (`tkt-38`, per its own issue row).

### Added

- **Validator: `finish_without_terminal_status` + `duplicate_ticket_id` (tkt-90, #90)** — error-level findings: a merged `## Finish` ledger with a non-terminal status, and two binder dirs claiming one `tkt-N`. `docs/workflow-fsm.md` §5 and ADR-004 §6 amended to state exactly what the validator checks (static snapshot coherence, not transition-history replay).

### Also in 0.2.4 (merge-time bullets, train members)

- **prs-row grammar single-sourced (tkt-91, #103)** — `lib/binder_rows.py` owns placeholder/canon/joiner; both writers emit the comma canon, bare `pr-N` never; build-review-context placeholder predicate + `--from-heads` ADR scan fixed.
- **CI enforcement (tkt-92, #101)** — new `artifacts.yml` workflow (artifact validator on PR + main/dev push); all workflows fire on dev pushes; finish-work red-run disposition duty; two vacuously-true bats guards fixed.
- **check-duplicate-work fail-loud (tkt-93, #99)** — coverage gaps reported instead of false "OK", `pipefail`, documented CJK match branch implemented (character-aware), arg guards, first bats suite (10), post-review numeric guard on gh payloads.
- **Registration surface integrity (tkt-94, #98)** — 13-skill parity on manifests/plugin README/llms.txt/lib inventory; `validate-skills.sh` now errors on keyword/README drift; routing catalog parity-tested (evals 100%).
- **Docs truth (tkt-95, #97)** — ADR-002 dated amendment (env gate → marker), README tier count, getting-started preferences.md coverage, day-phase/CHANGELOG corrections, batch tunables documented.
- **Observation duty (tkt-96, #102)** — decision-policy `NOTICED:` capture law for out-of-paths defects + review-delivery digest sweep.
- **Train gate linear/ancestor fix (tkt-114, #115)** — release-train acceptance now covers integration-branch push events and post-cut branch updates; mid-train dev pushes stay green, promotion restores the strict law.

## [0.2.3] - 2026-08-26

Helper polish from the first unattended consumption (digest rev-20260826-172600Z Findings 3–6, #81) plus the tkt-84 preference-capture law (#88): two-PR shared train cut — #89 owned the version bump, #88 carried the byte-identical cut.

### Added

- **Proactive preference capture** — decision-policy "Capture duty" INVARIANT: the active skill writes operator-stated preferences at utterance time (direct entry + provenance + one-line confirm); routing heuristic (preference / Spec Decisions / ADR); wired into start-work, finish-work, batch-work.
- **`stamp-pr-open.sh --check-all`** — checks every unchecked binder acceptance box, then mirrors to the issue; REFUSED when the binder Acceptance section carries a deferral note (a line containing "defer"), forcing explicit per-box checking. Usage header now states the ordering law: check binder boxes, then stamp — the issue sync mirrors only checked boxes.
- **`build-review-context.sh --from-heads`** — pre-merge mode: for each ticket with an open PR, fetches the PR head (read-only, `FETCH_HEAD` only) and reads binder state via `git show`, falling back to the local file; each manifest entry marks its source (`local` vs `head:pr-N`).

### Fixed

- **`finish-ledger.sh` / `stamp-pr-open.sh`** now REPLACE any `(none…)` prs-row placeholder variant with the canonical `pr-N — <URL>` entry instead of appending beside it (the tkt-43 duplication class); filled rows keep the append/merge behavior.
- **batch-work spawn-brief template** carries an explicit "Never `git add -A`; stage named paths" line — 2 of 3 round-3 agents hit the reflex and staged the batch marker.

## [0.2.2] - 2026-08-26

Deferred validator items from tkt-65 (#74): single-PR bump.

### Added

- **`prs_row_format` warning** in `validate-lattice-artifacts.py` — a filled binder `prs` row must match the canonical `pr-N — <URL>` format (em dash; comma-separated entries for multi-PR tickets); `(none…)` placeholders are exempt. Warning-level permanently — adopt flows may reintroduce legacy rows.
- **`preferences.md`** joined `lattice-init.sh`'s `assert_managed_paths_safe` list — initialization now refuses a symlinked `.lattice/preferences.md` before any mutation (matching ensure-lattice's existing refusal).

## [0.2.1] - 2026-08-26

Release train for the process-hardening batch (tkt-60…tkt-65, issues #60–#65): one identical cut on every train branch.

### Added

- **Release-train mode** in `validate-plugin-versions.py` — equal-version passes when the version files carry a byte-identical cut shared with the base (SemVer still increased since fork); `--no-train` restores the unconditional strict law. create-tickets paths gate now names implicit shared files.
- **Skill registration integrity** — validate-skills asserts every `skills/` dir is registered (USER_FACING/EXEMPT) and bundled; backfilled plugin symlinks for batch-work, generate-wiki, review-code, review-production; batch-work + run-e2e joined USER_FACING; CONTRIBUTING gains the new-skill checklist.
- **`tools/ci-local.sh`** — one-command local CI parity (all validators, shellcheck, evals, every bats suite); wired into the batch-work evidence contract.
- **Batch ergonomics** — check-pr-context batch-marker whitelist; `stamp-pr-open.sh` (binder prs/status + issue-body acceptance sync in one idempotent step).
- **Merge-train hardening** — finish-work CI-checks gate in the train recipe, file-explicit conflict law, post-merge marker sweep, orphaned-run hygiene; `update-pr-base.sh` emits `diff_changed`/conflict signals; mini-review text single-sourced.
- **Template/validator debts** — binder header-status dedup + canonical prs format, fsm fuse wording, label taxonomy sync, ensure-lattice symlink alignment, `find-spec.sh`.


## [0.2.0] - 2026-08-26

Release train for `spc-42` (attention loop): one identical version cut carried by every PR in the train (#52, #54–#58 + batch-work night upgrades); bundled-content increments land once for the whole set.

### Added

- **`decision-policy.md` + `fallback-policy.md`** (`_lattice-lib/references/`) — unattended decision resolution (chain, reversibility × blast-radius, park & pivot, journal contract) and bounded fallback (articulated-difference retries, caps, early-stop, batch fuse, stuck-with-ledger). ADR-004 §2/§5.
- **Binder FSM** — ticket binder `status` extended in place (`queued | in-progress | parked | stuck | pr-open | rework | deferred`, terminal `closed`, legacy `open` warns) + new sections `## Approach`, `## Anticipated decisions`, `## Decision journal`, `## Pending decisions`, `## Attempts`; `validate-lattice-artifacts.py` gains warning-level findings and status/transition checks.
- **`review-delivery` skill** — artifact-only chain review (A*→evidence fidelity, cross-PR coherence with throwaway integration build, decision-ratification queue, per-PR findings) + `build-review-context.sh` manifest builder + ranked morning digest with per-axis attestation. Never merges; never a gate.
- **Team preferences** — `ensure-lattice.sh` scaffolds `.lattice/preferences.md` (INVARIANT/DEFAULT/HINT) with promotion (×2-ratified) and supersede-with-date lifecycle. ADR-004 §3.
- **`create-tickets` anticipated-decisions scan** — per-ticket read-only dry-run at split time emits dispositioned decision points + `## Approach` sketch; dispositions ride the single delivery-meta batch.
- **Re-entry edges** — `start-work` resume honors `rework` (findings-as-brief, same PR), `parked` (atomic ratify → queued), `stuck` (operator-chosen exits); `finish-work` voids review verdicts on materially changed base updates and stamps `rework` on Hold-with-findings.
- **`batch-work` night upgrades** — decision/fallback/evidence contracts injected into spawn briefs, per-ticket watchdog/timebox, layer fuse with graceful drain, `--with-review` chaining review-delivery with a bounded fix loop.
- **Docs** — `docs/workflow-fsm.md` (three coupled machines, transition owners, bounded-loop invariant) and `docs/day-phase.md` (attended planning recipe). ADR-004.

- **`batch-work` skill** — DAG-orchestrated fan-out: reads `parallel_group` + `blocked_by` from ticket binders, spawns one `start-work` agent per ticket in a sibling worktree, layer-barrier sync, RAM threshold gate, failure isolation. Agents stop at `create-pr`; human reviews then `finish-work` per PR.
- **`run-e2e` skill** — reference pattern for writing ego-browser heredoc JS e2e stories: one Bash invocation per story, fail-loud auth check, structured JSON output via `console.log`. Not a YAML runner; the story file is the test.
- **`check-duplicate-work.sh`** script in `_lattice-lib/scripts/` — advisory duplicate-work precheck across 3 surfaces (open issues, local worktrees, open PRs) with semantic title token matching (≥2 shared tokens or CJK run ≥3 chars). Integrated into `create-tickets` pre-flight and `start-work` pre-flight.
- **Bug reproduction loop** in `start-work` — bug-class tickets (has `bug` label or Reproduction Steps) run Phase 0c (pre-fix reproduction) → Phase 1 (fix) → Phase 1b (post-fix verification with cross-comparison, max 2 cycles).
- **Privacy/Secrets axis** in `finish-work` mini-review and `review-code` — scan diff, PR body, ticket binders, and commit messages for local filesystem paths, API keys/tokens, closed-source project names, and DB schema details. Credentials/secrets → high (default Hold); local paths/project names → med (recommend cleanup).
- **Batch-work marker gate** in `finish-work` — `.lattice/.batch-work-active` marker file blocks `gh pr merge` when batch-work spawned the worktree, keeping a human review gate. Marker-based (not env-var) for reliability across ephemeral Bash sessions.
- **review-code skill extended** — added CI/CD, syntax/lint, docs-sync, and interface/contract impact axes; solution-oriented findings (recommended solution + alternatives); single batch confirmation (one AskUserQuestion, never per-finding). `finish-work` mini-review unchanged. See [ADR-003](docs/adr/003-review-code-extended-axes-and-solution-oriented-findings.md).

### Fixed

- Fix broken `run-e2e` plugin symlink (4→3 relative levels) so the skill is reachable when installed via `plugins/lattice/`.
- Fix `check-duplicate-work.sh` `--json` output: build overlap objects via `jq -nc --arg` instead of hand-concatenation, preventing invalid JSON when issue/PR titles contain double-quotes or backslashes.
- Fix `check-duplicate-work.sh` worktree surface double-counting: title tokens are now counted once per worktree (union of branch-token match and path-substring match), preventing false positives from common 3-letter words.
- Replace unreliable `BATCH_WORK=1` env-var gate with marker-file mechanism (` .lattice/.batch-work-active`) that survives across ephemeral Bash sessions in spawned agents.
- Fix dead `ego-browser` markdown link in `run-e2e` SKILL.md (relative path to non-existent `../../ego-lite/` replaced with name reference).
- Remove closed-source project name leakage from test fixtures.
- Serialize `finish-ledger.sh` rewrites on the binder directory inode so high-contention sibling PR stamps cannot split across unlinked sidecar locks and lose entries.
- Resolve Finish repository identity as case-insensitive `host/owner/repo`, including GitHub Enterprise and offline host-preserving URLs, while keeping cross-repository stamping fail-closed.
- Repair the online `gh pr view` / `gh issue view` JSON parsers used by `finish-ledger.sh`; real GitHub lookups no longer fail with an embedded Python `SyntaxError`.
- Recognize the full Bash/POSIX redirection family and arbitrary command-runner prefixes around direct `gh pr create` / `gh pr merge` calls; strict hooks no longer depend on an exhaustive wrapper allowlist.

## [0.1.0] - 2026-08-01

### Added

- Initial public release of Lattice. The six lifecycle skills (`start-work`, `create-spec`, `create-review`, `create-tickets`, `create-pr`, `finish-work`) plus `_lattice-lib`, the `create-adr` out-of-band ADR companion, optional PR-scoped quality side-paths (`review-code`, `review-production`), the `generate-wiki` doc tool, and optional `gh pr create/merge` advisory hooks (Claude Code).

### Fixed

- Make `create-adr` fail closed for malformed/missing ADR paths and duplicate numbers, atomically claim new ADR files, and serialize README index replacement so concurrent writers cannot silently overwrite files or lose rows.
- Recognize documented `gh --repo/-R … pr create|merge` flag placements in optional hooks.
- Preserve repository identity when listing multi-repository GitHub Project items.
- Bind post-merge issue closing to the pre-merge approved closing-id set.
- Support metadata-only validation on the first published branch push.

### Security

- Resolve installed helpers only from an absolute host-provided skill root; never execute consumer-cwd fallbacks.
- Reject symlinked or out-of-worktree asset uploads unless an outside path is explicitly approved.
- Resolve optional label synchronization only from the physical trusted sibling skill install, including when the initializer entrypoint is reached through a symlink; never execute a consumer-repository fallback.
- Reject symlinked `.lattice` managed paths and symlinked `.gitignore` targets before initialization writes.
