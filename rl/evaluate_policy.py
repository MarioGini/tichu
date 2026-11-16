#!/usr/bin/env python3
"""Evaluate a policy vs the heuristic (or another policy) and persist compact
safetensors metrics.

By default the evaluation is *duplicate*: every deal sequence is played twice,
once with the policy on the even seats and once (``--swap-teams``) on the odd
seats, with identical deals (``--deal-seed``). Card luck largely cancels out
in the per-deal average, which cuts the variance of the win-rate estimate a
lot compared with always seating the policy on team 0.

Per-deal results are stored as tensors so two evaluations on the same seed
can be compared pairwise (see ``compare_evals``).

Intermediate JSONL logs are written in a temp directory and removed.
"""

from __future__ import annotations

import argparse
import json
import math
import statistics
import tempfile
from pathlib import Path

import torch
from safetensors import safe_open
from safetensors.torch import save_file as st_save

from headless_runner import run_headless_sharded


def _run_side(
    *,
    nn_policy: str,
    opponent_policy: str,
    seed: int,
    deal_seed: int,
    episodes: int,
    target_score: int,
    shards: int,
    swap: bool,
    out: Path,
    extra_args: list[str],
) -> dict[int, tuple[float, int]]:
    """Run one seating; return {episode: (policy_score, policy_margin)}.

    policy_score is 1 for a policy-team win, 0 for a loss, 0.5 for a tie /
    unfinished match.
    """
    base_args = [
        f"--target-score={target_score}",
        "--mixed",
        f"--nn-policy={nn_policy}",
        "--format=summary",
    ]
    if opponent_policy:
        base_args.append(f"--opponent-policy={opponent_policy}")
    base_args.extend(extra_args)
    if swap:
        base_args.append("--swap-teams")
    run_headless_sharded(
        base_args=base_args,
        seed=seed,
        episodes=episodes,
        output_path=out,
        shards=shards or None,
        deal_seed=deal_seed,
    )
    policy_team = 1 if swap else 0
    results: dict[int, tuple[float, int]] = {}
    with out.open("r", encoding="utf-8") as fh:
        for line in fh:
            s = line.strip()
            if not s:
                continue
            row = json.loads(s)
            t1 = int(row.get("team_one_total", 0))
            t2 = int(row.get("team_two_total", 0))
            margin = (t1 - t2) if policy_team == 0 else (t2 - t1)
            w = row.get("winner")
            if w is None:
                score = 0.5
            else:
                score = 1.0 if int(w) == policy_team else 0.0
            results[int(row["episode"])] = (score, margin)
    return results


def _mean_se(xs: list[float]) -> tuple[float, float]:
    if not xs:
        return 0.0, 0.0
    m = sum(xs) / len(xs)
    if len(xs) < 2:
        return m, 0.0
    return m, statistics.stdev(xs) / math.sqrt(len(xs))


def evaluate(
    *,
    nn_policy: str,
    output: Path,
    seed: int,
    episodes: int,
    target_score: int,
    shards: int = 0,
    duplicate: bool = True,
    opponent_policy: str = "",
    tichu_net: str = "",
    grand_net: str = "",
    schupf_net: str = "",
    extra: list[str] | None = None,
) -> dict[str, float]:
    extra_args = list(extra or [])
    if schupf_net:
        extra_args.append(f"--schupf-net={schupf_net}")
    if tichu_net:
        extra_args.append(f"--tichu-net={tichu_net}")
    if grand_net:
        extra_args.append(f"--grand-net={grand_net}")
    output.parent.mkdir(parents=True, exist_ok=True)
    deal_seed = seed
    with tempfile.TemporaryDirectory(prefix="tichu_eval_") as td:
        sides = [False, True] if duplicate else [False]
        per_side = [
            _run_side(
                nn_policy=nn_policy,
                opponent_policy=opponent_policy,
                seed=seed + 17 * i,
                deal_seed=deal_seed,
                episodes=episodes,
                target_score=target_score,
                shards=shards,
                swap=swap,
                out=Path(td) / f"eval_{i}.jsonl",
                extra_args=extra_args,
            )
            for i, swap in enumerate(sides)
        ]

    episodes_common = sorted(set.intersection(*(set(r) for r in per_side)))
    deal_scores = [
        sum(r[e][0] for r in per_side) / len(per_side) for e in episodes_common
    ]
    deal_margins = [
        sum(r[e][1] for r in per_side) / len(per_side) for e in episodes_common
    ]
    win_rate, win_se = _mean_se(deal_scores)
    margin, margin_se = _mean_se(deal_margins)
    games = sum(len(r) for r in per_side)
    wins = sum(1 for r in per_side for v in r.values() if v[0] == 1.0)
    losses = sum(1 for r in per_side for v in r.values() if v[0] == 0.0)

    tensors = {
        "episodes": torch.tensor(episodes_common, dtype=torch.int32),
        "deal_scores": torch.tensor(deal_scores, dtype=torch.float32),
        "deal_margins": torch.tensor(deal_margins, dtype=torch.float32),
    }
    metrics = {
        "matches": float(games),
        "team0_wins": float(wins),
        "team1_wins": float(losses),
        "win_rate": 100.0 * win_rate,
        "win_rate_se": 100.0 * win_se,
        "avg_margin": margin,
        "avg_margin_se": margin_se,
    }
    metadata = {
        "format": "tichu_eval_summary_v2",
        "policy_path": str(Path(nn_policy)),
        "opponent_policy": opponent_policy or "heuristic",
        "tichu_net": tichu_net,
        "grand_net": grand_net,
        "seed": str(seed),
        "duplicate": "1" if duplicate else "0",
        "episodes_requested": str(episodes),
        "target_score": str(target_score),
        "matches": str(games),
        "team0_wins": str(wins),
        "team1_wins": str(losses),
        # Kept for backwards compatibility: "team0" = the evaluated policy.
        "team0_win_rate_non_tie": f"{100.0 * win_rate:.6f}",
        "win_rate_se": f"{100.0 * win_se:.6f}",
        "avg_margin_t0_minus_t1": f"{margin:.6f}",
        "avg_margin_se": f"{margin_se:.6f}",
        "median_margin_t0_minus_t1": (
            f"{statistics.median(deal_margins):.6f}" if deal_margins else "0"
        ),
    }
    st_save(tensors, str(output), metadata=metadata)
    return metrics


