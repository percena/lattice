---
name: run-e2e
description: "Reference pattern for writing ego-browser heredoc JS end-to-end test scripts: one Bash invocation per story, fail-loud auth checks, structured JSON output via console.log. Not a YAML runner, not ERP auto-playwright. Use when authoring or reviewing e2e stories that drive a real Chromium browser against a local or deployed web app."
allowed-tools: Bash Read Grep Glob
metadata:
  agents: "claude-code,codex"
---

# run-e2e

run-e2e is a **reference pattern** for writing end-to-end test scripts with the ego-browser skill (an externally installed skill; install separately before use). A story is a single `ego-browser nodejs <<'EOF' ... EOF` heredoc that navigates a real Chromium page, interacts through semantic locators, captures screenshot evidence, runs assertions via `page.evaluate`, and prints one structured JSON object to stdout. The caller (a Lattice skill, a CI step, or a human) reads that JSON.

This skill documents the pattern; it is **not** a separate runner. There is no YAML, no step DSL, no plugin loader. You write JavaScript in a heredoc and run it with one Bash call.

**Foundation (ADR-002 §2):** ego-browser is the foundation for browser automation in this stack — not ERP's auto-playwright, not a bespoke driver. Task-space login-state inheritance eliminates cross-port auth engineering: an agent-owned space reuses the user's already-logged-in Chromium profile, so a story that targets an authenticated app does not need to re-login, persist cookies, or mint tokens.

## Primitives

Every story composes these ego-browser primitives. Names mirror the ego-browser facade (Playwright-style).

| Primitive | ego-browser call | Notes |
| --- | --- | --- |
| **goto** | `browser.openOrReuseTab(url, { wait: true, timeout })` | Reuses tab if URL already open; otherwise opens. Prefer over `page.goto` for cross-tab safety. |
| **subscribe** | `page.on('console' \| 'pageerror' \| 'response' \| 'requestfailed', handler)` | Register **before** navigation; feeds the `consoleErrors` / `pageErrors` / `httpErrors` arrays in the JSON output. |
| **snapshot** | `await page.snapshot()` | Full-page accessibility snapshot; builds the `@N` ref map for the current command. Re-snapshot after navigation. |
| **locator** | `page.locator(sel)` / `page.getByRole(...)` / `page.getByLabel(...)` | Semantic first; raw CSS/xpath only when AX-poor. Locators are strict and auto-wait. |
| **click** | `await locator.click()` | Register `page.waitForResponse` / `page.waitForURL` *before* the click when it triggers network or navigation. |
| **fill** | `await locator.fill(value)` | Clears then fills. For selects use `locator.selectOption(value)`. |
| **select** | `await locator.selectOption(value)` | Strict; waits for the option. |
| **press** | `await page.keyboard.press('Enter')` / `await locator.press('Tab')` | For key chords and submit-on-Enter. |
| **screenshot** | `await page.screenshot({ path, fullPage: true })` | Evidence capture. Use `page.info()` first; if `w:0`/`h:0`, stop and re-verify the tab. |
| **assert** | `await page.evaluate(() => { ... ; return bool })` | Runs in-page; returns the value directly. Do **not** `JSON.parse` the result. Return `true`/`false` or a structured object; the story interprets. |
| **wait (state)** | `page.waitForURL` / `page.waitForLoadState` / `page.waitForFunction` | Register before the triggering action. These return falsy on timeout — check the result. |
| **wait (response)** | `page.waitForResponse` | Register before the triggering action. waitForResponse throws on timeout (not falsy); wrap in try/catch. |
| **fetch** | `fetch.server(...)` / `fetch.browser(...)` | Node-side or in-origin requests; escape hatch for API-level probes. |
| **cdp** | `cdp('Page.handleJavaScriptDialog', { accept: true })` | Escape hatch only; dismiss dialogs via `page.info()` first. |

## Fail-loud auth check

