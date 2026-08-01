# review-production policy (portable)

## Unit of analysis

**One PR change set** (+ minimal related). Not whole-repo security programs or monorepo threat models.

## Verdict

`go` / `go-with-risks` / `no-go` are **advice**. They do **not** HARD-block `finish-work` unless a future explicit profile Spec says so.

## Security quality bar

1. **Exploit bar** — Security **blocker** (and security contribution to **no-go**) requires a concrete attack sketch naming **sink** + **control**: attacker → sink → control → meaningful impact (see [security-pr-angles.md](./security-pr-angles.md) § Exploit bar).  
2. **Classification** — Per security item: `pass` | `blocker` | `residual` | `hardening` | `n/a` (one-line why).  
3. **Hardening ≠ blocker** — If another layer prevents exploit, record hardening (or residual), not no-go.  
4. **Self-check** — Before any security blocker, apply the 4 questions in [security-pr-angles.md](./security-pr-angles.md).  
5. **Evidence** — Blockers cite path/symbol or diff evidence; calibrate confidence as `reproduced` / `traced` / `unconfirmed` — `unconfirmed` → residual, never blocker (see [security-pr-angles.md](./security-pr-angles.md) § Confidence). Do not fake “confirmed” without support.  
6. **Upgrade, don’t expand** — Whole-repo audit / pen-test / “find all vulns in the codebase” → redirect to co-install **`security-audit`** (or Spec/program). Never silent-widen this skill.

## Depth

Short checklist in SKILL.md. Load [security-pr-angles.md](./security-pr-angles.md) when the diff touches auth/input/state/config/agent surfaces. Deeper whole-repo methodology → optional external packs, especially [cloudflare/security-audit-skill](https://github.com/cloudflare/security-audit-skill).
