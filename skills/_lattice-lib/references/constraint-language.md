# Constraint language (Lattice skills)

Portable labels for skill prose. **Scripts and true result gates stay hard.**
Prose and scripts must not invent a second methodology police layer (anti–Superpowers).

Use these labels in Core rules / tables when severity matters.  
Inspired by Agent Skills progressive disclosure + Anthropic “degrees of freedom”; not a new product surface.

## Labels

| Label | Meaning | Model freedom | Examples |
| --- | --- | --- | --- |
| **INVARIANT** | Result must hold; fail closed if violated | Path/order free; **outcome not free** | Honor user authority; prevent unproved data loss; verify repo/PR identity; `spc-N` = real GH issue #; no PR from live default; fresh evidence before completion claims |
| **DEFAULT** | Preferred happy path; override with user opt-in, profile, or stated equivalent-proof reason | High — skip when context already satisfies intent | Sibling worktree; tkt/spc bind; Review→Spec→tickets order; PCA batch size 2–5; skill reminder hooks |
| **HINT** | Quality or style guidance; never block ship alone | Full | Response brevity; “prefer templates”; progress comments on multi-day PRs |

## Rules of use

1. **Do not write DEFAULT/HINT as NEVER / HARD / must** unless the same rule is also an **INVARIANT** enforced by script or contract.
2. **Scripts > prose** for fragile outcome checks (`cleanup-workspace`, `alignment-check`, `check-pr-context`). Method helpers (`ensure-workspace`, `assert-shippable-cwd`, hooks) keep safe defaults and explicit evidence-bearing escapes.
3. **Progressive disclosure:** put long step scripts in `references/`; keep `SKILL.md` as overview + invariants + short path.
4. **Delegation:** follow `orchestration-patterns.md` — one accountable owner, bounded scope, disjoint writes, final validation; do not ban actors categorically.
5. **Equivalent-proof escape:** when a DEFAULT is skipped, make the reason and replacement evidence visible. A reason string does not waive authority, identity, destructive-action, or verification invariants.

## Anti-patterns

| Don’t | Why |
| --- | --- |
| Eight absolute NEVER rules for narrative style | Caps strong models; confuses with real safety gates |
| Duplicate full Create-path tutorials inside start-work | Token tax; hosts first-pass on create-spec |
| “Override any preference for parallelism” | Contradicts endorsed fan-out+merge |
| Hard-fail an unbound semantic worktree solely because no issue exists | Traceability default presented as safety; allow a reasoned explicit escape |

See `skill-anatomy.md`.
