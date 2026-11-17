#!/usr/bin/env python3
"""Rollout policy iteration for the play net (the loop that produced v4).

Each iteration improves the current best play policy by one exact
policy-improvement step:

  1. Data. The best bot plays (a) against the heuristic variants in
     ``--opponents`` and the fixed nets in ``--opponent-nets`` (both
     seatings) and (b) against itself. For a sampled
     share of its play decisions the round is forked once per legal action
     and played out (``headless --rollout-rate``), which gives the exact
     round result of every legal action on that deal.
  2. Train. ``rollout_train.py`` regresses the net on those values as
     per-decision advantages, starting from the best net and using the data
     of *all* iterations so far (more data beat fresher data in every test).
  3. Gate. The candidate must beat the best net in a duplicate duel
     (``duel.py``) by more than ``--promote-z`` standard errors; it is also
     measured against the heuristic.

Everything is written to ``--out-dir`` and every step is skipped when its
output already exists, so the loop can simply be restarted after a crash.

  rl/.venv/bin/python rl/rollout_loop.py --iterations=3 \
      --init-policy=assets/bots/tichu_q_v5.safetensors
"""

from __future__ import annotations

import argparse
import json
import shlex
import shutil
import subprocess
import sys
import time
from pathlib import Path

from duel import duel
from headless_runner import run_headless_sharded

RL = Path(__file__).resolve().parent
SCHUPF = "assets/bots/tichu_schupf_v2.safetensors"


def generate(out: Path, *, seed: int, episodes: int, shards: int, args: list[str]) -> None:
    """One sharded rollout-labelled run, converted to an npz cache."""
    if out.exists():
        return
    jsonl = out.with_suffix(".jsonl")
    t0 = time.time()
    run_headless_sharded(
        base_args=["--format=bc-jsonl", *args],
        seed=seed,
        episodes=episodes,
        output_path=jsonl,
        shards=shards,
    )
    from rollout_train import load, save_npz

    data = load([jsonl])
    tmp = out.with_suffix(".tmp.npz")
    save_npz(data, tmp)
    tmp.rename(out)
    jsonl.unlink()
    print(f"   {out.name}: {data.num_decisions} decisions ({time.time() - t0:.0f}s)", flush=True)


