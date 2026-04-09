#!/usr/bin/env python3
"""Compare headless heuristic self-play against policy-driven self-play.

This script automates:
1) Heuristic self-play trajectory generation
2) Policy table building from those trajectories
3) Heuristic and policy evaluation rollouts
4) Summary metrics and policy coverage reporting
"""

from __future__ import annotations

import argparse
import json
import statistics
import subprocess
import tempfile
from collections import defaultdict
from pathlib import Path


def _run(cmd: list[str], cwd: Path) -> None:
    completed = subprocess.run(cmd, cwd=str(cwd), capture_output=True, text=True)
    if completed.returncode != 0:
        raise RuntimeError(
            f"Command failed ({completed.returncode}): {' '.join(cmd)}\n"
            f"STDOUT:\n{completed.stdout}\nSTDERR:\n{completed.stderr}"
        )


def _summarize_transition_file(path: Path) -> dict[str, object]:
    steps_per_episode: dict[int, int] = defaultdict(int)
    done_rows: dict[int, dict[str, object]] = {}
    phase_counts: dict[str, int] = defaultdict(int)
    action_counts: dict[str, int] = defaultdict(int)

    with path.open("r", encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue

            row = json.loads(line)
            episode = int(row["episode"])
            steps_per_episode[episode] += 1
            phase_counts[str(row.get("phase", "unknown"))] += 1
            action_counts[str(row.get("action_type", "unknown"))] += 1

            if bool(row.get("done")):
                done_rows[episode] = row

    episodes = sorted(steps_per_episode)
    steps = [steps_per_episode[e] for e in episodes]

    winners: list[int] = []
    team0_totals: list[int] = []
    team1_totals: list[int] = []

    for ep in episodes:
        row = done_rows.get(ep)
        if row is None:
            continue
        next_state = row.get("next_state", {})
        score = next_state.get("score", {}) if isinstance(next_state, dict) else {}

        winner = score.get("winning_team")
        if isinstance(winner, int):
            winners.append(winner)

        t0 = score.get("team_one_total")
        t1 = score.get("team_two_total")
        if isinstance(t0, int) and isinstance(t1, int):
            team0_totals.append(t0)
            team1_totals.append(t1)

    def _mean(values: list[float] | list[int]) -> float:
        return float(statistics.mean(values)) if values else 0.0

    margin = [a - b for a, b in zip(team0_totals, team1_totals)]

    return {
        "episodes": len(episodes),
        "completed": len(done_rows),
        "avg_steps": _mean(steps),
        "median_steps": float(statistics.median(steps)) if steps else 0.0,
        "team0_win_rate": (sum(1 for w in winners if w == 0) / len(winners))
        if winners
        else 0.0,
        "team1_win_rate": (sum(1 for w in winners if w == 1) / len(winners))
        if winners
        else 0.0,
        "avg_team0_total": _mean(team0_totals),
        "avg_team1_total": _mean(team1_totals),
        "avg_margin_t0_minus_t1": _mean(margin),
        "phase_counts": dict(sorted(phase_counts.items())),
        "action_type_counts": dict(sorted(action_counts.items())),
    }


def _policy_coverage(eval_jsonl: Path, policy_json: Path) -> dict[str, float | int]:
    policy = json.loads(policy_json.read_text(encoding="utf-8"))
    table = policy.get("state_action_values", {})
    if not isinstance(table, dict):
        table = {}

    coarse_table = policy.get("coarse_state_action_values", {})
    if not isinstance(coarse_table, dict):
        coarse_table = {}

    state_seen = 0
    exact_state_hit = 0
    exact_state_action_hit = 0
    coarse_state_hit = 0
    coarse_state_action_hit = 0
    any_state_hit = 0
    any_state_action_hit = 0

    with eval_jsonl.open("r", encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue
            row = json.loads(line)
            state_key = row.get("state_key")
            coarse_state_key = row.get("state_key_coarse")
            action_key = row.get("action_key")
            action_shape_key = row.get("action_shape_key")
            if not isinstance(state_key, str) or not isinstance(action_key, str):
                continue

            state_seen += 1

            exact_actions = table.get(state_key)
            exact_hit = isinstance(exact_actions, dict)
            exact_action_hit = False
            if exact_hit:
                exact_state_hit += 1
                exact_action_hit = action_key in exact_actions or (
                    isinstance(action_shape_key, str)
                    and action_shape_key in exact_actions
                )
                if exact_action_hit:
                    exact_state_action_hit += 1

            coarse_actions = (
                coarse_table.get(coarse_state_key)
                if isinstance(coarse_state_key, str)
                else None
            )
            coarse_hit = isinstance(coarse_actions, dict)
            coarse_action_hit = False
            if coarse_hit:
                coarse_state_hit += 1
                coarse_action_hit = action_key in coarse_actions or (
                    isinstance(action_shape_key, str)
                    and action_shape_key in coarse_actions
                )
                if coarse_action_hit:
                    coarse_state_action_hit += 1

            if exact_hit or coarse_hit:
                any_state_hit += 1
            if exact_action_hit or coarse_action_hit:
                any_state_action_hit += 1

    return {
        "state_seen": state_seen,
        "exact_state_hit_ratio": (exact_state_hit / state_seen) if state_seen else 0.0,
        "exact_state_action_hit_ratio": (exact_state_action_hit / state_seen)
        if state_seen
        else 0.0,
        "coarse_state_hit_ratio": (coarse_state_hit / state_seen)
        if state_seen
        else 0.0,
        "coarse_state_action_hit_ratio": (coarse_state_action_hit / state_seen)
        if state_seen
        else 0.0,
        "any_state_hit_ratio": (any_state_hit / state_seen) if state_seen else 0.0,
        "any_state_action_hit_ratio": (any_state_action_hit / state_seen)
        if state_seen
        else 0.0,
    }


def _count_policy_entries(policy_json: Path, field: str) -> int:
    policy = json.loads(policy_json.read_text(encoding="utf-8"))
    table = policy.get(field, {})
    if not isinstance(table, dict):
        return 0

    total = 0
    for action_map in table.values():
        if isinstance(action_map, dict):
            total += len(action_map)
    return total


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Compare RL policy player against heuristic baseline in headless mode."
    )
    parser.add_argument("--repo", default=".", help="Repository root path")
    parser.add_argument("--episodes", type=int, default=200)
    parser.add_argument(
        "--train-episodes",
        type=int,
        default=0,
        help="Training episodes (defaults to --episodes when 0).",
    )
    parser.add_argument("--target-score", type=int, default=100)
    parser.add_argument("--train-seed", type=int, default=123)
    parser.add_argument("--eval-seed", type=int, default=456)
    parser.add_argument("--gamma", type=float, default=0.99)
    parser.add_argument("--min-samples", type=int, default=2)
    parser.add_argument(
        "--iterations",
        type=int,
        default=1,
        help="Number of iterative self-play rounds. "
        "Each iteration generates trajectories using the previous policy, "
        "then rebuilds the policy from the combined data.",
    )
    parser.add_argument(
        "--epsilon",
        type=float,
        default=0.0,
        help="Epsilon-greedy exploration rate for training episodes (0-1).",
    )
    parser.add_argument(
        "--workdir",
        default="",
        help="Optional artifact directory. If omitted, a temp dir is used.",
    )
    parser.add_argument(
        "--keep-artifacts",
        action="store_true",
        help="Keep temporary artifacts when --workdir is not provided.",
    )

    args = parser.parse_args()
    train_episodes = args.train_episodes if args.train_episodes > 0 else args.episodes
    iterations = max(1, args.iterations)

    repo = Path(args.repo).resolve()

    if args.workdir:
        workdir = Path(args.workdir).resolve()
        workdir.mkdir(parents=True, exist_ok=True)
        cleanup = False
    else:
        workdir = Path(tempfile.mkdtemp(prefix="tichu_policy_compare_"))
        cleanup = not args.keep_artifacts

    policy_json = workdir / "policy.json"
    eval_baseline = workdir / "eval_baseline.jsonl"
    eval_policy = workdir / "eval_policy.jsonl"

    try:
        # --- Iterative self-play loop ---
        # Iteration 0: heuristic self-play (no policy, no epsilon).
        # Iteration 1+: use the previous policy with epsilon-greedy exploration.
        combined_train = workdir / "combined_train.jsonl"
        next_episode_offset = 0

        for iteration in range(iterations):
            iter_train = workdir / f"train_iter{iteration}.jsonl"
            train_seed = args.train_seed + iteration

            train_cmd = [
                "dart",
                "run",
                "lib/headless/headless.dart",
                f"--seed={train_seed}",
                f"--target-score={args.target_score}",
                f"--episodes={train_episodes}",
                "--format=rl-jsonl",
                f"--output={iter_train}",
            ]

            if iteration > 0 and policy_json.exists():
                # Use the policy from the previous iteration with exploration.
                train_cmd.append(f"--rl-policy={policy_json}")
                if args.epsilon > 0:
                    train_cmd.append(f"--epsilon={args.epsilon}")

            print(
                f"iteration {iteration + 1}/{iterations}: generating "
                f"{train_episodes} training episodes (seed={train_seed})"
                + (
                    f", epsilon={args.epsilon}"
                    if iteration > 0 and args.epsilon > 0
                    else ""
                )
                + (
                    f", policy={policy_json.name}"
                    if iteration > 0 and policy_json.exists()
                    else ""
                ),
                flush=True,
            )
            _run(train_cmd, cwd=repo)

            # Append this iteration's data to the combined training file,
            # re-numbering episodes to maintain ascending order across
            # iterations (the policy builder requires this).
            max_episode_in_iter = 0
            with combined_train.open("a", encoding="utf-8") as out:
                with iter_train.open("r", encoding="utf-8") as inp:
                    for line in inp:
                        stripped = line.strip()
                        if not stripped:
                            continue
                        row = json.loads(stripped)
                        orig_episode = int(row.get("episode", 0))
                        row["episode"] = orig_episode + next_episode_offset
                        max_episode_in_iter = max(max_episode_in_iter, orig_episode)
                        out.write(json.dumps(row) + "\n")
            next_episode_offset += max_episode_in_iter + 1

            # Build policy from all accumulated trajectories.
            print(
                f"iteration {iteration + 1}/{iterations}: building policy",
                flush=True,
            )
            _run(
                [
                    "dart",
                    "run",
                    "tool/rl/build_policy_from_transitions.dart",
                    f"--input={combined_train}",
                    f"--output={policy_json}",
                    f"--gamma={args.gamma}",
                    f"--min-samples={args.min_samples}",
                ],
                cwd=repo,
            )

        # --- Evaluation ---
        # Baseline: pure heuristic on eval seed.
        _run(
            [
                "dart",
                "run",
                "lib/headless/headless.dart",
                f"--seed={args.eval_seed}",
                f"--target-score={args.target_score}",
                f"--episodes={args.episodes}",
                "--format=rl-jsonl",
                f"--output={eval_baseline}",
            ],
            cwd=repo,
        )
        # Policy: learned policy on the same eval seed (no epsilon).
        _run(
            [
                "dart",
                "run",
                "lib/headless/headless.dart",
                f"--seed={args.eval_seed}",
                f"--target-score={args.target_score}",
                f"--episodes={args.episodes}",
                "--format=rl-jsonl",
                f"--rl-policy={policy_json}",
                f"--output={eval_policy}",
            ],
            cwd=repo,
        )

        baseline_summary = _summarize_transition_file(eval_baseline)
        policy_summary = _summarize_transition_file(eval_policy)
        coverage_summary = _policy_coverage(eval_policy, policy_json)
        policy_entries_exact = _count_policy_entries(policy_json, "state_action_values")
        policy_entries_coarse = _count_policy_entries(
            policy_json, "coarse_state_action_values"
        )
        policy_entries = policy_entries_exact + policy_entries_coarse

        result = {
            "config": {
                "train_episodes": train_episodes,
                "eval_episodes": args.episodes,
                "target_score": args.target_score,
                "train_seed": args.train_seed,
                "eval_seed": args.eval_seed,
                "gamma": args.gamma,
                "min_samples": args.min_samples,
                "iterations": iterations,
                "epsilon": args.epsilon,
            },
            "policy_table_entries_exact": policy_entries_exact,
            "policy_table_entries_coarse": policy_entries_coarse,
            "policy_table_entries": policy_entries,
            "baseline": baseline_summary,
            "policy": policy_summary,
            "policy_coverage": coverage_summary,
            "artifacts": str(workdir),
        }

        print(json.dumps(result, indent=2, sort_keys=True))

        if policy_entries == 0:
            print(
                "\nwarning: policy table is empty; policy run is expected to match heuristic fallback.",
                flush=True,
            )

        return 0
    finally:
        if cleanup:
            for p in workdir.glob("*"):
                p.unlink(missing_ok=True)
            workdir.rmdir()


if __name__ == "__main__":
    raise SystemExit(main())
