#!/usr/bin/env python3
"""What the bots pass in the schupf, and what it does to every hand.

Reads bc-jsonl written with ``--skip-play-rows`` (schupf rows carry the
passer's 14 cards and the three other hands before the exchange; call rows
carry the post-exchange hand and whether the player called Tichu at the
first card). Rebuilds all four post-exchange hands of each round and
reports:

  * what goes to the partner / the opponents (rank, specials, the passer's
    strongest card or not), split by whether the passer calls Tichu;
  * whether passing splits a pair / triple / bomb or breaks a straight;
  * whether the passed card completes a bomb, pair or straight for the
    receiver (opponent or partner), and whether we receive bombs;
  * straights and bombs kept / built over the exchange.

  rl/.venv/bin/python rl/schupf_report.py rl/outputs/calls_v8/cf_*.jsonl
"""

from __future__ import annotations

import collections
import json
import sys

# Card slots: color*13 + (rank-2) for 2..A, 52 Mah Jong, 53 Dog, 54 Phoenix, 55 Dragon.
MJ, DOG, PH, DR = 52, 53, 54, 55


def rank(slot: int) -> int:
    """2..14 for normal cards, Mah Jong 1, Dog 0, Phoenix 15, Dragon 16."""
    if slot < 52:
        return slot % 13 + 2
    return {MJ: 1, DOG: 0, PH: 15, DR: 16}[slot]


def suit(slot: int) -> int:
    return slot // 13 if slot < 52 else -1


def counts(hand) -> collections.Counter:
    return collections.Counter(rank(s) for s in hand if s < 52)


def quads(hand) -> set[int]:
    return {r for r, k in counts(hand).items() if k == 4}


def straight_flushes(hand) -> int:
    n = 0
    for su in range(4):
        rs = sorted({rank(s) for s in hand if s < 52 and suit(s) == su})
        run = best = 0
        prev = None
        for r in rs:
            run = run + 1 if prev is not None and r == prev + 1 else 1
            prev = r
            best = max(best, run)
        n += best >= 5
    return n


def bombs(hand) -> int:
    return len(quads(hand)) + straight_flushes(hand)


def longest_straight(hand) -> int:
    """Longest run of consecutive ranks (Mah Jong = 1), Phoenix fills one gap."""
    rs = {rank(s) for s in hand if s < 52 or s == MJ}
    ph = PH in hand
    best = 0
    for start in range(1, 15):
        if start not in rs and not ph:
            continue
        gap = ph
        length = 0
        r = start
        while r <= 14:
            if r in rs:
                length += 1
            elif gap:
                gap = False
                length += 1
            else:
                break
            r += 1
        best = max(best, length)
    return best if best >= 5 else 0


def strength_order(hand) -> list[int]:
    return sorted(hand, key=lambda s: (rank(s), s), reverse=True)


def pct(a: float, b: float) -> str:
    return f"{100 * a / b:5.1f} %" if b else "   - "


