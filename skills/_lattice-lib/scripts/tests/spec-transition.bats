#!/usr/bin/env bats
# spec-transition.bats — guarded Spec locked→done / locked→superseded (tkt-473 /
# spc-475 A21–A25). Mirrors the transition-api.bats + spec-supersede.bats
# fixture style: a tmp git repo + LATTICE_HOME.
#
# Assertion idiom (tkt-460): use `[ ]` / `grep -qF`, never a bare `[[ ]]`
# assertion (it is exempt from `set -e`).

setup_file() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../../.." && pwd)"
  export REPO_ROOT
  export ST="$REPO_ROOT/skills/_lattice-lib/scripts/spec-transition.py"
  export CLOSE="$REPO_ROOT/skills/finish-work/scripts/close-spec-primary.sh"
  export VAL="$REPO_ROOT/tools/validate-lattice-artifacts.py"
}

setup() {
  REPO="$(mktemp -d)"
  export REPO
  cd "$REPO"
  git init -q
  git config user.email t@t
  git config user.name t
  export LATTICE_HOME="$REPO/.lattice"
  mkdir -p .lattice/specs .lattice/tickets .lattice/.transition-ledger
}

teardown() { [ -n "${REPO:-}" ] && rm -rf "$REPO"; }

# Fixture: a locked Spec spc-1 with one closed child tkt-1 (PR pr-5 merged).
write_spec() {
  cat > .lattice/specs/spc-1-demo.md <<EOF
---
id: spc-1
slug: demo
title: Demo
kind: feat
status: locked
mode: C
priority: P1
summary: demo
created: 2026-09-04
updated: 2026-09-04
tickets: [tkt-1]
prs: [${PRS:-pr-5}]
reviews: []
supersedes: []
superseded_by: null
---

# Demo

> **Kind:** feat · **Status:** locked · **Mode:** C · **Priority:** P1

## Acceptance
- [x] **A1** child closed
${A2_LINE:-- [x] **A2** second item}
EOF
}

write_child() {
  mkdir -p .lattice/tickets/tkt-1-child
  cat > .lattice/tickets/tkt-1-child/README.md <<'EOF'
# tkt-1-child

| Field | Value |
| --- | --- |
| kind | feat |
| status | closed |
| spec | spc-1 — demo (path: ../../specs/spc-1-demo.md) |
| prs | pr-5 — https://x/pull/5 |

## Finish
- pr-5 merged: 2026-09-05T04:00:00Z — https://x/pull/5
- issue #1 closed: 2026-09-05T04:01:00Z — https://x/issues/1
EOF
}

commit_all() { git add -A && git commit -qm fixture; }

@test "legal: locked->done and locked->superseded are legal; draft->locked is not" {
  run python3 "$ST" legal locked done
  [ "$status" -eq 0 ]
  run python3 "$ST" legal locked superseded
  [ "$status" -eq 0 ]
  run python3 "$ST" legal draft locked
  [ "$status" -eq 1 ]
}

@test "A23: happy-path done flips status, bumps updated, writes a ledger entry" {
  write_child; PRS=pr-5 write_spec; commit_all
  run python3 "$ST" done spc-1 claude \
    --soak-evidence-ref pr-5 --soak-attestation-ts 2026-09-05T05:00:00Z
  [ "$status" -eq 0 ]
  grep -q '^status: done' .lattice/specs/spc-1-demo.md
  grep -q '^updated: 2026-09-' .lattice/specs/spc-1-demo.md
  [ -f .lattice/.transition-ledger/spc-1.jsonl ]
  grep -q '"from":"locked"' .lattice/.transition-ledger/spc-1.jsonl
  grep -q '"to":"done"' .lattice/.transition-ledger/spc-1.jsonl
  grep -q '"soak_evidence_ref":"pr-5"' .lattice/.transition-ledger/spc-1.jsonl
}

@test "A21: an open (non-closed) child refuses done without mutation" {
  write_child; PRS=pr-5 write_spec; commit_all
  sed -i.bak 's/| status | closed |/| status | queued |/' .lattice/tickets/tkt-1-child/README.md
  rm -f .lattice/tickets/tkt-1-child/README.md.bak
  run python3 "$ST" done spc-1 claude \
    --soak-evidence-ref pr-5 --soak-attestation-ts 2026-09-05T05:00:00Z
  [ "$status" -eq 1 ]
  grep -qF 'not `closed`' <<<"$output"
  grep -q '^status: locked' .lattice/specs/spc-1-demo.md
  [ ! -f .lattice/.transition-ledger/spc-1.jsonl ]
}

@test "A21: a missing/extra PR refuses done (exact equality both directions)" {
  write_child; PRS=pr-9 write_spec; commit_all
  run python3 "$ST" done spc-1 claude \
    --soak-evidence-ref pr-5 --soak-attestation-ts 2026-09-05T05:00:00Z
  [ "$status" -eq 1 ]
  grep -qF 'PR-set mismatch' <<<"$output"
  grep -q '^status: locked' .lattice/specs/spc-1-demo.md
}

