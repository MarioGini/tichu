"""JSONL data loading and feature encoding for Tichu RL training.

Reads the transition JSONL produced by the Dart headless runner and encodes
each (state, action) pair into the same 64-dimensional feature vector that
the Dart-side feature_encoder.dart uses for inference.

This is the single source of truth for Python-side feature encoding.  Any
change here MUST be mirrored in lib/agents/nn/feature_encoder.dart.
"""

from __future__ import annotations

import json
from collections import defaultdict
from pathlib import Path

import numpy as np
import torch
from torch.utils.data import Dataset

# Must match Dart feature_encoder.dart constants.
STATE_FEATURE_COUNT = 46       # 0-31: core state, 32-39: hand structure, 40-45: opponent
OPPONENT_FEATURE_COUNT = 6
STATE_AND_OPP_COUNT = STATE_FEATURE_COUNT + OPPONENT_FEATURE_COUNT  # 52
ACTION_FEATURE_COUNT = 12
TOTAL_FEATURE_COUNT = STATE_AND_OPP_COUNT + ACTION_FEATURE_COUNT    # 64

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
    i = 0

    # ── state features (38) ──────────────────────────────────────────────
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

    # ── action features (12) ─────────────────────────────────────────────
    action = row.get("action", {})
    action_map = action if isinstance(action, dict) else {}
    action_type = str(action_map.get("type", row.get("action_type", "")))
    action_cards = row.get("cards", [])
    action_card_list = action_cards if isinstance(action_cards, list) else []

    if action_type == "pass":
        f[i + 5] = 1.0  # pass slot
    elif action_type == "play":
        shape_key = str(row.get("action_shape_key", ""))
        action_key = str(row.get("action_key", ""))
        key = shape_key if shape_key else action_key
        turn_type = _extract_turn_type(key)

        if turn_type == "single":
            f[i] = 1.0
        elif turn_type == "pair":
            f[i] = 0.5; f[i + 1] = 1.0
        elif turn_type in ("triple", "triplet"):
            f[i + 2] = 1.0
        elif turn_type in ("straight", "pairStraight", "fullHouse"):
            f[i + 3] = 1.0
        elif turn_type == "bomb":
            f[i + 4] = 1.0

        deck_value = _num(state.get("deck_value", 0))
        action_value = _extract_action_value(key)
        f[i + 6] = action_value / 25.0
        f[i + 7] = len(action_card_list) / 14.0

        for card in action_card_list:
            s = str(card) if card is not None else ""
            if s.startswith("phoenix"): f[i + 8] = 1.0
            if s.startswith("dragon"):  f[i + 9] = 1.0
            if s.startswith("dog"):     f[i + 10] = 1.0

        f[i + 11] = max(-1.0, min(1.0, (action_value - deck_value) / 25.0))

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


# ── Data loading ─────────────────────────────────────────────────────────────

