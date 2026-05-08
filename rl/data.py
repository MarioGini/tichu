"""JSONL feature encoder shared between Python (training) and Dart.

Encodes a transition JSONL row from the Dart headless runner into the
fixed-length feature vector defined by ``rl/schema/feature_spec.json``.

Only used as a fallback path: the preferred ``--format=bc-jsonl`` output
already contains the pre-encoded state vector, so the BC trainer skips
this re-encoding entirely. We keep ``encode_transition`` for compatibility
with legacy ``--format=rl-jsonl`` files.
"""

from __future__ import annotations

from collections import defaultdict

import numpy as np

# Authoritative layout lives in rl/schema/feature_spec.json. The Dart side
# loads the same file (see lib/agents/nn/feature_layout.dart and the schema
# test under test/agents/feature_layout_test.dart).
from schema import (
    ACTION_OFFSET,
    HAND_STRUCTURE_OFFSET,
    OPPONENT_OFFSET,
    STATE_OFFSET,
    TOTAL_FEATURE_COUNT,
)

_RANK_MAP = {
    "two": 2, "three": 3, "four": 4, "five": 5, "six": 6,
    "seven": 7, "eight": 8, "nine": 9, "ten": 10,
    "jack": 11, "queen": 12, "king": 13, "ace": 14,
}


def _rank(token: str) -> int:
    return _RANK_MAP.get(token, 0)


def _num(v: object) -> float:
    return float(v) if isinstance(v, (int, float)) else 0.0


def _bool(v: object) -> float:
    return 1.0 if v is True else 0.0


# ── Feature encoding ────────────────────────────────────────────────────────

