#!/usr/bin/env python3
"""Play-style profile of a bot: what it does, not only how often it wins.

Streams ``headless --format=bc-jsonl --describe`` (decision rows with the
actor's hand, the trick, the legal moves and the chosen one) and aggregates
style metrics for the policy team (team 0): pass rates when it could play,
overtaking the partner, spending control cards early, cheapest-beat rate,
breaking pairs / triples, lead shapes, blocking a one-card opponent, bombs,
plus round outcomes (going out first, double wins, calls, trick points).

  # v10 against the heuristic (the policy team is team 0)
  rl/.venv/bin/python rl/style_report.py --matches=400 \\
      --a="--nn-policy=assets/bots/tichu_q_v10.safetensors" --b=""
  # self-play: --self (all four seats play side A)

Output: one JSON object of metrics (``--json``) or a readable table.
"""

from __future__ import annotations

import argparse
import collections
import json
import math
import os
import shlex
import subprocess
import sys
import threading
from pathlib import Path

RANKS = {"Dog": 0, "1": 1, "T": 10, "J": 11, "Q": 12, "K": 13, "A": 14, "Ph": 15, "Dr": 16}
CONTROL = {"A", "Dr", "Ph"}


def rank(tok: str) -> int:
    return RANKS[tok] if tok in RANKS else int(tok)


def toks(s: str) -> list[str]:
    return s.split() if s else []


def shape(cards: list[str]) -> str:
    """Rough combination type from rank tokens (colors are not logged)."""
    n = len(cards)
    if n == 0:
        return "pass"
    if n == 1:
        return "single"
    c = collections.Counter(t for t in cards if t != "Ph")
    ph = "Ph" in cards
    if n == 2:
        return "pair"
    if n == 3:
        return "triple"
    if n == 4 and len(c) == 1 and not ph:
        return "bomb4"
    if n == 5 and sorted(c.values()) in ([2, 3], [1, 3], [2, 2]) and len(c) == 2:
        return "fullhouse"
    if n >= 4 and n % 2 == 0 and all(v <= 2 for v in c.values()) and len(c) * 2 >= n - 1 and len(c) < n - 1:
        return "pairseq"
    return "straight"


