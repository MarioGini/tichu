#!/usr/bin/env python3
"""What makes a good schupf? Analysis of exact schupf candidate labels.

Input: headless ``--schupf-rollout-rate`` rows (``schupf_cf``): for each
labelled decision, up to 16 candidate passes ([left, partner, right] card
slots; index 0 = the bot's own choice) and the exact outcome of each on the
same deal: round points for my team, went out first, double win, and the
Tichu calls that followed (mine, partner's, best opponent's).

Every comparison is within a decision (value minus the mean of that deal's
candidates), so card luck cancels.

  rl/.venv/bin/python rl/schupf_analysis.py rl/outputs/schupf/cf_*.jsonl
"""

from __future__ import annotations

import collections
import glob
import json
import sys

import numpy as np

NAMES = {52: "MahJong", 53: "Dog", 54: "Phoenix", 55: "Dragon"}
RANKS = "23456789TJQKA"


def rank(slot: int) -> int:
    """Strength order: Dog 0, MahJong 1, 2..14, Phoenix 15, Dragon 16."""
    return {52: 1, 53: 0, 54: 15, 55: 16}.get(slot, slot % 13 + 2) if slot >= 52 else slot % 13 + 2


def name(slot: int) -> str:
    return NAMES.get(slot, RANKS[slot % 13] if slot < 52 else "?")


def strength(hand: list[int]) -> float:
    """Quick Tichu strength: Dragon 1, Phoenix 0.8, Ace 0.7, King 0.2, Dog -0.7."""
    s = 0.0
    for c in hand:
        r = rank(c)
        s += {16: 1.0, 15: 0.8, 14: 0.7, 13: 0.2, 0: -0.7}.get(r, 0.0)
    return s


def bucket(x: float) -> str:
    return "weak (<1.0)" if x < 1.0 else ("medium (1.0-2.2)" if x < 2.2 else "strong (>=2.2)")


def partner_card(slot: int) -> str:
    r = rank(slot)
    if r >= 14:
        return name(slot)
    if r >= 11:
        return "J/Q/K"
    if r == 0:
        return "Dog"
    return "low (<=10, MahJong)"


def opp_card(slot: int) -> str:
    r = rank(slot)
    if r == 0:
        return "Dog"
    if r == 1:
        return "MahJong"
    if r <= 6:
        return "2-6"
    if r <= 10:
        return "7-10"
    return "J+"


def main(paths: list[str]) -> None:
    rows = []
    for p in paths:
        for f in glob.glob(p):
            with open(f) as fh:
                for line in fh:
                    if '"schupf_cf"' in line:
                        rows.append(json.loads(line))
    groups: dict[str, list[float]] = collections.defaultdict(list)
    regret, heur_vs_mean = [], []
    effects: dict[str, list[np.ndarray]] = collections.defaultdict(list)
    for r in rows:
        outs = r["out"]
        valid = [i for i, o in enumerate(outs) if o is not None]
        if len(valid) < 3 or outs[0] is None:
            continue
        vals = np.array([outs[i][0] for i in valid], dtype=float)
        mean = vals.mean()
        regret.append(vals.max() - outs[0][0])
        heur_vs_mean.append(outs[0][0] - mean)
        hands = r["hands"]
        me_s, partner_s = strength(hands[0]), strength(hands[2])
        ctx = f"me {bucket(me_s)}, partner {bucket(partner_s)}"
        # outcome deltas vs the decision's mean
        o = np.array([outs[i] for i in valid], dtype=float)
        stats = np.stack([
            o[:, 0],
            o[:, 1],
            (o[:, 2] == 1),
            (o[:, 2] == -1),
            np.isin(o[:, 4], [1, 2, 3, 4]),
            np.isin(o[:, 4], [2, 4]),
            np.isin(o[:, 3], [1, 2, 3, 4]),
            np.isin(o[:, 3], [2, 4]),
            np.isin(o[:, 5], [2, 4]),
        ], 1).astype(float)
        stats -= stats.mean(0)
        for k, i in enumerate(valid):
            left, partner, right = r["cands"][i]
            v = outs[i][0] - mean
            pc = partner_card(partner)
            groups[f"to partner: {pc}"].append(v)
            groups[f"to partner: {pc} | {ctx}"].append(v)
            effects[f"to partner: {pc}"].append(stats[k])
            for side, slot in (("left", left), ("right", right)):
                oc = opp_card(slot)
                groups[f"to an opponent: {oc}"].append(v / 2)
                effects[f"to an opponent: {oc}"].append(stats[k] / 2)
            if 53 in (left, right):
                groups["Dog to an opponent | " + ctx].append(v)
    n = len(heur_vs_mean)
    reg = np.array(regret)
    hm = np.array(heur_vs_mean)
    print(f"{n} schupf decisions, {sum(len([o for o in r['out'] if o]) for r in rows)} candidate rounds")
    print(f"bot's own pass vs the average candidate: {hm.mean():+.1f} ± {hm.std() / np.sqrt(n):.1f} points per round")
    print(f"best candidate on the actual deal (uses hidden cards, upper bound): +{reg.mean():.1f} points per round over the bot's pass")
    print("\nValue of a candidate minus the deal's average candidate (round points, ± SE):")
    for k in sorted(groups):
        v = np.array(groups[k])
        if len(v) < 200:
            continue
        print(f"  {k:62s} n={len(v):6d}  {v.mean():+7.1f} ± {v.std() / np.sqrt(len(v)):.1f}")
    labels = ["points", "we go out first", "our double win", "their double win", "partner calls",
              "partner makes it", "I call", "I make it", "opponent makes a call"]
    print("\nEffects relative to the deal's average candidate (points; rates in percentage points):")
    print(f"  {'':34s}" + "".join(f"{l[:14]:>15s}" for l in labels))
    for k in sorted(effects):
        e = np.array(effects[k])
        if len(e) < 200:
            continue
        m = e.mean(0)
        print(f"  {k:34s}" + f"{m[0]:+15.1f}" + "".join(f"{100 * x:+15.1f}" for x in m[1:]))


if __name__ == "__main__":
    main(sys.argv[1:])
