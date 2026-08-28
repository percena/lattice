# tkt-167 reproduction evidence

## Mechanism proof (raw bash + bats 1.13.0)

```text
$ bash -c 'set -e; [[ a = b ]]; echo survived'   → survived (exit 0)
$ bash -c 'set -e; false; echo survived'          → (dies, exit 1)
```

bash `set -e` exempts `[[ ]]` (compound command) and `! cmd` (negation). In bats test bodies this makes mid-body `[[ ]]` / `! cmd` assertions decorative — only the body's last command gates the result. End-to-end proof during tkt-163: a regression test with mid-body `[[ ]]` assertions passed 3× against a demonstrably buggy script.

The new guard suite (`tools/tests/bats-assertion-ergonomics.bats`) re-proves both semantics live and flags a planted fixture carrying all three banned forms.

## Sweep

- Codemod (quote-verbatim glob→grep translation) over all 48 bats files; 4 multi-part ordered globs hand-converted (multi-line semantics preserved via `tr -d '\n'`); 2 pre-existing decorative lines made real.
- Sweep-scale at start: ~660 `[[ ]]` assertion lines + 62 `! cmd` lines.
- Post-sweep: 0 bare `[[ ]]` / bare `! cmd` / `grep -q`-in-`$()` forms remain (guard-enforced).

## Latent defect uncovered by the sweep

`wrappers.bats` "Codex-style flat install" compared the resolver output against the mktemp symlink spelling (`/var/…`) while the resolver prints the canonical path (`/private/var/…`). The `[[ ]]` assertion had never gated anything; making it effective exposed the mismatch. Assertion fixed to compare against `pwd -P`.

## Iteration honesty

Codemod v1 introduced two mistranslation classes (unquoted regex literals breaking bash parse; `grep -q` inside `$()` making negatives always-true) — caught because every suite was re-run per iteration (28 failures → v2 → 12 → v3 → 1 latent-assertion fix → 0). All 49 suites (incl. the new guard) green.
