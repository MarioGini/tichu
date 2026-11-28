#!/usr/bin/env python3
"""How good are the bot's Tichu / Grand Tichu calls, and where to call.

Reads bc-jsonl call rows with exact counterfactual labels
(``headless --counterfactual-calls``): ``cf`` = R(call) - R(no call) on the
same deal, the rest of the round played by the bots (including their later
calls). Three decision points:

  grand  8 cards, before the rest of the deal;
  pre    14 cards, before the schupf (a call here is public before anyone
         passes: the partner can support, the opponents defend);
  tichu  the first card the player plays (after the schupf; the bot keeps
         the option while it passes).

For each: the value of the current rule (mean cf of the calls it makes,
per decision), the best threshold on a strength score, and the value by
strength bucket.

  rl/.venv/bin/python rl/call_audit.py rl/outputs/calls_v8/cf_*.jsonl
"""

from __future__ import annotations

import collections
import json
import sys

import numpy as np

MJ, DOG, PH, DR = 52, 53, 54, 55


def grand_strength(hand: list[int]) -> float:
    """DefaultTichuCallStrategy.grandStrength on card slots."""
    cnt = collections.Counter(s % 13 for s in hand if s < 52)

    def n(slot: int) -> int:
        return sum(1 for s in hand if s == slot)

    aces = cnt[12]
    kq = cnt[11] + cnt[10]
    quads = sum(1 for k, v in cnt.items() if v == 4)
    return 3 * n(DR) + 3 * n(PH) + aces + kq / 3 + 4 * quads - n(DOG)


def main(paths: list[str]) -> None:
    rows = collections.defaultdict(list)
    for p in paths:
        for line in open(p, encoding="utf-8"):
            if '"cf"' not in line:
                continue
            r = json.loads(line)
            r["_f"] = p
            if r.get("explore"):
                continue
            k = r["call"]
            if k == "grand":
                r["score"] = grand_strength(r["hand"])
            else:
                r["score"] = r["strength"]
            rows[k].append(r)
    for kind in ("grand", "pre", "tichu"):
        rs = rows[kind]
        if not rs:
            continue
        for opp in (False, True) if kind == "tichu" else (None,):
            sub = [r for r in rs if opp is None or r["opp_called"] == opp]
            if not sub:
                continue
            cf = np.array([r["cf"] for r in sub], dtype=float)
            sc = np.array([r["score"] for r in sub], dtype=float)
            called = np.array([r["called"] for r in sub], dtype=bool)
            n = len(sub)
            title = kind + ("" if opp is None else (" (an opponent already called)" if opp else " (no opponent call)"))
            print(f"\n=== {title}: {n} decisions, the rule calls {100 * called.mean():.1f} % ===")
            cur = (cf * called).sum() / n
            se = (cf * called).std(ddof=1) / n ** 0.5
            print(f"  value of the rule's calls: {cur:+.2f} ± {se:.2f} pts per decision (vs never calling)")
            print(f"  hindsight (call iff cf > 0): {np.maximum(cf, 0).mean():+.2f}; calls with cf > 0: {100 * (cf > 0).mean():.1f} %")
            if called.any():
                print(f"  rule's calls: mean cf {cf[called].mean():+.1f}, positive {100 * (cf[called] > 0).mean():.1f} %")
            if (~called).any():
                print(f"  rule's non-calls: mean cf {cf[~called].mean():+.1f} (calling them instead)")
            ths = np.unique(np.quantile(sc, np.linspace(0.5, 0.999, 60)))
            best = max(ths, key=lambda t: (cf * (sc >= t)).mean())
            bv = (cf * (sc >= best)).mean()
            print(f"  best threshold on the strength score: {best:.2f} -> {bv:+.2f} pts per decision, calls {100 * (sc >= best).mean():.1f} %")
            qs = np.quantile(sc, [0, 0.5, 0.75, 0.9, 0.95, 0.98, 0.99, 1.0])
            print("  mean cf by strength bucket (score range: n, mean cf, P(cf > 0)):")
            for lo, hi in zip(qs[:-1], qs[1:]):
                m = (sc >= lo) & (sc <= hi) if hi == qs[-1] else (sc >= lo) & (sc < hi)
                if m.sum() < 20:
                    continue
                print(f"    [{lo:5.2f}, {hi:5.2f}): {m.sum():6d}  {cf[m].mean():+7.1f}  {100 * (cf[m] > 0).mean():5.1f} %")
    promise_report(rows)
    # Pre-schupf vs waiting: for players whose rule calls at the first card.
    pre = {(r["_f"], r["episode"], r["round"], r["seat"]): r for r in rows["pre"]}
    tich = {(r["_f"], r["episode"], r["round"], r["seat"]): r for r in rows["tichu"]}
    both = [(pre[k], tich[k]) for k in pre.keys() & tich.keys()]
    callers = [(p, t) for p, t in both if t["called"]]
    if callers:
        cfp = np.array([p["cf"] for p, _ in callers])
        print(f"\n=== timing: {len(callers)} hands the rule calls at the first card ===")
        print(f"  calling already before the schupf instead of waiting: mean {cfp.mean():+.1f} ± {cfp.std(ddof=1) / len(cfp) ** 0.5:.1f} pts, better in {100 * (cfp > 0).mean():.1f} %")


