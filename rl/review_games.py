#!/usr/bin/env python3
"""Review a play policy's own games: where does it still lose points?

Plays the policy against itself (or reads an existing file), labels a share
of its decisions with exact rollouts (every legal move played out on the same
deal) and reports, per game phase and situation:

  regret    points between the move played and the best move on that deal.
            This uses the hidden cards, so it is an upper bound on mistakes;
            early in a round most of it is unavoidable.
  best%     how often the move played was the best one on that deal.
  heuristic exact value of playing the heuristic's move instead (negative =
            the policy's move is better). This uses no hidden information.

It then tests simple endgame rules ("lead the highest single against an
opponent with one card", ...) against the policy's own choices, and prints
random endgame positions with large regret for reading.

  rl/.venv/bin/python rl/review_games.py --nn-policy=assets/bots/tichu_q_v6.safetensors
  rl/.venv/bin/python rl/review_games.py --jsonl=games.jsonl --examples=30
"""

from __future__ import annotations

import argparse
import collections
import json
import tempfile
from pathlib import Path

import numpy as np

from headless_runner import run_headless_sharded

RANK = {"Dog": 0, "1": 1, "T": 10, "J": 11, "Q": 12, "K": 13, "A": 14, "Ph": 15, "Dr": 16}


def rank(token: str) -> int:
    return RANK[token] if token in RANK else int(token)


def kind(act: str) -> str:
    if act == "pass":
        return "pass"
    t = act.split()
    if t == ["Dog"]:
        return "dog"
    if len(t) == 4 and len(set(t)) == 1:
        return "bomb"
    return {1: "single", 2: "pair", 3: "triple"}.get(len(t), "combo")


def load(path: Path) -> list[tuple[list, int, dict, int]]:
    rows = []
    with path.open("r", encoding="utf-8") as fh:
        for line in fh:
            if '"q_rollout"' not in line or '"desc"' not in line:
                continue
            r = json.loads(line)
            q, c = r["q_rollout"], r["legal_play_chosen_index"]
            if r.get("explore") or q[c] is None:
                continue
            rows.append((q, c, r["desc"], (r.get("shadow_indices") or [-1])[0]))
    return rows


def phase(cards: int) -> str:
    if cards >= 11:
        return "11-14 cards"
    if cards >= 7:
        return "7-10 cards"
    return "4-6 cards" if cards >= 4 else "1-3 cards"


def is_lead(d: dict) -> bool:
    return d["trick_type"] in ("empty", "none", "dog")


