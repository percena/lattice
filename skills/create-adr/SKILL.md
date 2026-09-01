---
name: create-adr
description: "Create an Architecture Decision Record (ADR-NNN) under docs/adr/: allocate the next 3-digit number, copy the shipped template, fill the decision, and append the README index row. Use when a cross-feature architecture decision outlives one Spec and needs durable long-term law. Not for feature-local Spec decisions, GitHub PR reviews, or Lattice lineage artifacts (ADR is out-of-band)."
allowed-tools: Bash Read Grep Glob AskUserQuestion
metadata:
  agents: "claude-code,codex"
---

# Create ADR

Write a durable **Architecture Decision Record** (`ADR-NNN`) under the consumer repo's `docs/adr/`.
**Terminology:** this is **not** a Lattice lineage node, **not** a Spec, **not** a Review. ADR is **out-of-band** browse sugar.

**Numbers (boundary rule, distributed in `create-review` / `create-spec` / `_lattice-lib` policy):** zero-padded **3-digit**, monotonic in the `docs/adr/` folder only — `001`, `002`, … `999`. **Manual** — not timestamps, not GitHub-issued, not bare-decimal. Allocated by this skill's `scripts/next-adr-number.sh` (a pure read; **never** `next-artifact-id --kind adr` — the lineage mint only accepts `spc` / `rev`).

**Runtime path:** before executing skill-owned files, set `LATTICE_SKILL_ROOT` to the absolute directory containing this loaded `SKILL.md` (Claude may already provide `CLAUDE_SKILL_DIR`). Never infer it from consumer cwd.

## Load on demand

| When | Read |
| --- | --- |
| Boundary rules, promote trigger, team-base vs shippable, bootstrap | `references/policy.md` |
| ADR file shape | `references/templates/adr.md` |
| Pointer file copied to consumer `docs/adr/template.md` | `references/pointer-template.md` |
| Constraint severity (INVARIANT/DEFAULT/HINT) | `../_lattice-lib/references/constraint-language.md` |
| Delegation and accountable ownership | `../_lattice-lib/references/orchestration-patterns.md` |

## When to use / When NOT

| Use | Not — use instead |
| --- | --- |
| Cross-feature architecture decision that outlives one Spec | Feature-local decision → Spec `## Decisions` |
| System-shape law a cold reader should find in 6 months | One-off product call for a single ticket → Spec |
| Promote a Spec.Decisions item cited by ≥2 Specs/PRs | Delivery unit → `create-tickets`; merge → `create-pr` |
| Publish a decision a Review (`rev-…`) explored | PR change-set review → `review-code` / `review-production` |

## Core rules

1. **INVARIANT — ADR is not a fifth Lattice graph node:** no `adr-n` in lineage, no worktree bind, no `next-artifact-id --kind adr`. Cite as `ADR-NNN` or path, never as a lineage edge.
2. **INVARIANT — Numbers stay manual 3-digit:** `max(existing NNN) + 1` via `scripts/next-adr-number.sh`. Never guess by hand; never pad to 4 digits; never bare `adr-1`.
3. **DEFAULT — Promote, don't create orphan:** write an ADR only when the decision **outlives one Spec** or **constrains many features**. Feature-local decisions stay in Spec `## Decisions (principal)`.
4. **DEFAULT — Single source of truth for the template:** the canonical template ships with this skill (`references/templates/adr.md`). `docs/adr/template.md` in a consumer repo is a **pointer** to it, not a second copy.
5. **DEFAULT — Append the README index row:** every new ADR appends a row to `docs/adr/README.md` index table via `scripts/append-adr-index-row.sh`. Hand-maintained tables drift.
6. **DEFAULT — Status lives in the ADR file:** `Proposed` → `Accepted` → `Superseded by ADR-NNN`. Prefer **supersede over delete**. Record transitions in the optional `## Status history` block.
7. **INVARIANT — No product implementation:** this skill writes a doc; it does not implement code or open tickets/PRs.
8. **DEFAULT — Same-pass co-create reuses the worktree:** if `create-review` / `create-spec` / `create-tickets` already opened a shippable worktree in this pass, write the ADR **there**; do **not** open a second tree. ADR-only writes are exempt (team base OK — ADR is durable doc, not a delivery unit).
9. **DEFAULT — Reversing decision → preceding `rev-` by default:** when the ADR supersedes another ADR or replaces existing infrastructure, a preceding `create-review` (`rev-…`) evaluation carrying the up-front comparison is **required by default**. If skipped, the author records an explicit one-line skip reason (in `## Status history` or `## Notes`). A trivial reversal may skip, but the skip must be explicit, never silent. This connects `create-review`'s Problem Audit into the decision path so it cannot be bypassed by jumping to `create-adr` → `create-tickets` → `start-work` → code. (See `../create-review` Problem Audit policy.)
10. **INVARIANT — Accountable ownership:** one owner controls the decision, authority, and final validation of the ADR; bounded drafting may be delegated (`orchestration-patterns.md`).

