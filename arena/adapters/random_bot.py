#!/usr/bin/env python3
"""Reference adapter for the bot bridge (doc/bot_bridge.md): plays at random.

Shows the whole protocol in a few lines; also the weakest benchmark.
"""

import json
import random
import sys

rng = random.Random(int(sys.argv[1]) if len(sys.argv) > 1 else 0)


def check(state: dict) -> None:
    """The events must explain the hand: dealt - passed + received - played."""
    if "dealt" not in state:
        assert sorted(state["hand"]) == sorted(state["first_cards"]), state
        return
    hand = list(state["dealt"])
    me = state["seat"]
    for ev in state["events"]:
        if ev["e"] == "schupf" and ev["seat"] == me:
            for c in ev["give"].values():
                hand.remove(c)
        elif ev["e"] == "schupf_received":
            hand += ev["from"].values()
        elif ev["e"] == "play" and ev["seat"] == me:
            for c in ev["cards"]:
                hand.remove(c)
    assert sorted(hand) == sorted(state["hand"]), (hand, state["hand"])
    assert len(state["hand"]) == state["hand_counts"][me]


def decide(req: dict) -> dict:
    kind = req["type"]
    state = req["state"]
    check(state)
    if kind in ("grand", "tichu"):
        return {"call": False}
    if kind == "schupf":
        seat = state["seat"]
        cards = rng.sample(state["hand"], 3)
        return {"give": {str((seat + i + 1) % 4): c for i, c in enumerate(cards)}}
    if kind == "play":
        n = len(req["options"])
        if req["can_pass"] and rng.random() < 0.5 or n == 0:
            return {"option": None}
        i = rng.randrange(n)
        reply = {"option": i}
        if "MJ" in req["options"][i]["cards"]:
            reply["wish"] = rng.choice("23456789TJQKA")
        return reply
    if kind == "dragon":
        return {"to": rng.choice(req["targets"])}
    raise ValueError(f"unknown request {kind}")


for line in sys.stdin:
    req = json.loads(line)
    try:
        reply = decide(req)
    except Exception as e:  # report to the arena instead of dying silently
        reply = {"error": repr(e)}
    reply["id"] = req["id"]
    print(json.dumps(reply), flush=True)
