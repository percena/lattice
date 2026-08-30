# tkt-234-auto-trust-self-board

> **TL;DR:** `github-project-add.sh` auto-trusts a `.env`-selected board when `OWNER == authenticated gh user` (own board = non-abusable), removing the silent no-op friction while keeping the `ALLOW_DOTENV` gate for org/other boards.
> **Kind:** feat · **Status:** open · **Priority:** P2
> **Path:** tkt-234 → pr (one-PR)

| Field | Value |
| --- | --- |
| kind | feat |
| priority | P2 |
| labels | feat, P2 |
| github | https://github.com/percena/lattice/issues/234 |
| status | open |
| adopted | true |
| summary | Auto-trust .env board when OWNER == authenticated gh user; keep ALLOW_DOTENV gate for org/other |
| spec | none (ticket-only) |
| covers | github-project-add.sh trust gate (lines 231–252), .env.example, tests |
| blocked_by | (none) |
| parallel_group | (serial) |
| paths | skills/_lattice-lib/scripts/github-project-add.sh, .env.example, skills/_lattice-lib/scripts/tests/github-project-add.bats |
| solo_merge | yes |
| primary_ticket | tkt-234 |
| worktree_bind | tkt-234-auto-trust-self-board |
| worktree | sibling `…/lattice.worktrees/tkt-234-auto-trust-self-board/` |

## Acceptance (this slice)

- [x] **A1** When board target comes from `.env` AND `OWNER == authenticated gh user`, `github-project-add.sh` proceeds to `gh project item-add` without requiring `LATTICE_GITHUB_PROJECT_ALLOW_DOTENV`.
- [x] **A2** When `OWNER != authenticated gh user` (org/other), the existing `ALLOW_DOTENV` gate is unchanged (same `skip:` log + exit 0).
- [x] **A3** When `gh api user` cannot resolve (no auth / network), auto-trust does NOT fire; falls back to the existing gate (fail closed).
- [x] **A4** `.env.example` documents the auto-trust-self rule.
- [x] **A5** bats tests cover A1–A3 with a mocked `gh`.

## Approach

In `github-project-add.sh`, after `DOTENV_CHOSE_TARGET=true` is set (line 238–240) and before the `ALLOW_DOTENV` case (line 241), insert a self-ownership check:

```sh
# Auto-trust: if the .env-selected board owner == the authenticated gh user,
# the write targets the operator's own board — inherently non-abusable.
if $DOTENV_CHOSE_TARGET; then
  AUTH_USER="$(gh api user --jq .login 2>/dev/null || true)"
  if [[ -n "$AUTH_USER" && "$(printf '%s' "$OWNER" | tr '[:upper:]' '[:lower:]')" == "$(printf '%s' "$AUTH_USER" | tr '[:upper:]' '[:lower:]')" ]]; then
    log "board target $OWNER/$NUMBER owned by authenticated user ($AUTH_USER) — auto-trusted"
  else
    # existing ALLOW_DOTENV gate (org/other owner, or gh-unavailable)
    ...existing case block...
  fi
fi
```

Soft-fail: `gh api user` failure → `AUTH_USER` empty → fall through to the existing gate (A3). Case-insensitive compare (GitHub logins are case-insensitive).

## Anticipated decisions

- **Login case sensitivity** — GitHub logins are case-insensitive; compare lowercased. `pre-resolved`.
- **`gh api` cost** — one extra `gh api user` call per add when target is dotenv-sourced; negligible (skill-created items, not high-volume). `pre-resolved`.
- **Where to resolve `AUTH_USER`** — only when `DOTENV_CHOSE_TARGET` is true (env-sourced targets skip the gate already). `pre-resolved`.
- **Mocking `gh` in bats** — use a PATH-injected stub or `GIT_`-style function override; check existing test harness conventions. `agent-decides`.

## Notes

- ADOPT_CHECK: issue #234 body is SoT for long prose; binder is the recovery card. Do not rewrite issue body.
- `ALLOW_DOTENV=1` opt-in stays for org/other boards — the gate is narrowed, not removed.

## References

- GitHub issue (SoT): https://github.com/percena/lattice/issues/234
- Script: `skills/_lattice-lib/scripts/github-project-add.sh` (trust gate lines 231–252)

## Lineage

- Primary ticket: **tkt-234**
- Spec: none (ticket-only, no parent)
- Covers: github-project-add.sh trust gate + .env.example + tests
