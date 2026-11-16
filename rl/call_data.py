"""Call-decision rows (Tichu / Grand Tichu) from headless bc-jsonl output."""

from __future__ import annotations

import json
from pathlib import Path

import numpy as np
import torch

from oracle import oracle_onehot
from schema import ACTION_OFFSET

SCALE = 100.0


RECEIVED = 3 * 56  # one-hot received schupf card from left, partner, right
FEATURES = ACTION_OFFSET + RECEIVED  # = Dart callFeatureCount


def received_onehot(received: list[int] | None) -> list[float]:
    out = [0.0] * RECEIVED
    for block, slot in enumerate(received or []):
        if slot is not None and slot >= 0:
            out[block * 56 + slot] = 1.0
    return out


def call_input(state: list[float], called: bool) -> list[float]:
    """[state, flag, flag * state] — must match Dart ``callNetInput``."""
    f = 1.0 if called else 0.0
    return state + [f] + [v * f for v in state]


def with_flag(x: torch.Tensor, flag: float) -> torch.Tensor:
    n = FEATURES
    out = x.clone()
    out[:, n] = flag
    out[:, n + 1 :] = x[:, :n] * flag
    return out


def load_calls(jsonl: Path, kind: str) -> tuple[torch.Tensor, torch.Tensor, torch.Tensor]:
    """Return (inputs (N, 2F+1), targets (N,), heuristic_called (N,) bool,
    oracle one-hot (N, 168))."""
    rounds: dict[tuple[int, int], tuple[int, int]] = {}
    rows: list[dict] = []
    with jsonl.open("r", encoding="utf-8") as fh:
        for line in fh:
            if '"round_end"' in line:
                r = json.loads(line)
                rounds[(int(r["episode"]), int(r["round"]))] = (
                    int(r["team_one_round"]),
                    int(r["team_two_round"]),
                )
            elif f'"call":"{kind}"' in line:
                rows.append(json.loads(line))
    xs, ys, heur, orc = [], [], [], []
    for r in rows:
        key = (int(r["episode"]), int(r["round"]))
        if key not in rounds:
            continue
        t1, t2 = rounds[key]
        own, opp = (t1, t2) if int(r["team"]) == 0 else (t2, t1)
        state = r["state_features"]
        if len(state) != ACTION_OFFSET:
            raise ValueError(f"state_features len {len(state)} != {ACTION_OFFSET}")
        called = bool(r["called"])
        xs.append(call_input(state + received_onehot(r.get("received")), called))
        ys.append((own - opp) / SCALE)
        # The heuristic's own choice: flipped back for explored rows.
        heur.append(called != bool(r.get("explore", False)))
        orc.append(oracle_onehot(r.get("oracle")))
    if not xs:
        raise ValueError(f"no '{kind}' call rows with finished rounds in {jsonl}")
    return (
        torch.tensor(xs, dtype=torch.float32),
        torch.tensor(ys, dtype=torch.float32),
        torch.tensor(heur, dtype=torch.bool),
        torch.from_numpy(np.stack(orc)),
    )


def load_counterfactual(jsonl: Path, kind: str) -> tuple[torch.Tensor, torch.Tensor, torch.Tensor]:
    """Rows with an exact counterfactual label ``cf`` = R(call) - R(no call)
    (headless ``--counterfactual-calls``). Returns (call features (N, F),
    cf / SCALE (N,), heuristic_called (N,))."""
    xs, cfs, heur = [], [], []
    with jsonl.open("r", encoding="utf-8") as fh:
        for line in fh:
            if f'"call":"{kind}"' not in line or '"cf"' not in line:
                continue
            r = json.loads(line)
            xs.append(r["state_features"] + received_onehot(r.get("received")))
            cfs.append(float(r["cf"]) / SCALE)
            heur.append(bool(r["called"]) != bool(r.get("explore", False)))
    return (
        torch.tensor(xs, dtype=torch.float32),
        torch.tensor(cfs, dtype=torch.float32),
        torch.tensor(heur, dtype=torch.bool),
    )
