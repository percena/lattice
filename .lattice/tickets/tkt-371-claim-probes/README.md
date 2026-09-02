# tkt-371-claim-probes

> **TL;DR:** claim-probes.sh + references/probes.md registry: executable claim–implementation probes seeded from the spc-337 drift classes, per-repo overlay, planted-drift tests.
> **Kind:** feat · **Priority:** P1

| Field | Value |
| --- | --- |
| kind | feat |
| priority | P1 |
| labels | feat,P1 |
| github | https://github.com/percena/lattice/issues/371 |
| status | rework |
| fix_cycles | 1 |
| wait_reason | (none) |
| created | 2026-09-02T07:21:07Z |
| updated | 2026-09-02T07:47:14Z |
| adopted | false |
| summary | claim-probes.sh + references/probes.md registry: executable claim–implementation probes seeded from the spc-337 drift classes, per-repo overlay, planted-drift tests. |
| spec | spc-369 — review-lineage (path: ../../specs/spc-369-review-lineage.md) |
| covers | A2 |
| blocked_by | (none) |
| merge_blocked_by | (none) |
| parallel_group | G0 |
| paths | skills/review-lineage/scripts/claim-probes.sh, skills/review-lineage/references/probes.md, skills/review-lineage/scripts/tests/claim-probes.bats, skills/review-lineage/scripts/tests/fixtures/probes/** |
| solo_merge | yes |
| **primary_ticket** | tkt-371 (this issue) |
| **related_tickets** | (none) |
| **worktree_bind** | tkt-371-claim-probes |
| worktree | sibling `…/lattice.worktrees/tkt-371-claim-probes/` |
| prs | pr-376 — https://github.com/percena/lattice/pull/376 |

## Acceptance (this slice)

- [x] **A2** — see GitHub issue #371 and Spec spc-369 A2. Evidence: `skills/review-lineage/scripts/tests/claim-probes.bats` 23/23 (bats 1.2.1; clean-fixture pass + one planted-drift case per built-in + overlay/--only/malformed/exit-3/timeout), `tools/check-bats-assertions.py` OK, `shellcheck -S warning` clean, `tools/ci-local.sh --fast` green; on-repo run 4 pass / 3 fail (findings in the PR body).

## Approach

1. Registry: Markdown table in `references/probes.md` (`id | claim (where) | probe | expect | severity`); parser in a python3 heredoc inside `claim-probes.sh` (dependency-free); optional overlay `.lattice/lineage-probes.tsv` merged by id (overlay wins).
2. Built-in probes (each a shell one-liner run with `REPO_ROOT`, `LATTICE_HOME` exported): skill-scripts-exist (grep `scripts/[a-z0-9-]+\.sh` in each SKILL.md → test -x); hooks-json-files-exist; validator-codes-cited-exist (grep backticked snake_case codes in docs/*.md ∩ validator source); retired-paths-absent (deny-list file in references); adr-verification-refs-resolve; spec-done-cites-tests (each `- [x] **A` line in a done Spec mentions `.bats`/`test`/`bats` or the Spec is flagged); fsm-doc-edges-subset-of-schema (reuse the awk from transition-parity.bats).
3. Expectations: `exit0` or `regex:<pattern>` on stdout; status pass|fail|skip (skip when a prerequisite path is absent); `--md`/`--json`; always exit 0.
4. Bats: fixtures/probes/clean/ passes all; one planted fixture per probe (e.g. SKILL naming a missing script; docs with 'MAIN clone .lattice/'; a done Spec with an A* citing no test) fails exactly that probe; overlay override test.

## Anticipated decisions

- Registry format Markdown table vs TSV — pre-resolved(spc-369 Agent-assumed): Markdown table.
- Probe timeout per probe — agent-decides (default 20 s via `timeout` when available).

## Decision journal

- 2026-09-02 — **Registry = Markdown table, parsed by a python3 heredoc inside `claim-probes.sh`** (no YAML, no extra lib module); pipes inside a probe cell are written `\|` and unescaped by the runner. Source: binder Approach #1 (chain #1) + spc-369 Agent-assumed "Markdown table (grep-able, reviewable)".
- 2026-09-02 — **Skip contract = probe exit 3** (stdout is the reason); for `regex`/`empty` any other non-zero exit is a `fail`, so a crashed probe never passes by accident. Source: spc-369 Risks (noisy probes demote to `skip`, never deleted) + audit-recipe §2 verify-then-report; ticket-local, reversible.
- 2026-09-02 — **Per-probe timeout via `subprocess` (process group killed on expiry), default 20 s**, instead of shelling out to `timeout(1)` — always available, portable to macOS (no coreutils `timeout`). Source: binder Anticipated decisions (agent-decides, default 20 s); same behaviour, fewer host dependencies.
- 2026-09-02 — **`validator-codes-cited-exist` rule**: a backticked `snake_case` token with ≥ 2 underscores on a line that also mentions `validate-lattice-artifacts` or `validator`. Measured on this tree: 17 candidates, 17 real codes, 0 noise (the unscoped ≥2-underscore rule had 17 false positives — config keys, reconcile-state codes, hook rule ids). Source: ticket text "choose a decidable rule, document it in the table" + ADR-007 §3 decidability.
- 2026-09-02 — **`skill-scripts-exist` resolves `<sibling>/scripts/<name>` under `skills/<sibling>/`** when the segment before `scripts/` is an existing skill dir (`_lattice-lib/scripts/…`, `finish-work/scripts/…`), else under the naming skill; `$SKILL_ROOT/scripts/x` and bare `scripts/x` resolve to the naming skill. Source: the 15 SKILL.md references surveyed (all cross-skill ones name `_lattice-lib` or `finish-work`); ticket A2 wording "resolves under that skill and is executable".
- 2026-09-02 — **`retired-paths.txt` supports an optional TAB-separated scope** (space-separated dirs; default `skills docs`): `verify-mutation.sh --pr` is scoped to `skills/finish-work` because batch-work's in-wave `verify-mutation.sh --pr <N> --expected-oid` probe of an OPEN PR is legitimate (`batch-work/references/flow.md:238,250`). Source: rev-20260902-015425Z F4 (a) names the finish-work flow only; spc-369 Risks (false positives).
- 2026-09-02 — **`validator-codes-cited-exist` and `retired-paths-absent` pass `--exclude-dir=fixtures`**: the planted-drift fixtures (which must contain a retired phrase / an unknown code) live under `skills/review-lineage/scripts/tests/fixtures/` and would otherwise trip the real-repo run. Documented in the claim column. Source: ticket "planted test unambiguous" + ADR-007 §9 (no self-inflicted noise).
- 2026-09-02 — **`spec-done-acceptance-cites-evidence` inspects the `- [x] **A<n>**` bullet plus its indented continuation lines, case-insensitive**, one output line per Spec listing the A ids. A first-line-only rule flagged every wrapped bullet (spc-226). Source: ticket A2 wording ("else list the A* ids"); `ci` matched as a whole word so "ci-local" counts and "specific" does not.
- 2026-09-02 — **`tools/validate-skills.sh` registration failure → `review-lineage` added to its `EXEMPT` list + `plugins/lattice/skills/review-lineage` symlink** (2 out-of-paths touches, no placeholder SKILL.md). The brief pre-authorised a placeholder SKILL.md if validate-skills failed, but the actual failure is "skills/review-lineage not registered" + "missing plugin symlink" — a SKILL.md alone does not fix it, and full registration (USER_FACING + anatomy SKILL.md + both manifests' keywords + plugin README) is tkt-372/373's declared scope. The EXEMPT line names the tickets that lift it. tkt-370 hits the same wall and must land the identical two touches (or rebase onto this). Source: brief fallback clause + fallback-policy scope-escape rule (smallest reversible touch, reported); see Pending decisions.
- 2026-09-02T07:47:14Z — fix cycle 1: `pr-open` → rework (fix_cycles 1; cap ≤2; ADR-004 §5) — brief: review Hold (PR #376): M1 MED — explicit --overlay to a missing/non-UTF-8 file raises a python traceback and exits 1, breaking the always-exit-0 sensor contract (parse_overlay open() :204; set -e :29). M2 LOW — --home with a nonexistent parent resolves REPO_ROOT to / (cd fails silently :105) → vacuous passes. M3 LOW — overlay probe cells are not backtick-unwrapped (strip_code applies to registry rows only). Also: spec-done-acceptance-cites-evidence demoted to severity low (rule stricter than the Spec convention). Rebase onto dev: tools/validate-skills.sh EXEMPT line conflicts with the tkt-370 line already on dev — keep dev's line.

## Pending decisions

- **validate-skills registration for `skills/review-lineage/`** — landed as an `EXEMPT` entry + plugin symlink (see journal). Alternative: register now in `USER_FACING` with a placeholder anatomy SKILL.md + manifest keywords + plugin README mention (pre-empts tkt-373 A4). Operator to confirm the EXEMPT route is acceptable until tkt-373; no blocker for merge.

## Attempts

## Notes

On-repo run of the real registry (`claim-probes.sh --md`, this tree at c4b02bc + this slice): 4 pass / 3 fail / 0 skip — the fails are findings for `review-lineage`, not fixed here (out of paths):

- NOTICED: skills/_lattice-lib/scripts/stamp-pr-open.sh — tracked as mode 100644 (not executable) while `create-pr/SKILL.md` names `../_lattice-lib/scripts/stamp-pr-open.sh`; `after-pr-open.sh` invokes it via `bash …` so it works, but the "executable script" claim is false (probe `skill-scripts-exist`) (out-of-paths, 2026-09-02)
- NOTICED: skills/review-code/scripts/review-context.py — mode 100644 while `review-code/SKILL.md` names `$SKILL_ROOT/scripts/review-context.py` (probe `skill-scripts-exist`) (out-of-paths, 2026-09-02)
- NOTICED: skills/finish-work/references/flow.md:45, skills/review-code/SKILL.md:122, skills/review-code/references/ci-check.md:14 — still spell `gh pr checks … --json name,state,conclusion,link`; `conclusion` is not a `gh pr checks` field on gh 2.92 (tkt-338/tkt-341 NOTICED, now mechanised by probe `retired-paths-absent`) (out-of-paths, 2026-09-02)
- NOTICED: .lattice/specs — 14 of 16 `status: done` Specs have checked A* items that cite no test/PR/ticket evidence (84 items; e.g. spc-145 A1–A6/A8, spc-254 A1–A3/A5–A7); rev-20260902-015425Z F6 "`done` is self-reported" measured (probe `spec-done-acceptance-cites-evidence`) (out-of-paths, 2026-09-02)
- NOTICED: tools/validate-skills.sh — a skill directory cannot exist without full registration (USER_FACING + plugin symlink + keywords + README); a multi-ticket skill delivery (spc-369 W0 → W2) therefore needs an EXEMPT bridge; consider an `INCUBATING=(…)` list with a Spec citation so W0 slices do not touch the validator (out-of-paths, 2026-09-02)

## References

- Spec: `spc-369` → `.lattice/specs/spc-369-review-lineage.md`
- Review: `rev-20260902-015425Z` (method origin)

## Lineage

- Parent spec: **spc-369**
- Parent issue (GH sub-issue of Spec primary): **#369**
- Primary ticket: **tkt-371**
- Covers: **A2**
- Blocked by: (none)
- Parallel group: G0
- Worktree bind: tkt-371-claim-probes

## Finish

- (none yet)
