#!/usr/bin/env python3
"""Is the bot's one-on-one endgame play perfect, and where not?

Reads rows of ``build/bin/review_1v1`` (lib/headless/review_one_on_one.dart):
every one-on-one decision with the exact minimax value of each legal action
for the decider's team. A move is perfect when its value equals the best
value (the position's value); its loss is best - chosen (exact, whatever
the opponent does).

  rl/.venv/bin/python rl/review_1v1.py rl/outputs/review_1v1/net.jsonl
"""

from __future__ import annotations

import collections
import json
import sys

import numpy as np


def kind(row: dict, i: int) -> str:
    a = row["actions"][i]
    if a == "pass":
        return "pass"
    if a.startswith("dragon"):
        return "dragon"
    return "play"


def shape(a: str) -> str:
    n = len(a.split())
    return {1: "single", 2: "pair", 3: "triple"}.get(n, f"{n} cards")


def rank(tok: str) -> int:
    return {"Dog": 0, "1": 1, "T": 10, "J": 11, "Q": 12, "K": 13, "A": 14, "Ph": 15, "Dr": 16}.get(tok) or int(tok)


def report(path: str) -> None:
    rows = [json.loads(l) for l in open(path, encoding="utf-8")]
    n = len(rows)
    loss = np.array([max(r["values"]) - r["values"][r["chosen"]] for r in rows], dtype=float)
    choice = np.array([len(set(r["values"])) > 1 for r in rows])  # the move matters
    print(f"\n######## {path}: {n} one-on-one decisions (<= 10 cards in the two hands)")
    print(f"  the move matters (actions differ in value): {100 * choice.mean():.1f} %")
    err = loss > 0
    print(f"  perfect: {100 * (1 - err.mean()):.1f} % of all, {100 * (1 - err[choice].mean()):.1f} % of those where it matters")
    print(f"  mean loss {loss.mean():.2f} points per decision; per error {loss[err].mean():.1f}; "
          f"errors >= 50 points: {(loss >= 50).sum()} ({100 * (loss >= 50).mean():.1f} %)")

    def split(name, keyf):
        groups = collections.defaultdict(list)
        for r, l, c in zip(rows, loss, choice):
            if c:
                groups[keyf(r)].append(l)
        print(f"\n  by {name} (decisions where the move matters):")
        for k, ls in sorted(groups.items(), key=lambda kv: -len(kv[1])):
            ls = np.array(ls)
            print(f"    {str(k):34s} n={len(ls):6d}  perfect {100 * (ls == 0).mean():5.1f} %  mean loss {ls.mean():6.2f}  per error {ls[ls > 0].mean() if (ls > 0).any() else 0:6.1f}")

    split("situation", lambda r: "Dragon gift" if r["kind"] == "dragon" else ("lead" if r["leading"] else ("follow, I win the trick" if r["winner_is_me"] else "follow")))
    split("cards in the two hands", lambda r: len(r["me"].split()) + len(r["opp"].split()))
    split("my cards vs opponent's", lambda r: "I have fewer" if len(r["me"].split()) < len(r["opp"].split()) else ("equal" if len(r["me"].split()) == len(r["opp"].split()) else "I have more"))
    split("first player out", lambda r: {True: "my team went out first", False: "opponents went out first", None: "?"}[r["first_out_mine"]])

    # error types
    types = collections.Counter()
    type_loss = collections.defaultdict(float)
    examples = []
    for r, l in zip(rows, loss):
        if l <= 0:
            continue
        best = int(np.argmax(r["values"]))
        bests = [i for i, v in enumerate(r["values"]) if v == max(r["values"])]
        ck = kind(r, r["chosen"])
        bk = {kind(r, i) for i in bests}
        if r["kind"] == "dragon":
            t = "Dragon to the wrong opponent"
        elif ck == "pass":
            t = "passed, should have played"
        elif "pass" in bk and "play" not in bk:
            t = "played, should have passed"
        else:
            ca = r["actions"][r["chosen"]]
            ba = r["actions"][best]
            if r["leading"]:
                if shape(ca) != shape(ba):
                    t = f"led {shape(ca)}, should lead {shape(ba)}"
                else:
                    t = f"led the wrong {shape(ca)}"
            else:
                cr = max(rank(x) for x in ca.split())
                br = max(rank(x) for x in ba.split())
                t = "beat too high (kept a lower card)" if cr > br else ("beat too low" if cr < br else "wrong cards (same rank)")
        types[t] += 1
        type_loss[t] += l
        examples.append((l, t, r))
    tot = sum(types.values())
    print(f"\n  error types ({tot} errors):")
    for t, k in types.most_common():
        print(f"    {t:40s} {k:6d} ({100 * k / tot:4.1f} %)  total loss share {100 * type_loss[t] / loss.sum():4.1f} %  mean {type_loss[t] / k:5.1f}")
    print("\n  largest errors:")
    for l, t, r in sorted(examples, key=lambda e: -e[0])[:12]:
        acts = ", ".join(f"{a}={v:+d}" for a, v in zip(r["actions"], r["values"]))
        print(f"    -{l:.0f} [{t}] me: {r['me']} | opp: {r['opp']} | trick: {r['trick'] or '-'} ({r['trick_points']} pts)"
              f" | chose {r['actions'][r['chosen']]} | {acts}")


if __name__ == "__main__":
    for p in sys.argv[1:]:
        report(p)
