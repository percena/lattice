# PR-scoped security angles (progressive disclosure)

**Load when** the PR/diff touches auth, untrusted input, state machines, config/security defaults, or agent/LLM/tool surfaces.  
**Do not** dump this whole file into every `review-production` response.

Principles paraphrased from [cloudflare/security-audit-skill](https://github.com/cloudflare/security-audit-skill) (MIT) and `@openai/codex-security` (Apache-2.0; confidence ladder + static-assessment tuple) — **not** a whole-repo audit pipeline.

## Exploit bar (always)

A **blocker** needs a sketch naming four roles: *attacker → **sink** (dangerous op reached) → **control** (the guard/validator/authz check that should block, and why it does not) → meaningful impact*. Naming the **control** is what makes the hardening-vs-blocker call auditable: if a blocking control exists → **hardening**, not blocker.  
No sketch (or no named sink/control) → residual, hardening, or n/a — not no-go.

## Self-adversarial 4 questions (before any security blocker)

1. **Flow** — Does the claimed data/control path hold in the **actual** touched code (not assumed)?  
2. **Impact** — Is impact meaningful (not “learn a field name” / “cause a generic error” alone)?  
3. **Mitigation** — Does another layer already prevent exploitation? If yes → **hardening**, not blocker.  
4. **Assumptions** — Does the exploit depend on unverified parser/runtime behavior? Verify; else downgrade to **unconfirmed** (→ residual).

## Confidence (binds `blocker` vs `residual`)

The SKILL.md Blockers row asks for `confidence`. Calibrate from the **strongest evidence actually obtained** — not the scariness of the bug class. Three PR-scoped tiers (adapted from codex-security `validation-guidance.md`):

| Tier | Means | May carry |
| --- | --- | --- |
| **reproduced** | Local repro / PoC — run, crash, or observed exploit on the touched path | **blocker** (if impact meaningful) |
| **traced** | Defensible static trace: attacker-controlled source reaches a named **sink**, no blocking **control** on the path — no runtime, but the path holds in the **actual** touched code (4-Q1) | **blocker** (if impact meaningful) |
| **unconfirmed** | Suspicion without a traced source→sink path, or depends on unverified parser/runtime behavior (4-Q4) | **residual** (never blocker) |

**Rule:** `unconfirmed` → **residual**; only `reproduced` or `traced` → **blocker**-eligible. This binds the "do not fake 'confirmed'" line (SKILL.md) and "no sketch → residual": a path you cannot trace to a named sink is not a blocker. Counterevidence that defeats the path → downgrade to `n/a` or `residual`.

If a blocking **control** is present on the traced path → **hardening**, not blocker — the `traced` row above assumes no blocking control (see Exploit bar). A reproduced/traced finding with **non-meaningful** impact → residual/hardening/n/a, not blocker.

## PR angles (≤6 core)

Think like an attacker on **this change set**, not a whole-app recon.

1. **Sad path / error path** — Fallbacks, catch blocks, timeouts, partial failure: same authz rigor as happy path? Half-modified state?  
2. **Boundaries** — Empty, max-length, null vs missing, off-by-one, expiry edges on **new** inputs in the diff.  
3. **Implicit trust** — Does layer B assume layer A validated? Storage “already clean”? Re-check on use if the write path changed.  
4. **Order / replay** — Can steps run out of order, skip, or replay for **changed** workflows?  
5. **Privilege follow** — For each **state-changing** op in the diff: who authorized? Right permission? Right resource? Parallel weaker path?  
6. **Config / defaults** — Missing config, feature flags, debug/dev gates, env overrides that weaken security in this change.

Optional (only if diff clearly needs it): concurrent check-then-act races; two-parser disagreement (proxy vs app, schema vs DB).

## Conditional: AI / LLM / agent / MCP (when diff touches these)

- “Prompt injection” alone is **not** a finding — require a **boundary crossed** (other users’ data, elevated capability, sink the user could not reach).  
- Bug is missing **code-level** gate; model non-determinism is not a defense; prompt-only guardrails are not a control.  
- **Model output is untrusted input** — trace to sinks (SQL/shell/path/HTTP/tools) like any user input.  
- Tool calls under a **service identity** without re-checking the **user** on the **resource** → confused-deputy risk.

For full multi-phase hunt → co-install **`/security-audit`** (or equivalent); do not silent-expand this side-path.

## Obvious things (trace impact)

Secrets in diff, debug endpoints/flags, `eval`/shell with input, open CORS + credentials, open redirects (`redirect`/`next`/`url` params), stack traces in prod responses — **only** if impact is real for this change.