def encode_transition(row: dict) -> np.ndarray | None:
    """Encode a single JSONL transition into a float32 feature vector.

    Returns None if the row lacks the required ``state`` dict.
    """
    state = row.get("state")
    if not isinstance(state, dict):
        return None

    f = np.zeros(TOTAL_FEATURE_COUNT, dtype=np.float32)
    i = STATE_OFFSET

    # ── state features (32) ──────────────────────────────────────
    f[i] = _num(state.get("team", 0));                            i += 1  # 0
    f[i] = float(state.get("current_player_id") == state.get("player_id")); i += 1  # 1

    phase = str(state.get("phase", ""))
    f[i] = float(phase == "grandTichu");                          i += 1  # 2
    f[i] = float(phase == "schupf");                              i += 1  # 3
    f[i] = float(phase == "play");                                i += 1  # 4

    hand = state.get("hand", [])
    hand_list = hand if isinstance(hand, list) else []
    f[i] = len(hand_list) / 14.0;                                i += 1  # 5

    low = mid = high = special = 0
    has_mj = has_ph = has_dr = has_dg = False
    for tok in hand_list:
        s = str(tok) if tok is not None else ""
        if s.startswith("mahJong") or s.startswith("mah"):
            has_mj = True; special += 1
        elif s.startswith("phoenix"):
            has_ph = True; special += 1
        elif s.startswith("dragon"):
            has_dr = True; special += 1
        elif s.startswith("dog"):
            has_dg = True; special += 1
        else:
            rank = _rank(s.split("-")[0])
            if rank <= 6:   low += 1
            elif rank <= 10: mid += 1
            else:            high += 1

    f[i] = low / 14.0;      i += 1  # 6
    f[i] = mid / 14.0;      i += 1  # 7
    f[i] = high / 14.0;     i += 1  # 8
    f[i] = special / 4.0;   i += 1  # 9
    f[i] = float(has_mj);   i += 1  # 10
    f[i] = float(has_ph);   i += 1  # 11
    f[i] = float(has_dr);   i += 1  # 12
    f[i] = float(has_dg);   i += 1  # 13
    f[i] = _bool(state.get("has_bomb"));      i += 1  # 14
    f[i] = _bool(state.get("can_bomb"));      i += 1  # 15
    f[i] = _bool(state.get("can_call_tichu")); i += 1  # 16

    deck_type = str(state.get("deck_type", "empty"))
    is_empty = deck_type in ("empty", "none")
    is_bomb = deck_type == "bomb"
    f[i] = float(is_empty);                          i += 1  # 17
    f[i] = float(not is_empty and not is_bomb);       i += 1  # 18
    f[i] = float(is_bomb);                            i += 1  # 19
    f[i] = _num(state.get("deck_value", 0)) / 25.0;  i += 1  # 20

    deck_cards = state.get("deck_cards", [])
    f[i] = (len(deck_cards) if isinstance(deck_cards, list) else 0) / 14.0; i += 1  # 21

    i += 3  # 22-24: trick_winner_relation (zeros — not available in raw JSON)

    wish = str(state.get("active_wish", "none"))
    if wish != "none":
        f[i] = _rank(wish) / 14.0
    i += 1  # 25
    i += 1  # 26: has_wish_in_hand (zeros)

    f[i] = _num(state.get("consecutive_passes", 0)) / 3.0; i += 1  # 27

    score = state.get("score", {})
    score_map = score if isinstance(score, dict) else {}
    finish_order = score_map.get("finish_order", [])
    f[i] = (len(finish_order) if isinstance(finish_order, list) else 0) / 4.0; i += 1  # 28

    team = int(_num(state.get("team", 0)))
    t1 = _num(score_map.get("team_one_total", 0)) + _num(score_map.get("team_one_round", 0))
    t2 = _num(score_map.get("team_two_total", 0)) + _num(score_map.get("team_two_round", 0))
    own = t1 if team == 0 else t2
    opp = t2 if team == 0 else t1
    f[i] = max(-1.0, min(1.0, (own - opp) / 500.0)); i += 1  # 29

    tichu_calls = score_map.get("tichu_calls") or state.get("tichu_calls") or {}
    calls_map = tichu_calls if isinstance(tichu_calls, dict) else {}
    player_id = str(state.get("player_id", ""))
    own_call = str(calls_map.get(player_id, "none"))
    f[i] = float(own_call == "tichu");       i += 1  # 30
    f[i] = float(own_call == "grandTichu");  i += 1  # 31

    assert i == HAND_STRUCTURE_OFFSET, f"state group misaligned: i={i}"

    # ── hand structure features (8) ──────────────────────────────────────
    # We approximate from the hand token list.  The Dart side uses
    # generateLegalTurns() for exact counts; here we estimate from face
    # value grouping (good enough for training signal).
    face_counts: dict[str, int] = defaultdict(int)
    for tok in hand_list:
        s = str(tok) if tok is not None else ""
        face = s.split("-")[0] if "-" in s else s.split(":")[0]
        if face:
            face_counts[face] += 1

    pair_count = sum(1 for c in face_counts.values() if c >= 2)
    triplet_count = sum(1 for c in face_counts.values() if c >= 3)
    bomb_count = sum(1 for c in face_counts.values() if c >= 4)

    # Estimate straights: count runs of consecutive ranks.
    ranks_present = sorted(set(_rank(face) for face in face_counts if _rank(face) > 0))
    straight_count = 0
    if len(ranks_present) >= 5:
        run = 1
        for j in range(1, len(ranks_present)):
            if ranks_present[j] == ranks_present[j-1] + 1:
                run += 1
                if run >= 5:
                    straight_count += 1
            else:
                run = 1

    full_house_count = min(pair_count, triplet_count)
    pair_straight_count = sum(1 for c in face_counts.values() if c >= 2) // 2
    max_combo = max((max(face_counts.values()) if face_counts else 1), 1)
    if straight_count > 0:
        max_combo = max(max_combo, 5)

    multi_cards = pair_count * 2 + triplet_count * 3
    singleton_frac = max(0.0, 1.0 - multi_cards / max(1, len(hand_list)))

    f[i] = pair_count / 7.0;         i += 1  # 32
    f[i] = triplet_count / 4.0;      i += 1  # 33
    f[i] = straight_count / 4.0;     i += 1  # 34
    f[i] = full_house_count / 4.0;   i += 1  # 35
    f[i] = pair_straight_count / 4.0; i += 1  # 36
    f[i] = bomb_count / 2.0;         i += 1  # 37
    f[i] = max_combo / 14.0;         i += 1  # 38
    f[i] = singleton_frac;           i += 1  # 39

    assert i == OPPONENT_OFFSET, f"hand_structure group misaligned: i={i}"

    # ── opponent features (6) ────────────────────────────────────────────
    opp_counts = state.get("opponent_card_counts", {})
    opp_map = opp_counts if isinstance(opp_counts, dict) else {}
    counts = sorted(float(v) / 14.0 for v in opp_map.values() if isinstance(v, (int, float)))
    for j in range(min(3, len(counts))):
        f[i + j] = counts[j]
    i += 3  # 40-42

    partner_called = any_opp_tichu = any_opp_grand = False
    for k, v in calls_map.items():
        if k == player_id:
            continue
        c = str(v)
        if c == "tichu":      any_opp_tichu = True
        if c == "grandTichu": any_opp_grand = True
        if c != "none":       partner_called = True
    f[i] = float(partner_called);   i += 1  # 43
    f[i] = float(any_opp_tichu);    i += 1  # 44
    f[i] = float(any_opp_grand);    i += 1  # 45
    assert i == ACTION_OFFSET, f"opponent group misaligned: i={i}"
    # ── action features (20) ─────────────────────────────────────────────
    # Schema v3 layout: see rl/schema/feature_spec.json.
    action = row.get("action", {})
    action_map = action if isinstance(action, dict) else {}
    action_type = str(action_map.get("type", row.get("action_type", "")))
    action_cards = row.get("cards", [])
    action_card_list = action_cards if isinstance(action_cards, list) else []

    if action_type == "pass":
        f[i + 0] = 1.0  # type_pass
    elif action_type == "play":
        shape_key = str(row.get("action_shape_key", ""))
        action_key = str(row.get("action_key", ""))
        key = shape_key if shape_key else action_key
        turn_type = _extract_turn_type(key)

        # Type one-hot (mutually exclusive).
        if turn_type == "single":
            f[i + 1] = 1.0
        elif turn_type == "pair":
            f[i + 2] = 1.0
        elif turn_type in ("triple", "triplet"):
            f[i + 3] = 1.0
        elif turn_type == "fullHouse":
            f[i + 4] = 1.0
        elif turn_type == "straight":
            f[i + 5] = 1.0
        elif turn_type == "pairStraight":
            f[i + 6] = 1.0
        elif turn_type == "bomb":
            f[i + 7] = 1.0

        deck_value = _num(state.get("deck_value", 0))
        action_value = _extract_action_value(key)
        f[i + 8] = action_value / 25.0
        f[i + 9] = len(action_card_list) / 14.0

        # Special card flags + per-rank histograms + max rank.
        low_played = mid_played = high_played = 0
        max_rank = 0
        for card in action_card_list:
            s = str(card) if card is not None else ""
            if s.startswith("phoenix"):
                f[i + 10] = 1.0
                continue
            if s.startswith("dragon"):
                f[i + 11] = 1.0
                if 15 > max_rank:
                    max_rank = 15
                continue
            if s.startswith("dog"):
                f[i + 12] = 1.0
                continue
            if s.startswith("mahJong") or s.startswith("mah"):
                f[i + 13] = 1.0
                if 1 > max_rank:
                    max_rank = 1
                continue
            face = s.split("-")[0] if "-" in s else s.split(":")[0]
            r = _rank(face)
            if r <= 0:
                continue
            if r <= 6:
                low_played += 1
            elif r <= 10:
                mid_played += 1
            else:
                high_played += 1
            if r > max_rank:
                max_rank = r
        f[i + 14] = low_played / 14.0
        f[i + 15] = mid_played / 14.0
        f[i + 16] = high_played / 14.0
        f[i + 17] = max_rank / 15.0

        deck_type = str(state.get("deck_type", "empty"))
        f[i + 18] = max(-1.0, min(1.0, (action_value - deck_value) / 25.0))
        f[i + 19] = (
            1.0
            if deck_type in ("empty", "none")
            else (1.0 if action_value > deck_value else 0.0)
        )

    return f


def _extract_turn_type(key: str) -> str:
    parts = key.split(":")
    return parts[1] if len(parts) >= 2 else ""


def _extract_action_value(key: str) -> float:
    parts = key.split(":")
    if len(parts) >= 3:
        try:
            return float(parts[2])
        except ValueError:
            pass
    return 0.0
