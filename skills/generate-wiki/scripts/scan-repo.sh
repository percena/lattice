#!/usr/bin/env bash
# Single-pass repo scan for generate-wiki (optional helper).
# Prints a compact text report to stdout. No network. No writes.
set -euo pipefail
ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
cd "$ROOT"

echo "### root"
pwd
echo "### remote"
git remote get-url origin 2>/dev/null || echo "(none)"
echo "### branch"
echo "current=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"
echo "### top-level"
{ ls -1 || true; } | head -40
echo "### key-files (maxdepth 3)"
find . -maxdepth 3 -type f \( \
  -name 'README.md' -o -name 'package.json' -o -name 'pyproject.toml' \
  -o -name 'Cargo.toml' -o -name 'go.mod' -o -name 'Dockerfile' \
  -o -name 'SKILL.md' -o -name 'plugin.json' -o -name 'marketplace.json' \
  -o -name '*.yml' -o -name '*.yaml' -o -name 'CHANGELOG*' \
  -o -name 'CONTRIBUTING.md' -o -name 'LICENSE' \
\) ! -path './.git/*' ! -path './node_modules/*' ! -path './.lattice/*' 2>/dev/null | head -80 || true
echo "### skills"
ls -1 skills 2>/dev/null || echo "(none)"
echo "### plugins"
ls -1 plugins 2>/dev/null || echo "(none)"
echo "### docs"
{ ls -1 docs 2>/dev/null || echo "(none)"; } | head -30 || true
echo "### existing-wiki"
if [[ -d wiki ]]; then
  find wiki -type f | head -40 || true
  if [[ -f wiki/catalogue.json ]]; then echo "catalogue: present"; else echo "catalogue: missing"; fi
else
  echo "(none)"
fi
echo "### root-llms"
if [[ -f llms.txt ]]; then
  head -5 llms.txt
  if grep -q 'generated_by: generate-wiki\|generate-wiki' llms.txt 2>/dev/null; then
    echo "stamp: skill-or-mentioned"
  else
    echo "stamp: unknown-hand"
  fi
else
  echo "(none)"
fi
echo "### source-file-count-approx"
find . -type f \( \
  -name '*.ts' -o -name '*.tsx' -o -name '*.js' -o -name '*.jsx' \
  -o -name '*.mjs' -o -name '*.cjs' -o -name '*.py' -o -name '*.go' \
  -o -name '*.rs' -o -name '*.sh' -o -name '*.java' -o -name '*.kt' \
  -o -name '*.c' -o -name '*.cc' -o -name '*.cpp' -o -name '*.h' \
  -o -name '*.hpp' -o -name '*.cs' -o -name '*.rb' -o -name '*.php' \
  -o -name '*.swift' -o -name '*.vue' -o -name '*.svelte' \
\) \
  ! -path './.git/*' ! -path './node_modules/*' ! -path './.lattice/*' ! -path './wiki/*' 2>/dev/null | wc -l | awk '{print $1}'
echo "### markdown-file-count-approx"
find . -type f -name '*.md' \
  ! -path './.git/*' ! -path './node_modules/*' ! -path './.lattice/*' ! -path './wiki/*' 2>/dev/null | wc -l | awk '{print $1}'
