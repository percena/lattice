# Story template

Copy this template and adapt the URL, selectors, assertions, and expected values. It is a single `ego-browser nodejs <<'EOF' ... EOF` heredoc — no `.js` file, no Playwright import, no step DSL. Consumer repos keep story files in the catalog at `.lattice/e2e/stories/<name>.story.md` — one flow per file; the feature map's `story` column points there.

Every story file starts with the traceability header (docs convention — not parsed by tooling yet):

```yaml
feature: ftr-<slug>       # feature-map row id (.lattice/feature-map.md)
oracle: <citation>        # spc-N A* | README §x | generic invariants
mutations: none           # none | safe | destructive — must equal the map row's class
# console_allow: []       # optional: expected console.error lines (substring match)
# http_allow: []          # optional: expected first-party HTTP failures ("METHOD url-substring status")
# origins_allow: []       # optional: extra first-party origins (e.g. an API on another port)
```

```bash
ego-browser nodejs <<'EOF'
// ── 1. Task space: inherit the user's login state ──────────────────────
//    One per goal. ADR-002 §2: task-space login-state inheritance
//    eliminates cross-port auth engineering.
const task = await taskSpaces.useOrCreate('<story-name>')

// ── 2. Subscribe to console/page/HTTP errors BEFORE navigation ─────────
const target = process.env.STORY_URL || 'http://localhost:3000/health'
const ORIGINS_ALLOW = []   // mirror the header's origins_allow (extra first-party origins)
const HTTP_ALLOW = []      // mirror the header's http_allow ("METHOD url-substring status")

const consoleErrors = []
const pageErrors = []
const httpErrors = []
const isFirstParty = (u) => {
  try {
    const origin = new URL(u).origin
    return origin === new URL(target).origin || ORIGINS_ALLOW.includes(origin)
  } catch (e) { return false }
}
page.on('console', (msg) => { if (msg.type() === 'error') consoleErrors.push(msg.text()) })
page.on('pageerror', (err) => { pageErrors.push(err.message) })
page.on('response', (res) => {
  if (isFirstParty(res.url()) && res.status() >= 400) {
    httpErrors.push({ url: res.url(), status: res.status(), method: res.request().method() })
  }
})
page.on('requestfailed', (req) => {
  if (isFirstParty(req.url())) {
    httpErrors.push({ url: req.url(), failure: (req.failure() && req.failure().errorText) || 'failed', method: req.method() })
  }
})

// ── 3. Navigate ─────────────────────────────────────────────────────────
await browser.openOrReuseTab(target, { wait: true, timeout: 20000 })

// ── 4. Fail-loud auth check (INVARIANT) ────────────────────────────────
//    If the page should be authenticated but landed on a login form,
//    FAIL — never a silent pass by asserting the login page's own chrome.
const url = await page.url()
const title = await page.title()
const EXPECTED_AUTH = true   // set false for public pages (e.g. /health)
const looksLikeLogin = /\/auth\/login|\/sign-in|\/login/i.test(url) ||
  /sign in|log in/i.test(title || '')
if (EXPECTED_AUTH && looksLikeLogin) {
  const result = {
    status: 'fail',
    reason: 'landed-on-login',
    taskSpaceId: task.id,
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

// ── 5. Snapshot + interact ─────────────────────────────────────────────
//    Prefer semantic locators (getByRole / getByLabel). Re-snapshot after
//    navigation. Register waits BEFORE the triggering action.
// await page.snapshot()
// const responsePromise = page.waitForResponse(
//   (r) => r.url().includes('/api/') && r.ok(),
//   { timeout: 15000 },
// )
// await page.getByLabel('Search').fill('example')
// await page.getByRole('button', { name: /search/i }).click()
// const response = await responsePromise

// ── 6. Assert via page.evaluate ──────────────────────────────────────────
//    page.evaluate runs IN the page and returns the value directly.
//    Do NOT JSON.parse the result.
const assertions = []

const titleOk = await page.evaluate((expected) => {
  return document.title.includes(expected)
}, 'Weftd')
assertions.push({ name: 'title contains expected text', pass: titleOk })

// Example: assert a node is visible and non-empty.
// const bodyOk = await page.evaluate(() => {
//   const main = document.querySelector('main')
//   return !!main && main.textContent.trim().length > 0
// })
// assertions.push({ name: 'main has content', pass: bodyOk })

assertions.push({ name: 'no console errors', pass: consoleErrors.length === 0 })
assertions.push({ name: 'no page errors', pass: pageErrors.length === 0 })

// HTTP errors: allowlist filters the ASSERTION, never the evidence array.
const allowedHttp = (e) => HTTP_ALLOW.some((rule) => {
  const [method, frag, status] = rule.split(' ')
  return e.method === method && e.url.includes(frag) && String(e.status) === status
})
assertions.push({ name: 'no unexpected http errors', pass: httpErrors.every(allowedHttp) })

// ── 7. Evidence: screenshot for both pass and fail ──────────────────────
const screenshotPath = process.env.STORY_SCREENSHOT || '/tmp/story-evidence.png'
await page.screenshot({ path: screenshotPath, fullPage: true })

// ── 8. Emit one JSON object (DEFAULT: at the end) ──────────────────────
const allPass = assertions.every((a) => a.pass)
const result = {
  status: allPass ? 'pass' : 'fail',
  reason: allPass ? 'ok' : 'assertion-failed',
  taskSpaceId: task.id,
  url,
  title,
  assertions,
  consoleErrors,
  pageErrors,
  httpErrors,
  screenshot: screenshotPath,
}
console.log(JSON.stringify(result, null, 2))

// ── 9. (Optional, separate Bash call) Complete the task space ───────────
//    Do NOT call taskSpaces.complete here. Only after reviewing the JSON,
//    a dedicated final invocation runs:
//      taskSpaces.complete(<task.id>, { keep: false })
//    and performs no page/browser work.
EOF
```

