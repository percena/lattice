# Changelog

All notable changes to the **Lattice** toolkit (portable Agent Skills + the `lattice@percena` Claude Code plugin) are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). The packaged plugin adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html); the version in `plugins/lattice/.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` is the canonical release number, and portable skills under `skills/` ship with the same git history.

## [Unreleased]

### Fixed

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
