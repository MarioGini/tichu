#!/usr/bin/env python3
"""Analyse how a policy plays against the heuristic, and where it differs.

Plays duplicate matches (same deals, both seatings) of a policy team vs the
heuristic with ``--shadow-heuristic``, so every play/pass decision of the
policy also records what the heuristic would have done in the same spot.

Reports:
  * round outcomes per side: point diff, going out first, double wins,
    Tichu / Grand Tichu calls and their success rate;
  * the policy's decisions: how often it deviates from the heuristic, split
    by situation (leading / following, pass vs play, bombs, special cards),
    with examples;
  * per deviation kind, the mean round result of the policy's team (a rough,
    correlational signal of which deviations hurt).

  rl/.venv/bin/python rl/analyze_games.py \
      --nn-policy=rl/outputs/best_policy.safetensors --episodes=100
"""

from __future__ import annotations

import argparse
import collections
import json
import random
import tempfile
from pathlib import Path

from headless_runner import run_headless_sharded


def _side_stats(rounds: list[dict], team: int) -> dict[str, float]:
    n = len(rounds)
    own = [r["team_one_round"] if team == 0 else r["team_two_round"] for r in rounds]
    opp = [r["team_two_round"] if team == 0 else r["team_one_round"] for r in rounds]
    first = sum(1 for r in rounds if r.get("finish_teams") and r["finish_teams"][0] == team)
    double = sum(
        1
        for r in rounds
        if len(r.get("finish_teams", [])) >= 2
        and r["finish_teams"][0] == r["finish_teams"][1] == team
    )
    calls = collections.Counter()
    made = collections.Counter()
    for r in rounds:
        for t, kind, ok, *_ in r.get("calls", []):
            if t == team:
                calls[kind] += 1
                made[kind] += int(ok)
    return {
        "rounds": n,
        "avg_points": sum(own) / max(1, n),
        "avg_diff": (sum(own) - sum(opp)) / max(1, n),
        "first_out": 100 * first / max(1, n),
        "double_win": 100 * double / max(1, n),
        "tichu_calls": 100 * calls["tichu"] / max(1, n),
        "tichu_success": 100 * made["tichu"] / max(1, calls["tichu"]),
        "gt_calls": 100 * calls["grandTichu"] / max(1, n),
        "gt_success": 100 * made["grandTichu"] / max(1, calls["grandTichu"]),
    }


def _kind(desc: str) -> str:
    if desc == "pass":
        return "pass"
    cards = desc.split("+")
    if len(cards) == 4 and len(set(cards)) == 1:
        return "bomb"
    if len(cards) >= 5 and len(set(cards)) == len(cards) and "phoenix" not in cards:
        return "straight/bomb"
    for special in ("dragon", "phoenix", "dog", "mahJong"):
        if special in cards:
            return special
    return f"{len(cards)} cards"


