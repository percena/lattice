# Claim probes registry (spc-369 A2 — L2 sensor)

Executable claim–implementation probes for `scripts/claim-probes.sh`. Each row
turns a **documented promise** into a command and an expectation, so the
promise is *executed* against the tree instead of re-read (create-review
`audit-recipe.md` §3 enforcement-coverage axis, §4 claim–implementation
reconciliation). The seed rows are the drift classes `rev-20260902-015425Z`
F4/F5 and the tkt-338..342 PR reviews found by hand; every built-in has a
planted-drift bats case and a clean-fixture pass (`scripts/tests/claim-probes.bats`).

## Columns

| Column | Meaning |
| --- | --- |
| `id` | Stable probe id (`[a-z0-9._-]`); the overlay merges on it |
| `claim (where)` | The promise being executed, with the doc / law it comes from |
| `probe` | A bash one-liner run with `cwd = REPO_ROOT` and `REPO_ROOT`, `LATTICE_HOME`, `PROBE_ID`, `REGISTRY_DIR` (this file's directory) exported. Pipes are written `\|` (Markdown cell escape); the runner unescapes them. Exit **3** = `skip` (prerequisite absent; stdout is the reason). For `regex`/`empty` the probe must exit 0 — any other non-zero exit is a `fail`, so a crashed probe never passes |
| `expect` | `exit0` (probe exit status 0) · `regex:<pattern>` (stdout must match, multiline) · `empty` (stdout must be empty — each stdout line is one drift instance) |
| `severity` | `high` · `med` · `low` — reporting weight only; the runner always exits 0 |

Rows the parser cannot read (wrong cell count, unknown `expect`/`severity`,
bad regex) are reported as `skip` with the reason — never silently dropped
(spc-369 Risks: noisy probes are demoted to `skip`, not deleted).

## Per-repo overlay

`<LATTICE_HOME>/lineage-probes.tsv` (optional; `--overlay <file>` overrides the
path): `id<TAB>claim<TAB>probe<TAB>expect<TAB>severity`, `#` comments and blank
lines ignored, **no** pipe escaping; `id`/`probe`/`expect`/`severity` cells may be
wrapped in backticks like the registry's (unwrapped before use). An unreadable
overlay (missing file, bad bytes) is reported as a `claim-probes: overlay
unreadable: … (ignored)` line and skipped — the runner still exits 0. Merged by `id` — an overlay row **replaces**
the registry row with the same id (use it to re-scope or demote a noisy probe);
new ids are appended. Consumers add their own promises there without editing
this file.

## Registry

| id | claim (where) | probe | expect | severity |
| --- | --- | --- | --- | --- |
| `skill-scripts-exist` | Every `scripts/<name>.sh\|.py` a `skills/*/SKILL.md` names resolves under that skill (or the sibling skill named before `scripts/`, e.g. `_lattice-lib/scripts/…`) and is executable (`skill-anatomy.md` rule 1; rev-20260902-015425Z F4 prose:script drift) | `[ -d skills ] \|\| { echo "skip: no skills/ dir"; exit 3; }; for f in skills/*/SKILL.md; do d=${f%/SKILL.md}; grep -oE '([A-Za-z0-9_-]+/)?scripts/[A-Za-z0-9_.-]+\.(sh\|py)' "$f" \| sort -u \| while read -r p; do case "$p" in */scripts/*) s=${p%%/*}; if [ -d "skills/$s" ]; then t="skills/$s/scripts/${p##*/scripts/}"; else t="$d/scripts/${p##*/scripts/}"; fi;; *) t="$d/$p";; esac; [ -x "$t" ] \|\| echo "$f names $p -> $t (missing or not executable)"; done; done` | `empty` | high |
| `hooks-json-files-exist` | Every `hooks/*.sh` command in `plugins/lattice/hooks/hooks.json` exists and is executable (ADR-006 Verification: "L1/L3 hooks live in plugins/lattice/hooks/ + hooks.json") | `h=plugins/lattice/hooks/hooks.json; [ -f "$h" ] \|\| { echo "skip: no $h"; exit 3; }; grep -oE 'hooks/[A-Za-z0-9_.-]+\.sh' "$h" \| sort -u \| while read -r p; do [ -x "plugins/lattice/$p" ] \|\| echo "$h names $p (missing or not executable)"; done` | `empty` | high |
| `validator-codes-cited-exist` | A backticked `snake_case` token with >= 2 underscores on a `docs/**/*.md` or `skills/**/*.md` line that also mentions `validate-lattice-artifacts` or `validator` (test fixture trees excluded: `--exclude-dir=fixtures`) is a finding-code citation and must be a `"code": "…"` the validator emits (audit-recipe §4: docs promising validator behaviour) | `v=tools/validate-lattice-artifacts.py; [ -f "$v" ] \|\| { echo "skip: no $v"; exit 3; }; codes=$(grep -oE '"code": "[a-z0-9_]+"' "$v" \| sed 's/"code": "//; s/"$//' \| sort -u); grep -rhE 'validate-lattice-artifacts\|[Vv]alidator' docs skills --include='*.md' --exclude-dir=fixtures 2>/dev/null \| grep -oE '`[a-z]+(_[a-z0-9]+){2,}`' \| tr -d '`' \| sort -u \| while read -r c; do grep -qxF "$c" <<<"$codes" \|\| echo "cited code $c is not emitted by $v"; done` | `empty` | med |
| `retired-paths-absent` | No `skills/**/*.md` or `docs/**/*.md` line (test fixture trees excluded: `--exclude-dir=fixtures`) contains a retired phrase from `retired-paths.txt` (fixed-string deny-list: a phrase per line, optional TAB-separated scope dirs; `#` comments) — the drift classes rev-20260902-015425Z F4 + tkt-338..342 reviews found by hand | `d="$REGISTRY_DIR/retired-paths.txt"; [ -f "$d" ] \|\| { echo "skip: no retired-paths.txt beside the registry"; exit 3; }; while IFS=$'\t' read -r pat scope; do case "$pat" in ''\|'#'*) continue;; esac; grep -rnF --include='*.md' --exclude-dir=fixtures -- "$pat" ${scope:-skills docs} 2>/dev/null \| head -5; done <"$d"` | `empty` | med |
| `adr-verification-refs-resolve` | Every backticked file reference (`*.sh`, `*.py`, `*.bats`, `*.md`, `*.json`, `*.yml`; first word, `bash`/`python3`/`sh` prefix stripped) inside a `docs/adr/*.md` `**Verification:**` bullet (plus its indented continuation lines) resolves: paths with `/` by exact path or path suffix, bare names by basename | `[ -d docs/adr ] \|\| { echo "skip: no docs/adr"; exit 3; }; for f in docs/adr/*.md; do awk '/^- \*\*Verification:?\*\*\|^Verification:/{on=1; print; next} on && (/^[^ \t]/ \|\| /^$/){on=0} on{print}' "$f" \| grep -oE '`[^`]+`' \| tr -d '`' \| sed -E 's/^(bash\|python3\|sh) //' \| awk '{print $1}' \| grep -E '\.(sh\|py\|bats\|md\|json\|ya?ml)$' \| sort -u \| while read -r p; do case "$p" in */*) [ -e "$p" ] \|\| [ -n "$(find . -name .git -prune -o -path "*/$p" -print 2>/dev/null \| head -1)" ] \|\| echo "$f cites $p (unresolved)";; *) [ -n "$(find . -name .git -prune -o -name "$p" -print 2>/dev/null \| head -1)" ] \|\| echo "$f cites $p (unresolved)";; esac; done; done` | `empty` | med |
| `spec-done-acceptance-cites-evidence` | **Opt-in** (`LATTICE_PROBE_STRICT_EVIDENCE=1`): in every `status: done` Spec under `<home>/specs/`, each checked `- [x] **A<n>**` item (bullet + indented continuation lines, case-insensitive) mentions `bats`, `test`, `ci`, or a `pr-<N>` / `tkt-<N>` id — else the A<n> ids are listed. Stricter than the current Spec convention (evidence conventionally lives in binders / PR bodies, not on the Spec line), so it is gated off by default to avoid false-noise in the digest (tkt-412; rev-20260902-015425Z F6: `done` is self-reported; ADR-007 §3 decidability). Set the flag to run the strict audit on demand. | `[ -d "$LATTICE_HOME/specs" ] \|\| { echo "skip: no specs dir under $LATTICE_HOME"; exit 3; }; [ "${LATTICE_PROBE_STRICT_EVIDENCE:-0}" = "1" ] \|\| { echo "skip: opt-in — Spec evidence lives in binders/PRs by convention (tkt-412); set LATTICE_PROBE_STRICT_EVIDENCE=1 to run"; exit 3; }; for f in "$LATTICE_HOME"/specs/*.md; do [ -f "$f" ] \|\| continue; grep -qE '^status: done' "$f" \|\| continue; awk -v n="$(basename "$f")" 'function flush(){ if (cur != "") { l=tolower(cur); if (l !~ /bats\|test\|(^\|[^a-z])ci([^a-z]\|$)\|pr-[0-9]+\|tkt-[0-9]+/) { match(cur, /\*\*A[0-9]+/); ids=ids (ids==""?"":" ") substr(cur, RSTART+2, RLENGTH-2) } } cur="" } /^- \[x\] \*\*A[0-9]+/{flush(); cur=$0; next} /^[ \t]+[^ \t]/ && cur != "" {cur=cur " " $0; next} {flush()} END{flush(); if (ids != "") print n ": " ids " — no test/PR/ticket evidence cited"}' "$f"; done` | `empty` | low |
| `fsm-doc-edges-subset-of-schema` | Every `from → to` status pair in the `docs/workflow-fsm.md` `### M2 execution` table (same extraction rule as `tools/tests/transition-parity.bats` `docs_m2_status_pairs`: rows whose target is a schema status word) is a `transition_table.LEGAL_EDGES` edge (spc-254 A4 / D2; spc-369 D5 no second edge table) | `d=docs/workflow-fsm.md; t=skills/_lattice-lib/scripts/lib/transition_table.py; { [ -f "$d" ] && [ -f "$t" ]; } \|\| { echo "skip: no $d or $t"; exit 3; }; PYTHONPATH="$(dirname "$t")" python3 -c 'import re, transition_table as t; doc = open("docs/workflow-fsm.md", encoding="utf-8").read(); m = re.search(r"(?ms)^### M2 execution\s*\n(.*?)(?=^### )", doc); body = m.group(1) if m else ""; legal = {(e.from_, e.to) for e in t.LEGAL_EDGES}; words = {w for e in t.LEGAL_EDGES for w in (e.from_, e.to)} - {"any", "init"}; rows = [re.match(r"\\|\s*([^\|]+?)\s*→\s*([^\|]+?)\s*\\|", l) for l in body.splitlines()]; pairs = [(r.group(1).strip(), re.sub(r"\(.*$", "", r.group(2)).strip()) for r in rows if r]; [print(f"docs M2 edge {a} -> {b} is not in transition_table.LEGAL_EDGES") for a, b in pairs if b in words and (a, b) not in legal]'` | `empty` | high |

## Adding a probe

1. State the claim with its source (doc line, ADR §, Spec A*) — a probe without
   a citable promise is a lint, not a claim probe.
2. Prefer `empty` with one stdout line per drift instance (the evidence column
   shows the first 200 chars); use `exit 3` for an absent prerequisite.
3. Land it with a planted-drift fixture under `scripts/tests/fixtures/probes/`
   that fails exactly this probe, plus a `clean/` pass (spc-369 Risks: probe
   false positives teach agents to ignore the report).
