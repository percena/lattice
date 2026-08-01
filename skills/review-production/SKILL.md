---
name: review-production
description: "Optional PR-scoped production-readiness review (security, performance, test coverage expectations, ship/rollback). Use when the user asks if a PR is production-ready, wants a pre-merge production check, or security/perf/test coverage on the change set. Not create-review research reports, not whole-repo security audits (co-install security-audit), not a finish-work merge gate."
allowed-tools: Bash Read Grep Glob AskUserQuestion
metadata:
  agents: "claude-code,codex"
  domain: quality-side-path
---

# Review Production

**Quality side-path**. Heavier **PR change-set** production-readiness pass — **supplement**, not lifecycle.

- **Not** required for the six-skill pipeline; **does not** HARD-block `finish-work`.
- **Not** `create-review` (architecture/research **report**).
- **Not** `review-code` alone (that skill is the light bug/readability pass — you may still note obvious bugs here without duplicating a full light review).
- **Default: review-only** — no large implementation or drive-by refactors.
- Whole-repo audit → co-install **`security-audit`**. Stay thin here.

## Load on demand

| When | Read |
| --- | --- |
| Security quality bar / blocker vs hardening | `references/policy.md` |
| Auth/input/state angles when diff touches them | `references/security-pr-angles.md` |
| Practice-pack borrow boundary | (id-only; monorepo path if engine checkout) |

## When to use

| Trigger | Action |
| --- | --- |
| “production ready?”, “pre-merge production check”, “security/perf on this PR” | Run checklist on the PR/branch change set |
| Before or after `create-pr` | Same as `review-code` input resolution |

## When NOT to use

| Situation | Use instead |
| --- | --- |
| Quick bug/readability pass only | `review-code` |
| Design/ADR exploration, whole-system reconciling | `create-review` |
| Merge / cleanup | `finish-work` |
| Whole-repo security program, pen-test, “find vulnerabilities in the codebase”, multi-phase audit | Co-install **`/security-audit`** (or equivalent) + explicit program/Spec — **do not** silent-expand this skill |
| Whole-repo perf lab | Explicit program + practice packs / Spec — not silent expand |

## HARD scope (PR unit of analysis)

Same law as `review-code`:

| Allowed by default | Forbidden by default |
| --- | --- |
| One PR (or soon-to-be-PR) change set + minimal related context | Whole-repo architecture / monorepo health / whole-repo audit |
| Security, perf, test, ship axes **on that change** | Unrelated refactors, dependency upgrades “while here” |
| go / go-with-risks / no-go **advice** | Treating advice as an automatic merge blocker |

Explicit whole-repo / architecture requests → redirect to `create-review` / Spec / **`security-audit`**; **do not** silently widen.

## Inputs (before and after create-pr)

1. Resolve `pr-N` or open PR for branch, else `base...HEAD` on the feature branch/worktree.
2. Load PR body Acceptance/Verification if present; CI check rollup when available (`gh pr checks`).
3. Do not invent CI green — use command/API output or mark **unknown**.

## Process

### 1. Orient

Announce: `mode: review-production · unit: pr-N | branch-diff · axes: security, perf, tests, ship`

### 2. Checklist (short — PR-scoped)

#### Security

Quality bar: portable [references/policy.md](references/policy.md). 
Load [references/security-pr-angles.md](references/security-pr-angles.md) when the diff touches auth, untrusted input, state machines, config/defaults, or agent/LLM/tool surfaces.

- [ ] Authn/authz on **touched** paths — including **sad/error/fallback** paths and **parallel** routes to the same state change
- [ ] No new secrets in diff; secrets handling sane if touched
- [ ] Injection / SSRF / path traversal on **new** untrusted inputs — gaps need an **attack sketch** (attacker → sink → control → impact; see [security-pr-angles.md](references/security-pr-angles.md) § Exploit bar) to be **blocker**
- [ ] Dangerous defaults in this change (open CORS, debug flags, open redirects, eval/shell with input) — **trace impact** (flag alone ≠ blocker)
- [ ] State-changing ops in the diff: **who authorized?** right permission? right **resource**? (privilege follow)

**Per security item result:** `pass` | `blocker` | `residual` | `hardening` | `n/a` (one-line why).

| Class | Meaning |
| --- | --- |
| **blocker** | Concrete attack sketch + meaningful impact on this PR’s blast radius; may drive **no-go** |
| **residual** | Real concern, limited conditions/impact → **go-with-risks** territory |
| **hardening** | Defense-in-depth / hygiene; another layer already blocks or no standalone exploit — **not** a no-go driver |
| **pass** / **n/a** | No issue / axis not touched |

**Before any security blocker:** answer the **4 questions** in [security-pr-angles.md](references/security-pr-angles.md) (flow real? impact meaningful? other layer blocks? unverified parser assumptions?).  
Prefer local repro when cheap; a defensible static trace (`traced` — no runtime, but the source→sink path holds in the actual touched code) is also **blocker**-eligible — see [security-pr-angles.md](references/security-pr-angles.md) § Confidence. Mark **unconfirmed** (no traced path) → **residual** — do not fake “confirmed.”