@test "A21: an open Acceptance item refuses done" {
  A2_LINE="- [ ] **A2** still open"; PRS=pr-5; write_child; write_spec; commit_all
  run python3 "$ST" done spc-1 claude \
    --soak-evidence-ref pr-5 --soak-attestation-ts 2026-09-05T05:00:00Z
  [ "$status" -eq 1 ]
  grep -qF 'open non-deferred' <<<"$output"
}

@test "A21: an omitted historical child (backref not in tickets) refuses done" {
  write_child; PRS=pr-5 write_spec; commit_all
  mkdir -p .lattice/tickets/tkt-2-orphan
  cat > .lattice/tickets/tkt-2-orphan/README.md <<'EOF'
# tkt-2-orphan
| Field | Value |
| --- | --- |
| kind | feat |
| status | closed |
| spec | spc-1 — demo (path: ../../specs/spc-1-demo.md) |
| prs | pr-5 — https://x/pull/5 |
EOF
  git add -A && git commit -qm orphan
  run python3 "$ST" done spc-1 claude \
    --soak-evidence-ref pr-5 --soak-attestation-ts 2026-09-05T05:00:00Z
  [ "$status" -eq 1 ]
  grep -qF 'omitted historical child' <<<"$output"
}

@test "A22: missing soak evidence ref refuses done" {
  write_child; PRS=pr-5 write_spec; commit_all
  run python3 "$ST" done spc-1 claude --soak-attestation-ts 2026-09-05T05:00:00Z
  [ "$status" -eq 1 ]
  grep -qF -e '--soak-evidence-ref' <<<"$output"
}

@test "A22: attestation ts not later than the last child merge refuses done" {
  write_child; PRS=pr-5 write_spec; commit_all
  run python3 "$ST" done spc-1 claude \
    --soak-evidence-ref pr-5 --soak-attestation-ts 2026-09-05T03:00:00Z
  [ "$status" -eq 1 ]
  grep -qF 'not later than the last child merge' <<<"$output"
}

@test "A23: idempotent duplicate operation-id is a success no-op" {
  write_child; PRS=pr-5 write_spec; commit_all
  OPID="$(python3 -c 'import uuid;print(uuid.uuid4())')"
  run python3 "$ST" done spc-1 claude --soak-evidence-ref pr-5 \
    --soak-attestation-ts 2026-09-05T05:00:00Z --operation-id "$OPID"
  [ "$status" -eq 0 ]
  run python3 "$ST" done spc-1 claude --soak-evidence-ref pr-5 \
    --soak-attestation-ts 2026-09-05T05:00:00Z --operation-id "$OPID"
  [ "$status" -eq 0 ]
  grep -qF 'idempotent' <<<"$output"
  [ "$(grep -c '"operation_id"' .lattice/.transition-ledger/spc-1.jsonl)" -eq 1 ]
}

@test "A23: expected-revision mismatch refuses before mutation" {
  write_child; PRS=pr-5 write_spec; commit_all
  run python3 "$ST" done spc-1 claude --soak-evidence-ref pr-5 \
    --soak-attestation-ts 2026-09-05T05:00:00Z --expected-rev 9
  [ "$status" -eq 3 ]
  grep -qF 'expected-revision mismatch' <<<"$output"
  grep -q '^status: locked' .lattice/specs/spc-1-demo.md
}

@test "A23: W2 crash recovery completes an interrupted rename" {
  write_child; PRS=pr-5 write_spec; commit_all
  OPID="deadbeef-0000-0000-0000-00000000face"
  cp .lattice/specs/spc-1-demo.md ".lattice/specs/.spec-transition.${OPID}.tmp"
  sed -i.bak 's/^status: locked/status: done/' ".lattice/specs/.spec-transition.${OPID}.tmp"
  rm -f ".lattice/specs/.spec-transition.${OPID}.tmp.bak"
  printf '{"ts":"2026-09-05T05:00:00Z","spec":"spc-1","ticket":"spc-1","from":"locked","to":"done","owner":"claude","reason":"sim","guard":"g","operation_id":"%s","soak_evidence_ref":"pr-5","soak_attestation_ts":"2026-09-05T05:00:00Z"}\n' "$OPID" \
    > .lattice/.transition-ledger/spc-1.jsonl
  git add -A && git commit -qm crash-state
  run python3 "$ST" done spc-1 claude --soak-evidence-ref pr-5 \
    --soak-attestation-ts 2026-09-05T05:00:00Z --dry-run
  grep -q '^status: done' .lattice/specs/spc-1-demo.md
  [ ! -f ".lattice/specs/.spec-transition.${OPID}.tmp" ]
}

@test "A23: superseded flips status, sets superseded_by, writes ledger (no-sweep)" {
  write_child; PRS=pr-5 write_spec; commit_all
  cat > .lattice/specs/spc-2-new.md <<'EOF'
---
id: spc-2
slug: new
title: New
kind: feat
status: locked
mode: C
priority: P1
summary: new
created: 2026-09-05
updated: 2026-09-05
tickets: []
prs: []
reviews: []
supersedes: []
superseded_by: null
---
# New
EOF
  git add -A && git commit -qm second
  run python3 "$ST" superseded spc-1 spc-2 claude --no-sweep
  [ "$status" -eq 0 ]
  grep -q '^status: superseded' .lattice/specs/spc-1-demo.md
  grep -q '^superseded_by: spc-2' .lattice/specs/spc-1-demo.md
  grep -q '"to":"superseded"' .lattice/.transition-ledger/spc-1.jsonl
}

