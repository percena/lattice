#!/usr/bin/env python3
"""
Tier-2 trigger & routing evals.

Deterministic lexical ranking of skill descriptions against positive/negative
prompts. No model API spend.

Usage:
  python3 tools/run-routing-evals.py
  python3 tools/run-routing-evals.py --min-rank1 50
"""
from __future__ import annotations

import argparse
import json
import math
import re
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SKILLS_DIR = ROOT / "skills"
CASES_DIR = ROOT / "evals" / "routing"

# All user-facing skills with routing cases. Internal `_` packages are excluded.
# Must stay set-equal to USER_FACING in tools/validate-skills.sh — asserted by
# tools/tests/routing-catalog-parity.bats.
CATALOG = [
    "start-work",
    "create-spec",
    "create-review",
    "create-tickets",
    "batch-work",
    "create-pr",
    "finish-work",
    "generate-wiki",
    "create-adr",
    "run-e2e",
    "review-code",
    "review-production",
    "review-delivery",
]

LATIN_TOKEN_RE = re.compile(r"[a-z0-9]+", re.I)
CJK_CHUNK_RE = re.compile(r"[\u3400-\u4dbf\u4e00-\u9fff]+")
STOP = {
    "a", "an", "the", "and", "or", "to", "of", "for", "in", "on", "with", "when",
    "use", "using", "that", "this", "is", "are", "be", "as", "by", "from", "not",
    "do", "does", "into", "via", "at", "it", "its", "after", "before", "only",
}


def tokenize(text: str) -> list[str]:
    lowered = text.lower()
    tokens = [t for t in LATIN_TOKEN_RE.findall(lowered) if t not in STOP and len(t) > 1]
    for chunk in CJK_CHUNK_RE.findall(lowered):
        chars = list(chunk)
        tokens.extend(chars)
        tokens.extend(chunk[index : index + 2] for index in range(len(chunk) - 1))
    return tokens


def load_description(name: str) -> str:
    path = SKILLS_DIR / name / "SKILL.md"
    text = path.read_text(encoding="utf-8")
    if not text.startswith("---"):
        return text[:500]
    parts = text.split("---", 2)
    if len(parts) < 3:
        return text[:500]
    fm = parts[1]
    m = re.search(r"^description:\s*(.*(?:\n(?![a-zA-Z0-9_-]+:).*)*)", fm, re.M)
    if not m:
        return ""
    raw = m.group(1).strip()
    if raw.startswith('"') and raw.endswith('"'):
        raw = raw[1:-1]
    if raw.startswith("'") and raw.endswith("'"):
        raw = raw[1:-1]
    return re.sub(r"\s+", " ", raw)


def build_idf(docs: list[list[str]]) -> dict[str, float]:
    n = len(docs)
    df: Counter[str] = Counter()
    for d in docs:
        df.update(set(d))
    return {t: math.log((n + 1) / (df[t] + 1)) + 1.0 for t in df}


def tfidf_vec(tokens: list[str], idf: dict[str, float]) -> dict[str, float]:
    tf = Counter(tokens)
    if not tf:
        return {}
    max_tf = max(tf.values())
    return {t: (c / max_tf) * idf.get(t, 0.0) for t, c in tf.items()}


def cosine(a: dict[str, float], b: dict[str, float]) -> float:
    if not a or not b:
        return 0.0
    keys = set(a) | set(b)
    dot = sum(a.get(k, 0.0) * b.get(k, 0.0) for k in keys)
    na = math.sqrt(sum(v * v for v in a.values()))
    nb = math.sqrt(sum(v * v for v in b.values()))
    if na == 0 or nb == 0:
        return 0.0
    return dot / (na * nb)


def rank_skills(prompt: str, skill_vecs: dict[str, dict[str, float]], idf: dict[str, float]) -> list[tuple[str, float]]:
    q = tfidf_vec(tokenize(prompt), idf)
    scores = [(name, cosine(q, vec)) for name, vec in skill_vecs.items()]
    scores.sort(key=lambda x: (-x[1], x[0]))
    return scores


