#!/usr/bin/env python3
"""Clear endgame mistakes of a play net, robust to hidden-card luck.

Input: headless rows with `--rollout-rate=1 --label-max-cards=5
--rollout-worlds=9 --worlds-min-cards=0 --rollout-max-actions=60 --describe`.
Every legal move of every endgame decision is played out on the real deal and
on 8 re-deals of the unseen cards. A *clear mistake*: another legal move is at
least MARGIN points better on average over the 9 worlds and no worse in at
least 8 of them, i.e. better whatever the hidden cards are.

  rl/.venv/bin/python rl/endgame_review.py endgame.jsonl [--examples=20]
"""
import argparse, json, sys
from collections import Counter, defaultdict
import numpy as np

sys.path.insert(0, str(__import__('pathlib').Path(__file__).resolve().parent))
from schema import SPEC

I = {}
for g in SPEC.groups:
    for i, n in enumerate(g.feature_names):
        I[n] = g.offset + i
A0 = SPEC.group('action').offset
TYPES = ['pass', 'single', 'pair', 'triplet', 'full_house', 'straight', 'pair_straight', 'bomb', 'dog']


def mtype(a):
    for t in TYPES:
        if a[I[f'type_{t}'] - A0] > 0.5:
            return t
    return '?'


def main():
    p = argparse.ArgumentParser()
    p.add_argument('jsonl')
    p.add_argument('--margin', type=float, default=20)
    p.add_argument('--examples', type=int, default=20)
    args = p.parse_args()
    n = 0
    mistakes = []
    by = defaultdict(lambda: [0, 0, 0.0])
    for line in open(args.jsonl):
        if '"q_rollout_worlds"' not in line:
            continue
        r = json.loads(line)
        W = [r['q_rollout']] + r['q_rollout_worlds']
        acts = r['legal_play_action_features']
        c = r['legal_play_chosen_index']
        ok = [a for a in range(len(acts)) if all(w[a] is not None for w in W)]
        if c not in ok or len(ok) < 2:
            continue
        Q = np.array([[w[a] for a in ok] for w in W], float)
        ci = ok.index(c)
        n += 1
        s = r['state_features']
        hand = round(s[I['hand_size']] * 14)
        lead = s[I['trick_lead']] > 0.5
        opp1 = s[I['left_one_card']] + s[I['right_one_card']] > 0
        situation = ('lead' if lead else 'follow') + f', {hand} cards' + (', opp has 1 card' if opp1 else '')
        best = None
        for j in range(len(ok)):
            if j == ci:
                continue
            d = Q[:, j] - Q[:, ci]
            if d.mean() >= args.margin and np.sum(d >= 0) >= 8:
                if best is None or d.mean() > best[1]:
                    best = (j, d.mean())
        key = situation
        by[key][0] += 1
        if best:
            by[key][1] += 1
            by[key][2] += best[1]
            mistakes.append((best[1], r, ok[best[0]], c, Q[:, best[0]] - Q[:, ci]))
    print(f'{n} endgame decisions (<= 5 cards), clear mistakes: {len(mistakes)} '
          f'({len(mistakes)/max(1,n)*100:.1f} %), avg loss when it happens {np.mean([m[0] for m in mistakes]) if mistakes else 0:.0f} points')
    print(f'points lost per endgame decision: {sum(m[0] for m in mistakes)/max(1,n):.2f}\n')
    print('by situation (decisions, mistakes, % , avg loss):')
    for k, (cnt, mis, loss) in sorted(by.items(), key=lambda kv: -kv[1][1]):
        if cnt >= 30:
            print(f'  {k:32s} {cnt:6d} {mis:5d} {mis/cnt*100:5.1f} %  {loss/max(1,mis):5.0f}')
    kinds = Counter(f"played {mtype(r['legal_play_action_features'][c])}, better {mtype(r['legal_play_action_features'][b])}" for _, r, b, c, _ in mistakes)
    print('\nkind of mistake:')
    for k, v in kinds.most_common(12):
        print(f'  {k:40s} {v}')
    print(f'\nworst {args.examples} examples (D = describe; L/P/R = left opponent, partner, right opponent):')
    for loss, r, b, c, d in sorted(mistakes, key=lambda m: -m[0])[:args.examples]:
        desc = r.get('desc', {})
        print(f"- loss {loss:.0f} (better in {int(np.sum(d > 0))}/9 worlds): "
              f"{json.dumps({k: desc.get(k) for k in ('hand', 'trick', 'winner', 'trick_points', 'counts', 'hands', 'calls', 'out', 'wish')})}")
        acts = desc.get('acts', [])
        print(f"    played: {acts[c] if c < len(acts) else c}   better: {acts[b] if b < len(acts) else b}")


if __name__ == '__main__':
    main()
