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

## Workflow pipeline is mandatory (hard prohibition)

All code delivery MUST go through the skill pipeline:

  create-spec → create-tickets → start-work → create-pr → finish-work

This is a **hard prohibition**, not a recommendation. Violation = STOP and
surface to the user. Do not rationalize a bypass with engineering pragmatism
(coupling, efficiency, "just a quick fix") — if you feel justified to
deviate, STOP and ask first.

- **No manual `gh issue create`** — the hook blocks it unless create-tickets
  is active. Use `/create-tickets`.
- **No manual `gh pr create`** — the hook blocks it unless create-pr is
  active. Use `/create-pr`.
- **No manual `gh pr merge`** — the hook blocks it unless finish-work is
  active. Use `/finish-work`.
- **No ad-hoc branches** — L1 blocks `git checkout -b` in the main clone.
  Use `/start-work` to get a bound sibling worktree.
- **If coupling makes per-ticket worktree impractical** → use `batch-work`
  skill, or ASK the user first. Do not silently open a serial single-branch.

The hooks default to `strict` (block). To temporarily override for one shell:
`export LATTICE_HOOK_MODE=advisory` (nudge-only, does not block).
