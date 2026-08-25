---
name: e2e-story
description: "Reference pattern for writing ego-browser heredoc JS end-to-end test scripts: one Bash invocation per story, fail-loud auth checks, structured JSON output via console.log. Not a YAML runner, not ERP auto-playwright. Use when authoring or reviewing e2e stories that drive a real Chromium browser against a local or deployed web app."
allowed-tools: Bash Read Grep Glob
metadata:
  version: "0.1.0"
  date: "2026-08-25"
  agents: "claude-code,codex"
---

# e2e-story

e2e-story is a **reference pattern** for writing end-to-end test scripts with [ego-browser](../../ego-lite/skills/ego-browser/SKILL.md). A story is a single `ego-browser nodejs <<'EOF' ... EOF` heredoc that navigates a real Chromium page, interacts through semantic locators, captures screenshot evidence, runs assertions via `page.evaluate`, and prints one structured JSON object to stdout. The caller (a Lattice skill, a CI step, or a human) reads that JSON.

This skill documents the pattern; it is **not** a separate runner. There is no YAML, no step DSL, no plugin loader. You write JavaScript in a heredoc and run it with one Bash call.

**Foundation (ADR-002 §2):** ego-browser is the foundation for browser automation in this stack — not ERP's auto-playwright, not a bespoke driver. Task-space login-state inheritance eliminates cross-port auth engineering: an agent-owned space reuses the user's already-logged-in Chromium profile, so a story that targets an authenticated app does not need to re-login, persist cookies, or mint tokens.

## Primitives

Every story composes these ego-browser primitives. Names mirror the ego-browser facade (Playwright-style).

| Primitive | ego-browser call | Notes |
| --- | --- | --- |
| **goto** | `browser.openOrReuseTab(url, { wait: true, timeout })` | Reuses tab if URL already open; otherwise opens. Prefer over `page.goto` for cross-tab safety. |
| **snapshot** | `await page.snapshot()` | Full-page accessibility snapshot; builds the `@N` ref map for the current command. Re-snapshot after navigation. |
| **locator** | `page.locator(sel)` / `page.getByRole(...)` / `page.getByLabel(...)` | Semantic first; raw CSS/xpath only when AX-poor. Locators are strict and auto-wait. |
| **click** | `await locator.click()` | Register `page.waitForResponse` / `page.waitForURL` *before* the click when it triggers network or navigation. |
| **fill** | `await locator.fill(value)` | Clears then fills. For selects use `locator.selectOption(value)`. |
| **select** | `await locator.selectOption(value)` | Strict; waits for the option. |
| **press** | `await page.keyboard.press('Enter')` / `await locator.press('Tab')` | For key chords and submit-on-Enter. |
| **screenshot** | `await page.screenshot({ path, fullPage: true })` | Evidence capture. Use `page.info()` first; if `w:0`/`h:0`, stop and re-verify the tab. |
| **assert** | `await page.evaluate(() => { ... ; return bool })` | Runs in-page; returns the value directly. Do **not** `JSON.parse` the result. Return `true`/`false` or a structured object; the story interprets. |
| **wait** | `page.waitForResponse` / `page.waitForURL` / `page.waitForLoadState` / `page.waitForFunction` | Register before the triggering action. These return falsy on timeout — check the result. |
| **fetch** | `fetch.server(...)` / `fetch.browser(...)` | Node-side or in-origin requests; escape hatch for API-level probes. |
| **cdp** | `cdp('Page.handleJavaScriptDialog', { accept: true })` | Escape hatch only; dismiss dialogs via `page.info()` first. |

## Fail-loud auth check

**INVARIANT:** If a story expects an authenticated page but lands on a login form, the story **FAILS** — it must never silently pass by asserting against the login page's own chrome.

Pattern: after `goto`, inspect `await page.url()` and `await page.title()` (or a login-page marker). If the URL path matches a login route or the title/heading indicates a login form, emit a failure JSON object and stop. Do not continue to interactions that would incidentally "succeed" on a login page.

```js
const url = await page.url()
const title = await page.title()
const looksLikeLogin = /\/login|\/sign-in|\/auth/i.test(url) ||
  /sign in|log in/i.test(title || '')
if (expectedAuth && looksLikeLogin) {
  console.log(JSON.stringify({ status: 'fail', reason: 'landed-on-login', url, title }))
  return
}
```

Because task spaces inherit the user's login state, an unexpected login redirect usually means the session expired or the task space was not selected — surface it, do not mask it.

## Structured output

**DEFAULT:** A story prints **exactly one** JSON object to stdout via `console.log`. The caller parses it.

```json
{
  "status": "pass" | "fail",
  "reason": "short machine-readable code (e.g. title-mismatch, landed-on-login, console-errors)",
  "url": "final page url",
  "title": "final page title",
  "assertions": [
    { "name": "title contains Weftd", "pass": true },
    { "name": "no console errors", "pass": true }
  ],
  "screenshot": "path/to/evidence.png",
  "consoleErrors": []
}
```

- `console.log(JSON.stringify(result, null, 2))` once, at the end.
- Do not print intermediate JSON objects; intermediate reads stay in-script.
- Screenshots are file paths the caller can attach as evidence.
- Capture console errors by subscribing before navigation: `page.on('console', e => { if (e.type() === 'error') errors.push(e.text()) })` and via `page.on('pageerror', e => errors.push(e.message))`.