#### Performance

- [ ] Obvious N+1 / unbounded loops / full scans introduced in the diff
- [ ] New hot-path work without caching/batching where clearly needed
- [ ] Payload or log volume explosions from this change

Mark: **pass** / **gap** / **n/a** (with one-line why).

#### Tests (coverage expectations)

- [ ] New behavior has unit tests **or** an explicit gap + risk note
- [ ] Integration/contract touchpoints (API, DB, jobs) have some proof or named residual risk
- [ ] Failure/error paths considered when control flow changed
- [ ] Fresh command evidence if tests were run this session — no narrative “should pass”

Mark: **pass** / **gap** / **n/a** (with one-line why).

#### Ship / rollback

- [ ] Migrations / flags / config called out if present
- [ ] Rollback story thinkable (revert PR, flag off, migrate down) at least in prose
- [ ] Standing DoD honesty (`_lattice-lib` Definition of Done) considered when claiming ready

Mark: **pass** / **gap** / **n/a** (with one-line why).

### 3. Verdict (advice only)

| Verdict | When |
| --- | --- |
| **go** | No **blockers**; residual/hardening acceptable for stated environment |
| **go-with-risks** | Residuals (or med gaps on non-security axes) documented; user may still ship |
| **no-go** | ≥1 **blocker** on security/correctness/ship for **this** PR — **recommend** not merging yet; still **not** a tool-enforced finish-work block |

### 4. Output template

```markdown
## review-production · <pr-N | branch>

**Verdict:** go | go-with-risks | no-go
**Unit:** … (PR-scoped — not whole repo)

### Checklist
| Axis | Item | Result | Notes |
| --- | --- | --- | --- |
| security | … | pass/blocker/residual/hardening/n/a | attack sketch or why n/a |
| perf/tests/ship | … | pass/gap/n/a | … |

### Blockers (high)
- … (path/symbol · sketch · impact · confidence)

### Hardening notes (not blockers)
- …

### Residual risks
- …

### Security positives (optional)
- …

### Suggested next steps
- (optional) /review-code · fix in worktree · **co-install `/security-audit` for whole-repo depth** · practice-pack depth · do not auto-finish-work
```

### 5. Optional persist

- PR comment and/or Lattice `rev` (`inform_only` / `spawn_fix`) via create-review contract.
- **Do not** call `gh pr merge` / `finish-work` from this skill.

### 6. Implementation

- **Default: no code changes.**
- If the user explicitly asks to fix a named gap/blocker, keep edits inside the PR change set and re-run the affected checklist rows — prefer handing large work back to `start-work` EXECUTE.

## Compatibility

- Pipeline remains complete without this skill.
- `create-pr` / `finish-work` must not HARD-depend on a prior `review-production` run.
- Co-install practice packs for depth (TDD, **security-audit**, …); this skill stays a thin PR checklist.

## Common Rationalizations

| Rationalization | Reality |
| --- | --- |
| “Production check means audit the whole monorepo” | PR unit only; whole-repo → `/security-audit` or Spec |
| “no-go means I must block finish-work” | Advice; lifecycle gates unchanged unless a future profile Spec says otherwise |
| “Skip tests axis — CI is green” | Still record coverage expectations for **this** diff; CI unknown ≠ pass |
| “Implement a full security rewrite while reviewing” | Default review-only; explicit fix stays PR-scoped |
| “Same as create-review” | create-review = decision report; this = PR production checklist |
| “Missing second-layer check = blocker / no-go” | If Layer A already blocks exploit → **hardening**, not blocker |
| “Potential / theoretically vulnerable…” | No attack sketch → residual or n/a; not security no-go |
| “OWASP / checklist deviation = finding” | Checklist is not a bug list; need impact on this PR |
| “security audit this codebase — run full recon here” | Redirect to **`/security-audit`**; do not silent-expand |

## Red Flags

- Repo-wide dependency CVE sweep presented as this skill’s default
- Silent architecture redesign or whole-repo threat model
- Claiming “production certified” without checklist rows
- Narrative “tests pass” with no session command output when tests were claimed
- Merging from this skill
- Security **blocker** without attack sketch or without the 4-question self-check
- Rating pure defense-in-depth as **no-go**
- Inventing confirmed exploits from unverified parser assumptions

## Verification

- [ ] Target is a PR change set (or soon-to-be-PR diff), not whole repo
- [ ] All four axes touched (security, perf, tests, ship)
- [ ] Security items use pass/blocker/residual/hardening/n/a; blockers have sketch + evidence
- [ ] Verdict stated as advice only; no-go only with ≥1 blocker when security-driven
- [ ] No finish-work / merge invoked
- [ ] No large implementation unless user explicitly requested fixes
- [ ] Whole-repo audit language redirected (not expanded)
