# create-adr policy (portable)

Shipped with `create-adr`. No monorepo docs required at runtime.

## What an ADR is

A **long-lived architecture decision record** in the consumer repo (`docs/adr/NNN-kebab-title.md`).
Browse sugar — **not** a Lattice graph node, **not** a delivery unit, **not** a Spec.

| Artifact | Role | Home |
| --- | --- | --- |
| Spec | Delivery contract (why/in/out/acceptance) | `.lattice/specs/spc-n` |
| Ticket | Delivery unit | GitHub issue |
| PR | Merge unit | GitHub PR |
| Review | Decision-support research | `.lattice/reviews/rev-…` |
| **ADR** | **Durable architecture *why*** | **`docs/adr/NNN`** |

The boundary rules below are the **same** ones already distributed inline in
`create-spec` / `create-review` / `_lattice-lib` policy files. This skill
packages the **creation procedure and template**; it does not redefine the
boundary.

## Hard rules (must not violate)

1. **ADR is not a fifth Lattice graph node:** no `adr-n` in lineage, no worktree bind, no `next-artifact-id --kind adr`. The `--kind` flag of the lineage mint only accepts `spc` / `rev`. (Stated inline in `create-spec` / `create-review` policy.)
2. **Numbers stay manual 3-digit:** `max(existing NNN) + 1`, zero-padded 3-digit, scoped to the `docs/adr/` folder only. Not timestamps, not GitHub-issued, not bare-decimal. The skill's `next-adr-number.sh` reads the folder; it is a pure read, **not** a lineage claim. (Stated inline in `create-review` rule 6.)
3. **Feature-local decisions stay in Spec** (`## Decisions`). Promote to ADR only when the decision **outlives one Spec** or **constrains many features**.
   - **Promote trigger:** a Spec.Decisions item is cited by ≥2 Specs/PRs, or you would paste it into a new Spec again.
4. **Never put ADRs in Tickets.** Tickets may *cite* `ADR-NNN`; closing a ticket does not retire an ADR.
5. **Review may motivate an ADR** (explore → decide). Publish the decision here; keep the exploration as a Review (`rev-…`).
6. **Status** lives in the ADR file (`Proposed` / `Accepted` / `Superseded by ADR-NNN` / partial supersede notes). Prefer **supersede over delete**.
7. ADR is **out of band** of lineage (`spec → ticket → pr`); cite as `ADR-NNN` or path, never as a lineage edge.

## Reversing / replacing decisions (status-quo gate)

When an ADR **supersedes another ADR or replaces existing infrastructure** (author-declared trigger), the following become **INVARIANT (not optional)** — the status quo must be weighed as a real alternative against the real goal, not dismissed by "the user wants to change":

1. **`## Goal` is required** — the **underlying problem to solve**, distinct from `## Context` (which describes the proposed solution/situation). Forces the author to separate goal from means.
2. **`## Considered Options` is required** and MUST include a **"keep status quo"** row evaluated **against `## Goal`**. Dismissing the status quo requires a reason tied to the goal, not the author's intent to change.
3. A reversing decision that omits Goal, omits Considered Options, or dismisses the status quo without a goal-tied reason is **not shippable** — the checklist fails it.

**For non-reversing minimal ADRs**, the Nygard-minimal behavior stays: Goal and Considered Options remain optional. The reversing trigger is author-declared (supersede an ADR, or "replaces component X"); when in doubt, the author flips `## Goal` / `## Considered Options` on rather than off.

## Reversing decision → preceding `rev-` (DEFAULT gate)

When an ADR **supersedes another ADR or replaces existing infrastructure**, a preceding `create-review` (`rev-…`) evaluation carrying the up-front comparison is **required by default** (DEFAULT, not INVARIANT — a trivial reversal may skip). If skipped, the author records an explicit one-line skip reason in `## Status history` or `## Notes`. The skip must be explicit, never silent — this connects `create-review`'s Problem Audit (validity / info sufficiency / hidden issues / **existing-solution-meets-goal**) into the decision path so it cannot be bypassed by jumping straight to `create-adr` → `create-tickets` → `start-work` → code.

**Grandfather clause:** this gate applies to ADRs **created under this rule**. Existing Accepted ADRs are grandfathered as-is — do **not** back-fill `## Goal` / status-quo rows onto historical ADRs when superseding them; the superseding ADR carries the new gate, the superseded one stays an immutable audit trail.

