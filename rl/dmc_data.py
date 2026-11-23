#!/usr/bin/env python3
"""Cheap Monte-Carlo labels at scale (DouZero-style "deep Monte Carlo").

Plays self-play matches with the headless runner and keeps, for every play
decision, only the state, the chosen action and the round result that
followed for the deciding team (round point difference / 100). No rollouts:
one match gives a label for every decision, ~30x more labelled decisions
per CPU second than the all-action rollout labels, but each label is the
noisy outcome of one action instead of the exact value of all actions.

The runner's bc-jsonl output is parsed as it streams (it is ~4 KB per
decision) and written as compact npz shards:

  s (N, state) float16   a (N, action) float16   y (N,) float32
  game (N,) int64 (match id, for held-out splits)

  rl/.venv/bin/python rl/dmc_data.py --out-dir=rl/outputs/dmc --shards=4 \\
      --episodes=2000 --args="--nn-policy=... --schupf-net=... --epsilon=0.05"
"""

from __future__ import annotations

import argparse
import json
import os
import shlex
import subprocess
import sys
import multiprocessing as mp
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))

from schema import pad_action, pad_state  # noqa: E402

SCALE = 100.0


def stream(cmd: list[str], out_prefix: Path, shard_size: int, game_offset: int) -> int:
    """Run one runner process; write shards ``<prefix>_NNN.npz``."""
    p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, bufsize=1 << 20)
    assert p.stdout is not None
    ss, aa, yy, gg = [], [], [], []
    pending: list[tuple] = []  # decisions of the current round: (team, s, a, game)
    written = 0
    shard = 0

    def flush(final: bool = False) -> None:
        nonlocal ss, aa, yy, gg, shard
        if not ss or (not final and len(ss) < shard_size):
            return
        path = Path(f"{out_prefix}_{shard:03d}.npz")
        tmp = path.with_suffix(".tmp.npz")
        np.savez_compressed(
            tmp,
            s=pad_state(np.stack(ss)),
            a=pad_action(np.stack(aa)),
            y=np.asarray(yy, np.float32),
            game=np.asarray(gg, np.int64),
        )
        tmp.rename(path)
        shard += 1
        ss, aa, yy, gg = [], [], [], []

    for line in p.stdout:
        if line.startswith('{"episode"') and '"round_end"' in line[:60]:
            r = json.loads(line)
            diff = r["team_one_round"] - r["team_two_round"]
            for team, s, a, g in pending:
                ss.append(s)
                aa.append(a)
                yy.append((diff if team == 0 else -diff) / SCALE)
                gg.append(g)
            written += len(pending)
            pending = []
            flush()
            continue
        if '"legal_play_chosen_index"' not in line:
            continue
        r = json.loads(line)
        i = r["legal_play_chosen_index"]
        feats = r["legal_play_action_features"]
        if not 0 <= i < len(feats) or len(feats) < 2:
            continue  # forced moves teach nothing
        pending.append((
            r["team"],
            np.asarray(r["state_features"], np.float16),
            np.asarray(feats[i], np.float16),
            game_offset + int(r["episode"]),
        ))
    p.wait()
    flush(final=True)
    return written


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--out-dir", required=True)
    p.add_argument("--episodes", type=int, default=1000, help="matches per shard process")
    p.add_argument("--shards", type=int, default=4, help="parallel runner processes")
    p.add_argument("--seed", type=int, default=1)
    p.add_argument("--shard-size", type=int, default=400_000, help="decisions per npz file")
    p.add_argument("--args", default="", help="headless arguments (policy, schupf, epsilon, opponents)")
    args = p.parse_args()
    out = Path(args.out_dir)
    out.mkdir(parents=True, exist_ok=True)
    binary = os.environ.get("TICHU_HEADLESS", "build/bin/headless")
    jobs = []
    for k in range(args.shards):
        seed = args.seed * 1000 + k
        cmd = [binary, f"--seed={seed}", f"--episodes={args.episodes}", "--format=bc-jsonl",
               "--output=/dev/stdout", *shlex.split(args.args)]
        prefix = out / f"s{args.seed:04d}_{k}"
        jobs.append((cmd, prefix, args.shard_size, seed * 100_000))
    # One process per runner: JSON parsing is the bottleneck (GIL).
    with mp.Pool(args.shards) as pool:
        counts = pool.starmap(stream, jobs)
    print(f"{sum(counts)} decisions written to {out}")


if __name__ == "__main__":
    main()