@test "A23: supersede into a fictional Spec refuses" {
  write_child; PRS=pr-5 write_spec; commit_all
  run python3 "$ST" superseded spc-1 spc-999 claude --no-sweep
  [ "$status" -eq 1 ]
  grep -qF 'does not resolve to a tracked Spec' <<<"$output"
}

@test "A24: validator flags a hand-edited done Spec with no ledger (spec_terminal_without_ledger)" {
  write_child; PRS=pr-5 write_spec; commit_all
  sed -i.bak 's/^status: locked/status: done/' .lattice/specs/spc-1-demo.md
  rm -f .lattice/specs/spc-1-demo.md.bak
  git add -A && git commit -qm hand-edit
  run python3 "$VAL" --home "$LATTICE_HOME" --json
  printf '%s' "$output" | tr -d '\n' | grep -qF '"code": "spec_terminal_without_ledger"'
}

@test "A24: a done Spec WITH a valid ledger is clean (no spec_terminal finding)" {
  write_child; PRS=pr-5 write_spec; commit_all
  python3 "$ST" done spc-1 claude --soak-evidence-ref pr-5 \
    --soak-attestation-ts 2026-09-05T05:00:00Z
  run python3 "$VAL" --home "$LATTICE_HOME" --json
  found="$(printf '%s' "$output" | tr -d '\n' | grep -F '"code": "spec_terminal_without_ledger"' || true)"
  [ -z "$found" ]
}

@test "A25: close-spec-primary refuses to close the epic when the transition fails" {
  write_child; PRS=pr-5 write_spec; commit_all
  sed -i.bak 's/^prs: \[pr-5\]/prs: [pr-9]/' .lattice/specs/spc-1-demo.md
  rm -f .lattice/specs/spc-1-demo.md.bak
  git add -A && git commit -qm mismatch
  mkdir -p bin
  printf '#!/usr/bin/env bash\necho "GH-CALLED: $*" >> "$REPO/gh-calls.log"\n' > bin/gh
  chmod +x bin/gh
  PATH="$REPO/bin:$PATH" run "$CLOSE" --primary 999 --soak-evidence-ref pr-5 --id spc-1 --home "$LATTICE_HOME"
  [ "$status" -eq 1 ]
  grep -qF 'REFUSED' <<<"$output"
  grep -qF 'NOT closed (A25)' <<<"$output"
  [ ! -f gh-calls.log ]
  grep -q '^status: locked' .lattice/specs/spc-1-demo.md
}

@test "tkt-486: done syncs the TL;DR **Status:** display (no spec_header_status_mismatch)" {
  write_child; PRS=pr-5 write_spec; commit_all
  # pre-fix: TL;DR says locked
  grep -qF '**Status:** locked' .lattice/specs/spc-1-demo.md
  run python3 "$ST" done spc-1 claude --soak-evidence-ref pr-5 \
    --soak-attestation-ts 2026-09-05T05:00:00Z
  [ "$status" -eq 0 ]
  grep -qF '**Status:** done' .lattice/specs/spc-1-demo.md
  run python3 "$VAL" --home "$LATTICE_HOME" --json
  mismatch="$(printf '%s' "$output" | tr -d '\n' | grep -F '"code": "spec_header_status_mismatch"' || true)"
  [ -z "$mismatch" ]
}

@test "tkt-486: superseded syncs the TL;DR **Status:** display to superseded" {
  write_child; PRS=pr-5 write_spec; commit_all
  cat > .lattice/specs/spc-2-new.md <<'EOF'
---
id: spc-2
slug: new
title: New
kind: feat
status: locked
mode: C
priority: P1
summary: new
created: 2026-09-05
updated: 2026-09-05
tickets: []
prs: []
reviews: []
supersedes: []
superseded_by: null
---
# New
EOF
  git add -A && git commit -qm second
  run python3 "$ST" superseded spc-1 spc-2 claude --no-sweep
  [ "$status" -eq 0 ]
  grep -qF '**Status:** superseded' .lattice/specs/spc-1-demo.md
}

@test "A25: close-spec-primary flips the Spec + closes the epic on a clean transition" {
  write_child; PRS=pr-5 write_spec; commit_all
  mkdir -p bin
  printf '#!/usr/bin/env bash\necho "GH-CLOSE: $*" >> "$REPO/gh-calls.log"\n' > bin/gh
  chmod +x bin/gh
  PATH="$REPO/bin:$PATH" run "$CLOSE" --primary 999 --soak-evidence-ref pr-5 --id spc-1 \
    --home "$LATTICE_HOME" --owner claude
  [ "$status" -eq 0 ]
  grep -q '^status: done' .lattice/specs/spc-1-demo.md
  [ -f .lattice/.transition-ledger/spc-1.jsonl ]
  grep -qF 'GH-CLOSE: issue close 999' gh-calls.log
}
