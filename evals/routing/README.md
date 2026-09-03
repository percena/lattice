# Routing evals (Tier 2)

Deterministic lexical ranking that tests whether each skill's description and
aliases match realistic user prompts — in both English and Chinese. No model
API spend; runs in milliseconds.

## How it works

`tools/run-routing-evals.py` tokenizes skill descriptions (including CJK
bigrams) and scores each skill against every prompt using TF-IDF cosine
similarity. A prompt "passes" when the intended skill ranks in the top-k
(default 1 for most cases, 2–3 for ambiguous prompts).

## Running

```bash
# Full suite — exits non-zero if rank-1 rate < threshold
python3 tools/run-routing-evals.py

# With explicit threshold (CI uses 80%)
python3 tools/run-routing-evals.py --min-rank1 80

# Verbose (shows per-case ranking)
python3 tools/run-routing-evals.py --verbose
```

## Case files

One JSON file per user-facing skill: `evals/routing/<skill>.json`.

```json
{
  "skill_name": "start-work",
  "aliases": ["开始实现", "继续 ticket", ...],
  "trigger": {
    "positive": [
      { "prompt": "...", "top_k": 1 }
    ],
    "negative": [
      { "prompt": "...", "owner": "create-pr" }
    ]
  }
}
```

- **positive** — realistic asks that should rank this skill within `top_k`.
- **negative** — prompts that belong to another skill (`owner`); this skill
  must not rank first.
- **aliases** — CJK and alternate-language names; included in the skill's
  token pool during ranking.

### Current catalog

| Skill | File |
| --- | --- |
| start-work | `start-work.json` |
| create-spec | `create-spec.json` |
| create-review | `create-review.json` |
| create-tickets | `create-tickets.json` |
| batch-work | `batch-work.json` |
| create-pr | `create-pr.json` |
| finish-work | `finish-work.json` |
| generate-wiki | `generate-wiki.json` |
| create-adr | `create-adr.json` |
| run-e2e | `run-e2e.json` |
| verify-features | `verify-features.json` |
| review-code | `review-code.json` |
| review-production | `review-production.json` |
| review-delivery | `review-delivery.json` |
| review-lineage | `review-lineage.json` |

Catalog must stay set-equal to `USER_FACING` in `tools/validate-skills.sh` —
asserted by `tools/tests/routing-catalog-parity.bats`.

## Thresholds and anti-greenwashing ratchet

CI (`lint-heavy.yml`) enforces `--min-rank1 80` — the minimum percentage of
positive prompts where the correct skill ranks first. This threshold was
ratcheted up from 50 after the baseline hit 100% rank-1 on 24 positives.

**Ratchet rule:** thresholds go up only. Lowering the floor to make a failing
eval green is greenwashing — add better aliases or descriptions instead.

## Relationship to other tiers

| Tier | What | Deterministic? |
| --- | --- | --- |
| 1 Structural | Frontmatter, anatomy, `evals.json` presence, Codex invariants | Yes |
| **2 Routing** | **Lexical description ranking (this tier)** | **Yes** |
| 3 Behavioral | Per-skill prompt/response with model assertions | No (stochastic) |

See `evals/README.md` for the full eval framework overview.
