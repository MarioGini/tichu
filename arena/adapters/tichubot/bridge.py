#!/usr/bin/env python3
"""Bot bridge adapter (doc/bot_bridge.md) for rumoschilling/tichubot.

    rl/.venv/bin/python arena/adapters/tichubot/bridge.py [SEED]

Plays their released PPO model (checkpoints/tichubot-best.pt, fetched by
arena/fetch.sh) the way their own table plays it: the play policy samples
its move, the bundled pass and Grand Tichu nets and the Dragon and wish
heads decide the rest. Each request rebuilds their GameState from the
round's events with their advisor's tools (setup_game, apply_manual_passing,
force_play), which reconcile the guessed hidden hands with what the others
played, as at a real table.
"""

from __future__ import annotations

import copy
import importlib
import json
import random
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2] / ".bots" / "rumoschilling__tichubot"
sys.path.insert(0, str(REPO))

# Their package is importable only now.
torch = importlib.import_module("torch")
_cards = importlib.import_module("tichu_env.cards")
_combos = importlib.import_module("tichu_env.combinations")
advisor = importlib.import_module("training.advisor")
_play = importlib.import_module("training.play")
MAHJONG_INDEX = _cards.MAHJONG_INDEX
DOG_INDEX = _cards.DOG_INDEX
PHOENIX_INDEX = _cards.PHOENIX_INDEX
DRAGON_INDEX = _cards.DRAGON_INDEX
binary_phoenix_interpretations = _combos.binary_phoenix_interpretations
classify_cards = _combos.classify_cards
ai_gt = _play.ai_gt
ai_select_action = _play.ai_select_action
ai_select_dragon_recipient = _play.ai_select_dragon_recipient
ai_select_mahjong_wish = _play.ai_select_mahjong_wish
load_play_bundle = _play.load_play_bundle

RANKS = "23456789TJQKA"
SUITS = {"g": 0, "k": 1, "r": 2, "b": 3}  # their JADE, PAGODA, STAR, SWORD
SPECIAL = {"MJ": MAHJONG_INDEX, "DG": DOG_INDEX, "PH": PHOENIX_INDEX, "DR": DRAGON_INDEX}
SPECIAL_CODE = {v: k for k, v in SPECIAL.items()}
TYPES = {1: "dog", 2: "single", 3: "pair", 4: "triple", 5: "straight",
         6: "full_house", 7: "pair_straight", 8: "bomb", 9: "bomb"}


def card(code: str) -> int:
    if code in SPECIAL:
        return SPECIAL[code]
    return SUITS[code[1]] * 13 + RANKS.index(code[0])


