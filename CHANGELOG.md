# Changelog

All notable changes to the **Lattice** toolkit (portable Agent Skills + the `lattice@percena` Claude Code plugin) are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). The packaged plugin adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html); the version in `plugins/lattice/.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` is the canonical release number, and portable skills under `skills/` ship with the same git history.

## [Unreleased]

### Added

- **`batch-work` skill** — DAG-orchestrated fan-out: reads `parallel_group` + `blocked_by` from ticket binders, spawns one `start-work` agent per ticket in a sibling worktree, layer-barrier sync, RAM threshold gate, failure isolation. Agents stop at `create-pr`; human reviews then `finish-work` per PR.
- **`run-e2e` skill** — reference pattern for writing ego-browser heredoc JS e2e stories: one Bash invocation per story, fail-loud auth check, structured JSON output via `console.log`. Not a YAML runner; the story file is the test.
- **`check-duplicate-work.sh`** script in `_lattice-lib/scripts/` — advisory duplicate-work precheck across 3 surfaces (open issues, local worktrees, open PRs) with semantic title token matching (≥2 shared tokens or CJK run ≥3 chars). Integrated into `create-tickets` pre-flight and `start-work` pre-flight.
- **Bug reproduction loop** in `start-work` — bug-class tickets (has `bug` label or Reproduction Steps) run Phase 0c (pre-fix reproduction) → Phase 1 (fix) → Phase 1b (post-fix verification with cross-comparison, max 2 cycles).
- **Privacy/Secrets axis** in `finish-work` mini-review and `review-code` — scan diff, PR body, ticket binders, and commit messages for local filesystem paths, API keys/tokens, closed-source project names, and DB schema details. Credentials/secrets → high (default Hold); local paths/project names → med (recommend cleanup).
- **Batch-work marker gate** in `finish-work` — `.lattice/.batch-work-active` marker file blocks `gh pr merge` when batch-work spawned the worktree, keeping a human review gate. Marker-based (not env-var) for reliability across ephemeral Bash sessions.

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
