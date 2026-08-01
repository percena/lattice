# generate-wiki evals

Lightweight checks for dogfood + acceptance (acceptance criteria A3–A12). Run from the **repo root** after a full generate.

```bash
bash skills/generate-wiki/evals/check-dogfood.sh
```

## What is checked

| Check | Acceptance |
| --- | --- |
| `wiki/catalogue.json` exists and lists leaves | A3 |
| Each catalogue leaf path exists under `wiki/` | A3 |
| Leaf page count in 5–8 (README hub excluded) | A4 |
| Generated pages carry `generated_by: generate-wiki` | A6 stamp |
| Root `llms.txt` structure (H1, blockquote, H2, Optional) | A7 |
| Root `AGENTS.md` not skill-stamped | A9 |
| Architecture page cites `skills/_lattice-lib/SKILL.md`; size sane | A12 |
| Code citations look like `blob/` or `(path:line)` | A5 sample |
| Intra-wiki `./…` links resolve | A10 sample |
| **Policy unit tests (sandbox):** `manual: true` skip; `generated_at` preserve; handwritten root `llms.txt` → write `wiki/llms.txt` only | A6 / A7 negative paths |

These are **shell + Python heuristics**, not a full browser render of Mermaid. Small-repo 3–4 page collapse (A4 edge) remains documented in SKILL/policy and is not fixture-tested here.
