#!/usr/bin/env python3
"""Checks for rollout_train.py's label_p / stakes support (no pytest needed).

  rl/.venv/bin/python rl/test_rollout_train.py [stakes_run.jsonl]

Synthetic rows with and without ``label_p`` load from jsonl and through the
npz cache, old caches without the new columns still load, importance weights
are 1/label_p normalised to mean 1, and ``evaluate`` reports the gain per
stakes class. With a bc-jsonl file from ``headless --stakes-rollouts`` the
Dart stakes class of every row is also compared with the class derived from
its state features (``stakes_from_features``).
"""

from __future__ import annotations

import json
import sys
import tempfile
from pathlib import Path

import numpy as np
import torch

sys.path.insert(0, str(Path(__file__).resolve().parent))

from qnet import QNetwork  # noqa: E402
from rollout_train import (  # noqa: E402
    STAKES,
    _SEATS,
    _SELF,
    _TRICK,
    evaluate,
    importance_weights,
    load,
    save_npz,
    stakes_from_features,
)
from schema import ACTION_FEATURE_COUNT, STATE_FEATURE_COUNT, TOTAL_FEATURE_COUNT  # noqa: E402


def _state(*, hand: int = 10, lead: bool = False, partner_tichu: bool = False, left_few: bool = False):
    s = [0.0] * STATE_FEATURE_COUNT
    s[_SELF.index("hand_size")] = hand / 14
    s[_TRICK.index("trick_lead")] = 1.0 if lead else 0.0
    s[_SEATS.index("partner_tichu")] = 1.0 if partner_tichu else 0.0
    s[_SEATS.index("left_few_cards")] = 1.0 if left_few else 0.0
    return s


def _row(episode: int, state, q, *, label_p=None, stakes=None):
    rng = np.random.default_rng(episode * 31 + len(q))
    row = {
        "episode": episode,
        "state_features": state,
        "legal_play_action_features": rng.random((len(q), ACTION_FEATURE_COUNT)).round(3).tolist(),
        "legal_play_chosen_index": 0,
        "q_rollout": q,
        "q_rollout_own": [50.0] * len(q),
    }
    if label_p is not None:
        row["label_p"] = label_p
    if stakes is not None:
        row["stakes"] = stakes
    return row


def _write(path: Path, rows) -> None:
    path.write_text("".join(json.dumps(r) + "\n" for r in rows))


def check_synthetic() -> None:
    with tempfile.TemporaryDirectory() as td:
        td = Path(td)
        old = td / "old.jsonl"  # uniform --rollout-rate rows
        _write(old, [
            _row(1, _state(), [10.0, -10.0]),  # low
            _row(1, _state(lead=True), [0.0, 20.0, None]),  # mid (lead)
            _row(2, _state(hand=4), [5.0, 0.0]),  # high (endgame)
        ])
        new = td / "new.jsonl"  # --stakes-rollouts rows
        _write(new, [
            _row(3, _state(left_few=True), [30.0, -30.0], label_p=0.7, stakes="high"),
            _row(3, _state(partner_tichu=True), [1.0, 2.0], label_p=0.35, stakes="mid"),
            _row(4, _state(), [-5.0, 5.0], label_p=0.15, stakes="low"),
        ])
        data = load([old, new])
        assert data.num_decisions == 6
        assert torch.isnan(data.label_p[:3]).all()
        assert torch.allclose(data.label_p[3:], torch.tensor([0.7, 0.35, 0.15]))
        # Old rows get their class from the features, new rows keep theirs.
        assert data.stakes.tolist() == [2, 1, 0, 0, 1, 2], data.stakes.tolist()
        assert data.game.unique().numel() == 4

        w = importance_weights(data, default_label_p=0.5)
        assert abs(float(w.mean()) - 1.0) < 1e-6
        raw = 1 / torch.tensor([0.5, 0.5, 0.5, 0.7, 0.35, 0.15])
        assert torch.allclose(w, raw / raw.mean())

        # npz round trip keeps label_p and stakes.
        cache = td / "c.npz"
        save_npz(data, cache)
        back = load([cache])
        assert torch.equal(back.stakes, data.stakes)
        assert torch.allclose(back.label_p, data.label_p, equal_nan=True)

        # A cache written before label_p / stakes existed still loads.
        d = dict(np.load(cache))
        del d["label_p"], d["stakes"]
        legacy = td / "legacy.npz"
        np.savez_compressed(legacy, **d)
        old_back = load([legacy])
        assert torch.isnan(old_back.label_p).all()
        assert torch.equal(old_back.stakes, data.stakes)  # derived from features

        model = QNetwork(TOTAL_FEATURE_COUNT, [8])
        m = evaluate(model, data, torch.arange(data.num_decisions))
        for c in STAKES:
            assert f"gain_pts_{c}" in m, m
    print("synthetic checks: ok")


def check_run(path: Path) -> None:
    """Dart classes in a --stakes-rollouts run vs the feature-derived ones."""
    rows = [json.loads(line) for line in path.open() if '"q_rollout"' in line]
    rows = [r for r in rows if sum(v is not None for v in r["q_rollout"]) >= 2]
    assert rows and all("label_p" in r and "stakes" in r for r in rows)
    s = torch.tensor([r["state_features"] for r in rows])
    derived = stakes_from_features(s).tolist()
    dart = [STAKES.index(r["stakes"]) for r in rows]
    same = sum(a == b for a, b in zip(derived, dart))
    assert same == len(rows), f"{len(rows) - same} of {len(rows)} rows differ"
    data = load([path])
    assert not torch.isnan(data.label_p).any()
    shares = {c: dart.count(i) / len(dart) for i, c in enumerate(STAKES)}
    print(f"{path.name}: {len(rows)} labelled rows, classes agree; label shares {shares}")


if __name__ == "__main__":
    check_synthetic()
    for arg in sys.argv[1:]:
        check_run(Path(arg))
