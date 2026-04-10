#!/usr/bin/env python3
"""Iterative self-play loop with safetensors-only persisted artifacts.

Per iteration:
  1) Generate a fresh training dataset (.safetensors).
  2) Merge all datasets accumulated so far into one combined dataset.
  3) Train a policy from the combined dataset.
  4) Evaluate policy vs heuristic and save compact eval summary (.safetensors).
"""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
import time
from pathlib import Path

import torch
from safetensors import safe_open

from data import load_training_tensors_safetensors, save_training_tensors_safetensors


REPO = Path(__file__).resolve().parent.parent
RL_DIR = Path(__file__).resolve().parent
OUTPUTS = RL_DIR / "outputs"


def run(cmd: list[str], label: str = "") -> subprocess.CompletedProcess:
    if label:
        print(f"  [{label}] {' '.join(cmd[:6])}...", flush=True)
    result = subprocess.run(
        cmd,
        cwd=str(REPO),
        capture_output=True,
        text=True,
        shell=(sys.platform == "win32"),
    )
    if result.returncode != 0:
        raise RuntimeError(
            f"{label or 'command'} failed\n"
            f"stdout:\n{result.stdout}\n"
            f"stderr:\n{result.stderr}"
        )
    return result


def generate_dataset(
    *,
    seed: int,
    episodes: int,
    target_score: int,
    gamma: float,
    output_dataset: Path,
    nn_policy: Path | None,
    epsilon: float,
) -> int:
    cmd = [
        sys.executable,
        str(RL_DIR / "generate_train_dataset.py"),
        f"--output={output_dataset}",
        f"--seed={seed}",
        f"--episodes={episodes}",
        f"--target-score={target_score}",
        f"--gamma={gamma}",
    ]
    if nn_policy and nn_policy.exists():
        cmd.append("--mixed")
        cmd.append(f"--nn-policy={nn_policy}")
    if epsilon > 0:
        cmd.append(f"--epsilon={epsilon}")

    run(cmd, label="generate")

    with safe_open(str(output_dataset), framework="pt", device="cpu") as reader:
        samples = int((reader.metadata() or {}).get("samples", "0"))
    return samples


def merge_datasets(inputs: list[Path], output_path: Path) -> int:
    if not inputs:
        return 0

    feature_tensors: list[torch.Tensor] = []
    return_tensors: list[torch.Tensor] = []
    for path in inputs:
        features, returns, _ = load_training_tensors_safetensors(path)
        feature_tensors.append(features)
        return_tensors.append(returns)

    merged_features = torch.cat(feature_tensors, dim=0).cpu().numpy()
    merged_returns = torch.cat(return_tensors, dim=0).cpu().numpy()

    save_training_tensors_safetensors(
        features=merged_features,
        returns=merged_returns,
        output_path=output_path,
        metadata={
            "format": "tichu_train_dataset_v1",
            "merged_sources": str(len(inputs)),
        },
    )
    return int(merged_features.shape[0])


def train_policy(
    *,
    dataset_path: Path,
    output_policy: Path,
    epochs: int,
    hidden: str,
    lr: float,
    batch_size: int,
) -> str:
    cmd = [
        sys.executable,
        str(RL_DIR / "train.py"),
        f"--input={dataset_path}",
        f"--output={output_policy}",
        f"--epochs={epochs}",
        f"--hidden={hidden}",
        f"--lr={lr}",
        f"--batch-size={batch_size}",
    ]
    result = run(cmd, label="train")
    for line in reversed(result.stdout.splitlines()):
        if "val_loss" in line:
            return line.strip()
    return "training complete"


