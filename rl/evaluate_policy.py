#!/usr/bin/env python3
"""Evaluate a policy and persist compact safetensors metrics.

The evaluator writes only .safetensors output. Intermediate transition logs are
written in a temp directory and removed after summarization.
"""

from __future__ import annotations

import argparse
import json
import statistics
import tempfile
from pathlib import Path

import torch
from safetensors.torch import save_file as st_save

from headless_runner import run_headless_sharded


def main() -> None:
    parser = argparse.ArgumentParser(description="Evaluate policy and save safetensors summary")
    parser.add_argument("--nn-policy", required=True, help="Policy .safetensors file")
    parser.add_argument("--output", required=True, help="Output eval .safetensors file")
    parser.add_argument("--seed", type=int, default=7777)
    parser.add_argument("--episodes", type=int, default=100)
    parser.add_argument("--target-score", type=int, default=1000)
    parser.add_argument(
        "--shards",
        type=int,
        default=0,
        help="Parallel headless workers (0 = auto = cpu_count - 1)",
    )
    args = parser.parse_args()

    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory(prefix="tichu_eval_") as td:
        temp_jsonl = Path(td) / "eval.jsonl"

        base_args = [
            f"--target-score={args.target_score}",
            "--mixed",
            f"--nn-policy={args.nn_policy}",
            "--format=summary",
        ]
        run_headless_sharded(
            base_args=base_args,
            seed=args.seed,
            episodes=args.episodes,
            output_path=temp_jsonl,
            shards=args.shards or None,
        )

        winners: list[int] = []
        team_one_totals: list[int] = []
        team_two_totals: list[int] = []
        margins: list[int] = []

        with temp_jsonl.open("r", encoding="utf-8") as fh:
            for line in fh:
                s = line.strip()
                if not s:
                    continue
                row = json.loads(s)
                # Each line in --format=summary mode is one finished match.
                w = row.get("winner")
                winners.append(int(w) if w is not None else -1)
                t1 = int(row.get("team_one_total", 0))
                t2 = int(row.get("team_two_total", 0))
                team_one_totals.append(t1)
                team_two_totals.append(t2)
                margins.append(t1 - t2)

        total = len(winners)
        team0_wins = sum(1 for w in winners if w == 0)
        team1_wins = sum(1 for w in winners if w == 1)
        ties = sum(1 for w in winners if w == -1)
        non_ties = max(1, total - ties)
        win_rate = 100.0 * team0_wins / non_ties
        avg_margin = float(sum(margins) / max(1, len(margins)))
        median_margin = float(statistics.median(margins)) if margins else 0.0

        tensors = {
            "winners": torch.tensor(winners, dtype=torch.int16),
            "team_one_totals": torch.tensor(team_one_totals, dtype=torch.int32),
            "team_two_totals": torch.tensor(team_two_totals, dtype=torch.int32),
            "margins": torch.tensor(margins, dtype=torch.int32),
        }
        metadata = {
            "format": "tichu_eval_summary_v1",
            "policy_path": str(Path(args.nn_policy)),
            "seed": str(args.seed),
            "episodes_requested": str(args.episodes),
            "target_score": str(args.target_score),
            "matches": str(total),
            "team0_wins": str(team0_wins),
            "team1_wins": str(team1_wins),
            "ties": str(ties),
            "team0_win_rate_non_tie": f"{win_rate:.6f}",
            "avg_margin_t0_minus_t1": f"{avg_margin:.6f}",
            "median_margin_t0_minus_t1": f"{median_margin:.6f}",
        }
        st_save(tensors, str(output_path), metadata=metadata)

        print(f"Saved eval summary: {output_path}")
        print(
            f"  matches={total} team0_wins={team0_wins} team1_wins={team1_wins} "
            f"ties={ties} win_rate_non_tie={win_rate:.2f}% avg_margin={avg_margin:.2f}"
        )


if __name__ == "__main__":
    main()
