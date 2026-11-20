#!/usr/bin/env python3
"""Where do two play nets choose differently, and who is right?

Input: rollout-labelled bc-jsonl of games of net A (the labelled seats).
Both nets score every decision; where their greedy moves differ, the exact
rollout values (same deal, every legal move played out) give the points A's
move gains over B's. Decisions are grouped by situation and by how the moves
differ.

  build/bin/headless --format=bc-jsonl --rollout-rate=0.3 --mixed \\
      --nn-policy=A.safetensors --opponent-policy=B.safetensors ... --output=a.jsonl
  rl/.venv/bin/python rl/compare_policies.py --a=A.safetensors --b=B.safetensors \\
      --jsonl=a.jsonl[,b.jsonl] [--jsonl-b=games_of_b.jsonl]

The rollouts continue with A's policy, which flatters A a little: its moves
are judged by the continuation they were trained for. ``--jsonl-b`` takes
rollout data of B's games (B labelled and continuing, the same command with
the two nets swapped) and reports the gain measured there as well; the
truth lies between the two, and their mean is the fair estimate.
"""

from __future__ import annotations

import argparse
import json
import math
from collections import defaultdict
from pathlib import Path

import numpy as np
import torch

from qnet import load_qnetwork_from_safetensors
from schema import ACTION_OFFSET, SPEC, pad_state


def _idx(group: str) -> dict[str, int]:
    g = SPEC.group(group)
    return {n: g.offset + i for i, n in enumerate(g.feature_names)}


T, SEAT, SELF, ACT = _idx("trick"), _idx("seats"), _idx("self"), _idx("action")
A = {k: v - ACTION_OFFSET for k, v in ACT.items()}
TYPES = ["pass", "single", "pair", "triplet", "full_house", "straight", "pair_straight", "bomb", "dog"]
TRICKS = ["single", "pair", "triplet", "full_house", "straight", "pair_straight", "bomb"]


def move_type(a: np.ndarray) -> str:
    for t in TYPES:
        if a[A[f"type_{t}"]] > 0.5:
            return t
    return "?"


def situation(s: np.ndarray) -> list[str]:
    tags = []
    if s[T["trick_lead"]] > 0.5:
        tags.append("lead")
    else:
        t = next((t for t in TRICKS if s[T[f"trick_{t}"]] > 0.5), "?")
        who = "partner" if s[T["trick_winner_partner"]] > 0.5 else "opponent"
        tags += [f"follow: {who} winning", f"follow {t}"]
    hand = s[SELF["hand_size"]] * 14
    tags.append("hand 1-4" if hand <= 4.5 else "hand 5-9" if hand <= 9.5 else "hand 10-14")
    if s[SEAT["left_one_card"]] > 0.5 or s[SEAT["right_one_card"]] > 0.5:
        tags.append("an opponent has 1 card")
    elif s[SEAT["left_few_cards"]] > 0.5 or s[SEAT["right_few_cards"]] > 0.5:
        tags.append("an opponent has few cards")
    if s[SEAT["left_tichu"]] + s[SEAT["right_tichu"]] + s[SEAT["left_grand_tichu"]] + s[SEAT["right_grand_tichu"]] > 0:
        tags.append("an opponent called (G)T")
    if s[SEAT["partner_tichu"]] + s[SEAT["partner_grand_tichu"]] > 0:
        tags.append("partner called (G)T")
    if s[SELF["own_tichu"]] + s[SELF["own_grand_tichu"]] > 0:
        tags.append("I called (G)T")
    if s[SEAT["partner_finished"]] > 0.5:
        tags.append("partner is out")
    return tags


def difference(a: np.ndarray, b: np.ndarray) -> list[str]:
    ta, tb = move_type(a), move_type(b)
    if ta == "pass":
        return [f"A passes, B plays {tb}"]
    if tb == "pass":
        return [f"A plays {ta}, B passes"]
    tags = []
    if ta != tb:
        tags.append(f"A {ta} instead of {tb}")
    else:
        hi_a, hi_b = a[A["highest_rank"]], b[A["highest_rank"]]
        n_a, n_b = a[A["action_card_count"]], b[A["action_card_count"]]
        if n_a != n_b:
            tags.append(f"same type ({ta}), A {'longer' if n_a > n_b else 'shorter'}")
        elif hi_a != hi_b:
            tags.append(f"same type ({ta}), A {'higher' if hi_a > hi_b else 'lower'}")
        else:
            tags.append(f"same type ({ta}), other cards")
    for k, name in (("uses_dragon", "Dragon"), ("uses_phoenix", "Phoenix"), ("act_a", "an Ace")):
        if a[A[k]] > b[A[k]]:
            tags.append(f"A spends {name}, B keeps it")
        elif a[A[k]] < b[A[k]]:
            tags.append(f"A keeps {name}, B spends it")
    if a[A["type_bomb"]] > 0.5 and b[A["type_bomb"]] < 0.5:
        tags.append("A bombs, B does not")
    if b[A["type_bomb"]] > 0.5 and a[A["type_bomb"]] < 0.5:
        tags.append("A holds the bomb, B bombs")
    return tags


