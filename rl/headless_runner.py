"""Shared helpers for invoking the Dart headless runner.

Centralises two performance-critical decisions:

1. Prefer ``build/bin/headless.exe`` (compiled with ``dart compile exe``) over
   ``dart run lib/headless/headless.dart``. The compiled binary skips the
   2.5 s Dart VM cold-start and roughly doubles steady-state throughput.

2. Provide ``run_headless_sharded`` which fans an episode count out across
   multiple processes (one per shard, distinct seed offset) and concatenates
   the per-shard JSONL outputs. Headless is single-threaded, so this is the
   only way to use the box's 8 cores during data generation.
"""

from __future__ import annotations

import os
import shutil
import subprocess
import tempfile
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
COMPILED_EXE = REPO_ROOT / "build" / "bin" / "headless.exe"


def _ensure_dart_on_path() -> None:
    if shutil.which("dart") or shutil.which("dart.bat"):
        return
    for candidate in [Path(r"C:\flutter\flutter\bin"), Path.home() / "flutter" / "bin"]:
        if (candidate / "dart").exists() or (candidate / "dart.bat").exists():
            os.environ["PATH"] = str(candidate) + os.pathsep + os.environ.get("PATH", "")
            return
    raise RuntimeError("'dart' not found on PATH")


def headless_command_prefix() -> list[str]:
    """Return the argv prefix to invoke headless.

    Uses the compiled exe when present; otherwise falls back to ``dart run``.
    """
    if COMPILED_EXE.exists():
        return [str(COMPILED_EXE)]
    _ensure_dart_on_path()
    return ["dart", "run", "lib/headless/headless.dart"]


def run_headless(args: list[str]) -> subprocess.CompletedProcess:
    """Invoke headless once with the given args; raise on non-zero exit."""
    cmd = headless_command_prefix() + args
    result = subprocess.run(
        cmd,
        cwd=str(REPO_ROOT),
        capture_output=True,
        text=True,
        shell=False,  # native exe; no shell needed
    )
    if result.returncode != 0:
        raise RuntimeError(
            "Headless invocation failed\n"
            f"cmd: {cmd}\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
    return result


def _run_shard(args: list[str]) -> str:
    """Worker entrypoint: invoke headless and return the produced output path."""
    cmd = headless_command_prefix() + args
    result = subprocess.run(
        cmd,
        cwd=str(REPO_ROOT),
        capture_output=True,
        text=True,
        shell=False,
    )
    if result.returncode != 0:
        raise RuntimeError(
            f"shard failed\nargs: {args}\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
    # The output path is whatever the caller passed via --output=...
    for tok in args:
        if tok.startswith("--output="):
            return tok.split("=", 1)[1]
    raise AssertionError("missing --output= in shard args")


def run_headless_sharded(
    *,
    base_args: list[str],
    seed: int,
    episodes: int,
    output_path: Path,
    shards: int | None = None,
    seed_stride: int = 1_000_000,
) -> Path:
    """Run headless workers in parallel and concatenate their JSONL output.

    Each shard gets ``ceil(episodes/shards)`` episodes and a unique seed
    derived as ``seed + shard_index * seed_stride``. ``base_args`` should NOT
    contain ``--seed=``, ``--episodes=``, or ``--output=``.

    Threads (not processes) are used because each worker just spawns a
    headless subprocess and waits on it; ProcessPoolExecutor on Windows
    re-imports the parent module per worker which is heavier than the
    actual work for our small jobs.
    """
    if shards is None:
        shards = max(1, (os.cpu_count() or 1) - 1)
    shards = max(1, min(shards, episodes))

    per_shard = (episodes + shards - 1) // shards
    output_path = Path(output_path)
    output_path.parent.mkdir(parents=True, exist_ok=True)

    if shards == 1:
        run_headless(
            base_args
            + [f"--seed={seed}", f"--episodes={episodes}", f"--output={output_path}"]
        )
        return output_path

    with tempfile.TemporaryDirectory(prefix="tichu_shards_") as td:
        shard_paths: list[Path] = []
        shard_futures = []
        with ThreadPoolExecutor(max_workers=shards) as pool:
            for i in range(shards):
                ep_count = min(per_shard, episodes - i * per_shard)
                if ep_count <= 0:
                    continue
                shard_seed = seed + i * seed_stride
                shard_path = Path(td) / f"shard_{i:02d}.jsonl"
                shard_paths.append(shard_path)
                shard_args = list(base_args) + [
                    f"--seed={shard_seed}",
                    f"--episodes={ep_count}",
                    f"--output={shard_path}",
                ]
                shard_futures.append(pool.submit(_run_shard, shard_args))
            # Surface the first shard error rather than silently skipping.
            for fut in as_completed(shard_futures):
                fut.result()

        # Concatenate shards in deterministic shard-index order.
        with output_path.open("wb") as out:
            for sp in shard_paths:
                with sp.open("rb") as src:
                    shutil.copyfileobj(src, out)

    return output_path
