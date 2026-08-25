# Example: weftd smoke story

A concrete e2e story that smoke-tests a running weftd instance. Adapt `STORY_URL` to point at your local or deployed instance (e.g. `http://localhost:8080/health` for a local dev server, or the deployed weftd URL for a post-deploy smoke).

```bash
STORY_URL="${STORY_URL:-http://localhost:8080/health}" \
STORY_SCREENSHOT="${STORY_SCREENSHOT:-/tmp/weftd-smoke.png}" \
ego-browser nodejs <<'EOF'
// 1. Task space — inherit login state (ADR-002 §2).
const task = await taskSpaces.useOrCreate('weftd-smoke')

// 2. Subscribe to console + page errors BEFORE navigation.
const consoleErrors = []
const pageErrors = []
page.on('console', (msg) => { if (msg.type() === 'error') consoleErrors.push(msg.text()) })
page.on('pageerror', (err) => { pageErrors.push(err.message) })

// 3. Navigate to the health endpoint (public page).
const target = process.env.STORY_URL
await browser.openOrReuseTab(target, { wait: true, timeout: 20000 })

// 4. Fail-loud auth check — health is public, so EXPECTED_AUTH = false.
//    Kept here as the reference shape; flip to true for a protected page.
const url = await page.url()
const title = await page.title()
const EXPECTED_AUTH = false
const looksLikeLogin = /\/login|\/sign-in|\/auth/i.test(url) ||
  /sign in|log in/i.test(title || '')
if (EXPECTED_AUTH && looksLikeLogin) {
  console.log(JSON.stringify({
    status: 'fail',
    reason: 'landed-on-login',
    taskSpaceId: task.id,
    url,
    title,
    consoleErrors,
    pageErrors,
  }, null, 2))
  return
}

// 5. Assert via page.evaluate (runs in-page; value returned directly).
const assertions = []

// Health endpoints often return JSON — read the body text and check it
// reports healthy. The exact shape may differ; adapt to weftd's contract.
const bodyOk = await page.evaluate(() => {
  const text = (document.body && document.body.textContent) || ''
  return /ok|healthy|up/i.test(text)
})
assertions.push({ name: 'health body reports ok', pass: bodyOk })

assertions.push({ name: 'no console errors', pass: consoleErrors.length === 0 })
assertions.push({ name: 'no page errors', pass: pageErrors.length === 0 })

// 6. Evidence: screenshot for both pass and fail.
const screenshotPath = process.env.STORY_SCREENSHOT
await page.screenshot({ path: screenshotPath, fullPage: true })

// 7. Emit one JSON object.
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
  screenshot: screenshotPath,
}
console.log(JSON.stringify(result, null, 2))
EOF
```

## Expected output (pass)

```json
{
  "status": "pass",
  "reason": "ok",
  "taskSpaceId": 42,
  "url": "http://localhost:8080/health",
  "title": "",
  "assertions": [
    { "name": "health body reports ok", "pass": true },
    { "name": "no console errors", "pass": true },
    { "name": "no page errors", "pass": true }
  ],
  "consoleErrors": [],
  "pageErrors": [],
  "screenshot": "/tmp/weftd-smoke.png"
}
```

## Notes

- **Local run:** start weftd (`go run` / docker compose), then run the story with `STORY_URL=http://localhost:<port>/health`.
- **Post-deploy smoke:** set `STORY_URL` to the deployed weftd health URL; attach `STORY_SCREENSHOT` to the deploy artifact dir.
- **Protected page variant:** copy `references/story-template.md`, set `EXPECTED_AUTH = true`, target a login-protected route, and rely on the task space's inherited login state instead of minting a token.
- **No completion in-script:** if you want to close the task space, run a separate `ego-browser nodejs <<'EOF' ... taskSpaces.complete(<id>, { keep: false }) ... EOF` invocation *after* reviewing the JSON above — never in the same Bash call as the browser work.
