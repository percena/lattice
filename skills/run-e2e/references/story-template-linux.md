# Story template (Linux / camoufox-js)

Copy this template and adapt the URL, selectors, assertions, and expected
values. It is a single `node --input-type=module <<'EOF' … EOF` heredoc that
launches camoufox-js (an anti-detect Firefox driven via Playwright) — no `.js`
file, no step DSL. This is the Linux backend per ADR-009; on macOS use
[`story-template.md`](story-template.md) (`ego-browser nodejs`) instead.

Prerequisites (the preflight `scripts/ensure-e2e-runtime.sh` checks these and
guides a confirm-first install): `npm i -g camoufox-js`, `npx camoufox-js
fetch`, `npm i -g @playwright/cli@latest`. The preflight prints
`E2E_BACKEND=camoufox` when ready.

Consumer repos keep story files in the catalog at
`.lattice/e2e/stories/<name>.story.md` — one flow per file; the feature map's
`story` column points there.

Every story file starts with the traceability header (docs convention — not
parsed by tooling yet):

```yaml
feature: ftr-<slug>       # feature-map row id (.lattice/feature-map.md)
oracle: <citation>        # spc-N A* | README §x | generic invariants
mutations: none           # none | safe | destructive — must equal the map row's class
platform: linux           # linux (camoufox-js) | macos (ego-browser) — select backend
# console_allow: []       # optional: expected console.error lines (substring match)
# http_allow: []          # optional: expected first-party HTTP failures ("METHOD url-substring status")
# origins_allow: []       # optional: extra first-party origins (e.g. an API on another port)
```

```bash
node --input-type=module <<'EOF'
// ── 0. Launch camoufox-js (anti-detect Firefox via Playwright) ──────────
//    ADR-009 Linux backend. Real Playwright Page with BrowserForge
//    fingerprint injection; no Python bridge.
import { Camoufox } from 'camoufox-js'

const STORAGE_STATE = process.env.STORY_STORAGE_STATE || ''  // path to a saved auth storageState, or '' for unauthenticated
const launchOpts = { headless: process.env.STORY_HEADED ? false : true }
if (STORAGE_STATE) launchOpts.storageState = STORAGE_STATE
const browser = await Camoufox(launchOpts)
const page = await browser.newPage()

try {
  // ── 1. Login state (Linux has no ego task spaces) ──────────────────────
  //    Carry auth via a persistent storageState file (saved by a prior login
  //    story) or re-login inline. ADR-002 §2 task-space inheritance is
  //    macOS-only; on Linux, storageState is the carrier.

  // ── 2. Subscribe to console/page/HTTP errors BEFORE navigation ─────────
  const target = process.env.STORY_URL || 'http://localhost:3000/health'
  const ORIGINS_ALLOW = []   // mirror the header's origins_allow
  const HTTP_ALLOW = []      // mirror the header's http_allow

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
  await page.goto(target, { waitUntil: 'load', timeout: 20000 })

  // ── 4. Fail-loud auth check (INVARIANT) ────────────────────────────────
  //    If the page should be authenticated but landed on a login form,
  //    FAIL — never a silent pass by asserting the login page's own chrome.
  const url = page.url()
  const title = await page.title()
  const EXPECTED_AUTH = true   // set false for public pages (e.g. /health)
  const looksLikeLogin = /\/auth\/login|\/sign-in|\/login/i.test(url) ||
    /sign in|log in/i.test(title || '')
  if (EXPECTED_AUTH && looksLikeLogin) {
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

  // ── 5. Snapshot + interact ─────────────────────────────────────────────
  //    Standard Playwright locators. Re-snapshot after navigation.
  //    Register waits BEFORE the triggering action.
  // const ax = await page.accessibility.snapshot()
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
    backend: 'camoufox',
    url,
    title,
    assertions,
    consoleErrors,
    pageErrors,
    httpErrors,
    screenshot: screenshotPath,
  }
  console.log(JSON.stringify(result, null, 2))

  // ── 9. (Optional) Persist login state for a later story ────────────────
  //    if (STORAGE_STATE) await page.context().storageState({ path: STORAGE_STATE })
} finally {
  await browser.close()
}
EOF
```

## Adaptation guide

- **Backend selection:** this template is the Linux (camoufox-js) variant. On
  macOS, use [`story-template.md`](story-template.md) (`ego-browser nodejs`).
  The preflight (`scripts/ensure-e2e-runtime.sh`) selects the backend.
- **Login state on Linux:** there are no ego task spaces. Carry auth via a
  `storageState` JSON file saved by a prior login story, or re-login inline.
  Set `STORY_STORAGE_STATE` to the file path. A persistent context
  (`Camoufox({ persistentContext: … })`) is the alternative for a long-lived
  profile on a VPS.
- **Headless vs headed:** camoufox-js runs headless by default. On a headed
  VPS, set `STORY_HEADED=1` to launch headed (useful with a virtual display).
  The Python lib's built-in virtual display is a fallback when headless mode
  leaks (see ADR-009 fallback note).
- **Primitives parity:** the page-level calls (`goto`, `page.on`, locators,
  `click`/`fill`/`select`/`press`, `screenshot`, `evaluate`, waits) are
  identical to the macOS ego-browser facade — see the Primitives → backend
  mapping table in `../SKILL.md`. Differences: no `taskSpaces`, no `cdp`
  (Firefox/Juggler, not CDP — use `page.on('dialog')` for dialogs), and
  `fetch.server` becomes Node's `fetch`.
- **Traceability header:** fill `feature` from the feature-map row, cite the
  `oracle` you actually assert, set `mutations` to the map row's class, and set
  `platform: linux`. Keep the in-script `ORIGINS_ALLOW`/`HTTP_ALLOW` constants
  mirroring the header.
- **Mutation stories (`safe`/`destructive`):** follow the round-trip recipe in
  `../SKILL.md` — write → `page.reload()` (or re-navigate) → assert
  persistence on fresh page state; toasts don't count. `safe` stories clean up
  when the app allows and add a `leftovers` array to the result JSON.
- **In-process adaptation:** if an assertion fails and a retry is safe, retry
  within the same heredoc (re-snapshot, re-evaluate). Do not exit to plan the
  next step — one Bash invocation per story is the contract.
