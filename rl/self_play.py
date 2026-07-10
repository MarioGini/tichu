#!/usr/bin/env python3
"""Iterative self-play training loop.

Bootstrap: train a behavioural-cloning policy on heuristic-vs-heuristic data
(or load a provided one).

Per iteration:
  1. Generate self-play episodes: team0 = current candidate, team1 = best so
     far. Headless emits per-decision JSONL with legal action features and
     the chosen action index.
  2. Train a new candidate via ``bc_pretrain.py`` on the WON team's
     decisions only, warm-started from the current candidate, with a KL
     anchor that pulls the new policy back toward the previous best to
     prevent catastrophic forgetting.
  3. Evaluate the new candidate vs the heuristic. If it improves on the best
     policy we have so far (by win rate vs heuristic), promote it.

Exit conditions:
  * ``--iterations`` reached, OR
  * ``--target-win-rate`` exceeded for two consecutive iterations.

Artifacts (kept):
  rl/outputs/policy.safetensors          — current candidate
  rl/outputs/best_policy.safetensors     — best-so-far (vs heuristic)
  rl/outputs/self_play_history.json      — eval results per iteration
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

from safetensors import safe_open


REPO = Path(__file__).resolve().parent.parent
RL_DIR = Path(__file__).resolve().parent
OUTPUTS = RL_DIR / "outputs"


def _ensure_dart_on_path() -> None:
    if shutil.which("dart") or shutil.which("dart.bat"):
        return
    for candidate in [Path(r"C:\flutter\flutter\bin"), Path.home() / "flutter" / "bin"]:
        if (candidate / "dart").exists() or (candidate / "dart.bat").exists():
            os.environ["PATH"] = str(candidate) + os.pathsep + os.environ.get("PATH", "")
            return
    raise RuntimeError("'dart' not found on PATH")


def _run(cmd: list[str], label: str) -> subprocess.CompletedProcess:
    print(f"  [{label}] {' '.join(str(c) for c in cmd[:6])}...", flush=True)
    res = subprocess.run(
        cmd,
        cwd=str(REPO),
        capture_output=True,
        text=True,
        shell=(sys.platform == "win32"),
        env={**os.environ, "PYTHONIOENCODING": "utf-8"},
    )
    if res.returncode != 0:
        raise RuntimeError(
            f"{label} failed\nstdout:\n{res.stdout}\nstderr:\n{res.stderr}"
        )
    return res


def _generate_selfplay_jsonl(
    *,
    seed: int,
    episodes: int,
    target_score: int,
    candidate_policy: Path,
    opponent_policy: Path,
    output_jsonl: Path,
    epsilon: float,
    shards: int = 0,
) -> None:
    from headless_runner import run_headless_sharded

    base_args = [
        f"--target-score={target_score}",
        f"--nn-policy={candidate_policy}",
        f"--opponent-policy={opponent_policy}",
        "--format=bc-jsonl",
    ]
    if epsilon > 0:
        base_args.append(f"--epsilon={epsilon}")
    run_headless_sharded(
        base_args=base_args,
        seed=seed,
        episodes=episodes,
        output_path=output_jsonl,
        shards=shards or None,
    )


def _train_candidate(
    *,
    jsonl: Path,
    output: Path,
    init_from: Path,
    anchor: Path | None,
    kl_weight: float,
    epochs: int,
    hidden: str,
    lr: float,
    decisions_per_batch: int,
    seed: int,
    device: str,
    winners_only: bool,
) -> None:
    cmd = [
        sys.executable,
        str(RL_DIR / "bc_pretrain.py"),
        f"--output={output}",
        f"--jsonl={jsonl}",
        f"--init-from={init_from}",
        f"--epochs={epochs}",
        f"--hidden={hidden}",
        f"--lr={lr}",
        f"--decisions-per-batch={decisions_per_batch}",
        f"--seed={seed}",
        f"--device={device}",
    ]
    if winners_only:
        cmd.append("--winners-only")
    if anchor is not None:
        cmd.append(f"--anchor-policy={anchor}")
        cmd.append(f"--kl-weight={kl_weight}")
    _run(cmd, label="train")


def _evaluate(
    *,
    policy: Path,
    output_eval: Path,
    seed: int,
    episodes: int,
    target_score: int,
    shards: int = 0,
) -> dict[str, float]:
    cmd = [
        sys.executable,
        str(RL_DIR / "evaluate_policy.py"),
        f"--nn-policy={policy}",
        f"--output={output_eval}",
        f"--seed={seed}",
        f"--episodes={episodes}",
        f"--target-score={target_score}",
        f"--shards={shards}",
    ]
    _run(cmd, label="eval")
    with safe_open(str(output_eval), framework="pt", device="cpu") as reader:
        meta = reader.metadata() or {}
    return {
        "matches": float(meta.get("matches", 0)),
        "team0_wins": float(meta.get("team0_wins", 0)),
        "team1_wins": float(meta.get("team1_wins", 0)),
        "win_rate": float(meta.get("team0_win_rate_non_tie", 0)),
        "avg_margin": float(meta.get("avg_margin_t0_minus_t1", 0)),
    }


def _bootstrap_bc(
    *,
    output: Path,
    seed: int,
    episodes: int,
    target_score: int,
    epochs: int,
    hidden: str,
    lr: float,
    decisions_per_batch: int,
    device: str,
    shards: int = 0,
) -> None:
    cmd = [
        sys.executable,
        str(RL_DIR / "bc_pretrain.py"),
        f"--output={output}",
        f"--seed={seed}",
        f"--episodes={episodes}",
        f"--target-score={target_score}",
        f"--epochs={epochs}",
        f"--hidden={hidden}",
        f"--lr={lr}",
        f"--decisions-per-batch={decisions_per_batch}",
        f"--device={device}",
        f"--shards={shards}",
    ]
    _run(cmd, label="bootstrap-bc")


def main() -> None:
    p = argparse.ArgumentParser(description="Self-play iterative trainer")
    p.add_argument("--iterations", type=int, default=10)
    p.add_argument(
        "--bootstrap",
        default="",
        help="Existing safetensors policy to start from. If empty, run BC bootstrap.",
    )
    p.add_argument("--bootstrap-episodes", type=int, default=300)
    p.add_argument("--bootstrap-epochs", type=int, default=40)
    p.add_argument(
        "--selfplay-episodes",
        type=int,
        default=200,
        help="Episodes per self-play iteration (candidate vs best)",
    )
    p.add_argument(
        "--epochs",
        type=int,
        default=20,
        help="Epochs per fine-tune",
    )
    p.add_argument(
        "--eval-episodes",
        type=int,
        default=200,
        help="Episodes for evaluation vs heuristic each iteration",
    )
    p.add_argument(
        "--eval-target-score",
        type=int,
        default=500,
    )
    p.add_argument(
        "--selfplay-target-score",
        type=int,
        default=100,
    )
    p.add_argument("--epsilon", type=float, default=0.05)
    p.add_argument("--hidden", default="256,128,64")
    p.add_argument("--lr", type=float, default=2e-4)
    p.add_argument("--decisions-per-batch", type=int, default=512)
    p.add_argument("--kl-weight", type=float, default=0.5)
    p.add_argument("--device", default="cpu", choices=["auto", "cpu", "cuda", "directml"])
    p.add_argument("--base-seed", type=int, default=10000)
    p.add_argument("--eval-seed", type=int, default=12345)
    p.add_argument(
        "--target-win-rate",
        type=float,
        default=55.0,
        help="Stop early after two consecutive iterations exceeding this win rate vs heuristic",
    )
    p.add_argument(
        "--winners-only",
        action="store_true",
        default=True,
        help="Train only on decisions made by the winning team in self-play (default on)",
    )
    p.add_argument("--no-winners-only", dest="winners_only", action="store_false")
    p.add_argument(
        "--shards",
        type=int,
        default=0,
        help="Parallel headless workers (0 = auto = cpu_count - 1)",
    )
    args = p.parse_args()

    _ensure_dart_on_path()
    OUTPUTS.mkdir(parents=True, exist_ok=True)

    candidate_path = OUTPUTS / "policy.safetensors"
    best_path = OUTPUTS / "best_policy.safetensors"
    history_path = OUTPUTS / "self_play_history.json"

    history: list[dict] = []
    if history_path.exists():
        try:
            history = json.loads(history_path.read_text(encoding="utf-8"))
        except Exception:
            history = []

    # Bootstrap.
    if args.bootstrap:
        boot_src = Path(args.bootstrap)
        if not boot_src.exists():
            raise FileNotFoundError(boot_src)
        shutil.copy2(boot_src, candidate_path)
        print(f"Bootstrap: copied {boot_src} -> {candidate_path}")
    elif not candidate_path.exists():
        print(
            f"Bootstrapping BC ({args.bootstrap_episodes} eps, "
            f"{args.bootstrap_epochs} epochs)..."
        )
        _bootstrap_bc(
            output=candidate_path,
            seed=args.base_seed,
            episodes=args.bootstrap_episodes,
            target_score=args.selfplay_target_score,
            epochs=args.bootstrap_epochs,
            hidden=args.hidden,
            lr=1e-3,
            decisions_per_batch=args.decisions_per_batch,
            device=args.device,
            shards=args.shards,
        )
    else:
        print(f"Reusing existing candidate: {candidate_path}")

    # Initial eval to know the starting win rate.
    print("\nInitial eval vs heuristic...")
    initial_eval = _evaluate(
        policy=candidate_path,
        output_eval=OUTPUTS / "eval_initial.safetensors",
        seed=args.eval_seed,
        episodes=args.eval_episodes,
        target_score=args.eval_target_score,
        shards=args.shards,
    )
    print(
        f"  initial: wins={int(initial_eval['team0_wins'])}/{int(initial_eval['matches'])}  "
        f"rate={initial_eval['win_rate']:.2f}%  margin={initial_eval['avg_margin']:.1f}"
    )
    best_win_rate = initial_eval["win_rate"]
    if not best_path.exists():
        shutil.copy2(candidate_path, best_path)
    history.append({"iter": 0, "stage": "initial", **initial_eval})

    consecutive_above = 1 if best_win_rate > args.target_win_rate else 0

    with tempfile.TemporaryDirectory(prefix="tichu_sp_") as td:
        td_path = Path(td)
        for i in range(1, args.iterations + 1):
            t0 = time.time()
            print(f"\n{'='*60}")
            print(f"ITERATION {i}/{args.iterations}  (best vs heuristic: {best_win_rate:.2f}%)")
            print(f"{'='*60}")

            seed_sp = args.base_seed + 100 * i

            # 1) Self-play data: candidate vs best.
            sp_jsonl = td_path / f"selfplay_iter{i}.jsonl"
            print(
                f"\n1) Self-play  seed={seed_sp} eps={args.selfplay_episodes} "
                f"epsilon={args.epsilon}"
            )
            _generate_selfplay_jsonl(
                seed=seed_sp,
                episodes=args.selfplay_episodes,
                target_score=args.selfplay_target_score,
                candidate_policy=candidate_path,
                opponent_policy=best_path,
                output_jsonl=sp_jsonl,
                epsilon=args.epsilon,
                shards=args.shards,
            )

            # 2) Fine-tune candidate from self-play, anchored to best.
            new_candidate = td_path / f"candidate_iter{i}.safetensors"
            print(
                f"\n2) Fine-tune  init_from={candidate_path.name} "
                f"anchor={best_path.name} kl={args.kl_weight} "
                f"winners_only={args.winners_only}"
            )
            _train_candidate(
                jsonl=sp_jsonl,
                output=new_candidate,
                init_from=candidate_path,
                anchor=best_path,
                kl_weight=args.kl_weight,
                epochs=args.epochs,
                hidden=args.hidden,
                lr=args.lr,
                decisions_per_batch=args.decisions_per_batch,
                seed=seed_sp + 7,
                device=args.device,
                winners_only=args.winners_only,
            )

            # 3) Evaluate vs heuristic.
            eval_path = OUTPUTS / "eval_iter.safetensors"
            print(f"\n3) Evaluate vs heuristic ({args.eval_episodes} matches)")
            metrics = _evaluate(
                policy=new_candidate,
                output_eval=eval_path,
                seed=args.eval_seed,
                episodes=args.eval_episodes,
                target_score=args.eval_target_score,
                shards=args.shards,
            )
            print(
                f"   wins={int(metrics['team0_wins'])}/{int(metrics['matches'])}  "
                f"rate={metrics['win_rate']:.2f}%  "
                f"margin={metrics['avg_margin']:.1f}"
            )

            # Always promote the new candidate to "current" so the next
            # iteration's self-play sees the latest learning. Promote to
            # best only if it improves win rate vs heuristic.
            shutil.copy2(new_candidate, candidate_path)
            improved = metrics["win_rate"] > best_win_rate
            if improved:
                shutil.copy2(new_candidate, best_path)
                best_win_rate = metrics["win_rate"]
                print(f"   * NEW BEST: {best_win_rate:.2f}%")

            history.append(
                {
                    "iter": i,
                    "promoted_to_best": improved,
                    **metrics,
                    "elapsed_s": time.time() - t0,
                }
            )
            history_path.write_text(json.dumps(history, indent=2), encoding="utf-8")

            # Early stop on stable improvement.
            if metrics["win_rate"] > args.target_win_rate:
                consecutive_above += 1
                if consecutive_above >= 2:
                    print(
                        f"\nReached target win rate {args.target_win_rate:.1f}% "
                        f"for 2 consecutive iterations. Stopping."
                    )
                    break
            else:
                consecutive_above = 0

    print("\nDONE.")
    print(f"  best win rate: {best_win_rate:.2f}%")
    print(f"  history:       {history_path}")
    print(f"  current:       {candidate_path}")
    print(f"  best policy:   {best_path}")


if __name__ == "__main__":
    main()
