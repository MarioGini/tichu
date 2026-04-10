#!/usr/bin/env python3
"""Generate a safetensors training dataset from headless self-play.

This command persists only .safetensors output. Any intermediate transition log
is created in the OS temp directory and deleted after packing.
"""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from data import build_training_tensors_from_jsonl, save_training_tensors_safetensors


REPO = Path(__file__).resolve().parent.parent


def _ensure_dart_on_path() -> None:
    dart = shutil.which("dart") or shutil.which("dart.bat")
    if dart:
        return
    for candidate in [Path(r"C:\flutter\flutter\bin"), Path.home() / "flutter" / "bin"]:
        if (candidate / "dart").exists() or (candidate / "dart.bat").exists():
            os.environ["PATH"] = str(candidate) + os.pathsep + os.environ.get("PATH", "")
            return
    raise RuntimeError("'dart' not found on PATH")


def _run(cmd: list[str]) -> subprocess.CompletedProcess:
    return subprocess.run(
        cmd,
        cwd=str(REPO),
        capture_output=True,
        text=True,
        shell=(sys.platform == "win32"),
    )


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate safetensors train dataset")
    parser.add_argument("--output", required=True, help="Output .safetensors dataset path")
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--episodes", type=int, default=500)
    parser.add_argument("--target-score", type=int, default=100)
    parser.add_argument("--gamma", type=float, default=0.99)
    parser.add_argument("--epsilon", type=float, default=0.0)
    parser.add_argument("--mixed", action="store_true")
    parser.add_argument("--nn-policy", default="", help="Optional policy for mixed generation")
    args = parser.parse_args()

    _ensure_dart_on_path()

    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory(prefix="tichu_rl_") as td:
        temp_jsonl = Path(td) / "transitions.jsonl"

        cmd = [
            "dart", "run", "lib/headless/headless.dart",
            f"--seed={args.seed}",
            f"--target-score={args.target_score}",
            f"--episodes={args.episodes}",
            "--format=rl-jsonl",
            f"--output={temp_jsonl}",
        ]
        if args.mixed:
            cmd.append("--mixed")
        if args.nn_policy:
            cmd.append(f"--nn-policy={args.nn_policy}")
        if args.epsilon > 0:
            cmd.append(f"--epsilon={args.epsilon}")

        result = _run(cmd)
        if result.returncode != 0:
            raise RuntimeError(
                "Headless generation failed\n"
                f"stdout:\n{result.stdout}\n"
                f"stderr:\n{result.stderr}"
            )

        features, returns, metadata = build_training_tensors_from_jsonl(
            temp_jsonl,
            gamma=args.gamma,
        )
        save_training_tensors_safetensors(
            features=features,
            returns=returns,
            output_path=output_path,
            metadata=metadata,
        )

        print(f"Saved dataset: {output_path}")
        print(f"  samples={features.shape[0]} features={features.shape[1]}")


if __name__ == "__main__":
    main()
