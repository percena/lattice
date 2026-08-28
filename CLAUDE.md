# Lattice — project notes for Claude Code

## Worktree discipline is machine-enforced (strict profile)

This repo runs under `profile: strict`. Do **not** create or switch to feature
branches in the main clone, and do not write shippable artifacts (Specs, ticket
binders, lineage, tracked product code) there. The main checkout stays parked on
the integration branch (`dev`); shippable work happens in a bound sibling worktree.

This is enforced by PreToolUse hooks — it is not advice (see `ADR-006`, `spc-145`):

- **Raw `git checkout -b` / `git switch -c` in the main clone is blocked.** Use
  `/start-work` or `ensure-workspace.sh --mode worktree --bind tkt --id <N> --slug <slug>`.
- **Shippable writes on the main clone are blocked** (`.lattice/specs|tickets|lineage/**`
  + tracked code). Reviews (`.lattice/reviews/`) and ADRs (`docs/adr/`) are exempt
  and may be written on base.
- Inside a linked worktree, raw git ops and shippable writes are always allowed.
- Switching **to** a base branch (`main`/`dev`/`master`) is always allowed.

**Non-standard flow** (plain branch or direct base commit): the strict default
blocks drift. When the user explicitly authorizes a non-standard flow, **ask the
user first and wait for confirmation**, then route through the audited escape so
the reason is recorded:

```
ensure-workspace.sh --mode branch --branch <name> --allow-unbound --reason "user-authorized: <why>"
assert-shippable-cwd.sh --allow-base-write --reason "user-authorized: <why>"
```

Full policy: `skills/start-work/references/policy.md`.