def load_case(name: str) -> dict:
    path = CASES_DIR / f"{name}.json"
    if not path.exists():
        raise FileNotFoundError(f"missing routing case: {path}")
    return json.loads(path.read_text(encoding="utf-8"))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--min-rank1", type=float, default=80.0, help="%% of positive prompts that must rank owner first")
    ap.add_argument("--collision-error", type=float, default=0.85, help="pairwise description cosine error threshold")
    ap.add_argument("--collision-warn", type=float, default=0.70, help="pairwise description cosine warn threshold")
    args = ap.parse_args()

    cases = {}
    for n in CATALOG:
        try:
            cases[n] = load_case(n)
        except FileNotFoundError as exc:
            print(f"ERROR: {exc}", file=sys.stderr)
            return 1
    descs = {
        n: " ".join([load_description(n), *cases[n].get("aliases", [])])
        for n in CATALOG
    }
    docs = [tokenize(descs[n]) for n in CATALOG]
    idf = build_idf(docs)
    skill_vecs = {n: tfidf_vec(tokenize(descs[n]), idf) for n in CATALOG}

    errors = 0
    warnings = 0

    # Collision check
    for i, a in enumerate(CATALOG):
        for b in CATALOG[i + 1 :]:
            sim = cosine(skill_vecs[a], skill_vecs[b])
            if sim >= args.collision_error:
                print(f"ERROR: description collision {a} vs {b}: cosine={sim:.3f} >= {args.collision_error}")
                errors += 1
            elif sim >= args.collision_warn:
                print(f"WARN: description near-collision {a} vs {b}: cosine={sim:.3f}")
                warnings += 1

    positive_total = 0
    rank1_hits = 0
    topk_hits = 0

    for name in CATALOG:
        case = cases[name]
        if case.get("skill_name") != name:
            print(f"ERROR: {name}.json skill_name mismatch")
            errors += 1
        for item in case.get("trigger", {}).get("positive", []):
            prompt = item["prompt"]
            top_k = int(item.get("top_k", 3))
            ranked = rank_skills(prompt, skill_vecs, idf)
            positive_total += 1
            order = [n for n, _ in ranked]
            if order and order[0] == name:
                rank1_hits += 1
            if name in order[:top_k]:
                topk_hits += 1
            else:
                print(f"ERROR: positive miss owner={name} top_k={top_k} prompt={prompt!r}")
                print(f"       ranked={order[:5]}")
                errors += 1
            if order and order[0] != name:
                print(f"WARN: positive not rank-1 owner={name} got={order[0]} prompt={prompt!r}")

        for item in case.get("trigger", {}).get("negative", []):
            prompt = item["prompt"]
            owner = item.get("owner")
            ranked = rank_skills(prompt, skill_vecs, idf)
            order = [n for n, _ in ranked]
            if order and order[0] == name:
                print(f"ERROR: negative ranked this skill first skill={name} prompt={prompt!r}")
                errors += 1
            if owner and owner in skill_vecs:
                # owner should outrank this skill
                pos_owner = order.index(owner) if owner in order else 99
                pos_self = order.index(name) if name in order else 99
                if pos_self < pos_owner:
                    print(
                        f"ERROR: negative owner outrank fail skill={name} owner={owner} "
                        f"order={order[:5]} prompt={prompt!r}"
                    )
                    errors += 1

    rank1_pct = (100.0 * rank1_hits / positive_total) if positive_total else 0.0
    topk_pct = (100.0 * topk_hits / positive_total) if positive_total else 0.0
    print(
        f"routing: positives={positive_total} rank1={rank1_hits} ({rank1_pct:.1f}%) "
        f"top_k_ok={topk_hits} ({topk_pct:.1f}%) warnings={warnings} errors={errors}"
    )
    print(f"routing: floor min-rank1={args.min_rank1}%")

    if rank1_pct + 1e-9 < args.min_rank1:
        print(f"ERROR: rank-1 rate {rank1_pct:.1f}% below floor {args.min_rank1}%")
        errors += 1

    if errors:
        print("run-routing-evals: FAILED")
        return 1
    print("run-routing-evals: OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