**INVARIANT:** If a story expects an authenticated page but lands on a login form, the story **FAILS** — it must never silently pass by asserting against the login page's own chrome.

Pattern: after `goto`, inspect `await page.url()` and `await page.title()` (or a login-page marker). If the URL path matches a login route or the title/heading indicates a login form, emit a failure JSON object and stop. Do not continue to interactions that would incidentally "succeed" on a login page.

```js
const url = await page.url()
const title = await page.title()
const looksLikeLogin = /\/auth\/login|\/sign-in|\/login/i.test(url) ||
  /sign in|log in/i.test(title || '')
if (expectedAuth && looksLikeLogin) {
  const result = {
    status: 'fail',
    reason: 'landed-on-login',
    url,
    title,
    consoleErrors,
    pageErrors,
    httpErrors,
  }
  let failScreenshot = null
  try { failScreenshot = await page.screenshot({ path: '.playwright-artifacts/fail-auth.png', fullPage: true }) } catch (e) { /* best-effort */ }
  result.screenshot = failScreenshot
  console.log(JSON.stringify(result, null, 2))
  throw new Error('run-e2e: fail-loud auth check failed — landed on login page')
}
```

Because task spaces inherit the user's login state, an unexpected login redirect usually means the session expired or the task space was not selected — surface it, do not mask it.

## Mutation round-trip

**DEFAULT:** A story that mutates data (header `mutations: safe` or `destructive`) asserts the **round-trip**: perform the mutation → `page.reload()` (or re-navigate to the reading view) → assert the change via **fresh page state**. A success toast, a closed modal, or an optimistic list entry proves the UI handler ran — not that anything persisted. The reload is what separates "the frontend updated" from "the backend saved".

```js
// mutations: safe — create, reload, assert persisted
const created = page.waitForResponse(
  (r) => r.url().includes('/api/items') && r.ok(),
  { timeout: 15000 },
)
await page.getByLabel('Name').fill('e2e-roundtrip-item')
await page.getByRole('button', { name: /create/i }).click()
try { await created } catch (e) { /* timeout lands in httpErrors/assertions below */ }

// Round trip: only fresh page state counts as persistence.
await page.reload()
await page.snapshot()
const persisted = await page.evaluate(() =>
  Array.from(document.querySelectorAll('td, li'))
    .some((n) => n.textContent.includes('e2e-roundtrip-item')))
assertions.push({ name: 'created item persisted across reload', pass: persisted })

// Cleanup (safe stories): delete what you created when the app allows it;
// report leftovers in the JSON — never hide them.
const leftovers = []
// await page.getByRole('button', { name: /delete/i }).click() ... — on failure:
// leftovers.push('e2e-roundtrip-item')
```

`safe` stories clean up after themselves when the app exposes a way to; whatever remains goes into a `leftovers` array in the final JSON so the caller sees the residue. `destructive` stories follow the operator-authorization policy of the calling skill (see verify-features) — run-e2e itself only defines the pattern.

## Structured output

**DEFAULT:** A story prints **exactly one** JSON object to stdout via `console.log`. The caller parses it.

```json
{
  "status": "pass" | "fail",
  "reason": "short machine-readable code (e.g. title-mismatch, landed-on-login, console-errors)",
  "taskSpaceId": "task space id (string)",
  "url": "final page url",
  "title": "final page title",
  "assertions": [
    { "name": "title contains Weftd", "pass": true },
    { "name": "no console errors", "pass": true }
  ],
  "screenshot": "path/to/evidence.png",
  "consoleErrors": [],
  "pageErrors": [],
  "httpErrors": [
    { "url": "https://app.example.com/api/items", "status": 500, "method": "POST" },
    { "url": "https://app.example.com/api/ping", "failure": "net::ERR_CONNECTION_REFUSED", "method": "GET" }
  ]
}
```

