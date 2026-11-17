#!/usr/bin/env python3
"""Schupf when an opponent called Grand Tichu: which passes pay off?

Uses exact schupf candidate labels (`schupf_cf` rows). Context flags:
[grand, tichu] for me, partner, left, right. Values are per decision
relative to the deal's average candidate (round points for my team).

  rl/.venv/bin/python rl/schupf_vs_grand.py 'rl/outputs/schupf/cf_*.jsonl' [net.safetensors]
"""

from __future__ import annotations

import collections
import glob
import json
import sys

import numpy as np


def rank(s: int) -> int:
    return {52: 1, 53: 0, 54: 15, 55: 16}[s] if s >= 52 else s % 13 + 2


def cls(s: int) -> str:
    r = rank(s)
    return {0: "Dog", 1: "MahJong", 15: "Phoenix", 16: "Dragon", 14: "A"}.get(r, "2-6" if r <= 6 else ("7-10" if r <= 10 else "J/Q/K"))


def main(pattern: str, net: str | None) -> None:
    g: dict[str, list[float]] = collections.defaultdict(list)
    n = 0
    rows = []
    for f in glob.glob(pattern):
        for line in open(f):
            if '"schupf_cf"' not in line:
                continue
            r = json.loads(line)
            ctx = r["context"]
            caller = "left" if ctx[4] > 0.5 else ("right" if ctx[6] > 0.5 else None)
            if caller is None or ctx[2] > 0.5:  # opponent GT, partner did not call GT
                continue
            outs = r["out"]
            valid = [i for i, o in enumerate(outs) if o is not None]
            if len(valid) < 3:
                continue
            n += 1
            rows.append(r)
            mean = np.mean([outs[i][0] for i in valid])
            for i in valid:
                left, partner, right = r["cands"][i]
                to_caller, to_other = (left, right) if caller == "left" else (right, left)
                v = outs[i][0] - mean
                g[f"to the Grand Tichu caller: {cls(to_caller)}"].append(v)
                g[f"to the other opponent: {cls(to_other)}"].append(v)
                g[f"to partner: {cls(partner)}"].append(v)
                dog_in_hand = 53 in r["hands"][0]
                if dog_in_hand:
                    where = "caller" if to_caller == 53 else ("other opponent" if to_other == 53 else ("partner" if partner == 53 else "kept"))
                    g[f"I hold the Dog: Dog -> {where}"].append(v)
                # the caller's success
                g["caller makes it (rate) | Dog to caller" if to_caller == 53 else "caller makes it (rate) | other"].append(
                    100.0 * (outs[i][5] == 4))
    print(f"{n} schupf decisions with an opponent Grand Tichu (partner not calling)")
    for k in sorted(g):
        v = np.array(g[k])
        if len(v) < 60:
            continue
        print(f"  {k:48s} n={len(v):5d}  {v.mean():+7.1f} ± {v.std() / np.sqrt(len(v)):.1f}")
    # the heuristic's own pass in these situations: what does it do?
    own = collections.Counter()
    for r in rows:
        ctx = r["context"]
        left, partner, right = r["cands"][0]
        to_caller = left if ctx[4] > 0.5 else right
        own[f"own pass gives the caller: {cls(to_caller)}"] += 1
    print("  " + ", ".join(f"{k.split(': ')[1]} {v}" for k, v in own.most_common()))


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else None)