def main(paths: list[str]) -> None:
    rounds: dict[tuple, list[dict]] = collections.defaultdict(list)
    calls: dict[tuple, dict] = {}
    for p in paths:
        tag = p
        for line in open(p, encoding="utf-8"):
            if '"schupf"' in line:
                r = json.loads(line)
                rounds[(tag, r["episode"], r["round"])].append(r)
            elif '"call":"tichu"' in line:
                r = json.loads(line)
                calls[(tag, r["episode"], r["round"], tuple(sorted(r["hand"])))] = r
    c = collections.Counter()
    partner_rank = collections.defaultdict(collections.Counter)
    opp_rank = collections.Counter()
    for key, rows in rounds.items():
        if len(rows) != 4:
            continue
        by_hand = {tuple(sorted(r["hand"])): r for r in rows}
        try:
            # oracle = [left, partner, right] hands before the exchange
            nbr = {
                id(r): [by_hand[tuple(sorted(h))] for h in r["oracle"]] for r in rows
            }
        except KeyError:
            continue
        received = {id(r): [] for r in rows}  # (card, from: L/P/R)
        for r in rows:
            L, P, R = nbr[id(r)]
            received[id(L)].append((r["left"], "R"))  # I am L's right neighbour
            received[id(P)].append((r["partner"], "P"))
            received[id(R)].append((r["right"], "L"))
        post = {id(r): [s for s in r["hand"] if s not in (r["left"], r["partner"], r["right"])] + [x for x, _ in received[id(r)]] for r in rows}
        for r in rows:
            hand = r["hand"]
            L, P, R = nbr[id(r)]
            ph = post[id(r)]
            called = calls.get(key + (tuple(sorted(ph)),))
            group = "caller" if called and called["called"] else ("no_call" if called else "unknown")
            ctx = r["context"]  # [grand, tichu] x me, partner, left, right
            partner_grand = ctx[2] > 0
            c["schupfs"] += 1
            c[f"g_{group}"] += 1
            order = strength_order(hand)
            pr = r["partner"]
            pos = order.index(pr)
            partner_rank[group][pos + 1 if rank(pr) else "Dog"] += 1
            if partner_grand:
                partner_rank["partner_grand"][pos + 1 if rank(pr) else "Dog"] += 1
            for s in (r["left"], r["right"]):
                opp_rank[rank(s)] += 1
            # specials
            for name, slot in (("Dragon", DR), ("Phoenix", PH), ("Dog", DOG), ("MahJong", MJ)):
                if slot in hand:
                    c[f"held_{name}"] += 1
                    if pr == slot:
                        c[f"{name}_to_partner"] += 1
                    elif slot in (r["left"], r["right"]):
                        c[f"{name}_to_opp"] += 1
            aces = [s for s in hand if s < 52 and rank(s) == 14]
            if aces:
                c["held_ace"] += 1
                if pr in aces:
                    c["ace_to_partner"] += 1
            # splitting own sets / straights
            cnt = counts(hand)
            kept = [s for s in hand if s not in (r["left"], r["partner"], r["right"])]
            for s, who in ((r["left"], "opp"), (r["right"], "opp"), (pr, "partner")):
                if s < 52 and cnt[rank(s)] >= 2:
                    c[f"split_set_{who}"] += 1
                if s < 52 and cnt[rank(s)] == 4:
                    c["split_own_bomb"] += 1
            if longest_straight(hand) and not longest_straight(kept):
                c["broke_own_straight"] += 1
            elif longest_straight(hand) and longest_straight(kept) < longest_straight(hand):
                c["shortened_own_straight"] += 1
            if longest_straight(hand):
                c["had_straight"] += 1
            # bombs / straights over the exchange
            b0, b1 = bombs(hand), bombs(ph)
            c["bombs_before"] += b0
            c["bombs_after"] += b1
            if b1 > bombs(kept):
                c["received_bomb"] += 1
                for x, w in received[id(r)]:
                    if bombs(kept + [x]) > bombs(kept):
                        c[f"bomb_completed_by_{'partner' if w == 'P' else 'opponent'}"] += 1
            s0, s1 = longest_straight(hand), longest_straight(ph)
            if s1 and not s0:
                c["straight_built"] += 1
            if s0 and not s1:
                c["straight_lost"] += 1
            # what my pass does to the receivers
            for s, recv, who in ((r["left"], L, "opp"), (r["right"], R, "opp"), (pr, P, "partner")):
                rp = post[id(recv)]
                without = [x for x in rp if x != s]
                if bombs(rp) > bombs(without):
                    c[f"gave_bomb_{who}"] += 1
                if s < 52 and counts(without)[rank(s)] >= 1:
                    c[f"gave_pair_{who}"] += 1
                if longest_straight(rp) > longest_straight(without):
                    c[f"gave_straight_{who}"] += 1
    n = c["schupfs"]
    print(f"{n} schupf decisions ({c['g_caller']} by players who then call Tichu at the first card, {c['g_no_call']} who do not, {c['g_unknown']} already called / Grand)\n")
    print("TO THE PARTNER: position of the passed card in the passer's strength order (1 = strongest)")
    for g in ("caller", "no_call", "unknown", "partner_grand"):
        tot = sum(partner_rank[g].values())
        if not tot:
            continue
        row = "  ".join(f"{k}:{100 * v / tot:4.1f}%" for k, v in sorted(partner_rank[g].items(), key=lambda kv: (isinstance(kv[0], str), kv[0])))
        label = {"caller": "passer then calls Tichu", "no_call": "passer does not call", "unknown": "passer had called before", "partner_grand": "partner called Grand Tichu"}[g]
        print(f"  {label:28s} (n={tot:6d})  {row}")
    print("\nSPECIAL CARDS (share of the times the passer held it)")
    for name in ("Dragon", "Phoenix", "Dog", "MahJong"):
        h = c[f"held_{name}"]
        print(f"  {name:8s} to partner {pct(c[name + '_to_partner'], h)}   to an opponent {pct(c[name + '_to_opp'], h)}")
    print(f"  Ace      to partner {pct(c['ace_to_partner'], c['held_ace'])} (when holding one)")
    tot = sum(opp_rank.values())
    print("\nTO THE OPPONENTS: rank of the passed card (0 Dog, 1 Mah Jong, 2..14, 15 Ph, 16 Dr)")
    print("  " + "  ".join(f"{k}:{100 * v / tot:.1f}%" for k, v in sorted(opp_rank.items())))
    print("\nOWN HAND")
    print(f"  passes that split a pair/triple: to opponents {pct(c['split_set_opp'], 2 * n)} of opponent passes, to partner {pct(c['split_set_partner'], n)}")
    print(f"  passes that break up an own bomb: {c['split_own_bomb']} of {3 * n}")
    print(f"  straight (>= 5) before the exchange: {pct(c['had_straight'], n)} of hands; destroyed by the pass: {pct(c['broke_own_straight'], c['had_straight'])} of those, shortened {pct(c['shortened_own_straight'], c['had_straight'])}")
    print(f"  straight built by the received cards: {pct(c['straight_built'], n)} of hands; straight lost over the exchange: {pct(c['straight_lost'], n)}")
    print(f"  bombs per hand before {c['bombs_before'] / n:.3f}, after {c['bombs_after'] / n:.3f}; a received card completes a bomb in {pct(c['received_bomb'], n)} of hands"
          f" (by partner {c['bomb_completed_by_partner']}, by an opponent {c['bomb_completed_by_opponent']})")
    print("\nWHAT OUR PASS DOES TO THE RECEIVER (share of passes)")
    for who, den in (("opp", 2 * n), ("partner", n)):
        print(f"  to {'opponents' if who == 'opp' else 'partner  '}: completes a bomb {pct(c['gave_bomb_' + who], den)}, makes a pair (or more) {pct(c['gave_pair_' + who], den)}, lengthens a straight >= 5 {pct(c['gave_straight_' + who], den)}")


if __name__ == "__main__":
    main(sys.argv[1:])