- `console.log(JSON.stringify(result, null, 2))` once, at the end.
- Do not print intermediate JSON objects; intermediate reads stay in-script.
- Screenshots are file paths the caller can attach as evidence.
- Capture console errors by subscribing before navigation: `page.on('console', e => { if (e.type() === 'error') errors.push(e.text()) })` for `consoleErrors` and `page.on('pageerror', e => errors.push(e.message))` for `pageErrors`. `pageErrors` (uncaught page exceptions) and `consoleErrors` (`console.error` calls) are separate arrays — do not merge them.
- Capture HTTP errors with the same discipline — subscribe before navigation: `page.on('response', ...)` pushing `{ url, status, method }` for **first-party** responses with `status >= 400`, and `page.on('requestfailed', ...)` pushing `{ url, failure, method }` for failed first-party requests. `httpErrors` is a third separate array beside `consoleErrors`/`pageErrors` — do not merge.
- **First-party** = same origin as the app under test, plus any origins listed in the story header `origins_allow` (e.g. an API on another port). Third-party noise (analytics, CDNs, extensions) is excluded from `httpErrors` entirely.
- **Expected failures** (e.g. a negative story asserting a 422) are allowlisted via the story header `http_allow`. Allowlisted entries still appear in `httpErrors` (evidence stays complete); the story's `no unexpected http errors` assertion checks the array **after** removing allowlisted entries — same semantics as `console_allow`.
- **Caller parsing note:** extract the JSON object from stdout; a trailing `[ego-browser:notice]` line may follow the JSON and must be ignored before `JSON.parse`. Split on the last `{` ... `}` object or strip trailing notice lines before parsing.

## Story traceability header

**DEFAULT:** Every `*.story.md` file starts with a small fenced yaml block that says what the story verifies and how dangerous it is. It is a docs convention read by humans and skills (verify-features matches it against the feature map) — no tooling parses it yet.

```yaml
feature: ftr-<slug>       # feature-map row id (.lattice/feature-map.md)
oracle: spc-104 A2        # citation: spc-N A* | README §x | generic invariants
mutations: none           # none | safe | destructive — must equal the map row's class
# console_allow: []       # optional: expected console.error lines (substring match)
# http_allow: []          # optional: expected first-party HTTP failures ("METHOD url-substring status")
# origins_allow: []       # optional: extra first-party origins (e.g. an API on another port)
```

- `oracle` cites where the expected behavior comes from — a spec acceptance line beats a README claim beats generic invariants (see verify-features for the hierarchy).
- `mutations` gates the round-trip requirement above and the calling skill's environment policy.
- `http_allow` entries are `"<METHOD> <url-substring> <status>"` (e.g. `"POST /api/login 422"` for a negative login story); `console_allow` entries are substrings of tolerated `console.error` lines. Both filter assertions, not evidence — the arrays in the JSON stay complete.

## Not a YAML runner

run-e2e is **heredoc JS, not a YAML runner**. There is no `steps:` block, no `assert:` DSL, no plugin discovery. Rationale (ADR-002 §2):

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
| **DEFAULT** | Subscribe `page.on('response')` (first-party `status >= 400`) and `page.on('requestfailed')` **before** navigation; report them in a separate `httpErrors` array. Unexpected first-party 4xx/5xx fail the story; expected ones are allowlisted via the story header `http_allow`. |
| **DEFAULT** | Mutation stories (`mutations: safe`/`destructive`) assert the round-trip: mutate → `page.reload()`/re-navigate → assert on fresh page state. Toasts are not persistence. `safe` stories clean up when the app allows and report `leftovers` in the JSON. |
| **DEFAULT** | Prefer semantic locators (`getByRole`, `getByLabel`); fall back to raw CSS/xpath only on AX-poor surfaces. |
| **HINT** | Capture a screenshot for every pass and every fail; the path goes in the JSON. |
| **HINT** | Keep the story single-purpose — one user-visible flow. Split flows into separate story files. |

## Flow

Consumer repos keep stories in a catalog at `.lattice/e2e/stories/*.story.md` — one flow per file, traceability header at the top; the feature map's `story` column points there.