def load_episodes(path: Path) -> list[list[dict]]:
    """Load a JSONL file into a list of episodes (each a list of transitions)."""
    by_episode: dict[int, list[dict]] = defaultdict(list)
    with path.open("r", encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            row = json.loads(line)
            ep = int(row.get("episode", 0))
            by_episode[ep].append(row)
    return [by_episode[k] for k in sorted(by_episode)]


def compute_mc_returns(
    episodes: list[list[dict]],
    gamma: float = 0.99,
) -> list[tuple[dict, float]]:
    """Compute Monte Carlo returns for each transition, partitioned by team."""
    samples: list[tuple[dict, float]] = []
    for episode in episodes:
        by_team: dict[int, list[dict]] = defaultdict(list)
        for row in episode:
            team = int(row.get("team", 0))
            by_team[team].append(row)

        for team_rows in by_team.values():
            g = 0.0
            for row in reversed(team_rows):
                reward = float(row.get("reward", 0))
                disc_raw = row.get("discount")
                if isinstance(disc_raw, (int, float)):
                    discount = float(disc_raw)
                elif isinstance(row.get("done"), bool):
                    discount = 0.0 if row["done"] else 1.0
                else:
                    discount = 1.0
                g = reward + gamma * discount * g
                samples.append((row, g))
    return samples


# ── PyTorch Dataset ──────────────────────────────────────────────────────────

class TransitionDataset(Dataset):
    """Lazily‑encoded dataset of (feature_vector, mc_return) pairs."""

    def __init__(
        self,
        samples: list[tuple[dict, float]],
        target_mean: float = 0.0,
        target_std: float = 1.0,
    ) -> None:
        features: list[np.ndarray] = []
        targets: list[float] = []
        for row, mc_return in samples:
            f = encode_transition(row)
            if f is None:
                continue
            features.append(f)
            targets.append(mc_return)

        self.features = torch.from_numpy(np.stack(features))  # (N, 50) float32
        raw_targets = np.array(targets, dtype=np.float32)

        # Normalise targets and expose stats (needed for denormalisation).
        self.target_mean = target_mean
        self.target_std = target_std
        if target_mean == 0.0 and target_std == 1.0:
            # Auto‑compute from data.
            self.target_mean = float(raw_targets.mean())
            self.target_std = float(raw_targets.std()) if len(raw_targets) > 1 else 1.0
            if self.target_std < 1e-8:
                self.target_std = 1.0

        self.targets = torch.from_numpy(
            (raw_targets - self.target_mean) / self.target_std
        ).unsqueeze(1)  # (N, 1)

    def __len__(self) -> int:
        return len(self.features)

    def __getitem__(self, idx: int) -> tuple[torch.Tensor, torch.Tensor]:
        return self.features[idx], self.targets[idx]


class PreEncodedTransitionDataset(Dataset):
    """Dataset backed by pre-encoded feature and return tensors."""

    def __init__(
        self,
        features: torch.Tensor,
        raw_targets: torch.Tensor,
        target_mean: float = 0.0,
        target_std: float = 1.0,
    ) -> None:
        self.features = features.to(torch.float32).contiguous()

        raw = raw_targets.to(torch.float32).cpu().numpy()
        self.target_mean = target_mean
        self.target_std = target_std
        if target_mean == 0.0 and target_std == 1.0:
            self.target_mean = float(raw.mean())
            self.target_std = float(raw.std()) if len(raw) > 1 else 1.0
            if self.target_std < 1e-8:
                self.target_std = 1.0

        normalized = (raw - self.target_mean) / self.target_std
        self.targets = torch.from_numpy(normalized).unsqueeze(1)

    def __len__(self) -> int:
        return len(self.features)

    def __getitem__(self, idx: int) -> tuple[torch.Tensor, torch.Tensor]:
        return self.features[idx], self.targets[idx]


def build_training_tensors_from_jsonl(
    path: Path,
    gamma: float = 0.99,
) -> tuple[np.ndarray, np.ndarray, dict[str, str]]:
    """Create encoded features and MC-return targets from transition JSONL."""
    episodes = load_episodes(path)
    samples = compute_mc_returns(episodes, gamma=gamma)

    features: list[np.ndarray] = []
    returns: list[float] = []
    for row, mc_return in samples:
        encoded = encode_transition(row)
        if encoded is None:
            continue
        features.append(encoded)
        returns.append(mc_return)

    if not features:
        raise ValueError(f"No encodable samples found in {path}")

    feature_tensor = np.stack(features).astype(np.float32)
    return_tensor = np.asarray(returns, dtype=np.float32)
    metadata = {
        "format": "tichu_train_dataset_v1",
        "source": str(path),
        "episodes": str(len(episodes)),
        "samples": str(len(return_tensor)),
        "feature_count": str(feature_tensor.shape[1]),
        "gamma": str(gamma),
    }
    return feature_tensor, return_tensor, metadata


def save_training_tensors_safetensors(
    features: np.ndarray,
    returns: np.ndarray,
    output_path: Path,
    metadata: dict[str, str] | None = None,
) -> None:
    """Persist training tensors in safetensors format."""
    from safetensors.torch import save_file as st_save

    output_path.parent.mkdir(parents=True, exist_ok=True)
    tensors = {
        "features": torch.from_numpy(features).contiguous(),
        "returns": torch.from_numpy(returns).contiguous(),
    }
    header = {
        "format": "tichu_train_dataset_v1",
        "samples": str(features.shape[0]),
        "feature_count": str(features.shape[1]),
    }
    if metadata:
        header.update(metadata)
    st_save(tensors, str(output_path), metadata=header)


def load_training_tensors_safetensors(
    path: Path,
) -> tuple[torch.Tensor, torch.Tensor, dict[str, str]]:
    """Load pre-encoded training tensors from safetensors."""
    from safetensors import safe_open
    from safetensors.torch import load_file as st_load

    tensors = st_load(str(path))
    if "features" not in tensors or "returns" not in tensors:
        raise ValueError(
            f"{path} must contain 'features' and 'returns' tensors"
        )

    with safe_open(str(path), framework="pt", device="cpu") as reader:
        metadata = dict(reader.metadata() or {})

    features = tensors["features"].to(torch.float32).cpu().contiguous()
    returns = tensors["returns"].to(torch.float32).view(-1).cpu().contiguous()
    return features, returns, metadata