## Adaptation guide

- **Traceability header:** fill `feature` from the feature-map row, cite the `oracle` you actually assert, and set `mutations` to the map row's class. Keep the in-script `ORIGINS_ALLOW`/`HTTP_ALLOW` constants mirroring the header — the header documents intent, the constants enforce it.
- **Public vs auth page:** set `EXPECTED_AUTH = false` for public endpoints (health, landing) and delete the fail-loud block, or keep it and let `EXPECTED_AUTH` gate it.
- **Multiple assertions:** push one `{ name, pass }` per check. Keep each assertion atomic — one condition per entry.
- **Interactions that trigger network:** declare `const p = page.waitForResponse(...)` *before* `await locator.click()`, then `const response = await p`.
- **Form fill + submit:** `await page.getByLabel('Email').fill(...)` then `await page.getByRole('button', { name: /submit/i }).click()`; wait for the resulting URL or response.
- **Evidence path:** pass via env (`STORY_SCREENSHOT`) so CI can point it at an artifact dir; default to `/tmp`.
- **Expected HTTP failures (negative stories):** a story that asserts rejection (e.g. invalid login → 422) lists the failure in the header's `http_allow` and mirrors it in `HTTP_ALLOW` (`["POST /api/login 422"]`). The entry still appears in `httpErrors` — only the assertion is filtered.
- **API on another origin:** when the app calls an API on a different port/host, add that origin to `origins_allow`/`ORIGINS_ALLOW` so its 4xx/5xx count as first-party instead of being dropped as third-party noise.
- **Mutation stories (`safe`/`destructive`):** follow the round-trip recipe in `../SKILL.md` — write → `page.reload()` (or re-navigate) → assert persistence on fresh page state; toasts don't count. `safe` stories clean up when the app allows and add a `leftovers` array to the result JSON.
- **In-process adaptation:** if an assertion fails and a retry is safe, retry within the same heredoc (re-snapshot, re-evaluate). Do not exit to plan the next step.