class Stats:
    def __init__(self) -> None:
        self.c: collections.Counter[str] = collections.Counter()
        self.lead_shapes: collections.Counter[str] = collections.Counter()
        self.lock = threading.Lock()

    def ratio(self, num: str, den: str) -> float:
        return 100.0 * self.c[num] / self.c[den] if self.c[den] else float("nan")

    def decision(self, d: dict, chosen: str) -> None:
        c = self.c
        hand = toks(d["hand"])
        n = len(hand)
        acts = d["acts"]
        can_pass = "pass" in acts
        plays = [a for a in acts if a != "pass"]
        played = toks(chosen) if chosen != "pass" else []
        lead = not can_pass and d["trick_type"] in ("empty", "none")
        bucket = "early" if n >= 10 else ("mid" if n >= 5 else "late")
        c["decisions"] += 1
        hcount = collections.Counter(hand)
        if played:
            # breaking a set: played fewer cards of a rank than held (not
            # bombs: four of a kind counted separately)
            for r, k in collections.Counter(played).items():
                if r not in ("Ph",) and hcount[r] > k and hcount[r] >= 2:
                    c["broke_set"] += 1
                    break
            c["plays"] += 1
            if hcount and any(v == 4 for r, v in hcount.items() if r != "Ph"):
                c["plays_holding_bomb"] += 1
            if shape(played) == "bomb4":
                c["bombs"] += 1
                c[f"bombs_{bucket}"] += 1
                if d["winner"] == "P":
                    c["bombs_on_partner"] += 1
            if n >= 10 and any(t in CONTROL for t in played):
                c["control_spent_early"] += 1
            if any(t in CONTROL for t in played):
                c["control_spent"] += 1
        if n >= 10:
            c["decisions_early"] += 1
        if lead:
            c["leads"] += 1
            s = shape(played)
            self.lead_shapes[s] += 1
            c[f"lead_cards"] += len(played)
            if s == "single":
                c["lead_single"] += 1
                c["lead_single_rank"] += rank(played[0])
                if rank(played[0]) >= 13:
                    c["lead_single_high"] += 1
            if "Dog" in played:
                c["lead_dog"] += 1
            if "Dog" in hand:
                c["lead_holding_dog"] += 1
            counts = d["counts"]  # L, P, R
            opp_one = counts[0] == 1 or counts[2] == 1
            if opp_one:
                c["lead_vs_one_card_opp"] += 1
                if s == "single":
                    c["lead_single_vs_one_card_opp"] += 1
                    # a single that the one-card opponent can still beat
                    if rank(played[0]) < 14:
                        c["lead_low_single_vs_one_card_opp"] += 1
            if counts[1] <= 2 and counts[1] > 0:
                c["lead_partner_short"] += 1
                if "Dog" in played:
                    c["dog_to_short_partner"] += 1
                if "Dog" in hand:
                    c["lead_partner_short_holding_dog"] += 1
            return
        if not can_pass:
            return  # forced play (wish)
        c["follow"] += 1
        if not plays:
            c["follow_forced_pass"] += 1
            return
        c["follow_could_play"] += 1
        c[f"follow_could_play_{bucket}"] += 1
        w = d["winner"]
        who = "partner" if w == "P" else "opp"
        c[f"follow_could_play_{who}"] += 1
        if chosen == "pass":
            c["pass_could_play"] += 1
            c[f"pass_could_play_{bucket}"] += 1
            c[f"pass_could_play_{who}"] += 1
            if "P" in d["calls"] and who == "partner":
                c["pass_partner_tichu"] += 1
        else:
            if who == "partner" and "P" in d["calls"]:
                c["overtake_partner_tichu"] += 1
            # cheapest beat on singles: played the lowest single that beats
            if d["trick_type"] == "single" and len(played) == 1:
                singles = sorted(rank(a) for a in plays if len(toks(a)) == 1)
                c[f"single_beats_{who}"] += 1
                if singles and rank(played[0]) == singles[0]:
                    c[f"single_cheapest_{who}"] += 1
                c[f"single_overkill_{who}"] += rank(played[0]) - (singles[0] if singles else rank(played[0]))
                if played[0] in ("A", "Dr", "Ph") and int(d["trick_points"]) <= 0 and who == "opp":
                    c["control_on_pointless_single"] += 1
            if len(played) == n:
                c["play_out"] += 1
        if "P" in d["calls"] and who == "partner":
            c["follow_partner_tichu"] += 1

    def round_end(self, r: dict, team: int) -> None:
        c = self.c
        c["rounds"] += 1
        own = r["team_one_round"] if team == 0 else r["team_two_round"]
        opp = r["team_two_round"] if team == 0 else r["team_one_round"]
        c["round_diff"] += own - opp
        ft = r.get("finish_teams", [])
        if ft and ft[0] == team:
            c["first_out"] += 1
        if len(ft) >= 2 and ft[0] == ft[1] == team:
            c["double_win"] += 1
        if len(ft) >= 2 and ft[0] == ft[1] != team:
            c["double_lost"] += 1
        if ft and ft[-1] == team and len(ft) == 4:
            c["last_out"] += 1
        tp = r.get("trick_points_by_seat")
        if tp:
            c["trick_points"] += tp[team] + tp[team + 2]
        for t, kind, ok, *_ in r.get("calls", []):
            if t == team:
                c[f"call_{kind}"] += 1
                c[f"call_{kind}_ok"] += int(ok)

    def summary(self) -> dict[str, float]:
        c = self.c
        R = max(1, c["rounds"])
        total_leads = max(1, sum(self.lead_shapes.values()))
        ent = -sum(v / total_leads * math.log2(v / total_leads) for v in self.lead_shapes.values() if v)
        out = {
            "rounds": c["rounds"],
            "round_diff": c["round_diff"] / R,
            "first_out_%": 100 * c["first_out"] / R,
            "double_win_%": 100 * c["double_win"] / R,
            "double_lost_%": 100 * c["double_lost"] / R,
            "last_out_%(player)": 100 * c["last_out"] / R,
            "trick_points": c["trick_points"] / R,
            "tichu_calls_%": 100 * c["call_tichu"] / R,
            "tichu_success_%": 100 * c["call_tichu_ok"] / max(1, c["call_tichu"]),
            "grand_calls_%": 100 * c["call_grandTichu"] / R,
            "grand_success_%": 100 * c["call_grandTichu_ok"] / max(1, c["call_grandTichu"]),
            "decisions_per_round": c["decisions"] / R,
            "pass_when_could_play_%": self.ratio("pass_could_play", "follow_could_play"),
            "  vs_opponent_trick_%": self.ratio("pass_could_play_opp", "follow_could_play_opp"),
            "  on_partner_trick_%": self.ratio("pass_could_play_partner", "follow_could_play_partner"),
            "  early(>=10 cards)_%": self.ratio("pass_could_play_early", "follow_could_play_early"),
            "  mid(5-9)_%": self.ratio("pass_could_play_mid", "follow_could_play_mid"),
            "  late(<=4)_%": self.ratio("pass_could_play_late", "follow_could_play_late"),
            "overtake_partner_tichu_%": self.ratio("overtake_partner_tichu", "follow_partner_tichu"),
            "cheapest_single_beat_vs_opp_%": self.ratio("single_cheapest_opp", "single_beats_opp"),
            "single_overkill_vs_opp(ranks)": c["single_overkill_opp"] / max(1, c["single_beats_opp"]),
            "control_spent_early_per_round": c["control_spent_early"] / R,
            "control_on_pointless_single_per_round": c["control_on_pointless_single"] / R,
            "broke_set_%_of_plays": self.ratio("broke_set", "plays"),
            "bombs_per_round": c["bombs"] / R,
            "  bombs_early_share_%": self.ratio("bombs_early", "bombs"),
            "  bombs_on_partner_per_100_rounds": 100 * c["bombs_on_partner"] / R,
            "lead_cards_avg": c["lead_cards"] / max(1, c["leads"]),
            "lead_single_%": self.ratio("lead_single", "leads"),
            "lead_single_rank_avg": c["lead_single_rank"] / max(1, c["lead_single"]),
            "lead_single_high(K+)_%": self.ratio("lead_single_high", "lead_single"),
            "lead_shape_entropy_bits": ent,
            "lead_single_vs_1card_opp_%": self.ratio("lead_single_vs_one_card_opp", "lead_vs_one_card_opp"),
            "  low_single_vs_1card_opp_%": self.ratio("lead_low_single_vs_one_card_opp", "lead_vs_one_card_opp"),
            "dog_to_short_partner_%": self.ratio("dog_to_short_partner", "lead_partner_short_holding_dog"),
        }
        for s, v in sorted(self.lead_shapes.items()):
            out[f"lead_shape_{s}_%"] = 100 * v / total_leads
        return out