def breakdown(rows, examples: int, seed: int) -> None:
    cats: dict[str, dict] = collections.defaultdict(lambda: {"reg": [], "heur": [], "best": 0})
    total = 0.0
    endgame = []
    for q, c, d, shadow in rows:
        acts = d["acts"]
        values = [v for v in q if v is not None]
        regret = max(values) - q[c]
        total += regret
        cards = len(d["hand"].split())
        left, partner, right = d["counts"]
        opp_min = min([x for x in (left, right) if x > 0] or [99])
        situation = "lead" if is_lead(d) else ("follow partner" if d["winner"] == "P" else "follow opponent")
        keys = ["ALL", "phase: " + phase(cards), "situation: " + situation,
                f"{phase(cards)} | {situation}", "played: " + kind(acts[c])]
        if opp_min == 1:
            keys.append("context: an opponent has 1 card")
        if partner == 1:
            keys.append("context: partner has 1 card")
        if partner == 0:
            keys.append("context: partner is out")
        if "me" in d["calls"]:
            keys.append("context: I called Tichu")
        if "P" in d["calls"]:
            keys.append("context: partner called Tichu")
        if "L" in d["calls"] or "R" in d["calls"]:
            keys.append("context: an opponent called Tichu")
        heur = q[shadow] - q[c] if shadow >= 0 and q[shadow] is not None else None
        for k in keys:
            e = cats[k]
            e["reg"].append(regret)
            e["best"] += regret == 0
            if heur is not None:
                e["heur"].append(heur)
        if cards <= 4 and regret >= 100:
            endgame.append((d, acts, q, c))
    n = len(rows)
    print(f"{n} decisions, mean regret {total / n:.1f} points")
    print(f"{'category':40s} {'share':>6s} {'regret':>7s} {'of all':>7s} {'best%':>6s}   heuristic's move instead")
    for k, e in sorted(cats.items(), key=lambda kv: (":" not in kv[0] and "|" in kv[0], kv[0].split(":")[0], -len(kv[1]["reg"]))):
        r = np.array(e["reg"])
        if len(r) < 150:
            continue
        h = np.array(e["heur"]) if e["heur"] else None
        hs = f"{h.mean():+6.1f} ± {h.std() / np.sqrt(len(h)):.1f}" if h is not None else "     n/a"
        print(f"{k:40s} {len(r) / n:6.3f} {r.mean():7.1f} {r.sum() / total:7.3f} {100 * e['best'] / len(r):6.1f}   {hs}")
    if examples and endgame:
        rng = np.random.default_rng(seed)
        print(f"\n{len(endgame)} endgame decisions (4 cards or fewer) with 100+ points regret; {examples} at random")
        print("(hands: me / L = next player / P = partner / R; values = round result for my team)")
        for i in rng.permutation(len(endgame))[:examples]:
            d, acts, q, c = endgame[i]
            best = int(np.argmax([v if v is not None else -1e9 for v in q]))
            print(f"- me[{d['hand']}] L[{d['hands'][0]}] P[{d['hands'][1]}] R[{d['hands'][2]}] "
                  f"trick[{d['trick']}] by {d['winner']} calls{d['calls']} out{d['out']}")
            print(f"    played {acts[c]} ({q[c]:+.0f}), best {acts[best]} ({q[best]:+.0f}); all: "
                  + ", ".join(f"{a}:{v:+.0f}" for a, v in zip(acts, q) if v is not None))


