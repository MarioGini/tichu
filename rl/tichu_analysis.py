#!/usr/bin/env python3
"""Why do Tichu calls succeed or fail? (heuristic or any bot config)

Plays matches with headless ``--format=bc-jsonl --skip-play-rows`` and joins
each Tichu call (hand at call time) with the round result:

  * failures: who went out first instead (an opponent, or the caller's own
    partner) and how many cards the caller still held then (near miss vs
    clearly too weak);
  * successes: how comfortable the win was (fewest cards an opponent held
    when the caller went out);
  * success rate by hand feature (controls, low singles, Dog, bombs, ...);
  * "missed Tichus": players who went out first without calling, by hand.

  rl/.venv/bin/python rl/tichu_analysis.py --episodes=150
  rl/.venv/bin/python rl/tichu_analysis.py --extra=--nn-policy=... --extra=--tichu-net=...
"""

from __future__ import annotations

import argparse
import collections
import json
import tempfile
from pathlib import Path

from headless_runner import run_headless_sharded

RANK_NAMES = {11: "J", 12: "Q", 13: "K", 14: "A"}


def hand_features(slots: list[int]) -> dict:
    ranks = collections.Counter()
    by_color: dict[int, set[int]] = collections.defaultdict(set)
    specials = set()
    for s in slots:
        if s >= 52:
            specials.add({52: "mahjong", 53: "dog", 54: "phoenix", 55: "dragon"}[s])
        else:
            rank = s % 13 + 2
            ranks[rank] += 1
            by_color[s // 13].add(rank)
    quads = sum(1 for c in ranks.values() if c == 4)
    flushes = 0
    for rs in by_color.values():
        run = best = 0
        for r in range(2, 15):
            run = run + 1 if r in rs else 0
            best = max(best, run)
        flushes += best >= 5
    bombs = quads + flushes
    controls = ranks[14] + ("dragon" in specials) + ("phoenix" in specials) + bombs
    low_singles = sum(1 for r, c in ranks.items() if c == 1 and r < 10)
    present = set(ranks) | ({1} if "mahjong" in specials else set())
    run = longest = 0
    for r in range(1, 15):
        run = run + 1 if r in present else 0
        longest = max(longest, run)
    return {
        "controls": controls,
        "aces": ranks[14],
        "dragon": "dragon" in specials,
        "phoenix": "phoenix" in specials,
        "dog": "dog" in specials,
        "bombs": bombs,
        "low_singles": low_singles,
        "pairs": sum(1 for c in ranks.values() if c >= 2),
        "longest_run": longest,
    }


def describe(slots: list[int]) -> str:
    names = []
    for s in sorted(slots, key=lambda s: (s % 13 if s < 52 else 13 + s)):
        if s >= 52:
            names.append({52: "MJ", 53: "Dog", 54: "Ph", 55: "Dr"}[s])
        else:
            r = s % 13 + 2
            names.append(RANK_NAMES.get(r, str(r)))
    return " ".join(names)


def rate(rows: list[dict], key, label: str) -> None:
    groups = collections.defaultdict(list)
    for r in rows:
        groups[key(r["feat"])].append(r["success"])
    print(f"  by {label}:")
    for k in sorted(groups):
        v = groups[k]
        print(f"    {str(k):>6}: {len(v):5d} calls, success {100 * sum(v) / len(v):5.1f}%")


def main() -> None:
    p = argparse.ArgumentParser(description="Tichu call success / failure analysis")
    p.add_argument("--episodes", type=int, default=150)
    p.add_argument("--target-score", type=int, default=1000)
    p.add_argument("--seed", type=int, default=99)
    p.add_argument("--shards", type=int, default=1)
    p.add_argument("--examples", type=int, default=8)
    p.add_argument("--extra", action="append", default=[], help="Extra headless arg (repeatable)")
    args = p.parse_args()

    with tempfile.TemporaryDirectory(prefix="tichu_calls_") as td:
        out = Path(td) / "g.jsonl"
        run_headless_sharded(
            base_args=[f"--target-score={args.target_score}", "--format=bc-jsonl",
                       "--skip-play-rows", *args.extra],
            seed=args.seed, episodes=args.episodes, output_path=out,
            shards=args.shards, deal_seed=args.seed,
        )
        calls: dict[tuple, dict] = {}
        rounds: dict[tuple, dict] = {}
        for line in out.open():
            r = json.loads(line)
            if r.get("round_end"):
                rounds[(r["episode"], r["round"])] = r
            elif r.get("call") in ("tichu", "pre") and r.get("called") and "hand" in r:
                calls[(r["episode"], r["round"], r["seat"])] = r

    rows = []
    for (ep, rnd), re in rounds.items():
        order = re.get("finish_seats", [])
        left = re.get("cards_left_at_first_out")
        callers = {c[3] for c in re.get("calls", []) if c[1] == "tichu" and len(c) > 3}
        for seat in callers:
            c = calls.get((ep, rnd, seat))
            if c is None:
                continue
            first = order[0] if order else None
            own = re["team_one_round"] if seat % 2 == 0 else re["team_two_round"]
            opp = re["team_two_round"] if seat % 2 == 0 else re["team_one_round"]
            row = {
                "feat": hand_features(c["hand"]),
                "hand": c["hand"],
                "success": first == seat,
                "first": first,
                "rel_first": None if first is None else (first - seat) % 4,
                "caller_left": left[seat] if left else None,
                "opp_min_left": min(left[(seat + 1) % 4], left[(seat + 3) % 4]) if left else None,
                "diff": own - opp,
            }
            rows.append(row)
        if order and order[0] not in callers and left:
            # Went out first without calling: a missed +100.
            pass
    if not rows:
        print("no Tichu calls found")
        return

    n = len(rows)
    succ = [r for r in rows if r["success"]]
    fail = [r for r in rows if not r["success"]]
    print(f"Tichu calls: {n}, success {100 * len(succ) / n:.1f}%  "
          f"(mean round diff: success {sum(r['diff'] for r in succ) / max(1, len(succ)):+.0f}, "
          f"failure {sum(r['diff'] for r in fail) / max(1, len(fail)):+.0f})")

    print("\nFailures — who went out first instead:")
    who = collections.Counter({1: "left opponent", 2: "own partner", 3: "right opponent"}.get(r["rel_first"], "?")
                              for r in fail)
    for k, v in who.most_common():
        print(f"  {k:15s} {v:5d} ({100 * v / len(fail):.0f}%)")
    print("Failures — cards the caller still held when someone else went out:")
    cl = collections.Counter(r["caller_left"] for r in fail if r["caller_left"] is not None)
    near = sum(v for k, v in cl.items() if k <= 2)
    print("  " + ", ".join(f"{k}:{cl[k]}" for k in sorted(cl)))
    print(f"  near misses (<= 2 cards left): {100 * near / max(1, len(fail)):.0f}% of failures")

    print("Successes — fewest cards an opponent held when the caller went out:")
    ol = collections.Counter(r["opp_min_left"] for r in succ if r["opp_min_left"] is not None)
    print("  " + ", ".join(f"{k}:{ol[k]}" for k in sorted(ol)))
    close = sum(v for k, v in ol.items() if k <= 2)
    print(f"  close calls (an opponent had <= 2 cards): {100 * close / max(1, len(succ)):.0f}% of successes")

    print("\nSuccess rate by hand at call time:")
    rate(rows, lambda f: min(f["controls"], 5), "controls (Dragon, Phoenix, Aces, bombs; 5 = 5+)")
    rate(rows, lambda f: min(f["low_singles"], 5), "low singles (<10, unpaired; 5 = 5+)")
    rate(rows, lambda f: f["dog"], "holds the Dog")
    rate(rows, lambda f: f["dragon"], "holds the Dragon")
    rate(rows, lambda f: f["phoenix"], "holds the Phoenix")
    rate(rows, lambda f: min(f["bombs"], 2), "bombs")

    print("\nExample failures (hand at call → outcome):")
    for r in fail[: args.examples]:
        who_first = {1: "left opp", 2: "partner", 3: "right opp"}.get(r["rel_first"], "?")
        print(f"  {describe(r['hand']):45s} → {who_first} out first, caller had {r['caller_left']} left")


if __name__ == "__main__":
    main()
