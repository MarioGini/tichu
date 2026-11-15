#!/usr/bin/env python3
"""Joint training loop for the full bot (calls, schupf, play).

Each iteration:
  1. Decision data: the current bot plays itself with exploration of every
     decision kind — Grand Tichu / pre-schupf Tichu / Tichu calls
     (``--call-epsilon``), schupf (``--schupf-epsilon``), plays (``--epsilon``).
     Call/schupf rows come from a lean run (``--skip-play-rows``); play rows
     from a smaller full run.
  2. Train candidates on that data: call nets (call_train.py), schupf net
     (schupf_train.py), play policy (awr_train.py, warm-started from best).
  3. Evaluate vs the heuristic (duplicate, target 1000): each component
     group (play, calls, schupf) is tried on top of the current best and
     promoted only on a significant paired gain.

Because all components are retrained on data produced by the *current*
bot, they adapt to each other — e.g. the schupf net sees partners that
announce Tichu before the exchange and learns what to pass them.

  rl/.venv/bin/python rl/train_loop.py --iterations=5
"""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

from evaluate_policy import compare_evals, evaluate
from headless_runner import run_headless_sharded

RL = Path(__file__).resolve().parent
OUT = RL / "outputs"
# Component groups promoted independently (the value net follows the policy).
# Each entry: candidate file -> file name in the bot directory.
GROUPS = {
    "play": {"best_policy.safetensors": "best_policy.safetensors",
             "value.safetensors": "value.safetensors"},
    # DouZero-style Monte-Carlo Q step (with oracle baseline) as an
    # alternative play learner.
    "play_q": {"q_policy.safetensors": "best_policy.safetensors"},
    "calls": {n: n for n in ("tichu_net.safetensors", "grand_net.safetensors",
                             "pre_net.safetensors")},
    "schupf": {"schupf_net.safetensors": "schupf_net.safetensors"},
}
COMPONENTS = {
    # file name: headless flag
    "best_policy.safetensors": "--nn-policy",
    "tichu_net.safetensors": "--tichu-net",
    "grand_net.safetensors": "--grand-net",
    "pre_net.safetensors": "--pre-tichu-net",
    "schupf_net.safetensors": "--schupf-net",
}


def bot_args(directory: Path) -> list[str]:
    return [
        f"{flag}={directory / name}"
        for name, flag in COMPONENTS.items()
        if (directory / name).exists()
    ]


def run(cmd: list[str]) -> str:
    print("   $", " ".join(c if len(c) < 60 else "…" + c[-50:] for c in cmd[1:4]), flush=True)
    res = subprocess.run(cmd, cwd=RL.parent, capture_output=True, text=True)
    if res.returncode != 0:
        raise RuntimeError(f"failed: {cmd}\n{res.stdout}\n{res.stderr}")
    return res.stdout


def evaluate_bot(directory: Path, out: Path, args: argparse.Namespace) -> dict:
    extra = bot_args(directory)
    policy = next(a.split("=", 1)[1] for a in extra if a.startswith("--nn-policy="))
    return evaluate(
        nn_policy=policy,
        output=out,
        seed=args.eval_seed,
        episodes=args.eval_episodes,
        target_score=args.eval_target_score,
        shards=args.shards,
        extra=[a for a in extra if not a.startswith("--nn-policy=")],
    )


