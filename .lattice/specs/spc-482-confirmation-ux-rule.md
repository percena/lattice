---
id: spc-482
slug: confirmation-ux-rule
title: Confirmation-UX rule — recommended option marked + first across all skills
kind: feat
status: locked
mode: M
priority: P2
summary: "Every skill confirmation prompt marks one option (Recommended) and lists it first; yes/no states a lean + why."
created: 2026-09-05
updated: 2026-09-05
tickets: [483]
prs: [484]
reviews: []
supersedes: []
superseded_by: null
---

# Spec: Confirmation-UX rule — recommended option marked + first across all skills

> **TL;DR:** Add a shared DEFAULT rule that every user-facing confirmation presenting options tags exactly one `(Recommended)` and lists it first (dynamic ordering for severity-conditional sites); yes/no soft-confirms state a lean + one-line why. Fix all 9 enumerated-option sites.
> **Kind:** feat · **Status:** locked · **Mode:** M · **Priority:** P2
> **Path:** spc-482 → tkt-… → pr-…

## Why

Multiple Lattice skills present enumerated-option confirmation prompts (`AskUserQuestion`) to the operator without marking a recommended option, and several list the recommended option anywhere but first (e.g. `finish-work` mini-review lists `Merge anyway` first even when a `high` finding makes `Hold` the recommended pick). For an operator who lacks the real-time decision context (severity, fork-point inference, diff intent), a bare option list forces re-derivation of the agent's own reasoning — unfriendly UX. The agent already has the context to recommend; surfacing that recommendation explicitly and placing it first lets the operator accept the default in one tap.

## In scope

- New shared reference `_lattice-lib/references/confirmation-ux.md` (DEFAULT) stating the rule, linked from `skill-anatomy.md` footer contract.
- Audit + fix all enumerated-option confirmation sites:
  - `create-spec` PCA batch template (already inline `recommended:` — align to "recommended option listed first" wording).
  - `review-code` batch-fix options (SKILL.md:213-218) — tag one `(Recommended)`.
  - `finish-work` mini-review (SKILL.md:135, flow.md:200-210) — dynamic ordering: severity-default option tagged `(Recommended)` and first.
  - `finish-work` Privacy/Secrets override (flow.md:164) — tag `(Recommended)`.
  - `finish-work` MARKER GATE (flow.md:451) — tag `Proceed (Recommended)` first.
  - `create-pr` base-branch ask (workflow.md:108) — mark `recommended_base` `(Recommended)` first.
  - `create-pr` unexpected-diff (workflow.md:117) — recommend `exclude`, place first.
  - `create-tickets` propose-set reply (flow.md:76) — tag `go (Recommended)` first.
- Verification checklist entries on touched skills.

## Out of scope

- Non-Lattice skills and third-party tooling.
- `generate-wiki --confirm-toc` (deliberately Codex-safe, free-form — unchanged).
- Rewriting the `decision-policy.md` resolution chain or `autonomy-rubric.md`.
- New automated enforcement hooks for the UX rule (the rule is DEFAULT prose + checklists).

## Acceptance

- [ ] **A1** — `_lattice-lib/references/confirmation-ux.md` exists, states the DEFAULT rule (mark exactly one option `(Recommended)` and list it first; for yes/no soft-confirms state a recommended lean + one-line why), and is linked from `skill-anatomy.md`.
- [ ] **A2** — Every enumerated-option confirmation site in `create-spec`, `review-code`, `finish-work`, `create-pr`, `create-tickets` (SKILL.md + references) tags exactly one recommended option and lists it first; for the conditional `finish-work` mini-review site, the instruction is dynamic ordering (severity-default option tagged `(Recommended)` and presented first at run time).
- [ ] **A3** — The rule covers yes/no soft-confirms (state a lean + one-line why); `create-pr` / `start-work` / `run-e2e` yes/no sites reference the rule and exemplify the lean, without requiring per-site rewrite where the rule already covers them.
- [ ] **A4** — Each touched skill's verification checklist gains an entry asserting the confirmation-UX rule (recommended option marked + first).

## Decisions (principal, user-confirmed)

1. **D1** Host the rule in a new shared reference file `_lattice-lib/references/confirmation-ux.md` (DEFAULT), linked from `skill-anatomy.md` footer contract — not inline. Single-responsibility, linkable, easy to cite in verification checklists. *(trade-off: one more file vs. mixing UX policy into the anatomy doc.)*
2. **D2** For conditional-recommendation sites (finish-work mini-review: `Hold` when high, `Merge anyway` when med/low), use dynamic ordering at presentation time: the severity-default option is tagged `(Recommended)` and listed first. No fixed order. *(trade-off: agent must reorder at run time vs. a fixed order that would violate "recommended first" when severity=high.)*
3. **D3** `create-pr` unexpected-diff confirm default recommended option = `exclude` (keep PR to session-intended files; surface unexpected files as a follow-up). Safest for intent fidelity. *(trade-off: requires a follow-up for the unexpected files vs. `split` which opens a second PR now.)*
4. **D4** The rule covers yes/no soft-confirms too: state a lean + one-line why; no option reorder needed. *(trade-off: minor extra prose per yes/no vs. leaving bare questions.)*

## Agent-assumed (secondary)

- The `(Recommended)` label convention matches the host harness's AskUserQuestion guidance ("(Recommended)" suffix on the first option).

## Risks / open questions

- The rule is prose + checklist (DEFAULT), not hook-enforced; drift is possible. Mitigation: skill verification checklists reference it, and review-code/review-delivery can flag missing recommendations during PR review.

## References

- Prior art: `create-spec` PCA batch template (already uses inline `recommended:`).
- `skill-anatomy.md` footer contract (where the link lands).

## Links / bloodline (L0)

- Tickets: (to be split by `create-tickets` — `tkt-N`)
- PRs: prefer GitHub `Fixes`/`Refs`
- Reviews: (none)
