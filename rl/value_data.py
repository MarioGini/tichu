#!/usr/bin/env python3
"""Training data for the perfect-information value net (``value_train.py``).

Streams headless bc-jsonl self-play and keeps, for a sample of play
decisions, the decider's state features, who really holds each card the
decider cannot see (as ``belief_data.py``), and how the round ended from the
decider's point of view. Labels are free in self-play.

  s (N, state) float16    h (N, 56) int8: -1 = not unseen (mine / played),
                          0 = left opponent, 1 = partner, 2 = right opponent
  y (N, 2) float32        round points of the decider's team, of the other team
  f (N,) int8             first out: 0 self, 1 left, 2 partner, 3 right
  d (N,) int8             double victory: 0 us, 1 them, 2 neither

  rl/.venv/bin/python rl/value_data.py --out-dir=rl/outputs/value --seed=1 \\
      --episodes=200 --shards=4 --args="--nn-policy=... --schupf-net=..."

The rows of one round share its outcome (correlated labels, see
rl/REVIEW.md): keep ``--rate`` low and spread the data over many deals;
``value_train.py`` holds out whole files.
"""

from __future__ import annotations

import argparse
import json
import multiprocessing as mp
import os
import random
import shlex
import subprocess
from pathlib import Path

import numpy as np
from schema import pad_state


def labels(end: dict, team: int, seat: int) -> tuple[list[float], int, int]:
    one, two = float(end["team_one_round"]), float(end["team_two_round"])
    y = [one, two] if team == 0 else [two, one]
    seats = end["finish_seats"]
    first = (seats[0] - seat) % 4 if seats else 0
    teams = end["finish_teams"]
    if len(teams) >= 2 and teams[0] == teams[1]:
        double = 0 if teams[0] == team else 1
    else:
        double = 2
    return y, first, double


def stream(cmd: list[str], out: Path, rate: float, seed: int) -> int:
    rng = random.Random(seed)
    p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, bufsize=1 << 20)
    assert p.stdout is not None
    ss, hh, yy, ff, dd = [], [], [], [], []
    pending: list[tuple[np.ndarray, np.ndarray, int, int]] = []
    for line in p.stdout:
        if '"round_end"' in line:
            end = json.loads(line)
            for s, h, team, seat in pending:
                y, f, d = labels(end, team, seat)
                ss.append(s)
                hh.append(h)
                yy.append(y)
                ff.append(f)
                dd.append(d)
            pending = []
            continue
        if '"legal_play_chosen_index"' not in line or rng.random() >= rate:
            continue
        r = json.loads(line)
        h = np.full(56, -1, np.int8)
        for holder, hand in enumerate(r["oracle"]):
            for slot in hand:
                h[slot] = holder
        pending.append((np.asarray(r["state_features"], np.float16), h, r["team"], r["seat"]))
    p.wait()
    if ss:
        tmp = out.with_suffix(".tmp.npz")
        np.savez_compressed(
            tmp,
            s=pad_state(np.stack(ss)),
            h=np.stack(hh),
            y=np.asarray(yy, np.float32),
            f=np.asarray(ff, np.int8),
            d=np.asarray(dd, np.int8),
        )
        tmp.rename(out)
    return len(ss)


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--out-dir", required=True)
    p.add_argument("--episodes", type=int, default=200, help="matches per shard")
    p.add_argument("--shards", type=int, default=2)
    p.add_argument("--seed", type=int, default=1)
    p.add_argument("--rate", type=float, default=0.2, help="share of play decisions kept")
    p.add_argument("--args", default="")
    args = p.parse_args()
    out = Path(args.out_dir)
    out.mkdir(parents=True, exist_ok=True)
    binary = os.environ.get("TICHU_HEADLESS", "build/bin/headless")
    jobs = []
    for k in range(args.shards):
        seed = args.seed * 1000 + k
        cmd = [binary, f"--seed={seed}", f"--episodes={args.episodes}", "--format=bc-jsonl",
               "--output=/dev/stdout", *shlex.split(args.args)]
        jobs.append((cmd, out / f"v{args.seed:04d}_{k}.npz", args.rate, seed))
    with mp.Pool(args.shards) as pool:
        n = pool.starmap(stream, jobs)
    print(f"{sum(n)} positions written to {out}")


if __name__ == "__main__":
    main()
