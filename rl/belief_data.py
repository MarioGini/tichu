#!/usr/bin/env python3
"""Training data for the card-location (belief) model.

Streams headless bc-jsonl self-play and keeps, for a sample of play
decisions, the decider's state features and who really holds each card the
decider cannot see (the ``oracle`` hands: left opponent, partner, right
opponent). Labels are free in self-play; the model learns where the unseen
cards probably are from what the play revealed (passes, plays, schupf).

  s (N, state) float16      h (N, 56) int8: -1 = not unseen (mine / played),
                            0 = left opponent, 1 = partner, 2 = right opponent

  rl/.venv/bin/python rl/belief_data.py --out-dir=rl/outputs/belief --seed=1 \\
      --episodes=200 --shards=2 --args="--nn-policy=... --schupf-net=..."
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


def stream(cmd: list[str], out: Path, rate: float, seed: int) -> int:
    rng = random.Random(seed)
    p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, bufsize=1 << 20)
    assert p.stdout is not None
    ss, hh = [], []
    for line in p.stdout:
        if '"legal_play_chosen_index"' not in line or rng.random() >= rate:
            continue
        r = json.loads(line)
        h = np.full(56, -1, np.int8)
        for holder, hand in enumerate(r["oracle"]):
            for slot in hand:
                h[slot] = holder
        ss.append(np.asarray(r["state_features"], np.float16))
        hh.append(h)
    p.wait()
    if ss:
        tmp = out.with_suffix(".tmp.npz")
        np.savez_compressed(tmp, s=pad_state(np.stack(ss)), h=np.stack(hh))
        tmp.rename(out)
    return len(ss)


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--out-dir", required=True)
    p.add_argument("--episodes", type=int, default=200, help="matches per shard")
    p.add_argument("--shards", type=int, default=2)
    p.add_argument("--seed", type=int, default=1)
    p.add_argument("--rate", type=float, default=0.25, help="share of play decisions kept")
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
        jobs.append((cmd, out / f"b{args.seed:04d}_{k}.npz", args.rate, seed))
    with mp.Pool(args.shards) as pool:
        n = pool.starmap(stream, jobs)
    print(f"{sum(n)} positions written to {out}")


if __name__ == "__main__":
    main()
