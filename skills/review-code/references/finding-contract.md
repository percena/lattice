# review-code finding contract (portable)

## Material finding bar

Every **material** finding answers:

1. What can go wrong? (failure scenario)
2. Why is this path vulnerable?
3. Likely impact?
4. **Recommended solution** — best-practice fix with brief rationale (not just "direction"; give the concrete approach you'd apply).
5. **Alternatives** — 1–2 viable alternative solutions with trade-off notes. If only one sound approach exists, say "no viable alternative" rather than padding.

## Calibration

- Prefer one strong finding over several weak ones.
- Empty material findings is a valid pass — say *No material findings*.
- Style/naming/cleanup → optional **Nits** appendix only, never mixed into material severity ranking.
- Do not invent severity to look useful.

## Grounding

- Evidence: `path:line` and/or precise symbol in the change set (or justified minimal related read).
- Label **inference** when not direct from diff/tool output; keep confidence honest.
- No invented files, lines, or runtime behavior.

## Dig deeper (where diff touches)

Before finalizing: empty/null paths, retries/partial failure/idempotency, stale state/ordering, rollback/irreversible writes, **interface/contract breakage** (see [interface-impact.md](./interface-impact.md)).

## High-cost priority (touched only)

authz/trust · data loss/corruption · retry/idempotency · races · empty/timeout · schema/compat when contracts change · observability that would hide the above.

Not a full threat model — use `review-production` + practice packs for depth.

Security **high** needs exploit bar (attacker → action → impact); theoretical potential stays med/low.

## Output fields

| Field | Values / rule |
| --- | --- |
| Overall | `ship-as-is` \| `fix-first` \| `unclear` |
| Sev | `high` \| `med` \| `low` |
| Confidence | `high` \| `med` \| `low` |
| Table | Sev · Finding · Failure scenario · Evidence · Confidence · Recommended solution |
| Solutions subsection | Per material finding: **Recommended** (best practice + rationale) + **Alternatives** (1–2 with trade-offs) |
| Sort | material findings by severity (high first) |

Do **not** use `review-production` `go|go-with-risks|no-go` or Codex `approve|needs-attention` as this skill’s overall line.

## Review-only hard stop

After presenting findings: **STOP**. Do not auto-fix. Edit only if the user explicitly names findings or asks for tests/fixes. When offering fixes via `AskUserQuestion`, use **one** batch confirmation for all findings — never per-finding or per-axis.

## Target order

1. Explicit `pr-N`
2. Open PR for current branch
3. Dirty working tree (staged / unstaged / **untracked**)
4. Clean feature branch → `base...HEAD`
5. No change set on default branch → refuse unbounded review
