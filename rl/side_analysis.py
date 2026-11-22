#!/usr/bin/env python3
"""Dragon gift and Mah Jong wish: exact values of every option.

Input: headless `--side-rollout-rate=1` rows (`"side": "dragon"|"wish"`).
For each decision every option was played out on the same deal, so the
difference between two options has no card luck. Reports the value of the
bots' rule against simple alternatives (points per decision, ± SE).

  rl/.venv/bin/python rl/side_analysis.py rl/outputs/side/side.jsonl
"""
import json, math, sys
from collections import defaultdict
import numpy as np

rows = defaultdict(list)
for line in open(sys.argv[1]):
    if '"side"' not in line:
        continue
    r = json.loads(line)
    if any(v is None for v in r['values']):
        continue
    rows[r['side']].append(r)

def report(name, gains):
    g = np.asarray(gains, float)
    se = g.std(ddof=1) / math.sqrt(len(g)) if len(g) > 1 else 0
    print(f"  {name:58s} {g.mean():+6.2f} ± {se:4.2f}  (differs in {np.mean(g != 0)*100:4.1f} %)")

# ---------------------------------------------------------------- Dragon
d = rows['dragon']
print(f"DRAGON GIFT: {len(d)} decisions with two opponents to choose from")
d = [r for r in d if len(r['options']) == 2]
spread = np.array([abs(r['values'][0] - r['values'][1]) for r in d])
print(f"  options differ in {np.mean(spread > 0)*100:.0f} % of decisions, by {spread[spread>0].mean():.1f} points when they do")
best = [max(r['values']) - r['values'][r['chosen']] for r in d]
print(f"  rule's loss vs the better recipient (hindsight): {np.mean(best):.2f} points per decision")
def pick(r, key):  # index of the option chosen by a rule; key(seat) -> score, higher = give
    sc = [key(r, s) for s in r['options']]
    return int(np.argmax(sc)) if sc[0] != sc[1] else r['chosen']
cards = lambda r, s: r['cards_by_seat'][s]
rules = {
    'more cards (likely last)': lambda r, s: cards(r, s),
    'fewer cards': lambda r, s: -cards(r, s),
    'not out yet, else more cards': lambda r, s: (cards(r, s) > 0, cards(r, s)),
    'no call, then more cards': lambda r, s: (r['call_by_seat'][s] == 0, cards(r, s)),
    'fewer points won so far': lambda r, s: -r['points_by_seat'][s],
    'left opponent (next to play)': lambda r, s: (s - r['seat']) % 4 == 1,
    'right opponent': lambda r, s: (s - r['seat']) % 4 == 3,
}
for name, key in rules.items():
    gains = []
    for r in d:
        i = pick(r, lambda rr, s: key(rr, s) if not isinstance(key(rr, s), tuple) else key(rr, s))
        gains.append(r['values'][i] - r['values'][r['chosen']])
    report(f"{name} vs the bots' rule", gains)
# by situation: does someone already out matter?
for label, sel in [('nobody out yet', lambda r: not r['finish_seats']),
                   ('my team has the first player out', lambda r: r['finish_seats'] and r['finish_seats'][0] % 2 == r['seat'] % 2),
                   ('an opponent is out first', lambda r: r['finish_seats'] and r['finish_seats'][0] % 2 != r['seat'] % 2)]:
    sub = [r for r in d if sel(r)]
    if len(sub) > 50:
        g = [r['values'][pick(r, lambda rr, s: cards(rr, s))] - r['values'][r['chosen']] for r in sub]
        o = [max(r['values']) - r['values'][r['chosen']] for r in sub]
        print(f"   {label:34s} n={len(sub):5d}  hindsight loss {np.mean(o):5.2f}; 'more cards' vs rule {np.mean(g):+5.2f}")

# ---------------------------------------------------------------- Wish
w = rows['wish']
print(f"\nMAH JONG WISH: {len(w)} decisions, 14 options (none, 2..A)")
names = w[0]['options'] if w else []
V = np.array([r['values'] for r in w])
ch = np.array([r['chosen'] for r in w])
chosen_v = V[np.arange(len(w)), ch]
print(f"  rule's loss vs the best wish (hindsight): {np.mean(V.max(1) - chosen_v):.2f} points per decision")
for j, nm in enumerate(names):
    report(f"always wish {nm} vs the rule", V[:, j] - chosen_v)
# wish the highest rank not in hand and not ... (variants)
RANK = {n: i for i, n in enumerate(names)}
def hand_ranks(r):
    return {s % 13 + 2 for s in r['hand'] if s < 52}
def best_unheld(r, order):
    held = hand_ranks(r)
    for nm in order:
        if RANK[nm] and (RANK[nm] + 1) not in held:
            return RANK[nm]
    return 0
for label, order in [('highest unheld A..10 (the rule)', ['ace', 'king', 'queen', 'jack', 'ten']),
                     ('highest unheld A..2', names[:0:-1]),
                     ('highest unheld K..10 (never ace)', ['king', 'queen', 'jack', 'ten'])]:
    g = [r['values'][best_unheld(r, order)] - r['values'][r['chosen']] for r in w]
    report(f"{label} vs the rule", g)
