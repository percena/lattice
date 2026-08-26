# Changelog

All notable changes to the **Lattice** toolkit (portable Agent Skills + the `lattice@percena` Claude Code plugin) are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). The packaged plugin adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html); the version in `plugins/lattice/.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` is the canonical release number, and portable skills under `skills/` ship with the same git history.

## [Unreleased]

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