def compare_evals(a: Path, b: Path) -> tuple[float, float]:
    """Paired difference (a - b) in win rate (percentage points) and its SE,
    over the deals both evaluations share. Both must use the same seed."""

    def load(p: Path) -> dict[int, float]:
        with safe_open(str(p), framework="pt", device="cpu") as r:
            eps = r.get_tensor("episodes").tolist()
            sc = r.get_tensor("deal_scores").tolist()
        return dict(zip(eps, sc))

    ra, rb = load(a), load(b)
    common = sorted(set(ra) & set(rb))
    diffs = [100.0 * (ra[e] - rb[e]) for e in common]
    return _mean_se(diffs)


def main() -> None:
    parser = argparse.ArgumentParser(description="Evaluate policy and save safetensors summary")
    parser.add_argument("--nn-policy", required=True, help="Policy .safetensors file")
    parser.add_argument("--output", required=True, help="Output eval .safetensors file")
    parser.add_argument("--seed", type=int, default=7777)
    parser.add_argument(
        "--episodes",
        type=int,
        default=100,
        help="Deal sequences; duplicate mode plays each twice",
    )
    parser.add_argument("--target-score", type=int, default=1000)
    parser.add_argument(
        "--opponent-policy",
        default="",
        help="Evaluate against this NN policy instead of the heuristic",
    )
    parser.add_argument("--tichu-net", default="", help="Call-value net for Tichu")
    parser.add_argument("--grand-net", default="", help="Call-value net for Grand Tichu")
    parser.add_argument("--schupf-net", default="", help="Schupf value net")
    parser.add_argument(
        "--extra",
        action="append",
        default=[],
        help="Extra headless args for the policy side, e.g. --extra=--heuristic=legacy",
    )
    parser.add_argument(
        "--no-duplicate",
        dest="duplicate",
        action="store_false",
        help="Only play with the policy on team 0 (old behaviour)",
    )
    parser.add_argument(
        "--shards",
        type=int,
        default=0,
        help="Parallel headless workers (0 = auto = cpu_count - 1)",
    )
    args = parser.parse_args()

    m = evaluate(
        nn_policy=args.nn_policy,
        output=Path(args.output),
        seed=args.seed,
        episodes=args.episodes,
        target_score=args.target_score,
        shards=args.shards,
        duplicate=args.duplicate,
        opponent_policy=args.opponent_policy,
        tichu_net=args.tichu_net,
        grand_net=args.grand_net,
        schupf_net=args.schupf_net,
        extra=args.extra,
    )
    print(f"Saved eval summary: {args.output}")
    print(
        f"  matches={int(m['matches'])} wins={int(m['team0_wins'])} "
        f"losses={int(m['team1_wins'])} "
        f"win_rate={m['win_rate']:.2f}% ± {m['win_rate_se']:.2f} "
        f"avg_margin={m['avg_margin']:.1f} ± {m['avg_margin_se']:.1f}"
    )


if __name__ == "__main__":
    main()
