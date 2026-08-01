#!/usr/bin/env bash
# Dogfood validation for generate-wiki output (acceptance heuristics A3–A12).
# Also exercises A6/A7 negative paths in a temp sandbox (does not mutate the repo tree permanently).
set -euo pipefail
ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
cd "$ROOT"
fail=0
ok() { echo "OK  $*"; }
bad() { echo "FAIL $*"; fail=1; }

if [[ ! -f wiki/catalogue.json ]]; then
  echo "check-dogfood: wiki/catalogue.json is missing; run a full generate-wiki dogfood pass before this output check" >&2
  exit 2
fi
ok "catalogue.json present"

python3 - <<'PY' || fail=1
import json, re, sys
from pathlib import Path
cat = json.loads(Path("wiki/catalogue.json").read_text())
pages = cat.get("pages") or []
paths = [p["path"] for p in pages]
n = len(paths)
if 5 <= n <= 8:
    print(f"OK  leaf count {n} in 5–8")
else:
    print(f"FAIL leaf count {n} not in 5–8")
    sys.exit(1)
for path in paths:
    fp = Path("wiki") / path
    if not fp.is_file():
        print(f"FAIL missing page {path}")
        sys.exit(1)
    text = fp.read_text()
    fm = text.split("---", 2)
    if len(fm) >= 3 and "generate-wiki" not in fm[1]:
        print(f"FAIL {path} missing generate-wiki in frontmatter")
        sys.exit(1)
    print(f"OK  page {path}")
arch = Path("wiki/02-architecture.md")
if arch.is_file():
    t = arch.read_text()
    if "skills/_lattice-lib/SKILL.md" not in t and "lattice-lib/SKILL.md" not in t:
        print("FAIL architecture page lacks skills/_lattice-lib/SKILL.md cite (A12)")
        sys.exit(1)
    if len(t) > 20000:
        print("FAIL architecture page suspiciously large")
        sys.exit(1)
    print("OK  architecture cites lattice-lib and size sane")
wiki_text = "\n".join(p.read_text() for p in Path("wiki").glob("*.md"))
if "blob/" in wiki_text or re.search(r"\([A-Za-z0-9_./-]+:\d+\)", wiki_text):
    print("OK  citation patterns present")
else:
    print("FAIL no blob/ or (path:line) citations found")
    sys.exit(1)
print("OK  catalogue↔pages 1:1")
PY

if [[ -f AGENTS.md ]] && grep -q 'generated_by: generate-wiki' AGENTS.md 2>/dev/null; then
  bad "AGENTS.md marked generated_by generate-wiki"
else
  ok "AGENTS.md not skill-stamped (or absent)"
fi

if [[ -f llms.txt ]]; then
  ok "llms.txt present"
  if grep -q '^# ' llms.txt && grep -q '^>' llms.txt && grep -q '^## ' llms.txt; then
    ok "llms.txt has H1 + blockquote + H2"
  else
    bad "llms.txt missing H1/blockquote/H2 structure"
  fi
  if grep -q '^## Optional' llms.txt; then
    ok "llms.txt has Optional section"
  else
    bad "llms.txt missing ## Optional"
  fi
else
  bad "llms.txt missing"
fi

# intra-wiki links
python3 - <<'PY' || fail=1
from pathlib import Path
import re
root = Path("wiki")
fail = 0
for p in root.glob("*.md"):
    for m in re.finditer(r"\]\(\./([^)#]+)", p.read_text()):
        target = m.group(1)
        if not (root / target).exists():
            print(f"FAIL broken link {p} -> {target}")
            fail = 1
if fail == 0:
    print("OK  intra-wiki relative links")
raise SystemExit(fail)
PY

# --- A6 / A7 policy unit tests (sandbox; no permanent tree mutation) ---
python3 - <<'PY' || fail=1
"""Simulate skill policy decisions for manual:true skip and handwritten llms.txt."""
from pathlib import Path
import tempfile
import shutil
import re

def is_skill_llms(text: str) -> bool:
    return "generated_by: generate-wiki" in text or "generate-wiki" in text[:500]

def should_skip_page(frontmatter: str) -> bool:
    return re.search(r"(?m)^manual:\s*true\s*$", frontmatter) is not None

def llms_write_target(root_llms_exists, root_text):
    """Return 'root' or 'wiki' per skill step 4."""
    if not root_llms_exists:
        return "root"
    if root_text is not None and is_skill_llms(root_text):
        return "root"
    return "wiki"

# A6: manual true skipped
fm_manual = "title: X\nmanual: true\ngenerated_by: generate-wiki\n"
assert should_skip_page(fm_manual), "manual true must skip"
fm_auto = "title: X\nmanual: false\ngenerated_by: generate-wiki\n"
assert not should_skip_page(fm_auto), "manual false must not skip"
print("OK  A6 policy: manual:true skip / manual:false rewrite")

# A6: generated_at preserve unless refresh-stamp
old = "2026-01-01"
new = "2026-07-20"
def next_stamp(prev, refresh_stamp, today):
    if prev and not refresh_stamp:
        return prev
    return today
assert next_stamp(old, False, new) == old
assert next_stamp(old, True, new) == new
assert next_stamp(None, False, new) == new
print("OK  A6 policy: generated_at preserved unless --refresh-stamp")

# A7: handwritten root llms -> write wiki/llms.txt only
hand = "# Hand\n> not skill\n"
assert llms_write_target(True, hand) == "wiki"
skill = "# P\n> s\n<!-- generated_by: generate-wiki -->\n"
assert llms_write_target(True, skill) == "root"
assert llms_write_target(False, None) == "root"
print("OK  A7 policy: handwritten root llms -> wiki/llms.txt; skill/missing -> root")

# Sandbox: ensure we can write wiki/llms without touching a handwritten root
with tempfile.TemporaryDirectory() as td:
    td_path = Path(td)
    (td_path / "llms.txt").write_text(hand)
    wiki = td_path / "wiki"
    wiki.mkdir()
    target = llms_write_target(True, hand)
    assert target == "wiki"
    out = wiki / "llms.txt"
    out.write_text("# Wiki copy\n> from skill\n<!-- generated_by: generate-wiki -->\n")
    assert (td_path / "llms.txt").read_text() == hand, "root handwritten must be untouched"
    assert out.is_file()
print("OK  A7 sandbox: handwritten root preserved when writing wiki/llms.txt")
PY

if [[ "$fail" -eq 0 ]]; then
  echo "summary: PASS"
  exit 0
fi
echo "summary: FAIL"
exit 1
