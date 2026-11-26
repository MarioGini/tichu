#!/usr/bin/env python3
"""Rollout-data worker for another machine (e.g. a second cloud session).

Generates the same rollout-labelled data as ``rollout_loop.py`` for the
iteration the loop has published (``--publish-run``: the current best net,
its schupf net, the opponent nets and ``job.json``) and uploads every chunk
to the loop's data run, which the loop downloads before training
(``--sync-run``). It refreshes the job before each chunk, so a promotion
reaches the workers within one chunk. Chunks are small and self-contained:
the worker can be killed and restarted at any time.

  dart compile exe lib/headless/headless.dart -o build/bin/headless
  rl/.venv/bin/python rl/data_worker.py --worker=1 --hours=1.9

The Supabase secret key must be available (network secret or
SUPABASE_SECRET_KEY), as for ``training_data_store.py``.
"""

from __future__ import annotations

import argparse
import json
import random
import sys
import time
from pathlib import Path

RL = Path(__file__).resolve().parent
sys.path.insert(0, str(RL))

from rollout_loop import generate, last_generated, upload  # noqa: E402
from training_data_store import download  # noqa: E402


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    p.add_argument("--worker", type=int, required=True, help="worker id (part of the file names)")
    p.add_argument("--job-run", default="v10_job", help="store run the loop publishes to")
    p.add_argument("--data-run", default="v10", help="store run the data goes to")
    p.add_argument("--hours", type=float, default=1.9, help="stop after this long (no new chunk is started)")
    p.add_argument("--mixed-episodes", type=int, default=100, help="matches per chunk against an opponent net")
    p.add_argument("--self-episodes", type=int, default=250, help="matches per self-play chunk")
    p.add_argument("--shards", type=int, default=4)
    p.add_argument("--work-dir", default=str(RL / "outputs" / "worker"))
    args = p.parse_args()

    work = Path(args.work_dir)
    nets, data = work / "nets", work / "data"
    data.mkdir(parents=True, exist_ok=True)
    rng = random.SystemRandom()
    deadline = time.time() + 3600 * args.hours
    cycle = 0
    while time.time() < deadline:
        download(args.job_run, nets, refresh=True)
        job = json.loads((nets / "job.json").read_text())
        it = int(job["iteration"])
        kinds = [(i, swap) for i in range(len(job["opponents"])) for swap in (False, True)] + [None]
        kind = kinds[cycle % len(kinds)]
        cycle += 1
        common = [f"--nn-policy={nets / 'best.safetensors'}", *job["args"]]
        if job["schupf"]:
            common.append(f"--schupf-net={nets / job['schupf']}")
        tag = f"w{args.worker}x{int(time.time()) % 10**8:08d}"
        if kind is None:
            out = data / f"it{it:02d}_{tag}_self.npz"
            extra, episodes = [], args.self_episodes
        else:
            i, swap = kind
            out = data / f"it{it:02d}_{tag}_net{i}{'b' if swap else 'a'}.npz"
            extra = ["--mixed", f"--opponent-policy={nets / job['opponents'][i]}"]
            if job["opponent_schupf"]:
                extra.append(f"--opponent-schupf-net={nets / job['opponent_schupf']}")
            if swap:
                extra.append("--swap-teams")
            episodes = args.mixed_episodes
        # Random seeds: distinct from the loop's (100k + 10k * it + ...) and
        # from other workers' with overwhelming probability.
        generate(out, seed=rng.randrange(10**8, 2 * 10**9), episodes=episodes, shards=args.shards, args=common + extra)
        if not upload(last_generated[0], args.data_run, nets / "best.safetensors"):
            continue  # kept on disk; a later run of the store tool can upload it
        for f in (out, out.with_suffix(".games.jsonl.xz")):
            f.unlink(missing_ok=True)  # stored; the worker's disk stays small


if __name__ == "__main__":
    main()
