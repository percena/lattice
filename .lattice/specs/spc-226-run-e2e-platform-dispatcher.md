---
id: spc-226
slug: run-e2e-platform-dispatcher
title: run-e2e platform dispatcher + confirm-first preflight
kind: feat
status: done
mode: C
priority: P2
summary: "Platform-split run-e2e: macOS→ego-lite, Linux→camoufox-js via playwright-cli, with a confirm-first install gate"
created: 2026-08-30
updated: 2026-08-30
tickets: [tkt-227]
prs: [pr-229]
reviews: []
supersedes: []
superseded_by: null
---

# Spec: run-e2e platform dispatcher + confirm-first preflight

> **TL;DR:** Make the repo-tracked `run-e2e` skill platform-aware — macOS keeps ego-lite; Linux uses camoufox-js driven via playwright-cli — and gate first-install behind explicit user confirmation. Implements ADR-009.
> **Kind:** feat · **Status:** locked · **Mode:** C · **Priority:** P2
> **Path:** ADR-009 → spc-226 → tkt-… → pr-…

## Why

`run-e2e` assumes a single runtime (`ego-browser` / ego-lite), which is
**macOS-only** (Windows/Linux on the upstream roadmap). On a Linux VPS
(headless or headed) the entire e2e substrate is inert. There is no platform
detection in any e2e skill, and the preflight `ensure-lattice.sh` checks only
`python3` — the declared ego-browser presence check is unimplemented. Camoufox
is absent from the repo. We need a Linux runtime (anti-detect Firefox via
Playwright) and a first-install gate that asks before installing a browser
binary, so the agent never silently triggers a multi-hundred-MB download.

## In scope

- New preflight script `skills/run-e2e/scripts/ensure-e2e-runtime.sh`:
  platform detection (`uname -s`); macOS checks `command -v ego-browser`;
  Linux checks `npx --no-install camoufox-js` (or `npm ls -g camoufox-js`)
  plus playwright-cli availability; on success prints `E2E_BACKEND=ego|camoufox`
  for the caller; on failure exits non-zero with install guidance and does
  **not** attempt install.
- Update `skills/run-e2e/SKILL.md`: invoke the preflight as the first step;
  document the two execution backends (macOS `ego-browser nodejs` heredoc,
  Linux `playwright-cli` via camoufox-js); add a primitives→backend mapping
  table (snapshot / click / fill / goto / assert / JSON-emit for each);
  cite ADR-009.
- New `skills/run-e2e/references/story-template-linux.md`: Linux story-template
  variant using playwright-cli primitives, mirroring the existing
  `story-template.md` (traceability header, fail-loud auth check, mutation
  round-trip, structured JSON output).

## Out of scope

- Modifying the external `ego-browser`, `playwright-cli`, or
  `playwright-record-demo` skills (global `~/.claude/skills`, shared across
  all projects — ADR-009 §3 smallest blast radius).
- Adding the camoufox Python remote-server (`python -m camoufox server`) as a
  primary path — only a documented fallback note in `SKILL.md`.
- A CI story runner or YAML orchestration — `run-e2e` stays a reference
  pattern.

## Acceptance

- [ ] **A1** On macOS with `ego-browser` installed,
  `ensure-e2e-runtime.sh` exits 0 and prints `E2E_BACKEND=ego`; with
  `ego-browser` missing it exits non-zero, prints install guidance pointing at
  the ego-lite macOS DMG flow, and does not attempt install.
- [ ] **A2** On Linux with camoufox-js + playwright-cli installed,
  `ensure-e2e-runtime.sh` exits 0 and prints `E2E_BACKEND=camoufox`; with
  either missing it exits non-zero, prints install guidance
  (`npm i -g camoufox-js` + `npx camoufox-js fetch` + `npm i -g @playwright/cli`),
  and does not attempt install.
- [ ] **A3** `run-e2e/SKILL.md`'s first step invokes `ensure-e2e-runtime.sh`;
  a missing runtime is surfaced to the user for confirmation before any install
  runs (never auto-installed).
- [ ] **A4** `run-e2e/SKILL.md` cites ADR-009 and documents both backends plus
  the primitives→backend mapping table.
- [ ] **A5** `skills/run-e2e/references/story-template-linux.md` exists and
  mirrors `story-template.md` structure (traceability header, fail-loud auth,
  mutation round-trip, JSON output).

## Non-goals

- No Windows support — out of platform scope (only macOS + Linux per intent).

## Decisions (principal, user-confirmed)

1. Platform split per ADR-009: macOS = ego-lite (ego-browser CLI, unchanged);
   Linux = camoufox-js driven via Playwright, surfaced through `playwright-cli`.
2. The Linux integration is `camoufox-js` (Node, in-process Playwright `Page`
   with full BrowserForge fingerprint injection, no Python bridge). The
   camoufox Python remote-server is a **documented fallback only** for
   pool/fingerprint-rotation at scale.
3. Confirm-first install gate: the agent **never auto-installs**; it recommends
   and waits for explicit user confirmation on the first install. The runtime
   presence check is re-run on every invocation — passing it is the gate, so
   post-install runs proceed directly without re-prompting. **No sentinel file.**
4. `run-e2e` is the **only** skill modified; the external `ego-browser`,
   `playwright-cli`, and `playwright-record-demo` skills are untouched.

## Risks / open questions

- `camoufox-js` is an apify community port, not the canonical Python lib —
  upstream drift risk. Mitigation: pin the version in install guidance;
  document the Python remote-server fallback in `SKILL.md`.
- Two backend implementations of the primitives table must stay in sync.
  Mitigation: the primitives table is the contract; backends are thin mappers.

## References

- ADR: `ADR-009` → `docs/adr/009-platform-stratified-e2e-runtime.md`
- Prior Spec: `spc-145` (worktree discipline gate)

## Links / bloodline (L0)

- Tickets: `tkt-227` (#227, sub-issue of #226) — `.lattice/tickets/tkt-227-run-e2e-platform-dispatcher/`
- PRs: (none yet)
- Reviews: (none)
