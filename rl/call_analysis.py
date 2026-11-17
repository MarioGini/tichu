#!/usr/bin/env python3
"""Exact value of Tichu / Grand Tichu call rules.

Input: headless ``--counterfactual-calls --counterfactual-rate=1`` rows. For
each call decision ``cf`` = round result (own team) when calling minus when
not calling, on the same deal with the same bots. The value of a rule per
decision is mean(cf * [rule calls]); comparing rules on the same rows is
exact up to sampling of deals.

  rl/.venv/bin/python rl/call_analysis.py rl/outputs/calls_v5/cf.jsonl
"""

from __future__ import annotations

import json
import sys

import numpy as np


def rank(slot: int) -> int:
    return {52: 1, 53: 0, 54: 15, 55: 16}[slot] if slot >= 52 else slot % 13 + 2


def grand_strength(hand: list[int]) -> float:
    """Mirror of DefaultTichuCallStrategy.grandStrength."""
    ranks = [rank(s) for s in hand]
    quads = sum(1 for r in range(2, 15) if ranks.count(r) == 4)
    return (3 * ranks.count(16) + 3 * ranks.count(15) + ranks.count(14)
            + (ranks.count(13) + ranks.count(12)) / 3 + 4 * quads - ranks.count(0))


def partner_called(r: dict) -> bool:
    """Partner's Tichu / Grand Tichu flags in the seats group (partner block)."""
    f = r["state_features"]
    return f[158 + 5] > 0.5 or f[158 + 6] > 0.5


def report(name: str, cf: np.ndarray, mask: np.ndarray, current: np.ndarray | None = None) -> None:
    v = cf * mask
    per_call = cf[mask].mean() if mask.any() else 0.0
    succ = ""
    print(f"  {name:46s} calls {100 * mask.mean():5.1f}%  value {v.mean():+6.2f} ± {v.std() / np.sqrt(len(v)):.2f} "
          f"pts/decision  ({per_call:+6.1f} per call){succ}")


def main(path: str) -> None:
    rows = {"grand": [], "tichu": [], "pre": []}
    with open(path) as fh:
        for line in fh:
            if '"cf"' not in line:
                continue
            r = json.loads(line)
            rows.setdefault(r["call"], []).append(r)
    g = rows["grand"]
    if g:
        cf = np.array([r["cf"] for r in g], dtype=float)
        gs = np.array([grand_strength(r["hand"]) for r in g])
        partner = np.array([partner_called(r) for r in g])
        print(f"Grand Tichu: {len(g)} decisions; calling always would be {cf.mean():+.1f} per decision")
        print(f"  clairvoyant upper bound {np.maximum(cf, 0).mean():+.2f} pts/decision")
        for t in (4, 4.5, 5, 5.5, 6, 6.5, 7, 8):
            report(f"strength >= {t}", cf, (gs >= t) & ~partner)
        print("  Value per call by strength (8 cards):")
        for lo, hi in ((3, 4), (4, 5), (5, 6), (6, 7), (7, 99)):
            m = (gs >= lo) & (gs < hi) & ~partner
            if m.sum() >= 30:
                print(f"    strength {lo}-{hi}: n={m.sum():5d}  cf {cf[m].mean():+7.1f} ± {cf[m].std() / np.sqrt(m.sum()):.1f}")
    t_rows = rows["tichu"]
    if t_rows:
        cf = np.array([r["cf"] for r in t_rows], dtype=float)
        st = np.array([r["strength"] for r in t_rows])
        opp = np.array([bool(r.get("opp_called")) for r in t_rows])
        partner = np.array([partner_called(r) for r in t_rows])
        heur = np.array([bool(r["called"]) != bool(r.get("explore", False)) for r in t_rows])
        print(f"\nTichu (first opportunity): {len(t_rows)} decisions; calling always {cf.mean():+.1f} per decision")
        print(f"  clairvoyant upper bound {np.maximum(cf, 0).mean():+.2f} pts/decision")
        report("current rule", cf, heur)
        for t in (-0.5, -0.3, -0.1, 0.1, 0.3, 0.5, 0.8):
            for tv in (0.5, 1.0):
                report(f"strength >= {t:+.1f} (vs a call: >= {tv})", cf,
                       ~partner & np.where(opp, st >= tv, st >= t))
        print("  Value per call by strength (no opponent call, partner not called):")
        for lo in np.arange(-1.0, 2.0, 0.25):
            m = (st >= lo) & (st < lo + 0.25) & ~opp & ~partner
            if m.sum() >= 50:
                print(f"    strength {lo:+.2f}..{lo + 0.25:+.2f}: n={m.sum():5d}  cf {cf[m].mean():+7.1f} ± "
                      f"{cf[m].std() / np.sqrt(m.sum()):.1f}")


if __name__ == "__main__":
    main(sys.argv[1])