def main() -> None:
    p = argparse.ArgumentParser(description="Analyse policy vs heuristic games")
    p.add_argument("--nn-policy", required=True)
    p.add_argument(
        "--extra",
        action="append",
        default=[],
        help="Extra headless arg for the policy team (repeatable, e.g. --extra=--heuristic=latest,lowLeadPreference:4)",
    )
    p.add_argument("--episodes", type=int, default=100, help="Deal sequences (×2 seatings)")
    p.add_argument("--target-score", type=int, default=500)
    p.add_argument("--seed", type=int, default=2468)
    p.add_argument("--shards", type=int, default=0)
    p.add_argument("--examples", type=int, default=12)
    args = p.parse_args()

    rounds_by_side: dict[str, list[dict]] = {"policy": [], "heuristic": []}
    decisions: list[dict] = []
    with tempfile.TemporaryDirectory(prefix="tichu_analyze_") as td:
        for swap in (False, True):
            out = Path(td) / f"g{int(swap)}.jsonl"
            base = [
                f"--target-score={args.target_score}",
                "--mixed",
                f"--nn-policy={args.nn_policy}",
                "--format=bc-jsonl",
                "--shadow-heuristic",
                *args.extra,
            ]
            if swap:
                base.append("--swap-teams")
            run_headless_sharded(
                base_args=base,
                seed=args.seed + int(swap),
                episodes=args.episodes,
                output_path=out,
                shards=args.shards or None,
                deal_seed=args.seed,
            )
            policy_team = 1 if swap else 0
            round_results: dict[tuple[int, int], dict] = {}
            with out.open() as fh:
                for line in fh:
                    r = json.loads(line)
                    if r.get("round_end"):
                        round_results[(r["episode"], r["round"])] = r
                        rounds_by_side["policy"].append({**r, "_team": policy_team})
                    elif "shadow_index" in r and r["team"] == policy_team:
                        r.pop("state_features", None)
                        r.pop("legal_play_action_features", None)
                        r["_team"] = policy_team
                        decisions.append(r)
            for d in decisions:
                if "_result" not in d and d["_team"] == policy_team:
                    rr = round_results.get((d["episode"], d["round"]))
                    if rr is not None:
                        own = rr["team_one_round"] if policy_team == 0 else rr["team_two_round"]
                        opp = rr["team_two_round"] if policy_team == 0 else rr["team_one_round"]
                        d["_result"] = own - opp

    print(f"=== Round outcomes ({len(rounds_by_side['policy'])} rounds, both seatings) ===")
    pol = collections.defaultdict(float)
    heu = collections.defaultdict(float)
    for side_rounds in [rounds_by_side["policy"]]:
        by_team = collections.defaultdict(list)
        for r in side_rounds:
            by_team[r["_team"]].append(r)
        n = 0
        for team, rs in by_team.items():
            sp, sh = _side_stats(rs, team), _side_stats(rs, 1 - team)
            for k, v in sp.items():
                pol[k] += v * len(rs)
                heu[k] += sh[k] * len(rs)
            n += len(rs)
    n = max(1, len(rounds_by_side["policy"]))
    print(f"{'':16s}{'policy':>10s}{'heuristic':>11s}")
    for k in ("avg_points", "avg_diff", "first_out", "double_win", "tichu_calls",
              "tichu_success", "gt_calls", "gt_success"):
        print(f"{k:16s}{pol[k]/n:10.1f}{heu[k]/n:11.1f}")

    print(f"\n=== Policy decisions vs heuristic ({len(decisions)} play/pass decisions) ===")
    diff = [d for d in decisions if d["legal_play_chosen_index"] != d["shadow_index"]]
    print(f"deviates from heuristic: {100*len(diff)/max(1,len(decisions)):.1f}%")
    for label, sel in (("leading", True), ("following", False)):
        sub = [d for d in decisions if d["leading"] == sel]
        sd = [d for d in sub if d["legal_play_chosen_index"] != d["shadow_index"]]
        print(f"  {label:10s}: {len(sub):6d} decisions, deviates {100*len(sd)/max(1,len(sub)):5.1f}%")

    kinds = collections.Counter()
    results = collections.defaultdict(list)
    for d in diff:
        k = f"{_kind(d['shadow_desc'])} -> {_kind(d['chosen_desc'])}" + (
            " (lead)" if d["leading"] else ""
        )
        kinds[k] += 1
        if "_result" in d:
            results[k].append(d["_result"])
    all_res = [d["_result"] for d in decisions if "_result" in d]
    base = sum(all_res) / max(1, len(all_res))
    print(f"\nmost common deviations (heuristic -> policy), mean round diff "
          f"of the policy team in those rounds (all decisions: {base:+.1f}):")
    for k, c in kinds.most_common(15):
        rs = results[k]
        print(f"  {c:5d}  {k:32s} {sum(rs)/max(1,len(rs)):+7.1f}")

    print("\nexamples:")
    rng = random.Random(0)
    for d in rng.sample(diff, min(args.examples, len(diff))):
        print(
            f"  hand={d['hand_size']:2d} trick={d['trick_type']:10s} "
            f"heuristic: {d['shadow_desc']:28s} policy: {d['chosen_desc']}"
        )


if __name__ == "__main__":
    main()