def run_shard(binary: str, args: list[str], seed: int, episodes: int, stats: Stats, team_of_interest: int, self_play: bool) -> None:
    cmd = [binary, f"--seed={seed}", f"--episodes={episodes}", "--format=bc-jsonl", "--describe",
           "--output=/dev/stdout", "--epsilon=0", *args]
    p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, bufsize=1 << 20)
    local = Stats()
    assert p.stdout is not None
    for line in p.stdout:
        if '"round_end"' in line[:60]:
            r = json.loads(line)
            local.round_end(r, team_of_interest)
            if self_play:
                local.round_end(r, 1 - team_of_interest)
            continue
        if '"desc"' not in line:
            continue
        d = json.loads(line)
        if not self_play and d.get("team") != team_of_interest:
            continue
        desc = d["desc"]
        i = d.get("legal_play_chosen_index", -1)
        acts = desc["acts"]
        if not (0 <= i < len(acts)):
            continue
        local.decision(desc, acts[i])
    p.wait()
    with stats.lock:
        stats.c.update(local.c)
        stats.lead_shapes.update(local.lead_shapes)


def profile(a: str, b: str | None, matches: int, seed: int, shards: int) -> dict[str, float]:
    binary = os.environ.get("TICHU_HEADLESS", "build/bin/headless")
    self_play = b is None
    args = shlex.split(a) + ([] if self_play else ["--mixed", *shlex.split(b)])
    stats = Stats()
    per = math.ceil(matches / shards)
    th = [threading.Thread(target=run_shard, args=(binary, args, seed + 1000 * k, per, stats, 0, self_play)) for k in range(shards)]
    for t in th:
        t.start()
    for t in th:
        t.join()
    return stats.summary()


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--a", default="", help="headless args of the profiled side (team 0)")
    p.add_argument("--b", default="", help="opponent args (--opponent-policy=...); '' = heuristic")
    p.add_argument("--self", action="store_true", help="all four seats play side A")
    p.add_argument("--matches", type=int, default=200)
    p.add_argument("--seed", type=int, default=5150)
    p.add_argument("--shards", type=int, default=4)
    p.add_argument("--json", action="store_true")
    args = p.parse_args()
    s = profile(args.a, None if args.self else args.b, args.matches, args.seed, args.shards)
    if args.json:
        print(json.dumps(s))
    else:
        for k, v in s.items():
            print(f"{k:42s} {v:8.2f}")


if __name__ == "__main__":
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    main()