def main() -> None:
    p = argparse.ArgumentParser(description="Compare the moves of two play nets on A's decisions")
    p.add_argument("--a", required=True)
    p.add_argument("--b", required=True)
    p.add_argument("--jsonl", required=True, help="comma-separated rollout bc-jsonl of A's games")
    p.add_argument("--jsonl-b", default="", help="rollout bc-jsonl of B's games (B continues)")
    p.add_argument("--min-count", type=int, default=150)
    p.add_argument("--markdown", action="store_true")
    args = p.parse_args()
    dev = torch.device("cpu")
    na = load_qnetwork_from_safetensors(Path(args.a), dev).eval()
    nb = load_qnetwork_from_safetensors(Path(args.b), dev).eval()
    stats, n_dec, n_sit = collect(na, nb, args.jsonl)
    print(f"{n_dec} decisions of A; gain = points per round A's move wins over B's (exact rollouts, A continues)\n")
    report(stats, n_dec, n_sit, args)
    if args.jsonl_b:
        stats_b, n_dec_b, n_sit_b = collect(na, nb, args.jsonl_b)
        print(f"{n_dec_b} decisions of B; same gain (A's move minus B's), B continues\n")
        report(stats_b, n_dec_b, n_sit_b, args)
        ga, gb = stats[("situation", "all")], stats_b[("situation", "all")]
        if ga and gb:
            ma, mb = float(np.mean(ga)), float(np.mean(gb))
            sa = float(np.std(ga, ddof=1) / math.sqrt(len(ga)))
            sb = float(np.std(gb, ddof=1) / math.sqrt(len(gb)))
            print(
                f"gain per differing move: A continues {ma:+.2f} ± {sa:.2f}, "
                f"B continues {mb:+.2f} ± {sb:.2f}, mean {(ma + mb) / 2:+.2f} ± {math.hypot(sa, sb) / 2:.2f}"
            )


def collect(na, nb, paths: str):
    stats: dict[tuple[str, str], list[float]] = defaultdict(list)
    n_dec = 0
    n_sit: dict[str, int] = defaultdict(int)
    for path in paths.split(","):
        with open(path, encoding="utf-8") as fh:
            for line in fh:
                if '"q_rollout"' not in line:
                    continue
                r = json.loads(line)
                if r.get("explore"):
                    continue
                # Rows of an older layout: zeros for the missing state groups.
                s = pad_state(np.asarray(r["state_features"], dtype=np.float32)[None])[0]
                acts = np.asarray(r["legal_play_action_features"], dtype=np.float32)
                x = torch.from_numpy(np.concatenate([np.repeat(s[None], len(acts), 0), acts], 1))
                with torch.no_grad():
                    ia = int(na(x).squeeze(-1).argmax())
                    ib = int(nb(x).squeeze(-1).argmax())
                q = r["q_rollout"]
                n_dec += 1
                sit = situation(s)
                for t in sit + ["all"]:
                    n_sit[t] += 1
                if ia == ib:
                    continue
                if q[ia] is None or q[ib] is None:
                    continue
                gain = q[ia] - q[ib]
                diff = difference(acts[ia], acts[ib])
                for t in sit + ["all"]:
                    stats[("situation", t)].append(gain)
                for d in diff:
                    stats[("move", d)].append(gain)
    return stats, n_dec, n_sit


def report(stats, n_dec: int, n_sit, args) -> None:
    for kind in ("situation", "move"):
        rows = []
        for (k, name), g in stats.items():
            if k != kind or len(g) < args.min_count:
                continue
            m = float(np.mean(g))
            se = float(np.std(g, ddof=1) / math.sqrt(len(g)))
            share = len(g) / n_dec * 100
            dis = len(g) / n_sit[name] * 100 if kind == "situation" else float("nan")
            rows.append((m * len(g) / n_dec, name, len(g), share, dis, m, se))
        rows.sort(reverse=True)
        if args.markdown:
            print(f"| {kind} | differ | % of decisions | gain/differing move | contribution/decision |")
            print("|---|---|---|---|---|")
        for contrib, name, n, share, dis, m, se in rows:
            disag = f"{dis:.0f} %" if not math.isnan(dis) else ""
            if args.markdown:
                print(f"| {name} | {disag} | {share:.1f} | {m:+.1f} ± {se:.1f} | {contrib:+.2f} |")
            else:
                print(f"{kind:9s} {name:40s} n={n:6d} ({share:4.1f}% of dec, differ {disag:>5s})  "
                      f"gain {m:+6.1f} ± {se:4.1f}  contrib {contrib:+.2f}/dec")
        print()


if __name__ == "__main__":
    main()
