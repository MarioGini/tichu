#!/usr/bin/env python3
"""Train the schupf (card passing) value network.

Reads headless ``--format=bc-jsonl`` output; every schupf decision is logged
as ``{"schupf": true, "hand": [slots], "left", "partner", "right",
"context": [gt_me, gt_partner, gt_left, gt_right], "explore"?}``. Generate
with ``--schupf-epsilon=p`` so that alternatives to the heuristic's choice are
observed.

  x = SchupfFeatures (228): hand bitmap, one-hot left / partner / right card,
      Grand Tichu context            — must match lib/agents/nn/nn_schupf_strategy.dart
  y = round point difference / 100 (own team minus opponents)

Dart's ``NnSchupfStrategy`` scores all 2184 assignments and picks the best.

  rl/.venv/bin/python rl/schupf_train.py --jsonl=data.jsonl \
      --output=rl/outputs/schupf_net.safetensors
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
import torch
import torch.nn as nn

from bc_pretrain import QNetwork, _select_device
from call_train import train
from schema import SPEC

SCALE = 100.0
HAND, LEFT, PARTNER, RIGHT, CONTEXT, SIZE = 0, 56, 112, 168, 224, 228


def encode(hand: list[int], left: int, partner: int, right: int, ctx: list[float]) -> np.ndarray:
    f = np.zeros(SIZE, dtype=np.float32)
    f[[HAND + s for s in hand]] = 1.0
    f[LEFT + left] = 1.0
    f[PARTNER + partner] = 1.0
    f[RIGHT + right] = 1.0
    f[CONTEXT : CONTEXT + 4] = ctx
    return f


def load(jsonl: Path) -> tuple[torch.Tensor, torch.Tensor, torch.Tensor]:
    """Return (x (N, 228), y (N,), explored (N,) bool)."""
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
            elif '"schupf":true' in line:
                rows.append(json.loads(line))
    xs, ys, ex = [], [], []
    for r in rows:
        key = (int(r["episode"]), int(r["round"]))
        if key not in rounds:
            continue
        t1, t2 = rounds[key]
        own, opp = (t1, t2) if int(r["team"]) == 0 else (t2, t1)
        xs.append(encode(r["hand"], r["left"], r["partner"], r["right"], r["context"]))
        ys.append((own - opp) / SCALE)
        ex.append(bool(r.get("explore", False)))
    if not xs:
        raise ValueError(f"no schupf rows with finished rounds in {jsonl}")
    return (
        torch.from_numpy(np.stack(xs)),
        torch.tensor(ys, dtype=torch.float32),
        torch.tensor(ex, dtype=torch.bool),
    )


def main() -> None:
    p = argparse.ArgumentParser(description="Train the schupf value net")
    p.add_argument("--jsonl", required=True)
    p.add_argument("--output", default="rl/outputs/schupf_net.safetensors")
    p.add_argument("--hidden", default="128,64")
    p.add_argument("--epochs", type=int, default=30)
    p.add_argument("--lr", type=float, default=1e-3)
    p.add_argument("--seed", type=int, default=0)
    args = p.parse_args()
    _select_device()

    x, y, explored = load(Path(args.jsonl))
    d = float(y[explored].mean() - y[~explored].mean()) * SCALE if explored.any() else float("nan")
    print(
        f"[schupf] rows={x.shape[0]} explored={int(explored.sum())}  "
        f"heuristic beats random perturbation by {-d:+.1f} pts/round"
    )
    hidden = [int(h) for h in args.hidden.split(",") if h]
    model, mse = train(x, y, hidden=hidden, epochs=args.epochs, lr=args.lr, seed=args.seed)
    with torch.no_grad():
        pred = model(x).squeeze(-1)
    gap = float((pred[~explored].mean() - pred[explored].mean()) * SCALE) if explored.any() else 0.0
    print(
        f"[schupf] val_mse={mse:.4f} (var={float(y.var()):.4f})  "
        f"model rates heuristic passes {gap:+.1f} pts above perturbed ones"
    )
    _export(model, Path(args.output), mse, x.shape[0])
    print(f"[schupf] saved {args.output}")


def _export(model: QNetwork, path: Path, val_mse: float, n: int) -> None:
    from safetensors.torch import save_file

    linear = [m for m in model.net if isinstance(m, nn.Linear)]
    tensors: dict[str, torch.Tensor] = {}
    sizes = [linear[0].in_features]
    for i, layer in enumerate(linear):
        tensors[f"layer.{i}.weight"] = layer.weight.detach().cpu().contiguous()
        tensors[f"layer.{i}.bias"] = layer.bias.detach().cpu().contiguous()
        sizes.append(layer.out_features)
    path.parent.mkdir(parents=True, exist_ok=True)
    save_file(
        tensors,
        str(path),
        metadata={
            "layer_sizes": json.dumps(sizes),
            "kind": "schupf_value",
            "target": "round_points_diff",
            "target_mean": "0.0",
            "target_std": str(SCALE),
            "val_mse": f"{val_mse:.6f}",
            "training_rows": str(n),
            "schema_version": str(SPEC.version),
        },
    )


if __name__ == "__main__":
    main()
