#!/usr/bin/env python3
"""Match-win probability W(own total, opponent total) for win-aware targets.

The rollout labels are round point differences, but a match to 1000 is won
or lost, not scored: ahead near the target a safe round is worth more than a
risky one, behind it is the other way round. DouZero made the same point for
Dou Dizhu (agents trained on win probability win more often than agents
trained on points, which score more).

``WinTable`` gives the probability that the own team wins the match from
round-start totals ``(a, b)``, assuming i.i.d. rounds drawn from an empirical
distribution of round results (both teams' points). It is computed by Monte
Carlo on a 10-point grid and looked up bilinearly. ``after_round`` is the
value once a round with result ``(ra, rb)`` is scored: the match ends when a
team reaches the target (higher total wins, a tie is a draw = 0.5).

  rl/.venv/bin/python rl/win_prob.py --rounds=rounds.jsonl --output=rl/win_table.npz
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np

RL = Path(__file__).resolve().parent
DEFAULT_TABLE = RL / "win_table.npz"
LO, HI, STEP = -800, 1000, 10


class WinTable:
    def __init__(self, grid: np.ndarray, target: int = 1000) -> None:
        self.grid = grid  # (n, n) W at (LO + i*STEP, LO + j*STEP)
        self.target = target

    @classmethod
    def load(cls, path: Path = DEFAULT_TABLE) -> WinTable:
        d = np.load(path)
        return cls(d["grid"], int(d["target"]))

    def start(self, a: np.ndarray, b: np.ndarray) -> np.ndarray:
        """W at the start of a round with totals a (own) and b (opponent)."""
        n = self.grid.shape[0]
        fa = np.clip((np.asarray(a, float) - LO) / STEP, 0, n - 1 - 1e-9)
        fb = np.clip((np.asarray(b, float) - LO) / STEP, 0, n - 1 - 1e-9)
        ia, ib = fa.astype(int), fb.astype(int)
        ta, tb = fa - ia, fb - ib
        g = self.grid
        return (
            g[ia, ib] * (1 - ta) * (1 - tb)
            + g[ia + 1, ib] * ta * (1 - tb)
            + g[ia, ib + 1] * (1 - ta) * tb
            + g[ia + 1, ib + 1] * ta * tb
        )

    def after_round(self, a, b, ra, rb) -> np.ndarray:
        """Match value once a round with result (ra, rb) is added to (a, b)."""
        a2 = np.asarray(a, float) + ra
        b2 = np.asarray(b, float) + rb
        over = (a2 >= self.target) | (b2 >= self.target)
        final = np.where(a2 > b2, 1.0, np.where(a2 < b2, 0.0, 0.5))
        return np.where(over, final, self.start(a2, b2))


def compute(rounds: np.ndarray, target: int = 1000, sims: int = 2000, seed: int = 0) -> np.ndarray:
    """Monte Carlo W on the grid; ``rounds`` is (N, 2) own/opp round points,
    symmetric (each round in both orientations)."""
    rng = np.random.default_rng(seed)
    axis = np.arange(LO, HI + 1, STEP)
    n = axis.size
    grid = np.zeros((n, n))
    for i, a0 in enumerate(axis):
        a = np.full((n, sims), float(a0))
        b = np.repeat(axis[:, None].astype(float), sims, axis=1)
        val = np.full((n, sims), np.nan)
        for _ in range(200):
            live = np.isnan(val)
            if not live.any():
                break
            r = rounds[rng.integers(0, len(rounds), size=live.sum())]
            a[live] += r[:, 0]
            b[live] += r[:, 1]
            over = live & ((a >= target) | (b >= target))
            val[over] = np.where(a[over] > b[over], 1.0, np.where(a[over] < b[over], 0.0, 0.5))
        val = np.where(np.isnan(val), 0.5, val)
        grid[i] = val.mean(axis=1)
    # The game is symmetric: W(a, b) = 1 - W(b, a).
    return (grid + 1.0 - grid.T) / 2


def main() -> None:
    p = argparse.ArgumentParser(description="Match-win probability table")
    p.add_argument("--rounds", required=True, help="bc-jsonl with round_end rows")
    p.add_argument("--output", default=str(DEFAULT_TABLE))
    p.add_argument("--target-score", type=int, default=1000)
    p.add_argument("--sims", type=int, default=2000)
    args = p.parse_args()
    pairs = []
    with open(args.rounds, encoding="utf-8") as fh:
        for line in fh:
            if '"round_end"' in line:
                r = json.loads(line)
                pairs.append((r["team_one_round"], r["team_two_round"]))
                pairs.append((r["team_two_round"], r["team_one_round"]))
    rounds = np.asarray(pairs, dtype=float)
    print(f"{len(pairs) // 2} rounds; mean sum {rounds.sum(1).mean():.0f}, sd diff {np.std(rounds[:, 0] - rounds[:, 1]):.0f}")
    grid = compute(rounds, args.target_score, args.sims)
    np.savez(args.output, grid=grid, target=args.target_score)
    t = WinTable(grid, args.target_score)
    for a, b in [(0, 0), (500, 300), (800, 600), (900, 950), (950, 700)]:
        print(f"  W({a}, {b}) = {float(t.start(a, b)):.3f}")
    print(f"Saved {args.output}")


if __name__ == "__main__":
    main()