## Not a YAML runner

e2e-story is **heredoc JS, not a YAML runner**. There is no `steps:` block, no `assert:` DSL, no plugin discovery. Rationale (ADR-002 §2):

- ego-browser already exposes a complete, Playwright-style JS facade; a DSL on top only re-encodes the same calls with less power.
- In-process adaptation (branch on `page.evaluate` results, retry within the same script) is the ego-browser execution model; a YAML step list forces one round-trip per step.
- The heredoc is auditable: the story file *is* the test.

If you reach for a runner, write the heredoc instead.

## When to use / When NOT

| Use | Not — use instead |
| --- | --- |
| E2e smoke against a running local or deployed web app | Unit tests of pure functions — use the project's test runner |
| Verifying a load-bearing user flow after a deploy or PR | Visual regression of pixel layout — use a screenshot-diff tool |
| Capturing evidence (screenshot + assertions) a reviewer can read | Load/perf benchmarks — use a dedicated load tool |
| Auth-protected flows where task-space login inheritance applies | Headless-only API contract tests — use `fetch.server` directly, no page |
| One Bash invocation that adapts in-process to page state | Multi-day browser automation campaigns — break into task spaces per goal |

## Core rules

| Severity | Rule |
| --- | --- |
| **INVARIANT** | Fail-loud auth: expected-auth story that lands on a login page emits `{status:'fail', reason:'landed-on-login'}` and stops — never a silent pass. |
| **INVARIANT** | One JSON object to stdout via `console.log`, at the end. Intermediate reads stay in-script. |
| **DEFAULT** | One Bash invocation per story (`ego-browser nodejs <<'EOF' ... EOF`). Each `await` is an internal op, not a step boundary; adapt in-process. |
| **DEFAULT** | `taskSpaces.useOrCreate(name)` once near the start; reuse the same `task.id`/name for the same goal. Do not create a new space per assertion. |
| **DEFAULT** | Register `waitForResponse` / `waitForURL` *before* the action that triggers them; verify resulting state, do not trust the click alone. |
| **DEFAULT** | Prefer semantic locators (`getByRole`, `getByLabel`); fall back to raw CSS/xpath only on AX-poor surfaces. |
| **HINT** | Capture a screenshot for every pass and every fail; the path goes in the JSON. |
| **HINT** | Keep the story single-purpose — one user-visible flow. Split flows into separate story files. |

## Flow

1. **Select task space.** `const task = await taskSpaces.useOrCreate('weftd smoke')`.
2. **Subscribe to console/page errors** before navigation, so errors during load are captured.
3. **Navigate.** `await browser.openOrReuseTab(url, { wait: true, timeout: 20000 })`.
4. **Fail-loud auth check.** If the page should be authenticated but looks like a login page, emit fail JSON and return.
5. **Snapshot + interact.** `page.snapshot()` → locators → click/fill/select/press. Register waits before triggering actions.
6. **Assert.** `await page.evaluate(() => ...)` returning booleans; assemble an `assertions` array.
7. **Evidence.** `await page.screenshot({ path, fullPage: true })`.
8. **Emit.** One `console.log(JSON.stringify(result, null, 2))`.
9. **(Separate, optional) Complete.** Only after reviewing the JSON, a dedicated final Bash call may run `taskSpaces.complete(task.id, { keep: false })`. This is the one exception to the one-invocation default and performs no `page`/`browser` work.

## Anti-patterns

| Don't | Why |
| --- | --- |
| Assert against the login page's own heading/title and call it pass | Masks an auth regression; violates the fail-loud INVARIANT. |
| Print multiple JSON objects across the script | Caller cannot tell which is final; one object, at the end. |
| One Bash call per "step" with intermediate `console.log` planning | Re-encodes a YAML runner in Bash; loses in-process adaptation. |
| `page.waitForTimeout(5000)` as the primary sync | Brittle; use state-based waits (`waitForLoadState`, `waitForFunction`). |
| Hardcode/select a `targetId` from a prior command | Short-lived handle; discover and use within the same invocation. |
| `JSON.parse(page.evaluate(...))` | `page.evaluate` returns the value directly; parsing throws on non-JSON. |
| Skip screenshot on fail | Evidence is most useful on the failure path. |
| Mint a new task space per assertion | Breaks login-state reuse and goal continuity. |

## Verification checklist

Before declaring a story done, confirm:

- [ ] Story runs as a single `ego-browser nodejs <<'EOF' ... EOF` Bash invocation.
- [ ] `taskSpaces.useOrCreate(...)` appears once near the top.
- [ ] Fail-loud auth check present when the target page expects authentication.
- [ ] Console/pageerror subscription set **before** navigation.
- [ ] All waits (`waitForResponse`/`waitForURL`) registered before the triggering action.
- [ ] Assertions run via `page.evaluate` (or locator `evaluateAll`); no `JSON.parse` of evaluate results.
- [ ] Screenshot captured for both pass and fail paths; path included in JSON.
- [ ] Exactly one `console.log(JSON.stringify(result, null, 2))` at the end.
- [ ] JSON `status` is `'pass'` or `'fail'`; `reason` is a short machine-readable code; `assertions` array lists each check.
- [ ] No `.js` file written; no Playwright import; no second browser launched.

# References:
- [Story heredoc template](references/story-template.md)
- [Example: weftd smoke story](examples/weftd-smoke.story.md)
