# Monorepo maintainer tools

These scripts are **not** part of the portable `_lattice-lib` install unit.
Consumers who install Lattice skills do not need them.

| Tool | Role |
| --- | --- |
| `validate-skills.sh` | Tier-1 skill anatomy / eval presence lint |
| `validate-plugin-versions.py` | Plugin/marketplace SemVer + bundle change gate |
| `run-routing-evals.py` | Tier-2 routing catalog ranking |
| `run-behavioral-evals.py` | Behavioral eval runner / corpus validate |

Runtime shared scripts live in `skills/_lattice-lib/scripts/`.