1. **Select task space.** `const task = await taskSpaces.useOrCreate('app smoke')`.
2. **Subscribe to console/page/HTTP errors** before navigation, so errors during load are captured: `page.on('console')` + `page.on('pageerror')` + `page.on('response')` (first-party `status >= 400`) + `page.on('requestfailed')` (failed first-party requests).
3. **Navigate.** `await browser.openOrReuseTab(url, { wait: true, timeout: 20000 })`.
4. **Fail-loud auth check.** If the page should be authenticated but looks like a login page, capture a fail screenshot, emit fail JSON, then throw.
5. **Snapshot + interact.** `page.snapshot()` → locators → click/fill/select/press. Register waits before triggering actions. Mutation stories add the round-trip (reload → assert fresh state) here.
6. **Assert.** `await page.evaluate(() => ...)` returning booleans; assemble an `assertions` array (including `no unexpected http errors` filtered through `http_allow`).
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
| Assert the success toast and call the mutation verified | Toasts prove the UI handler ran, not that data persisted; round-trip through a reload. |
| Merge HTTP failures into `consoleErrors`, or drop allowlisted ones from the JSON | Three separate arrays; allowlists filter assertions, never evidence. |

## Common Rationalizations

| Rationalization | Reality |
| --- | --- |
| "One quick `waitForTimeout` won't hurt" | Time-based waits are the top flake source; a state-based wait exists for every case |
| "The page rendered, so login worked" | Asserting against the login page's own content masks auth regressions — fail loud instead |
| "I'll split the story into several Bash calls to watch progress" | Browser handles die between invocations; one heredoc per story is the contract |
| "The toast said 'Saved', so it saved" | Optimistic UI renders success before (or without) the write landing — reload and assert fresh state |
| "That 500 is from an analytics beacon, I'll skip HTTP capture" | The first-party filter already excludes third-party noise; a silently-500ing app API is exactly the bug class `httpErrors` exists for |

## Red Flags

- More than one JSON object printed across the story — the caller cannot tell which is final
- A `targetId` or page handle carried over from a previous invocation
- No screenshot on the failure path — evidence is most useful exactly there
- A mutation story with no reload/re-navigate between the write and the persistence assertion
- A story file with no traceability header — the caller cannot tell what feature/oracle it verifies

## Verification

Before declaring a story done, confirm:

- [ ] Story runs as a single `ego-browser nodejs <<'EOF' ... EOF` Bash invocation.
- [ ] `taskSpaces.useOrCreate(...)` appears once near the top.
- [ ] Fail-loud auth check present when the target page expects authentication.
- [ ] Console/pageerror subscription set **before** navigation.
- [ ] HTTP error subscription (`response` with first-party `status >= 400` + `requestfailed`) set **before** navigation; `httpErrors` is its own array (never merged), entries `{url, status|failure, method}`.
- [ ] Story file starts with the traceability header: `feature`, `oracle`, `mutations` (plus `console_allow`/`http_allow`/`origins_allow` when needed), and lives at `.lattice/e2e/stories/` in consumer repos.
- [ ] Mutation stories (`safe`/`destructive`) round-trip: reload/re-navigate between the write and the persistence assertion; `safe` stories clean up when possible and report `leftovers` in the JSON.
- [ ] All waits (`waitForResponse`/`waitForURL`) registered before the triggering action.
- [ ] Assertions run via `page.evaluate` (or locator `evaluateAll`); no `JSON.parse` of evaluate results.
- [ ] Screenshot captured for both pass and fail paths; path included in JSON.
- [ ] Exactly one `console.log(JSON.stringify(result, null, 2))` at the end.
- [ ] JSON `status` is `'pass'` or `'fail'`; `reason` is a short machine-readable code; `assertions` array lists each check.
- [ ] No `.js` file written; no Playwright import; no second browser launched.

# References:
- [Story heredoc template](references/story-template.md)
- [Example: app smoke story](examples/smoke-test.story.md)
