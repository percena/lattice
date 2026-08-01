# Lattice skill evals (engine monorepo)

| Tier | What | Command | CI |
| --- | --- | --- | --- |
| **1 Structural** | Frontmatter, anatomy sections, lifecycle `evals.json` presence, **Codex cross-agent invariants** (`metadata.agents` lists `codex`; no `CLAUDE_PLUGIN_ROOT` in shared bodies/refs/scripts) | `bash tools/validate-skills.sh` | yes |
| **2 Routing** | Multilingual lexical metadata ranking + description collision for all user-facing skills | `python3 tools/run-routing-evals.py` | yes (`--min-rank1 80`) |
| **3 Behavioral** | Isolated per-skill cases, machine assertions, and no-skill/previous-skill comparison | `python3 tools/run-behavioral-evals.py …` | corpus + fake-provider **protocol smoke** in CI; live models are capability evidence |

**Codex scope honesty:** Tier-1 now machine-checks the *structural* half of the `claude-code,codex` claim — every user-facing skill (and `_lattice-lib`) declares `codex` in `metadata.agents`, and no shared body/reference/script hardcodes `CLAUDE_PLUGIN_ROOT` (Codex has no plugin root). A Codex-style flat install (no git, sibling `_lattice-lib`) is smoke-tested for `resolve-lattice-lib.sh` in `skills/_lattice-lib/scripts/tests/wrappers.bats`. This does **not** run a live Codex model — behavioral parity across agents stays capability evidence, like Tier-3.

Tier-2 includes the lifecycle six plus `review-code`, `review-production`, and `generate-wiki`. CJK tokenization and aliases exercise natural Chinese requests, including the ambiguous boundary between PR code review and a durable Lattice Review. This deterministic lane catches catalog collisions; it does **not** claim to reproduce a live model router.

## Routing cases

One file per routed user-facing skill: `evals/routing/<skill>.json`.

```json
{
  "skill_name": "start-work",
  "trigger": {
    "positive": [{ "prompt": "…", "top_k": 3 }],
    "negative": [{ "prompt": "…", "owner": "create-pr" }]
  }
}
```

- **positive:** realistic user asks that should rank this skill (prefer rank-1; `top_k` soft gate).
- **negative:** belongs to another skill; this skill must not rank first; when `owner` is set, owner must outrank this skill.

**Floor:** CI uses `--min-rank1 80` (ratcheted from 50 after baseline hit 100% rank-1 on 24 positives). Ratchet **up** only; never lower to greenwash.

## Anatomy

See `skills/_lattice-lib/references/skill-anatomy.md`.

## Behavioral pressure

Gate skills (`start-work`, `create-pr`, `finish-work`) include pressure cases in `evals/evals.json` (authority / skip-worktree / bare-merge style prompts). Tier-1 `validate-skills.sh` fails if any gate skill lacks a `pressure-*` case id.

## Behavioral corpus contract

Each `skills/<name>/evals/evals.json` uses `schema_version: 1`, a matching
`skill_name`, and unique behavioral cases:

```json
{
  "schema_version": 1,
  "skill_name": "start-work",
  "cases": [
    {
      "id": "resume-skip-full-regrill",
      "type": "behavioral",
      "prompt": "…",
      "expect": ["…"]
    }
  ]
}
```

Credential-free validation (schema + free full execution):

```bash
python3 tools/run-behavioral-evals.py --validate-only
printf '%s\n' '{"default":{"candidate":true,"baseline":false}}' > /tmp/fake-eval-scenario.json
FAKE_EVAL_SCENARIO=/tmp/fake-eval-scenario.json \
python3 tools/run-behavioral-evals.py \
  --provider-command "python3 evals/providers/fake-provider.py"
bats skills/_lattice-lib/scripts/tests/behavioral-evals.bats
```

CI (`lint` → skill-quality) runs both `--validate-only` and the free fake-provider
full corpus as a **harness/protocol smoke** so schema, isolation, artifacts, comparison,
and failure handling regressions fail without model spend. The fake scenario directly
chooses assertion truth values, so this lane is never model-quality evidence.

## Provider protocol and artifacts

`--provider-command` starts a fresh process for every `invoke` and `assert`
phase. It receives one JSON request on stdin and returns one JSON object on
stdout with `protocol_version: 1`.

- `invoke` returns non-empty `text`.
- `assert` returns exactly one `{index, passed, evidence}` object for every
  expectation.
- candidate and baseline phases use separate sandbox directories and do not
  share conversation state.

The runner records the raw request, stdout, stderr, parsed response, duration,
assertions, per-case comparison, manifest, and summary. Default artifacts live
under ignored `evals/artifacts/<run-id>/`. Exit status is `0` for pass, `1` for
quality/assertion failure, and `2` for corpus/provider/protocol failure.

The default comparison is the current skill versus **no skill**, with 100% of
candidate expectations required and no regression allowed. Use
`--baseline-skill-root <checkout-or-skills-dir>` for a previous skill version.
Exploratory thresholds and `--allow-regression` are explicit flags and should
not be used to greenwash a release gate.

## Protocol smoke and live capability examples

Deterministic fake-provider protocol smoke (`true`/`false` expands across all expectations;
per-case arrays are also supported as shown in the Bats suite):

```bash
printf '%s\n' '{"default":{"candidate":true,"baseline":false}}' > /tmp/eval-scenario.json
FAKE_EVAL_SCENARIO=/tmp/eval-scenario.json \
python3 tools/run-behavioral-evals.py \
  --provider-command "python3 evals/providers/fake-provider.py" \
  --skill start-work --case pressure-authority-skip-worktree
```

Opt-in Claude Code live capability run (requires Claude authentication and incurs model
cost). Pin the CLI version separately, choose a fixed model, start with one case,
and preserve artifacts. The provider records model, cost, duration, and session metadata
when exposed by the CLI:

```bash
npm install -g @anthropic-ai/claude-code@2.1.216
CLAUDE_EVAL_MODEL=<full-model-id> \
python3 tools/run-behavioral-evals.py \
  --provider-command \
    "python3 evals/providers/claude-cli-provider.py --max-budget-usd 1.00" \
  --skill start-work --case pressure-authority-skip-worktree
```

The example above is intentionally opt-in. Repeat noisy live cases, inspect raw
responses/evidence, and separate judge variance from harness errors before
drawing a quality conclusion. A single stochastic pass or failure is not a
release verdict. `--max-budget-usd` applies to each isolated Claude CLI phase,
so one case can make up to four separately capped calls (candidate/baseline
invoke + judge).