def endgame_rules(rows) -> None:
    """Exact value of simple endgame rules against the policy's own choice."""

    def singles(acts, q):
        return [i for i, a in enumerate(acts) if a not in ("pass", "Dog") and len(a.split()) == 1 and q[i] is not None]

    def multis(acts, q):
        return [i for i, a in enumerate(acts) if a != "pass" and len(a.split()) >= 2
                and q[i] is not None and kind(a) != "bomb"]

    def cost(a):
        return sum(rank(t) for t in a.split())

    def cards(d):
        return len(d["hand"].split())

    def opp_min(d):
        return min([x for x in (d["counts"][0], d["counts"][2]) if x > 0] or [99])

    def follow_opp(d):
        return not is_lead(d) and d["winner"] in ("L", "R")

    def follow_partner(d):
        return not is_lead(d) and d["winner"] == "P"

    def highest(acts, q):
        s = singles(acts, q)
        return max(s, key=lambda i: rank(acts[i])) if s else None

    def lowest(acts, q):
        s = singles(acts, q)
        return min(s, key=lambda i: rank(acts[i])) if s else None

    def cheapest_multi(acts, q):
        m = multis(acts, q)
        return min(m, key=lambda i: cost(acts[i])) if m else None

    def cheapest_beat(acts, q):
        cand = [i for i, a in enumerate(acts) if a != "pass" and q[i] is not None and kind(a) != "bomb"]
        return min(cand, key=lambda i: cost(acts[i])) if cand else None

    rules = [
        ("lead a single, an opponent has 1 card: the highest single",
         lambda q, c, d, a: highest(a, q) if is_lead(d) and opp_min(d) == 1 and kind(a[c]) == "single" else None),
        ("lead, an opponent has 1 card: a multi-card play if possible",
         lambda q, c, d, a: cheapest_multi(a, q) if is_lead(d) and opp_min(d) == 1 else None),
        ("lead with two single cards: the higher one first",
         lambda q, c, d, a: highest(a, q) if is_lead(d) and cards(d) == 2 and len(singles(a, q)) == 2 and not multis(a, q) else None),
        ("lead a single with 3 cards or fewer: the highest",
         lambda q, c, d, a: highest(a, q) if is_lead(d) and cards(d) <= 3 and kind(a[c]) == "single" else None),
        ("lead a single with 3 cards or fewer: the lowest",
         lambda q, c, d, a: lowest(a, q) if is_lead(d) and cards(d) <= 3 and kind(a[c]) == "single" else None),
        ("lead with 4 cards or fewer: a multi-card play first",
         lambda q, c, d, a: cheapest_multi(a, q) if is_lead(d) and cards(d) <= 4 else None),
        ("lead, partner has 1 card: the lowest single",
         lambda q, c, d, a: lowest(a, q) if is_lead(d) and d["counts"][1] == 1 and opp_min(d) > 1 else None),
        ("opponent's trick, 3 cards or fewer: never pass",
         lambda q, c, d, a: cheapest_beat(a, q) if follow_opp(d) and cards(d) <= 3 and a[c] == "pass" else None),
        ("opponent's single, next opponent has 1 card: the highest single",
         lambda q, c, d, a: highest(a, q) if follow_opp(d) and d["trick_type"] == "single" and d["counts"][0] == 1 and a[c] != "pass" else None),
        ("partner's trick, partner has 2 cards or fewer: pass",
         lambda q, c, d, a: len(a) - 1 if follow_partner(d) and d["counts"][1] <= 2 and a[c] != "pass" and "pass" in a else None),
        ("partner's trick: always pass",
         lambda q, c, d, a: len(a) - 1 if follow_partner(d) and a[c] != "pass" and "pass" in a else None),
        ("opponent's trick after my own Tichu call: never pass",
         lambda q, c, d, a: cheapest_beat(a, q) if follow_opp(d) and "me" in d["calls"] and a[c] == "pass" else None),
    ]
    n = len(rows)
    print("\nSimple endgame rules against the policy's own choice (points when the rule applies):")
    for name, rule in rules:
        gains = []
        for q, c, d, _ in rows:
            b = rule(q, c, d, d["acts"])
            if b is None:
                continue
            gains.append(q[b] - q[c] if b != c and q[b] is not None else 0.0)
        if len(gains) < 50:
            continue
        g = np.array(gains)
        m, se = g.mean(), g.std() / np.sqrt(len(g))
        verdict = "better" if m > 2 * se else ("worse" if m < -2 * se else "no difference")
        print(f"  {name:64s} {100 * len(g) / n:5.2f}% of decisions  {m:+6.1f} ± {se:.1f}  {verdict}")


def main() -> None:
    p = argparse.ArgumentParser(description="Review a play policy's games with exact rollouts")
    p.add_argument("--nn-policy", default="assets/bots/tichu_q_v6.safetensors")
    p.add_argument("--jsonl", default="", help="existing --rollout-rate/--describe file (skips generation)")
    p.add_argument("--episodes", type=int, default=240)
    p.add_argument("--rollout-rate", type=float, default=0.25)
    p.add_argument("--examples", type=int, default=20)
    p.add_argument("--seed", type=int, default=510_000)
    p.add_argument("--shards", type=int, default=0)
    args = p.parse_args()
    if args.jsonl:
        rows = load(Path(args.jsonl))
    else:
        with tempfile.TemporaryDirectory(prefix="tichu_review_") as td:
            out = Path(td) / "review.jsonl"
            run_headless_sharded(
                base_args=["--format=bc-jsonl", "--target-score=1000", f"--nn-policy={args.nn_policy}",
                           f"--rollout-rate={args.rollout_rate}", "--describe", "--shadow-heuristics=latest"],
                seed=args.seed, episodes=args.episodes, output_path=out, shards=args.shards or None,
            )
            rows = load(out)
    breakdown(rows, args.examples, args.seed)
    endgame_rules(rows)


if __name__ == "__main__":
    main()