def promise_bucket(slot: int) -> str:
    """What a partner card says under 2+ HC Odd (lib/agents/partner_convention.dart)."""
    if slot in (PH, DR) or (0 <= slot < 52 and slot % 13 == 12):
        return "1 HC (passed)"
    if slot in (MJ, DOG) or (0 <= slot < 52 and (slot % 13 + 2) % 2 == 1):
        return "2+ HC (odd)"
    return "0 HC (even)"


def promise_report(rows: dict[str, list[dict]]) -> None:
    """Tichu decisions (no call at the table yet) by the partner card's promise.

    Only meaningful for labels from bots with ``--convention=twoHcOdd``. A
    Grand call by me or the partner turns the convention off, so those rounds
    are left out (joined from the grand rows of the same round).
    """
    grand = {(r["_f"], r["episode"], r["round"], r["seat"]): r["called"] for r in rows["grand"]}
    by = collections.defaultdict(list)
    for r in rows["tichu"]:
        if r["opp_called"] or r["received"][1] < 0:
            continue
        key = (r["_f"], r["episode"], r["round"])
        if grand.get((*key, r["seat"])) or grand.get((*key, (r["seat"] + 2) % 4)):
            continue
        by[promise_bucket(r["received"][1])].append(r)
    if not by:
        return
    print("\n=== tichu by the partner card's promise (2+ HC Odd; no call at the table) ===")
    for name in sorted(by):
        sub = by[name]
        cf = np.array([r["cf"] for r in sub], dtype=float)
        sc = np.array([r["score"] for r in sub], dtype=float)
        called = np.array([r["called"] for r in sub], dtype=bool)
        n = len(sub)
        ths = np.unique(np.quantile(sc, np.linspace(0.3, 0.999, 80)))
        best = max(ths, key=lambda t: (cf * (sc >= t)).mean())
        print(f"  {name}: {n} decisions, rule calls {100 * called.mean():.1f} %, "
              f"value {(cf * called).mean():+.2f} ± {(cf * called).std(ddof=1) / n ** 0.5:.2f}; "
              f"best threshold {best:.2f} -> {(cf * (sc >= best)).mean():+.2f}, calls {100 * (sc >= best).mean():.1f} %")
        for t in (-0.6, -0.4, -0.2, -0.1, 0.0, 0.2, 0.4):
            v = cf * (sc >= t)
            print(f"    threshold {t:+.1f}: {v.mean():+.2f} ± {v.std(ddof=1) / n ** 0.5:.2f}, calls {100 * (sc >= t).mean():.1f} %")


if __name__ == "__main__":
    main(sys.argv[1:])