def evaluate_policy(
    *,
    policy_path: Path,
    output_eval: Path,
    seed: int,
    episodes: int,
    target_score: int,
) -> dict[str, float]:
    cmd = [
        sys.executable,
        str(RL_DIR / "evaluate_policy.py"),
        f"--nn-policy={policy_path}",
        f"--output={output_eval}",
        f"--seed={seed}",
        f"--episodes={episodes}",
        f"--target-score={target_score}",
    ]
    run(cmd, label="evaluate")

    with safe_open(str(output_eval), framework="pt", device="cpu") as reader:
        meta = reader.metadata() or {}
    return {
        "matches": float(meta.get("matches", "0")),
        "team0_wins": float(meta.get("team0_wins", "0")),
        "team1_wins": float(meta.get("team1_wins", "0")),
        "ties": float(meta.get("ties", "0")),
        "win_rate": float(meta.get("team0_win_rate_non_tie", "0")),
        "avg_margin": float(meta.get("avg_margin_t0_minus_t1", "0")),
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="Iterative safetensors RL loop")
    parser.add_argument("--iterations", type=int, default=3)
    parser.add_argument("--episodes", type=int, default=500)
    parser.add_argument("--eval-episodes", type=int, default=100)
    parser.add_argument("--epochs", type=int, default=100)
    parser.add_argument("--hidden", default="256,128,64")
    parser.add_argument("--lr", type=float, default=0.001)
    parser.add_argument("--batch-size", type=int, default=256)
    parser.add_argument("--epsilon", type=float, default=0.1)
    parser.add_argument("--gamma", type=float, default=0.99)
    parser.add_argument("--base-seed", type=int, default=1000)
    parser.add_argument("--eval-seed", type=int, default=7777)
    parser.add_argument("--train-target-score", type=int, default=100)
    parser.add_argument("--eval-target-score", type=int, default=1000)
    parser.add_argument("--bootstrap", default="", help="Optional .safetensors dataset")
    args = parser.parse_args()

    OUTPUTS.mkdir(parents=True, exist_ok=True)
    policy_path = OUTPUTS / "nn_iter.safetensors"
    best_policy = OUTPUTS / "nn_policy_best.safetensors"

    datasets: list[Path] = []
    if args.bootstrap:
        bootstrap_path = Path(args.bootstrap)
        if bootstrap_path.exists() and bootstrap_path.suffix.lower() == ".safetensors":
            datasets.append(bootstrap_path)
            print(f"Bootstrapping from {bootstrap_path}", flush=True)

    best_win_rate = -1.0

    for i in range(args.iterations):
        start = time.time()
        print(f"\n{'='*60}")
        print(f"ITERATION {i+1}/{args.iterations}")
        print(f"{'='*60}")

        iter_dataset = OUTPUTS / f"train_iter{i}.safetensors"
        seed = args.base_seed + i * 100
        epsilon = args.epsilon if i > 0 else 0.0
        current_policy = policy_path if policy_path.exists() else None

        print(f"\n1) Generate dataset (seed={seed}, episodes={args.episodes}, eps={epsilon})")
        sample_count = generate_dataset(
            seed=seed,
            episodes=args.episodes,
            target_score=args.train_target_score,
            gamma=args.gamma,
            output_dataset=iter_dataset,
            nn_policy=current_policy,
            epsilon=epsilon,
        )
        print(f"   -> samples={sample_count}")
        datasets.append(iter_dataset)

        combined_dataset = OUTPUTS / "combined_train.safetensors"
        print(f"\n2) Merge datasets ({len(datasets)} sources)")
        total_samples = merge_datasets(datasets, combined_dataset)
        print(f"   -> total_samples={total_samples}")

        print(f"\n3) Train policy (epochs={args.epochs}, hidden={args.hidden})")
        train_summary = train_policy(
            dataset_path=combined_dataset,
            output_policy=policy_path,
            epochs=args.epochs,
            hidden=args.hidden,
            lr=args.lr,
            batch_size=args.batch_size,
        )
        print(f"   -> {train_summary}")

        eval_output = OUTPUTS / "eval_iter.safetensors"
        print(f"\n4) Evaluate policy ({args.eval_episodes} episodes @ target={args.eval_target_score})")
        metrics = evaluate_policy(
            policy_path=policy_path,
            output_eval=eval_output,
            seed=args.eval_seed,
            episodes=args.eval_episodes,
            target_score=args.eval_target_score,
        )
        print(
            "   -> "
            f"wins={int(metrics['team0_wins'])}/{int(metrics['matches'])} "
            f"ties={int(metrics['ties'])} "
            f"win_rate={metrics['win_rate']:.2f}% "
            f"avg_margin={metrics['avg_margin']:.2f}"
        )

        if metrics["win_rate"] > best_win_rate:
            best_win_rate = metrics["win_rate"]
            shutil.copy2(policy_path, best_policy)
            print(f"   * new best saved: {best_policy.name}")

        print(f"\nIteration time: {time.time() - start:.0f}s")

    print(f"\nDONE. Best win rate: {best_win_rate:.2f}%")
    if best_policy.exists():
        print(f"Best policy: {best_policy}")


if __name__ == "__main__":
    main()