## Flow

### 0. Ensure Lattice ready + choose write home (required)

```bash
SKILL_ROOT="${LATTICE_SKILL_ROOT:-${CLAUDE_SKILL_DIR:-}}"
[[ "$SKILL_ROOT" = /* && -f "$SKILL_ROOT/SKILL.md" ]] || { echo "Error: resolve the active SKILL.md directory to absolute LATTICE_SKILL_ROOT" >&2; exit 1; }
RESOLVE="$SKILL_ROOT/../_lattice-lib/scripts/resolve-lattice-lib.sh"
[[ -f "$RESOLVE" ]] || { echo "Error: _lattice-lib is not installed beside $SKILL_ROOT" >&2; exit 1; }
LIB=$(bash "$RESOLVE")
bash "$LIB/ensure-lattice.sh"
```

**Bootstrap docs/adr/ (first ADR in this repo):** if `docs/adr/` or its README index does not exist yet, create them now.

```bash
mkdir -p docs/adr
[[ -f docs/adr/README.md ]] || cat > docs/adr/README.md <<'EOF'
# Architecture Decision Records (ADR)

## Index

| ADR | Title | Status | Supersede / amend |
| --- | --- | --- | --- |
EOF
[[ -f docs/adr/template.md ]] || cp "$SKILL_ROOT/references/pointer-template.md" docs/adr/template.md
```

**Same-pass co-create?** If a Spec / Review / tickets are being written in this same request, the shippable worktree is **already open** — `cd` into it and write the ADR there. Do **not** open a worktree bound to an ADR id.

**ADR-only** (no Spec/ticket/Review in this pass): ADR is durable doc, not a delivery unit — committing on `dev`/`main` is fine. Optionally assert:
```bash
bash "$LIB/assert-shippable-cwd.sh" --allow-base-write --reason "ADR-only durable doc; no delivery unit" \
  || { echo "Error: base-write blocked; open a worktree bound to spc/tkt if co-creating" >&2; exit 1; }
```

### 1. Allocate the next 3-digit number

```bash
N=$(bash "$SKILL_ROOT/scripts/next-adr-number.sh")   # pure read; max+1; NOT a lineage mint
echo "next ADR: $N"
```

Fail closed — do **not** hand-guess `max+1` if the script is missing.

### 2. Atomically claim the number + copy the shipped template

```bash
SLUG="<kebab-title>"
ADR_FILE="docs/adr/${N}-${SLUG}.md"
ADR_FILE=$(bash "$SKILL_ROOT/scripts/claim-adr-file.sh" \
  --num "$N" --slug "$SLUG" \
  --template "$SKILL_ROOT/references/templates/adr.md" \
  --home docs/adr)
```

The claim is filesystem-local and fail-closed: it never overwrites an existing
ADR, and two cooperating creators in the same checkout cannot claim the same
number. If it reports a conflict, re-run `next-adr-number.sh`; do not delete or
rename the competing ADR automatically.

Then fill:
- Title line `# ADR NNN: <Title>`
- **Status:** `Proposed` (default for new) — flip to `Accepted` once deciders agree
- **Date:** today `YYYY-MM-DD`
- **Deciders:** names or `maintainers`
- **Related / Related ADRs:** bare ids (`spc-n`, `rev-YYYYMMDD-HHMMSSZ`, `pr-n`, `ADR-NNN`)
- Body: `## Goal` (required for reversing/replacing; optional otherwise) · `## Context` (required) · `## Decision Drivers` (optional) · `## Considered Options` (optional; required + status-quo row for reversing) · `## Decision` (required) · `## Consequences` (required) · `## Status history` (optional) · `## Notes` (optional)

Keep the optional sections when the decision has real alternatives or a supersede chain; drop them (delete the placeholder — including `## Goal` and the `Keep status quo` row) for a crisp Nygard-minimal ADR. Either way, the footer note stays. A non-reversing ADR that leaves `## Goal` / `Keep status quo` placeholders in is not mis-classified as reversing — the reversing checklist is conditional on an author-declared reversing trigger, not on section presence.