def main() -> None:
    p = argparse.ArgumentParser(description="Rollout policy iteration for the play net")
    p.add_argument("--iterations", type=int, default=3)
    p.add_argument("--out-dir", default=str(RL / "outputs" / "rollout_loop"))
    p.add_argument("--init-policy", default="assets/bots/tichu_q_v5.safetensors")
    p.add_argument("--mixed-episodes", type=int, default=800, help="matches vs the heuristic per iteration")
    p.add_argument("--self-episodes", type=int, default=200, help="self-play matches per iteration")
    p.add_argument(
        "--opponents",
        default="latest",
        help="heuristic specs for the mixed games, separated by ';' (matches are split evenly)",
    )
    p.add_argument(
        "--opponent-nets",
        default="",
        help="fixed play nets to train and measure against, separated by ';' "
        "(share --mixed-episodes with the heuristic opponents)",
    )
    p.add_argument(
        "--schupf-net",
        default=SCHUPF,
        help="schupf net of the learner in every game and duel ('' = heuristic schupf); "
        "the play net is trained for the exchange it actually plays with",
    )
    p.add_argument(
        "--opponent-schupf-net",
        default=SCHUPF,
        help="schupf net of the --opponent-nets team ('' = heuristic schupf)",
    )
    p.add_argument(
        "--train-args",
        default="--ema=0.999",
        help="extra rollout_train.py arguments (the epoch with the best held-out "
        "gain is kept; the labels are noisy and later epochs overfit)",
    )
    p.add_argument("--rollout-rate", type=float, default=0.5)
    p.add_argument("--epsilon", type=float, default=0.02)
    p.add_argument("--target-score", type=int, default=1000)
    p.add_argument("--epochs", type=int, default=4)
    p.add_argument("--lr", type=float, default=3e-4)
    p.add_argument("--window", type=int, default=0, help="train on the last N iterations (0 = all)")
    p.add_argument("--duel-deals", type=int, default=1000)
    p.add_argument("--promote-z", type=float, default=2.0)
    p.add_argument("--shards", type=int, default=4)
    p.add_argument("--seed", type=int, default=100_000)
    args = p.parse_args()

    out = Path(args.out_dir)
    data_dir, nets = out / "data", out / "nets"
    data_dir.mkdir(parents=True, exist_ok=True)
    nets.mkdir(parents=True, exist_ok=True)
    best = out / "best.safetensors"
    if not best.exists():
        shutil.copy2(args.init_policy, best)
    history_path = out / "history.json"
    history = json.loads(history_path.read_text()) if history_path.exists() else []
    start = 1 + max((h["iter"] for h in history), default=0)
    opponents = [o for o in args.opponents.split(";") if o]
    opponent_nets = [o for o in args.opponent_nets.split(";") if o]
    own_schupf = [f"--schupf-net={args.schupf_net}"] if args.schupf_net else []
    opp_schupf = [f"--opponent-schupf-net={args.opponent_schupf_net}"] if args.opponent_schupf_net else []
    # The candidate and the best net play the duel with the same schupf.
    best_schupf = [f"--opponent-schupf-net={args.schupf_net}"] if args.schupf_net else []

    for it in range(start, start + args.iterations):
        t0 = time.time()
        print(f"\n=== iteration {it} ===\n1) rollout data from {best}", flush=True)
        common = [
            f"--target-score={args.target_score}",
            f"--rollout-rate={args.rollout_rate}",
            f"--epsilon={args.epsilon}",
            f"--nn-policy={best}",
            *own_schupf,
        ]
        seed = args.seed + 10_000 * it
        per = max(1, args.mixed_episodes // (2 * max(1, len(opponents) + len(opponent_nets))))
        for i, net in enumerate(opponent_nets):
            for swap in (False, True):
                generate(
                    data_dir / f"it{it:02d}_net{i}{'b' if swap else 'a'}.npz",
                    seed=seed + 2000 + 100 * i + int(swap),
                    episodes=per,
                    shards=args.shards,
                    args=common
                    + ["--mixed", f"--opponent-policy={net}", *opp_schupf]
                    + (["--swap-teams"] if swap else []),
                )
        for i, spec in enumerate(opponents):
            for swap in (False, True):
                generate(
                    data_dir / f"it{it:02d}_mix{i}{'b' if swap else 'a'}.npz",
                    seed=seed + 100 * i + int(swap),
                    episodes=per,
                    shards=args.shards,
                    args=common
                    + ["--mixed", f"--opponent-heuristic={spec}"]
                    + (["--swap-teams"] if swap else []),
                )
        if args.self_episodes > 0:
            generate(
                data_dir / f"it{it:02d}_self.npz",
                seed=seed + 5000,
                episodes=args.self_episodes,
                shards=args.shards,
                args=common,
            )

        print("2) train", flush=True)
        files = sorted(data_dir.glob("*.npz"))
        if args.window > 0:
            keep = {f"it{k:02d}" for k in range(it - args.window + 1, it + 1)}
            files = [f for f in files if f.name[:4] in keep]
        cand = nets / f"it{it:02d}.safetensors"
        res = None if cand.exists() else subprocess.run(
            [
                sys.executable,
                str(RL / "rollout_train.py"),
                "--jsonl=" + ",".join(str(f) for f in files),
                f"--init-from={best}",
                f"--output={cand}",
                f"--epochs={args.epochs}",
                f"--lr={args.lr}",
                *shlex.split(args.train_args),
            ],
            cwd=RL.parent,
            capture_output=True,
            text=True,
        )
        if res is None:
            print(f"   {cand.name} already trained", flush=True)
        elif res.returncode != 0:
            cand.unlink(missing_ok=True)
            raise RuntimeError(res.stdout + res.stderr)
        else:
            print("   " + res.stdout.strip().splitlines()[-1], flush=True)

        print("3) duels", flush=True)
        vs_best = duel(
            [f"--nn-policy={cand}", *own_schupf],
            [f"--opponent-policy={best}", *best_schupf],
            deals=args.duel_deals,
            seed=4242 + it,
            shards=args.shards,
        )
        promoted = vs_best["win_rate"] - 50 > args.promote_z * vs_best["win_rate_se"]
        print(
            f"   vs best: {vs_best['win_rate']:.1f}% ± {vs_best['win_rate_se']:.1f} "
            f"-> {'PROMOTED' if promoted else 'rejected'}",
            flush=True,
        )
        entry = {"iter": it, "vs_best": vs_best, "promoted": promoted, "data_files": len(files)}
        for spec in opponents:
            r = duel(
                [f"--nn-policy={cand}", *own_schupf],
                [f"--opponent-heuristic={spec}"],
                deals=args.duel_deals,
                seed=4242,
                shards=args.shards,
            )
            entry[f"vs_heuristic[{spec}]"] = r
            print(
                f"   vs heuristic [{spec}]: {r['win_rate']:.1f}% ± {r['win_rate_se']:.1f} "
                f"margin {r['margin']:+.0f}",
                flush=True,
            )
        for net in opponent_nets:
            r = duel(
                [f"--nn-policy={cand}", *own_schupf],
                [f"--opponent-policy={net}", *opp_schupf],
                deals=args.duel_deals,
                seed=4242,
                shards=args.shards,
            )
            entry[f"vs_net[{Path(net).stem}]"] = r
            print(
                f"   vs {Path(net).stem}: {r['win_rate']:.1f}% ± {r['win_rate_se']:.1f} "
                f"margin {r['margin']:+.0f}",
                flush=True,
            )
        if promoted:
            shutil.copy2(cand, best)
        entry["seconds"] = time.time() - t0
        history.append(entry)
        history_path.write_text(json.dumps(history, indent=2))

    print(f"\nbest policy: {best}")


if __name__ == "__main__":
    main()