def code(c: int) -> str:
    if c in SPECIAL_CODE:
        return SPECIAL_CODE[c]
    suit = {v: k for k, v in SUITS.items()}[c // 13]
    return RANKS[c % 13] + suit


def rank_key(cards) -> list[str]:
    return sorted(code(c) if c >= 52 else code(c)[0] for c in cards)


class Adapter:
    def __init__(self, seed: int):
        random.seed(seed)
        torch.manual_seed(seed)
        self.rng = random.Random(seed)
        self.device = torch.device("cpu")
        ckpt = REPO / "checkpoints" / "tichubot-best.pt"
        self.policy, self.pass_policy, self.gt_policy, self.kind, _ = load_play_bundle(
            str(ckpt), None, self.device)
        # Their move for (seat, round, events seen): asked for the Tichu call
        # first, then played.
        self.pending: dict[tuple, tuple] = {}

    # -- the shadow game ------------------------------------------------------

    def shadow(self, state: dict):
        me = state["seat"]
        events = state["events"]
        gs = advisor.setup_game([card(c) for c in state["dealt"]], me,
                                track_history=(self.kind == "history"))
        for ev in events:
            if ev["e"] == "grand" and ev["call"]:
                gs.tichu_declarations[ev["seat"]] = 2
        early = [ev["seat"] for ev in events
                 if ev["e"] == "tichu" and not any(e["e"] == "schupf_received" for e in events[:events.index(ev)])]
        for s in early:
            gs.tichu_declarations[s] = 1
        give = next((ev["give"] for ev in events if ev["e"] == "schupf" and ev["seat"] == me), None)
        got = next((ev["from"] for ev in events if ev["e"] == "schupf_received"), None)
        if got is None:
            return gs, False
        order = [(me + i) % 4 for i in (1, 2, 3)]
        advisor.apply_manual_passing(
            gs, me, tuple(card(give[str(s)]) for s in order), tuple(card(got[str(s)]) for s in order))
        first = next((ev["seat"] for ev in events if ev["e"] == "play"), None)
        if MAHJONG_INDEX not in gs.hands[me]:
            holder = advisor.known_mahjong_holder_from_passing(gs, me)
            if holder is None and first is not None:
                holder = first
                owner = next(p for p in range(4) if MAHJONG_INDEX in gs.hands[p])
                if owner != holder:
                    swap = self.rng.choice([c for c in gs.hands[holder] if c != MAHJONG_INDEX])
                    gs.hands[owner].remove(MAHJONG_INDEX)
                    gs.hands[owner].add(swap)
                    gs.hands[holder].remove(swap)
                    gs.hands[holder].add(MAHJONG_INDEX)
                    gs._invalidate_cache()
            if holder is not None:
                gs.current_player = holder
        started = False
        for ev in events:
            if ev["e"] == "schupf_received":
                started = True
                continue
            if not started:
                continue
            kind = ev["e"]
            if kind == "tichu":
                gs.tichu_declarations[ev["seat"]] = 1
            elif kind in ("play", "pass"):
                p = ev["seat"]
                cards = [card(c) for c in ev.get("cards", [])]
                phoenix_as = self.phoenix_as(cards, ev.get("type"), ev.get("value"))
                if p == me:
                    ok = gs.play(p, (cards, False), phoenix_as=phoenix_as)
                else:
                    ok = advisor.force_play(gs, p, cards, me, phoenix_as=phoenix_as)
                if not ok:
                    raise ValueError(f"their engine refused seat {p} {kind} {ev.get('cards')}")
                if MAHJONG_INDEX in cards:
                    w = ev.get("wish")
                    gs.set_mahjong_wish(None if w is None else RANKS.index(w) + 2)
            elif kind == "dragon":
                if not gs.give_dragon_trick(ev["seat"], ev["to"]):
                    raise ValueError("their engine refused the Dragon gift")
        return gs, True

    @staticmethod
    def phoenix_as(cards, kind, value):
        if PHOENIX_INDEX not in cards or len(cards) < 5:
            return None
        meanings = binary_phoenix_interpretations(cards)
        if not meanings:
            return None
        for m in meanings:
            if abs(m.rank - value) < 0.01:
                return m.phoenix_as
        return None

    # -- decisions --------------------------------------------------------------

    def choose(self, state: dict, gs):
        me = state["seat"]
        key = (me, state["events"][0]["round"], len([e for e in state["events"] if e["e"] != "tichu"]))
        if key not in self.pending:
            self.pending = {key: ai_select_action(self.policy, gs, me, self.device, self.rng, self.kind)}
        return self.pending[key]

    def to_option(self, action, options: list[dict]):
        cards = list(action[0])
        if not cards:
            return None
        phoenix_high = bool(action[2]) if len(action) == 3 else False
        combo = classify_cards(cards)
        meanings = binary_phoenix_interpretations(cards) if PHOENIX_INDEX in cards else None
        if meanings:
            combo = meanings[1] if phoenix_high else meanings[0]
        kind = TYPES[int(combo.type)]
        value = 0.0 if kind == "dog" else (25.0 if cards == [DRAGON_INDEX] else float(combo.rank))
        want = sorted(code(c) for c in cards)
        exact = by_rank = by_value = None
        for j, o in enumerate(options):
            if o["type"] != kind:
                continue
            same_value = kind in ("single", "dog") or abs(o["value"] - value) < 0.01 \
                or (kind == "bomb" and len(o["cards"]) == len(cards))
            if sorted(o["cards"]) == want and (same_value or exact is None):
                exact = j
            elif kind != "bomb" and same_value and by_rank is None and \
                    rank_key([card(c) for c in o["cards"]]) == rank_key(cards):
                by_rank = j
            elif kind != "bomb" and same_value and by_value is None and len(o["cards"]) == len(cards):
                by_value = j
        j = next((x for x in (exact, by_rank, by_value) if x is not None), None)
        if j is None:
            raise ValueError(f"their bot chose {want} ({kind} {value}), not among our options")
        return j

    def decide(self, req: dict) -> dict:
        state = req["state"]
        me = state["seat"]
        t = req["type"]
        if t == "grand":
            return {"call": ai_gt(self.gt_policy, [card(c) for c in state["first_cards"]], self.device)}
        gs, playing = self.shadow(state)
        if t == "tichu":
            if req["phase"] != "play" or not gs.can_call_tichu(me):
                return {"call": False}
            return {"call": bool(self.choose(state, gs)[1])}
        if t == "schupf":
            left, partner, right = advisor.suggest_pass(self.pass_policy, gs, me, self.device)
            return {"give": {str((me + 1) % 4): code(left), str((me + 2) % 4): code(partner),
                             str((me + 3) % 4): code(right)}}
        if t == "play":
            if sorted(code(c) for c in gs.hands[me]) != sorted(state["hand"]):
                raise ValueError("shadow hand differs from the real one")
            action = self.choose(state, gs)
            j = self.to_option(action, req["options"])
            reply = {"option": j}
            if j is not None and MAHJONG_INDEX in action[0]:
                after = copy.deepcopy(gs)
                after.play(me, (list(action[0]), False))
                w = ai_select_mahjong_wish(self.policy, after, me, self.device, self.rng, self.kind)
                reply["wish"] = None if w is None else RANKS[w - 2]
            return reply
        if t == "dragon":
            to = ai_select_dragon_recipient(self.policy, gs, me, self.device, self.rng, self.kind)
            if to not in req["targets"]:
                to = req["targets"][0]
            return {"to": to}
        raise ValueError(f"unknown request {t}")


def main() -> None:
    seed = int(sys.argv[1]) if len(sys.argv) > 1 else 1
    ad = Adapter(seed)
    out = sys.stdout
    sys.stdout = sys.stderr  # their code prints; keep the protocol channel clean
    for line in sys.stdin:
        req = json.loads(line)
        try:
            reply = ad.decide(req)
        except Exception as e:  # reported to the arena, which stops the match
            import os
            import traceback
            dump = os.environ.get("BRIDGE_DUMP")
            if dump:
                with open(dump, "a") as f:
                    f.write(line)
            reply = {"error": f"{e!r} {traceback.format_exc(limit=3)}"}
        reply["id"] = req["id"]
        out.write(json.dumps(reply) + "\n")
        out.flush()


if __name__ == "__main__":
    main()