def main() -> None:
    p = argparse.ArgumentParser(description="Joint call / schupf / play training loop")
    p.add_argument("--iterations", type=int, default=5)
    p.add_argument("--call-episodes", type=int, default=3000)
    p.add_argument("--play-episodes", type=int, default=600)
    p.add_argument("--target-score", type=int, default=500)
    p.add_argument("--call-epsilon", type=float, default=0.15)
    p.add_argument("--schupf-epsilon", type=float, default=0.3)
    p.add_argument("--epsilon", type=float, default=0.05)
    p.add_argument("--eval-episodes", type=int, default=100)
    p.add_argument("--eval-target-score", type=int, default=1000)
    p.add_argument("--eval-seed", type=int, default=12345)
    p.add_argument("--promote-z", type=float, default=1.0)
    p.add_argument("--awr-epochs", type=int, default=6)
    p.add_argument("--no-q", dest="q", action="store_false", help="Skip the Q-learning candidate")
    p.add_argument("--shards", type=int, default=0)
    p.add_argument("--seed", type=int, default=50000)
    p.add_argument("--out-dir", default=str(OUT))
    p.add_argument("--init-policy", default=str(OUT / "best_policy.safetensors"))
    p.add_argument("--init-value", default=str(OUT / "value_policy.safetensors"))
    args = p.parse_args()

    out_dir = Path(args.out_dir)
    best = out_dir / "bot_best"
    best.mkdir(parents=True, exist_ok=True)
    if not (best / "best_policy.safetensors").exists():
        shutil.copy2(args.init_policy, best / "best_policy.safetensors")
    if Path(args.init_value).exists() and not (best / "value.safetensors").exists():
        shutil.copy2(args.init_value, best / "value.safetensors")
    history_path = out_dir / "train_loop_history.json"
    history = json.loads(history_path.read_text()) if history_path.exists() else []

    best_eval = out_dir / "eval_bot_best.safetensors"
    m = evaluate_bot(best, best_eval, args)
    print(f"start: win {m['win_rate']:.1f}% ± {m['win_rate_se']:.1f}  margin {m['avg_margin']:.0f}", flush=True)
    py = sys.executable

    for it in range(1, args.iterations + 1):
        t0 = time.time()
        print(f"\n=== iteration {it} ===", flush=True)
        with tempfile.TemporaryDirectory(prefix="tichu_loop_") as td:
            td = Path(td)
            cand = td / "cand"
            shutil.copytree(best, cand)
            seed = args.seed + 1000 * it
            common = [f"--target-score={args.target_score}", "--format=bc-jsonl", *bot_args(best)]

            print("1) data", flush=True)
            calls = td / "calls.jsonl"
            run_headless_sharded(
                base_args=common + [
                    f"--call-epsilon={args.call_epsilon}",
                    f"--schupf-epsilon={args.schupf_epsilon}",
                    "--skip-play-rows",
                ],
                seed=seed, episodes=args.call_episodes, output_path=calls,
                shards=args.shards or None,
            )
            plays = td / "plays.jsonl"
            run_headless_sharded(
                base_args=common + [f"--epsilon={args.epsilon}"],
                seed=seed + 1, episodes=args.play_episodes, output_path=plays,
                shards=args.shards or None,
            )

            print("2) train", flush=True)
            out = run([py, str(RL / "call_train.py"), f"--jsonl={calls}", f"--output-dir={cand}",
                       "--kind=all"])
            for line in out.splitlines():
                if "worth" in line or "would call" in line:
                    print("  ", line.strip())
            out = run([py, str(RL / "schupf_train.py"), f"--jsonl={calls}",
                       f"--output={cand / 'schupf_net.safetensors'}"])
            print("  ", out.strip().splitlines()[-2].strip())
            out = run([py, str(RL / "awr_train.py"), f"--jsonl={plays}",
                       f"--output={cand / 'best_policy.safetensors'}",
                       f"--init-from={best / 'best_policy.safetensors'}",
                       f"--epochs={args.awr_epochs}",
                       f"--value-init={best / 'value.safetensors'}",
                       f"--value-output={cand / 'value.safetensors'}"])
            for line in out.splitlines():
                if line.startswith("  value:") or "oracle baseline" in line:
                    print("  ", line.strip())
            if args.q:
                out = run([py, str(RL / "q_train.py"), f"--jsonl={plays}",
                           f"--init-from={best / 'best_policy.safetensors'}",
                           f"--output={cand / 'q_policy.safetensors'}"])
                for line in out.splitlines():
                    if "oracle baseline" in line or "epoch" in line:
                        print("  ", line.strip())

            print("3) evaluate (each component group on top of the current best)", flush=True)
            results = {}
            for group, names in GROUPS.items():
                trial = td / f"trial_{group}"
                shutil.copytree(best, trial)
                if not any((cand / src).exists() for src in names):
                    continue
                for src, dst in names.items():
                    if (cand / src).exists():
                        shutil.copy2(cand / src, trial / dst)
                trial_eval = td / f"eval_{group}.safetensors"
                m = evaluate_bot(trial, trial_eval, args)
                diff, se = compare_evals(trial_eval, best_eval)
                promoted = diff > 0 and diff > args.promote_z * se
                print(
                    f"   {group:7s}: win {m['win_rate']:.1f}% ± {m['win_rate_se']:.1f}  "
                    f"margin {m['avg_margin']:.0f}  vs best {diff:+.1f} ± {se:.1f} pp"
                    f"  -> {'PROMOTED' if promoted else 'rejected'}",
                    flush=True,
                )
                if promoted:
                    shutil.rmtree(best)
                    shutil.copytree(trial, best)
                    shutil.copy2(trial_eval, best_eval)
                results[group] = {**m, "diff": diff, "diff_se": se, "promoted": promoted}
            history.append({"iter": it, "groups": results, "seconds": time.time() - t0})
            history_path.write_text(json.dumps(history, indent=2))

    print(f"\nbest bot: {best}  ({' '.join(bot_args(best))})")


if __name__ == "__main__":
    main()
