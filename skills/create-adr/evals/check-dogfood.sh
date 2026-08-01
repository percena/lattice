#!/usr/bin/env bash
# check-dogfood.sh — end-to-end smoke for the create-adr skill.
# Runs against a throwaway temp dir shaped like docs/adr/ so it does not
# mutate the real repo. Verifies: number allocator, atomic template claim,
# index-row append (idempotent).
set -euo pipefail
SKILL_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/docs/adr"
cat > "$TMP/docs/adr/README.md" <<'EOF'
# ADR

## Index

| ADR | Title | Status | Supersede / amend |
| --- | --- | --- | --- |
| [001](./001-foo.md) | Foo | Active | — |
EOF
touch "$TMP/docs/adr/001-foo.md"

echo "== next-adr-number =="
N=$(bash "$SKILL_ROOT/scripts/next-adr-number.sh" --home "$TMP/docs/adr")
echo "next: $N"
[[ "$N" == "002" ]] || { echo "FAIL: expected 002, got $N" >&2; exit 1; }

echo "== atomic template claim =="
ADR_FILE=$(bash "$SKILL_ROOT/scripts/claim-adr-file.sh" \
  --num "$N" --slug bar --template "$SKILL_ROOT/references/templates/adr.md" \
  --home "$TMP/docs/adr")
[[ -f "$ADR_FILE" ]] || { echo "FAIL: template not claimed" >&2; exit 1; }
grep -q '^# ADR NNN: Title' "$ADR_FILE" || { echo "FAIL: template shape wrong" >&2; exit 1; }

echo "== append index row =="
bash "$SKILL_ROOT/scripts/append-adr-index-row.sh" \
  --num "$N" --file "$ADR_FILE" --title "Bar" --status "Proposed" \
  --readme "$TMP/docs/adr/README.md"
grep -qE "^\| \[${N}\]\(" "$TMP/docs/adr/README.md" || { echo "FAIL: row not appended" >&2; exit 1; }

echo "== idempotent re-run =="
bash "$SKILL_ROOT/scripts/append-adr-index-row.sh" \
  --num "$N" --file "$ADR_FILE" --title "Bar" --status "Proposed" \
  --readme "$TMP/docs/adr/README.md"
[[ "$(grep -cE "^\| \[${N}\]\(" "$TMP/docs/adr/README.md")" -eq 1 ]] \
  || { echo "FAIL: row duplicated on re-run" >&2; exit 1; }

echo "dogfood: OK"
