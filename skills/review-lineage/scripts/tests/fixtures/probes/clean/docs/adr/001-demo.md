# ADR-001: demo

## Decision

Demo.

## Consequences

- **Verification:** `bash tools/validate-lattice-artifacts.py --strict` passes;
  `demo-hook.sh` is wired in `hooks.json`; `grep -n demo docs/` finds this line.
  - `skills/demo/scripts/demo.sh` prints hello.

## Status history

- 2026-09-02: Proposed