| Reversing decision | Precursor |
| --- | --- |
| Supersedes an ADR | `rev-…` by default; explicit skip reason if omitted |
| Replaces existing infrastructure | `rev-…` by default; explicit skip reason if omitted |
| Non-reversing minimal ADR | no precursor required |

## When to write an ADR

| Write ADR | Keep in Spec.Decisions only |
| --- | --- |
| Storage layout, ID strategy, SoT ownership | "This feature skips Spec" |
| Auth model, multi-tenant boundary | "This slice uses approach B" |
| Worktree pool policy, plugin packaging | Temporary implementation choice |
| Anything you expect a cold reader to find in 6 months | One-off product call for a single ticket |

## Template

- Canonical source of truth: `references/templates/adr.md` (shipped with this skill).
- Consumer repo may keep a `docs/adr/template.md` as a **pointer** to this file (single source of truth); the skill always copies from its shipped template.

## Bootstrapping docs/adr/ (first ADR in a repo)

If the consumer repo has no `docs/adr/` yet, the skill bootstraps it:

```bash
mkdir -p docs/adr
# If no README index exists, create one with the table header:
[[ -f docs/adr/README.md ]] || cat > docs/adr/README.md <<'EOF'
# Architecture Decision Records (ADR)

## Index

| ADR | Title | Status | Supersede / amend |
| --- | --- | --- | --- |
EOF
# docs/adr/template.md becomes a pointer (single source of truth)
[[ -f docs/adr/template.md ]] || cp "$SKILL_ROOT/references/pointer-template.md" docs/adr/template.md
```

The shipped `references/templates/adr.md` is the only template the skill ever copies from. `docs/adr/template.md` is a pointer so offline `cp` muscle memory still lands on a file that directs users to the skill.

## Team base vs shippable cwd

| Situation | Write ADR on team base? |
| --- | --- |
| **ADR-only** (no Spec / ticket binder / new Review in the same request) | **Yes** — ADR is durable doc, not a delivery unit; may commit on `main`/`master`/`dev` (like Review-only) |
| **Same-pass co-create** ADR + Review and/or Spec and/or tickets | **No** — open **one** shippable worktree first (`spc-`/`tkt-` bind, or reuse the already-open one), write the ADR **with** the delivery artifacts there |
| Spec / ticket binders / product code alone | **No** — `assert-shippable-cwd` HARD; bound worktree first |

**ADR-only Step 0:** `ensure-lattice` + `assert-shippable-cwd --allow-base-write --reason "ADR-only durable doc, no delivery unit"` (or just commit on base — ADR is out-of-band doc).
**Co-create Step 0:** reuse the worktree `create-review` / `create-spec` already opened; do **not** open a second tree for the ADR. If no tree is open yet, open one bound to `spc`/`tkt` (never to an ADR id).

## Scripts

```bash
SKILL_ROOT="${LATTICE_SKILL_ROOT:-${CLAUDE_SKILL_DIR:-}}"
[[ "$SKILL_ROOT" = /* && -f "$SKILL_ROOT/SKILL.md" ]] || { echo "Error: resolve the active SKILL.md directory to absolute LATTICE_SKILL_ROOT" >&2; exit 1; }
# next-adr-number.sh — pure read, max+1, 3-digit; NOT a lineage mint
bash "$SKILL_ROOT/scripts/next-adr-number.sh" [--home <docs-adr-dir>]
# claim-adr-file.sh — atomically publish the selected NNN + slug from template
bash "$SKILL_ROOT/scripts/claim-adr-file.sh" --num NNN --slug <kebab> --template <adr.md> [--home <docs-adr-dir>]
# append-adr-index-row.sh — idempotent README index row append
bash "$SKILL_ROOT/scripts/append-adr-index-row.sh" --num NNN --file <path> --title "…" --status "Active|Superseded" [--supersede "…"]
```

If `next-adr-number.sh` is missing, fail closed — do **not** hand-guess `max+1`.

## Relation to lineage / RTM

- Lineage primary path: `spec → ticket → pr` (delivery). ADR is **out of band**.
- Light RTM: Spec Acceptance `A*` + Ticket `covers` — ADR is not in this graph.
- No generated BOARD or global ADR index product.