### 3. Append the README index row

```bash
bash "$SKILL_ROOT/scripts/append-adr-index-row.sh" \
  --num "$N" --file "$ADR_FILE" \
  --title "<Title>" --status "Proposed" \
  --readme docs/adr/README.md
```

Idempotent — safe to re-run if the row already exists. Use `--supersede "Superseded by [ADR-NNN](./NNN-…)"` when the new ADR supersedes an old one, and flip the old ADR's Status to `Superseded by ADR-NNN` in its own file.

### 4. Link from origin + report

- From a Spec: add `ADR-NNN` → `docs/adr/NNN-….md` to `## References`.
- From a Review: add `ADR-NNN` to `## Follow-ups` / outcome.
- From a PR: cite `ADR-NNN` in the PR body.

Report: ADR path, `ADR-NNN`, Status, and the next-step handoff (e.g. `create-spec`, `create-tickets`, or `inform_only`).

## Anti-patterns

| Don't | Why |
| --- | --- |
| Use `next-artifact-id --kind adr` | ADR is out-of-band; the mint only takes `spc` / `rev` |
| Pad to 4 digits or use `adr-1` bare-decimal | Breaks the 3-digit contract and invites lineage confusion |
| Put feature-local decisions here | Stays in Spec `## Decisions`; promote only when cross-feature |
| Maintain the README index by hand | Tables drift; the script is idempotent and deterministic |
| Edit existing ADR bodies | Status flips via supersede-in-place; new ADRs get the richer optional sections, old ones stay valid |
| Open a worktree bound to an ADR id | ADR is not a delivery unit; co-create reuses the spc/tkt-bound tree |
| Delete an ADR | Prefer `Superseded by ADR-NNN`; keep the audit trail |

## Common Rationalizations

| Rationalization | Reality |
| --- | --- |
| "Just `max+1` by eye — it's only a number" | `next-adr-number.sh` is the deterministic allocator; hand-guessing drifts and races |
| "It's a system decision, put it in the Spec" | Cross-feature law → `docs/adr/`; Spec is one delivery contract |
| "I'll keep a local `docs/adr/template.md` copy for offline" | The shipped template is the SoT; `docs/adr/template.md` is a pointer — one truth, not two |
| "The README index is fine, I'll edit it later" | Run `append-adr-index-row.sh` now; deferred hand-edits are exactly how rows go missing |
| "Same pass — let me open a fresh worktree for the ADR" | Co-create reuses the open spc/tkt-bound tree; ADR never binds its own tree |
| "Status is Accepted, delete the old ADR" | Supersede in place; the old body is the audit trail |
| "4-digit pad is cleaner next to spc-N" | 3-digit is the folder contract through `999` |
| "I'll promote this Spec.Decisions item to ADR later" | Promote trigger = cited by ≥2 Specs/PRs; do it now or leave it feature-local |

## Red Flags

- `next-artifact-id --kind adr` invoked anywhere
- 4-digit or bare-decimal ADR id in a filename or cite
- New ADR written without an `append-adr-index-row.sh` run
- ADR opening a worktree bound to `adr-` / `NNN`
- Feature-local decision promoted to ADR prematurely
- ADR body pasting full Review prose instead of the decision
- `docs/adr/template.md` diverging from the shipped skill template
- Existing ADR bodies rewritten (only Status/Superseded flips allowed)

## Verification

Before claiming the ADR is written:

- [ ] `ensure-lattice` ran
- [ ] Co-create: reused the open shippable worktree (no `adr-`-bound tree); ADR-only: base write explicit
- [ ] `next-adr-number.sh` printed a 3-digit id; no `--kind adr` used
- [ ] `claim-adr-file.sh` atomically wrote `docs/adr/NNN-kebab-title.md` from the shipped template
- [ ] `append-adr-index-row.sh` ran (idempotent) — README index row present
- [ ] Status set (`Proposed` / `Accepted`); footer note intact
- [ ] Origin linked (Spec `## References` / Review `## Follow-ups` / PR body)
- [ ] No product implementation; no existing ADR body rewritten
- [ ] Reversing/replacing decision: `## Goal` + `## Considered Options` (with status-quo row against Goal) present; status-quo dismissal tied to Goal
- [ ] Reversing/replacing decision: preceding `rev-…` recorded, or explicit one-line skip reason in `## Status history` / `## Notes`
