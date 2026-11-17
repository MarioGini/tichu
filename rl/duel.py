#!/usr/bin/env python3
"""Duplicate match between two bot configurations (heuristics and/or nets).

Side A is the headless "policy" team, side B the "opponent" team; by default
side B is the shipped bot (``BASELINE``: play net v5 + learned schupf). Every deal
sequence is played twice with the seats swapped (same ``--deal-seed``), and
the result is the per-deal average, so card luck largely cancels out.

  # heuristic variant vs the current heuristic, 5000 deals (10000 matches)
  rl/.venv/bin/python rl/duel.py --a="--heuristic=latest,-early_dog" \
      --b="--opponent-heuristic=latest" --deals=5000

  # a policy vs the heuristic / vs another policy
  rl/.venv/bin/python rl/duel.py --a="--nn-policy=new.safetensors" --deals=1000
  rl/.venv/bin/python rl/duel.py --a="--nn-policy=new.safetensors" \
      --b="--opponent-policy=old_policy.safetensors" --deals=1000

With a heuristic-only matchup this plays ~100 matches per second and core.
"""

from __future__ import annotations

import argparse
import json
import math
import shlex
import tempfile
from pathlib import Path

from headless_runner import run_headless_sharded

# The reference opponent for comparisons: the shipped bot (play net + learned
# schupf; calls heuristic). The heuristic is too weak to tell strong bots apart.
BASELINE = (
    "--opponent-policy=assets/bots/tichu_q_v5.safetensors "
    "--opponent-schupf-net=assets/bots/tichu_schupf_v2.safetensors "
    "--opponent-tichu-net=assets/bots/tichu_call_v1.safetensors"
)


def duel(
    a: list[str],
    b: list[str],
    *,
    deals: int,
    seed: int = 4242,
    target_score: int = 1000,
    shards: int = 0,
) -> dict[str, float]:
    """Play ``deals`` deal sequences twice; return A's paired results."""
    per_deal: dict[int, list[tuple[float, float]]] = {}
    with tempfile.TemporaryDirectory(prefix="tichu_duel_") as td:
        for swap in (False, True):
            out = Path(td) / f"side_{int(swap)}.jsonl"
            run_headless_sharded(
                base_args=[
                    f"--target-score={target_score}",
                    "--mixed",
                    "--format=summary",
                    *a,
                    *b,
                    *(["--swap-teams"] if swap else []),
                ],
                seed=seed + int(swap),
                episodes=deals,
                output_path=out,
                shards=shards or None,
                deal_seed=seed,
            )
            a_team = 1 if swap else 0
            with out.open("r", encoding="utf-8") as fh:
                for line in fh:
                    if not line.strip():
                        continue
                    row = json.loads(line)
                    t1 = int(row.get("team_one_total", 0))
                    t2 = int(row.get("team_two_total", 0))
                    w = row.get("winner")
                    score = 0.5 if w is None else float(int(w) == a_team)
                    margin = float(t1 - t2 if a_team == 0 else t2 - t1)
                    per_deal.setdefault(int(row["episode"]), []).append((score, margin))
    pairs = [v for v in per_deal.values() if len(v) == 2]
    wins = [(x[0] + y[0]) / 2 for x, y in pairs]
    margins = [(x[1] + y[1]) / 2 for x, y in pairs]

    def mean_se(xs: list[float]) -> tuple[float, float]:
        m = sum(xs) / len(xs)
        var = sum((x - m) ** 2 for x in xs) / max(1, len(xs) - 1)
        return m, math.sqrt(var / len(xs))

    win, win_se = mean_se(wins)
    margin, margin_se = mean_se(margins)
    return {
        "deals": len(pairs),
        "win_rate": 100 * win,
        "win_rate_se": 100 * win_se,
        "margin": margin,
        "margin_se": margin_se,
    }


def main() -> None:
    p = argparse.ArgumentParser(description="Duplicate duel between two bots")
    p.add_argument("--a", default="", help="headless args of side A (e.g. --nn-policy=.. --heuristic=..)")
    p.add_argument("--b", default=BASELINE,
                   help="headless args of side B (default: the shipped bot, v5 + learned schupf; "
                        "'' for the heuristic)")
    p.add_argument("--deals", type=int, default=1000)
    p.add_argument("--seed", type=int, default=4242)
    p.add_argument("--target-score", type=int, default=1000)
    p.add_argument("--shards", type=int, default=0)
    p.add_argument("--label", default="")
    args = p.parse_args()
    r = duel(
        shlex.split(args.a),
        shlex.split(args.b),
        deals=args.deals,
        seed=args.seed,
        target_score=args.target_score,
        shards=args.shards,
    )
    label = args.label or f"A[{args.a}] vs B[{args.b}]"
    print(
        f"{label}: A wins {r['win_rate']:.1f}% ± {r['win_rate_se']:.1f}  "
        f"margin {r['margin']:+.0f} ± {r['margin_se']:.0f}  ({r['deals']} deals x 2)",
        flush=True,
    )


if __name__ == "__main__":
    main()
