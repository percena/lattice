# Security Policy

## Supported versions

| Component | Support |
| --- | --- |
| This monorepo on the default branch (`main` / current release line) | Security fixes accepted |
| Published Claude plugin `lattice@percena` (SemVer in `plugins/lattice/`) | Latest released version preferred |
| Forked / vendored copies | Best-effort only |

## Reporting a vulnerability

Please **do not** open a public GitHub issue for undisclosed security problems.

**Preferred:** use [GitHub Security Advisories](https://github.com/percena/lattice/security/advisories/new) for `percena/lattice`.

If advisories are unavailable, email [info@percena.co](mailto:info@percena.co) with `[lattice security]` in the subject.

Include:

- Affected component (skill name, plugin hook, script path, consumer impact)
- Reproduction steps or proof-of-concept **without** weaponized exploit payloads when possible
- Impact assessment (confidentiality / integrity / availability)
- Any known workarounds

We aim to acknowledge reports within **7 days** and to provide a remediation plan or status update within **30 days**. Timelines may vary with severity and complexity.

## Scope notes (Lattice-specific)

Lattice ships **shell scripts**, **agent skill instructions**, and optional **Claude Code hooks** that run in the user’s environment with that user’s `git` / `gh` credentials.

| In scope (examples) | Out of scope (examples) |
| --- | --- |
| Credential leakage via scripts (tokens on argv, logs) | Compromised third-party agent host or model provider |
| Path traversal / unsafe write outside intended `.lattice/` or worktree roots when using shipped scripts as designed | Malicious skill prompts the operator deliberately installs from elsewhere |
| Hook bypass that falsely authorizes bare `gh pr merge` in **strict** mode | Default **advisory** hooks that only warn (not a security boundary by design) |
| Supply-chain issues in this repo’s published packaging metadata | Consumer application vulnerabilities unrelated to Lattice |

Security quality for **PR change-sets** in consumer work is guided by optional side-path skills; those skills are advice, not a merge gate.

## Safe disclosure

Please allow maintainers time to fix and release before public disclosure. Coordinated disclosure is appreciated.
