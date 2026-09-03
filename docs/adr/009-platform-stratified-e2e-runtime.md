# ADR 009: Platform-stratified e2e runtime + confirm-first preflight

- **Status:** Accepted
- **Date:** 2026-08-30
- **Deciders:** maintainers
- **Related:** `spc-145` (worktree discipline gate), `ADR-006`
- **Related ADRs:** none

## Context

The `run-e2e` skill is the repo-tracked reference pattern for end-to-end test
stories. It assumes a single browser runtime — `ego-browser` (the ego-lite
app). ego-lite is **macOS-only** today (Windows and Linux are on the upstream
roadmap, `https://github.com/citrolabs/ego-lite`). On a Linux VPS (headless
or headed) there is no ego-lite path, so the whole e2e substrate is inert on
roughly half the environments where Lattice runs.

Two gaps make this worse:

1. **No platform detection.** No e2e skill branches on `uname -s`; every
   skill assumes ego-browser is the runtime.
2. **No real install preflight.** `verify-features` *declares* an ego-browser
   presence check, but `ensure-lattice.sh` only checks `python3`. The
   e2e-runtime check is prose, not implemented. `camoufox` is entirely absent
   from the repo (`grep -ri camoufox` → no hits).

We need a runtime split that keeps macOS on ego-lite (unchanged, no
regression) and gives Linux a real anti-detect browser driven through the
existing Playwright substrate, with a first-install gate that asks before it
installs anything.

## Decision Drivers

- **No regression on macOS.** ego-lite is the chosen substrate there; the
  existing `ego-browser` heredoc story API must keep working untouched.
- **Anti-detect on Linux.** A plain Playwright Firefox leaks
  `navigator.webdriver` and has no fingerprint rotation — defeats the purpose.
- **Node substrate fit.** `run-e2e` stories are JS heredocs; a Node runtime
  avoids forcing a Python bridge onto a Node skill.
- **Smallest blast radius.** Three of the four e2e skills
  (`ego-browser`, `playwright-cli`, `playwright-record-demo`) live in
  `~/.claude/skills` and are shared across every project on this machine.
  Touching them affects all projects; the repo-tracked `run-e2e` is the safe
  orchestration point.
- **First-install consent.** Installing a browser binary is an outward-facing,
  slow, network-bound action. The agent must recommend and wait for explicit
  user confirmation before the first install; later runs proceed directly.

## Considered Options

- **Option A — camoufox-js (Node, in-process).** `npm i camoufox-js` +
  `npx camoufox-js fetch` downloads the patched Firefox into a per-user cache;
  `import { Camoufox } from 'camoufox-js'` returns a real Playwright `Page`
  with full BrowserForge fingerprint injection. Good: pure Node, matches
  `playwright-cli`, full anti-detect, no bridge. Bad: community port (apify),
  not the canonical Python lib; `npx fetch` is a large download.
- **Option B — camoufox Python remote-server.** `python -m camoufox server`
  exposes `ws://localhost:port/path`; Node Playwright `firefox.connect(ws)`.
  Good: canonical lib, language-agnostic. Bad: upstream-docs call it
  **experimental** ("hacky workaround to gain access to undocumented Playwright
  methods"); **fingerprints do not rotate** between sessions on a single
  server; requires a Python sidecar process. Rejected as primary.
- **Option C — Playwright plain Firefox (no camoufox).** Bad: no
  anti-fingerprint, `navigator.webdriver` leak — defeats the purpose. Rejected.
- **Option D — ego-lite on Linux.** Bad: not supported upstream. Rejected.
- **Option E — Python `camoufox.sync_api` only.** Bad: forces a Python
  substrate onto a Node `run-e2e`, mismatched. Rejected.

## Decision

We will **platform-split the e2e runtime** and make the repo-tracked
**`run-e2e` skill the dispatcher**:

1. **macOS → ego-lite (ego-browser CLI).** Unchanged. The existing
   `ego-browser nodejs <<'EOF' … EOF` heredoc story API stays the macOS
   backend. ego-lite's own `scripts/install.sh` (macOS DMG flow) remains the
   install path.
2. **Linux → Camoufox driven via Playwright, surfaced through `playwright-cli`.**
   The Node integration is **camoufox-js** (Option A): `npm i camoufox-js` +
   `npx camoufox-js fetch`, then `Camoufox({...})` yields an in-process
   Playwright `Page` with full BrowserForge fingerprint injection — no Python
   bridge. Option B (Python remote-server) is retained only as a **documented
   fallback** for pool/fingerprint-rotation at scale, not the primary path.
3. **`run-e2e` orchestrates; external skills stay untouched.** Only the
   repo-tracked `run-e2e` skill gains platform-aware logic. The
   `ego-browser`, `playwright-cli`, and `playwright-record-demo` skills (global
   `~/.claude/skills`, shared across projects) are **not modified** — smallest
   blast radius.
4. **Confirm-first install gate.** Every e2e skill invocation first runs a
   preflight (`skills/run-e2e/scripts/ensure-e2e-runtime.sh`). It detects the
   platform (`uname -s`) and checks the chosen runtime is installed (macOS:
   `command -v ego-browser`; Linux: `npx --no-install camoufox-js` + playwright
   availability). If the runtime is missing, the agent **recommends the install
   and waits for explicit user confirmation** before installing — it never
   auto-installs. After install, the presence check is re-run on every
   invocation; passing the check is the gate, so subsequent runs proceed
   directly without re-prompting. **No sentinel file is needed.**
5. **Primitives stay platform-neutral.** `run-e2e`'s existing primitives table
   (`snapshot` / `click` / `fill` / `goto` / `assert` / JSON-emit) is the
   cross-backend contract. Two reference implementations map primitives to
   ego-browser heredoc helpers (macOS) and `playwright-cli` commands (Linux).

## Consequences

- **Positive:**
  - Linux VPS (headless or headed) gets a real e2e substrate with anti-detect
    fingerprints via the same Playwright API the Node stack already uses.
  - macOS is untouched — zero regression.
  - External/global skills untouched — no cross-project side effects.
  - First-install consent is enforced; no silent multi-hundred-MB downloads.
- **Negative / trade-offs:**
  - `camoufox-js` is a community port (apify), not the canonical Python lib —
    upstream drift risk. Mitigation: pin the version; document Option B as the
    fallback if camoufox-js stalls.
  - Two backend implementations of the primitives table = more surface to
    keep in sync. Mitigation: the primitives table is the contract; backends
    are thin mappers.
  - Stories are no longer a single heredoc shape across platforms; a Linux
    story uses the playwright-cli mapping. Mitigation: story-template variant.
- **Follow-ups:** a Spec (`spc-N`) will deliver
  `skills/run-e2e/scripts/ensure-e2e-runtime.sh`, the `run-e2e/SKILL.md`
  two-backend update, and the Linux story-template variant. Tickets split
  from that Spec; implement via `start-work`.
- **Verification:** the preflight script itself is the gate — a non-zero exit
  with install guidance is the red flag an agent must surface to the user.
  CI alignment-check confirms `run-e2e/SKILL.md` cites `ADR-009`.

## Status history

- 2026-08-30 — Proposed (initial draft).
- 2026-08-30 — Accepted (implemented via pr-229 / spc-226; tkt-227 merged to dev).

<!-- ADR is out-of-band Lattice sugar: not a lineage node, no `adr-n` edge.
     Cite as `ADR-009` or `docs/adr/009-platform-stratified-e2e-runtime.md`. -->
