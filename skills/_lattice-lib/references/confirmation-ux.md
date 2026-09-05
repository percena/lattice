# Confirmation UX (Lattice DEFAULT rule)

How a Lattice skill **presents a choice to the operator**. Applies to every
**user-facing** skill (`skill-anatomy.md` footer contract). `_lattice-lib` is
internal and exempt; `generate-wiki --confirm-toc` is deliberately free-form
(Codex-safe) and exempt.

This is a **DEFAULT** rule — not a hook-enforced gate. Skill verification
checklists assert it; `review-code` / `review-delivery` may flag drift.

## The rule — DEFAULT

Every time a skill asks the operator to confirm, decide, or pick among
options (`AskUserQuestion`, a numbered option list, or even a yes/no
soft-confirm), the agent **already has the context to recommend** — surface it.

| Prompt shape | Requirement |
| --- | --- |
| **Enumerated options** (≥2 named choices) | Tag **exactly one** option `(Recommended)` and **list it first**. One-line trade-off after it. |
| **Conditional recommendation** (the recommended pick depends on a runtime signal like severity) | At presentation time, present the option the signal points to **tagged `(Recommended)` and first** (dynamic ordering). Do not fix an order that puts the recommended pick second. |
| **Yes / no soft-confirm** (e.g. "landing on `main`, ok?") | State a lean + one-line why: "recommended: yes — release-merge is a separate operator-authorized step." No option reorder needed. |
| **Open-ended** (free-form reply, "go / edit") | Still name the recommended path inline: "recommended: **go**" so the operator can accept the default in one word. |

## Why

An operator who lacks the real-time decision context (severity, fork-point
inference, diff intent) is forced to re-derive the agent's own reasoning from a
bare option list. The recommendation is the agent's reasoning made one-tap
cheap; placing it first lets the operator accept the default without scanning.

## Mechanics

1. **One, not many.** Tag exactly one option `(Recommended)`. Two tagged
   recommendations defeat the point.
2. **First.** The recommended option is the first item in the presented list
   (the host harness renders the first option as the default-acceptable one).
3. **Dynamic, not static, when conditional.** When the recommended pick is a
   function of a runtime signal (e.g. `finish-work` mini-review: `Hold` when a
   `high` finding, `Merge anyway` when only med/low), the agent **reorders at
   presentation time** so the signal-default option is tagged and first. The
   prose may list options in a canonical order for readability, but the
   `AskUserQuestion` call must place the recommended one first.
4. **Cite the trade-off in one line** after the recommended option, not a
   paragraph — the operator can read the finding table for detail.
5. **Yes/no leans, not options.** For yes/no, do not manufacture a second
   option; just append "recommended: yes/no — <why>."

## Examples

**Enumerated, static:**
```
- go (Recommended) — proposed set is well-formed; independence obvious
- edit rows — adjust granularity / deps / paths
- single issue instead — ticket-only, no Spec
```

**Enumerated, conditional (finish-work mini-review):** when any `high` finding
is present, present:
```
- Hold (I'll address) (Recommended) — high finding present; fix before merge
- Merge anyway — operator accepts the risk
- Invoke full /review-code — deeper pass before deciding
```
when only med/low, present `Merge anyway (Recommended)` first.

**Yes/no:**
> landing on `main`? recommended: yes — `dev → main` is the separate operator-authorized release merge, so this feature PR targeting `main` is the intended base.

## Anti-patterns

| Don't | Why |
| --- | --- |
| Present a bare option list with no `(Recommended)` tag | Forces re-derivation; the whole point of this rule |
| Tag two options `(Recommended)` | Defeats "one-tap default" — the operator must still choose |
| List the recommended option second "because Merge sounds safer first" | Violates "first"; the default-accept position is slot 1 |
| Fix a static order for a conditional site so `Hold` is never first | When severity=high the recommended pick (`Hold`) is not first — breaks the rule |
| Manufacture a yes + no enumerated list for a soft-confirm | Bloats a one-word lean into a modal; just append the lean |
| Omit the one-line trade-off | A bare tag is a vote without a reason |

## Common Rationalizations

| Rationalization | Reality |
| --- | --- |
| "The operator knows their context better — I shouldn't lean" | You already ran the analysis; the lean is your reasoning surfaced, not a guess of their preference. They can still pick otherwise. |
| "Conditional means I can't pick, so I'll just order Merge first" | Conditional means *dynamic ordering at presentation time* — the signal picks the slot-1 option. |
| "Yes/no doesn't need a recommendation" | A bare yes/no forces the operator to re-derive; the lean costs you one line. |
| "I'll recommend in prose after the list" | After-the-list prose is invisible to the default-accept affordance; the tag must be on the first option. |

## Verification

- [ ] Every enumerated-option confirmation tags exactly one option `(Recommended)` and lists it first
- [ ] Conditional-recommendation sites present the signal-default option tagged + first at run time
- [ ] Yes/no soft-confirms state a lean + one-line why
- [ ] No prompt manufactures a second "recommended" or leaves a bare option list

See `skill-anatomy.md` (footer contract) for where this is linked.
`constraint-language.md` for DEFAULT semantics.
