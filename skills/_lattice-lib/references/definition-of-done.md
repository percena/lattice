# Definition of Done (Lattice standing bar)

A **project-wide** bar every shippable change should clear before it counts as done.  
Distinct from Spec **Acceptance `A*`** (per-slice “did we build the right thing?”).

| | Acceptance (`A*`) | Definition of Done |
| --- | --- | --- |
| Scope | One Spec / ticket slice | Every increment that may merge |
| Changes | Per delivery | Fixed checklist |
| Answers | Right thing? | Ready to land? |
| Owner | Spec / ticket | This reference (+ consumer overrides if any) |

A ticket is done only when **its** Acceptance is met **and** this standing bar is satisfied (or explicitly deferred with a follow-up).


## Iron Law — Evidence Before Claims

**NO** completion / ship / "tests pass" / "aligned" / "done" claims without **fresh verification evidence in this session**.

| Step | Action |
| --- | --- |
| 1 IDENTIFY | Which command or check proves the claim? |
| 2 RUN | Full command **now** (not memory of a prior turn) |
| 3 READ | Exit code + failure count + relevant output |
| 4 VERIFY | Does output actually support the claim? |
| 5 ONLY THEN | State the claim **with** evidence (command + result) |

| Claim | Requires | Not enough |
| --- | --- | --- |
| Tests pass | Fresh suite/file run, 0 failures | "should pass", last PR CI green, agent said ok |
| Bug fixed | Symptom was red, now green | Code changed, assumed fixed |
| Alignment OK | `alignment-check.sh` (or equivalent) output | Diff "looks right" |
| Ready to merge | Base update + checks + alignment + this DoD | Green CI alone |

**Red flags — stop claiming:** "should", "probably", "seems", "Done!" before a run, partial checks, "just this once".

Not a TDD mandate. Prefer real commands when the repo has a harness; if no harness, say so and use the best available proof.

## Standing checklist

### Correctness

- [ ] Acceptance criteria for the slice are met (or deferred with ticket id)
- [ ] Behavior verified with **fresh command output** in this session — not “should pass”
- [ ] New behavior has tests or an equivalent proof when the repo has a test harness; no silent skip
- [ ] Existing suite / typecheck / build still green when those tools exist
- [ ] Error paths considered when the change touches control flow

### Quality

- [ ] Diff is scoped to the task; no unrelated drive-by refactors
- [ ] No debug leftovers, secrets, or commented-out blocks left behind
- [ ] Naming and structure match surrounding code

### Integration & delivery

- [ ] Works with the rest of the system, not only in isolation
- [ ] Migrations / config / feature flags accounted for when relevant
- [ ] **Shippable work** used a bound sibling worktree unless pure no-PR throwaway
- [ ] PR body is self-contained (Why / How; real Verification only if run) — `create-pr` policy
- [ ] Before merge: base update + **alignment-check** when Lattice binders/Spec apply — `finish-work` policy

### Honesty

- [ ] Do not check off Acceptance the diff does not implement
- [ ] Do not claim “tests pass” without running them this session
- [ ] Out-of-scope items stay out; inventing scope is a fail

## How skills use this

| Skill | Use |
| --- | --- |
| `create-pr` | Treat DoD + Iron Law as the readiness lens when drafting Verification / deciding the branch is shippable |
| `finish-work` | Alignment + green CI are necessary; DoD + Iron Law is the standing bar that Acceptance alone does not replace |
| `start-work` | Before handoff to `create-pr`, point at this DoD (EXECUTE exit) |
| Consumers | May add project-local DoD under their own docs; this file is the portable default shipped with `_lattice-lib` |

## Non-goals

- Not a substitute for Spec `A*` or light RTM (`covers`)
- Not a mandate to run every optional practice-pack skill (TDD persona, security auditor, …)
- Not enforced by a separate merge bot — agents and `alignment-check` enforce via policy
