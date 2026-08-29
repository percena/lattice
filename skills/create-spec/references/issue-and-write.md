# create-spec — issue number + write (detail)

Load when executing the team write path (after PREP/BATCH or already-locked COMMITTED).

## Adopt existing primary

If operator already has epic issue `#N` for this intent:

- **Reuse `#N`** as `spc-N`; **do not rewrite** title/body
- Soft-add `epic` + kind/priority if missing; optional one adopt comment
- Write Spec file only
- Still **≥1 separate delivery ticket** on Spec-then-ticket path
- Do not dual-role a delivery-only issue as Spec primary without explicit operator intent

## Team path (default)

GitHub issue number is team SoT for `spc-N`. Create (or choose) primary **before** writing the Spec file. Never guess `max(issue)+1` (Issue+PR share one sequence).

```bash
SKILL_ROOT="${LATTICE_SKILL_ROOT:-${CLAUDE_SKILL_DIR:-}}"
[[ "$SKILL_ROOT" = /* && -f "$SKILL_ROOT/SKILL.md" ]] || { echo "Error: resolve the active SKILL.md directory to absolute LATTICE_SKILL_ROOT" >&2; exit 1; }
RESOLVE="$SKILL_ROOT/../_lattice-lib/scripts/resolve-lattice-lib.sh"
[[ -f "$RESOLVE" ]] || { echo "Error: _lattice-lib is not installed beside $SKILL_ROOT" >&2; exit 1; }
LIB=$(bash "$RESOLVE")
# Primary = Spec intent tracker / GH parent only — not the delivery ticket.
# Always label epic so operators can filter Spec primaries. Include kind+priority.
ISSUE_URL=$(gh issue create \
  --title "Spec: <short title>" \
  --label "epic,feat,P2" \
  --body "Placeholder / primary tracker for this Spec. Contract lives in .lattice/specs/spc-N-….md. Delivery tickets are separate issues (GH sub-issues of this primary).")
N=$(printf '%s' "$ISSUE_URL" | grep -oE '[0-9]+$')
bash "$LIB/github-project-add.sh" "$ISSUE_URL" || true
# Fill references/templates/spec.md → $PH/specs/spc-${N}-<semantic-slug>.md
#   id: spc-${N}
# Later delivery issues are GH sub-issues of primary #N (create-tickets; soft-fail).
# Do not invent a second epic under the Spec primary.
# Do not dual-role this primary as the sole delivery ticket on Spec-then-ticket path.
```

## Offline / explicit local degrade only

Multi-clone unsafe — warn the user:

```bash
# NOT team SoT — prints a warning on stderr
N=$(bash "$LIB/next-artifact-id.sh" --kind spc --claim)
```

## Checklist before write

| Field / section | Required |
| --- | --- |
| `id`, `slug`, `title`, `kind`, `status`, `mode`, `summary` | yes |
| `priority` | recommended (default P2) |
| `tickets` / `prs` / `reviews` | yes (lists; often empty at create) |
| TL;DR + Path line | yes |
| Why / In / Out / Acceptance | yes |
| Decisions (principal) | yes when user confirmed axes |
| References (Review, ADR by **id**) | when known |

`status`: start `draft` unless principals already locked → then `locked` (do not multi-ticket off silent draft). Set `done` when delivery is complete. To **supersede** an existing Spec: write the new `spc-N`, then flip the old Spec's front matter (`status: superseded` + `superseded_by: spc-N` + `supersedes: [old]` on the new), and run the trip-time sweep so still-active child binders learn they are obsolete at supersede time, not land-time:

```bash
bash "$LIB/spec-supersede.sh" --spec "$PH/specs/spc-<old>-<slug>.md"
```

The sweep stamps queued / in-progress / deferred children to `deferred` + `wait_reason: spec-superseded` (one commit per binder); terminal (`closed`), side-state (`parked` / `stuck` / `rework`), `pr-open`, and legacy (`open`) children are skipped and surfaced in morning triage (spc-186 A3 / tkt-190). The Spec flip must precede the sweep — the script refuses a non-`superseded` Spec.

## Bloodline (L0 only)

Keep `tickets` / `prs` / `reviews` lists accurate on the Spec — bloodline is L0 + GitHub. No global BOARD index.
