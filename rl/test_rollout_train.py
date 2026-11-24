#!/usr/bin/env python3
"""Checks for rollout_train.py's data loading (no pytest needed).

  rl/.venv/bin/python rl/test_rollout_train.py

Synthetic rows load from jsonl and through the npz cache, caches with the
columns of removed experiments (``own``, ``label_p``, ``stakes``) still
load, ``evaluate`` reports the held-out gains, and data and nets of the
layouts before v7 pad / widen with zeros and keep their outputs.
"""

from __future__ import annotations

import json
import sys
import tempfile
from pathlib import Path

import numpy as np
import torch

sys.path.insert(0, str(Path(__file__).resolve().parent))

from qnet import QNetwork, export_safetensors, load_qnetwork_from_safetensors  # noqa: E402
from data_upgrade import BEAT  # noqa: E402
from rollout_train import evaluate, load, save_npz  # noqa: E402
from schema import (  # noqa: E402
    ACTION_FEATURE_COUNT,
    ACTION_OFFSET,
    LEGACY_ACTION_FEATURE_COUNT,
    LEGACY_STATE_PREFIX,
    STATE_FEATURE_COUNT,
    TOTAL_FEATURE_COUNT,
)


def _state(seed: int):
    return np.random.default_rng(seed).random(STATE_FEATURE_COUNT).round(3).tolist()


def _row(episode: int, state, q, **extra):
    rng = np.random.default_rng(episode * 31 + len(q))
    return {
        "episode": episode,
        "state_features": state,
        "legal_play_action_features": rng.random((len(q), ACTION_FEATURE_COUNT)).round(3).tolist(),
        "legal_play_chosen_index": 0,
        "q_rollout": q,
        "q_rollout_own": [50.0] * len(q),
        **extra,
    }


def _write(path: Path, rows) -> None:
    path.write_text("".join(json.dumps(r) + "\n" for r in rows))


def check_synthetic() -> None:
    with tempfile.TemporaryDirectory() as td:
        td = Path(td)
        rows = td / "rows.jsonl"
        _write(rows, [
            _row(1, _state(1), [10.0, -10.0]),
            _row(1, _state(2), [0.0, 20.0, None]),  # unlabelled action dropped
            _row(2, _state(3), [5.0, None]),  # one labelled action: skipped
            _row(2, _state(4), [5.0, 0.0]),
            # Columns of removed experiments are ignored.
            _row(3, _state(5), [30.0, -30.0], label_p=0.7, stakes="high"),
        ])
        data = load([rows])
        assert data.num_decisions == 4, data.num_decisions
        assert data.a.shape[0] == 8
        assert data.game.unique().numel() == 3
        assert torch.allclose(data.q[:4], torch.tensor([0.1, -0.1, 0.0, 0.2]))

        # npz round trip.
        cache = td / "c.npz"
        save_npz(data, cache)
        back = load([cache])
        for k in ("s", "a", "q", "starts", "chosen", "explore", "game"):
            assert torch.equal(getattr(back, k), getattr(data, k)), k

        # A cache with the columns of removed experiments still loads.
        d = dict(np.load(cache))
        n = len(d["chosen"])
        d.update(
            own=np.zeros(len(d["q"]), np.float32),
            label_p=np.full(n, 0.5, np.float32),
            stakes=np.zeros(n, np.int8),
        )
        legacy = td / "legacy.npz"
        np.savez_compressed(legacy, **d)
        old_back = load([legacy])
        assert torch.equal(old_back.q, data.q) and torch.equal(old_back.s, data.s)

        # Recency weights by rollout_loop iteration (file name itNN_*).
        first, third = td / "it01_self.npz", td / "it03_self.npz"
        save_npz(data, first)
        save_npz(data, third)
        both = load([first, third], recency=0.8)
        assert torch.allclose(both.weight[:4], torch.full((4,), 0.64))
        assert torch.allclose(both.weight[4:], torch.ones(4))

        model = QNetwork(TOTAL_FEATURE_COUNT, [8])
        m = evaluate(model, data, torch.arange(data.num_decisions))
        for k in ("agree", "gain_pts", "vs_uniform_pts", "clairvoyant_pts", "mse", "var"):
            assert k in m, m
    print("synthetic checks: ok")


def check_legacy_layouts() -> None:
    """Data and nets of the layouts before v7 (state 201 / 267 / 268 wide,
    51 action features) pad / widen with zeros and keep their outputs."""
    with tempfile.TemporaryDirectory() as td:
        td = Path(td)
        for size, prefix in sorted(LEGACY_STATE_PREFIX.items()):
            na = size - prefix  # action features of this layout (51, or 54 for v7)
            rng = np.random.default_rng(size)
            rows = []
            for ep in range(3):
                rows.append({
                    "episode": ep,
                    "state_features": rng.random(prefix).round(3).tolist(),
                    "legal_play_action_features": rng.random((2, na)).round(3).tolist(),
                    "legal_play_chosen_index": 0,
                    "q_rollout": [10.0, -10.0],
                })
            path = td / f"v{size}.jsonl"
            _write(path, rows)
            data = load([path])
            assert data.s.shape == (3, STATE_FEATURE_COUNT), data.s.shape
            assert data.a.shape == (6, ACTION_FEATURE_COUNT), data.a.shape
            assert float(data.s[:, prefix:].abs().sum()) == 0.0
            # Groups the layout lacks are 0, except those data_upgrade can
            # compute from the old features (v9 beatability, columns 54..57).
            assert float(data.a[:, na:BEAT].abs().sum()) == 0.0 if na < BEAT else True
            s0 = torch.tensor(rows[0]["state_features"], dtype=torch.float16)
            assert torch.equal(data.s[0, :prefix], s0)

            # Old "x" cache (layouts up to v6 only) (one full input row per action) of this layout.
            x = np.concatenate([
                np.repeat(np.asarray([r["state_features"] for r in rows], dtype=np.float16), 2, 0),
                np.asarray([a for r in rows for a in r["legal_play_action_features"]], dtype=np.float16),
            ], 1)
            if na == LEGACY_ACTION_FEATURE_COUNT:
                cache = td / f"x{size}.npz"
                np.savez_compressed(
                    cache, x=x, q=np.zeros(6, np.float32), starts=np.arange(0, 7, 2),
                    chosen=np.zeros(3, np.int64), explore=np.zeros(3, bool),
                )
                back = load([cache])
                assert torch.equal(back.s, data.s) and torch.equal(back.a, data.a)

            # A net of this layout, widened on load, computes the same values.
            torch.manual_seed(size)
            old = QNetwork(size, [16, 8])
            net_path = td / f"net{size}.safetensors"
            export_safetensors(old, net_path, target_mean=0.0, target_std=1.0, metadata={})
            new = load_qnetwork_from_safetensors(net_path, torch.device("cpu"))
            xs = torch.rand(5, size)
            padded = torch.zeros(5, TOTAL_FEATURE_COUNT)
            padded[:, :prefix] = xs[:, :prefix]
            padded[:, ACTION_OFFSET : ACTION_OFFSET + na] = xs[:, prefix:]
            # New inputs must not matter: fill them with noise.
            noisy = padded.clone()
            noisy[:, prefix:ACTION_OFFSET] = torch.rand(5, ACTION_OFFSET - prefix)
            noisy[:, ACTION_OFFSET + na :] = 1.0
            with torch.no_grad():
                assert torch.allclose(old(xs), new(padded), atol=1e-6)
                assert torch.allclose(old(xs), new(noisy), atol=1e-6)
    print("legacy layout checks: ok")


if __name__ == "__main__":
    check_synthetic()
    check_legacy_layouts()
