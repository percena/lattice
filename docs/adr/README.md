# Architecture Decision Records (ADR)

## Index

| ADR | Title | Status | Supersede / amend |
| --- | --- | --- | --- |
| [001](./001-dependabot-github-actions-policy.md) | Dependabot GitHub Actions upgrade policy | Accepted | — |
| [002](./002-lattice-skill-gap-bridge-adaptations.md) | Lattice skill-gap bridge — ERP pattern adaptation strategy | Accepted | Amended 2026-08-27 (§3 env gate → marker; skill count) |
| [003](./003-review-code-extended-axes-and-solution-oriented-findings.md) | review-code skill — extended axes (CI/CD, syntax/lint, docs-sync, interface-impact) + solution-oriented findings | Accepted | — |
| [004](./004-attention-contract-and-night-shift-delivery.md) | Attention contract and night-shift delivery laws | Accepted | — |
| [005](./005-version-bump-at-release-boundary.md) | Version bump enforced at dev→main release boundary, not per-PR on dev | Accepted | — |
| [006](./006-worktree-discipline-hard-enforcement.md) | Worktree discipline via PreToolUse hard enforcement (location gate + interactive-confirmation escape) | Accepted | — |
| [007](./007-hard-limit-scope-law.md) | Hard-limit scope law — constrain transitions, free deliberation; compiled corner cases and human-adjudicated exceptions | Accepted | — |
| [008](./008-batch-work-process-isolation-spawn.md) | Batch-work process-isolation spawn mode | Accepted | — |
| [009](./009-platform-stratified-e2e-runtime.md) | Platform-stratified e2e runtime + confirm-first preflight | Accepted | — |
| [010](./010-review-release-boundary-merge-review-mode.md) | review-code + review-production release-boundary merge-review mode | Accepted | — |
| [011](./011-consumer-repo-footprint-hygiene.md) | Consumer-repo footprint hygiene — relocate runtime state, bootstrap tracked gitignore | Accepted | — |
| [012](./012-transitions-stamped-by-the-path.md) | Transitions are stamped by the path, not by the agent — ledger coverage as conformance sensor | Accepted | — |
| [013](./013-finish-ledger-ledger-write-separation.md) | Post-merge ledger stamping — belt-and-suspenders (simplified local stamp + GHA safety net) | Proposed | Revises initial proposal twice (Option A rejected → Option E single-point-of-failure → Option E+); implements ADR-012 §5 |
