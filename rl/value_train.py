#!/usr/bin/env python3
"""Train the perfect-information value net: the round outcome from the full
deal, as seen by the player to move (Dart ``ValueModel``).

Input: the decider's state features plus who holds every card (56 x 3
one-hot: left opponent, partner, right opponent). Outputs (9): the round
points of the decider's team and of the other team (in units of
``--scale`` points), who goes out first (4 logits: self, left, partner,
right) and the double victory (3 logits: us, them, neither). The first-out
and double-victory heads are auxiliary: they shape the hidden layers and
let a search read more than one number off a leaf (tichuengine.com shows
the same outcome distribution next to its search).

The search uses it as the leaf of truncated rollouts
(``--endgame-leaf-after``): its error there is the error of the search, so
the script reports the held-out error of the point difference next to the
spread of the labels.

  rl/.venv/bin/python rl/value_train.py --data='rl/outputs/value/*.npz' \\
      --output=rl/outputs/value/value.safetensors
"""

from __future__ import annotations

import argparse
import glob
import time
from pathlib import Path

import numpy as np
import torch
import torch.nn as nn
import torch.nn.functional as F

from qnet import export_safetensors, select_device
from rollout_train import permute_suits_with as permute_state_suits
from schema import STATE_FEATURE_COUNT

HOLDERS = 56 * 3
INPUTS = STATE_FEATURE_COUNT + HOLDERS
OUTPUTS = 2 + 4 + 3


class ValueNet(nn.Module):
    def __init__(self, hidden: list[int]) -> None:
        super().__init__()
        layers: list[nn.Module] = []
        prev = INPUTS
        for h in hidden:
            layers += [nn.Linear(prev, h), nn.ReLU()]
            prev = h
        layers.append(nn.Linear(prev, OUTPUTS))
        self.net = nn.Sequential(*layers)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        return self.net(x)


def permute_suits(s: torch.Tensor, h: torch.Tensor) -> tuple[torch.Tensor, torch.Tensor]:
    """The same random suit relabelling of the state's card bitmaps (as
    ``rollout_train.permute_suits``) and of the holders (slots 0..51 are
    suit x rank)."""
    k = s.shape[0]
    perms = torch.argsort(torch.rand(k, 4), dim=1)
    s = permute_state_suits(s.float(), perms)
    h = h.clone()
    h[:, :52] = h[:, :52].reshape(-1, 4, 13).gather(1, perms[:, :, None].expand(-1, 4, 13)).reshape(-1, 52)
    return s, h


def features(s: torch.Tensor, h: torch.Tensor, augment: bool = False) -> torch.Tensor:
    """State features followed by the one-hot holders (as Dart
    ``encodeValueFeatures``: index state + slot * 3 + holder)."""
    if augment:
        s, h = permute_suits(s, h)
    onehot = F.one_hot(h.long().clamp_min(0), 3).float() * (h >= 0).unsqueeze(-1).float()
    return torch.cat([s.float(), onehot.reshape(len(h), HOLDERS)], 1)


def losses(out: torch.Tensor, y: torch.Tensor, f: torch.Tensor, d: torch.Tensor, scale: float, aux: float):
    points = F.smooth_l1_loss(out[:, :2], y / scale)
    first = F.cross_entropy(out[:, 2:6], f.long())
    double = F.cross_entropy(out[:, 6:9], d.long())
    return points + aux * (first + double), points, first, double


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--data", required=True)
    p.add_argument("--output", required=True)
    p.add_argument("--hidden", default="512,256,128")
    p.add_argument("--epochs", type=int, default=8)
    p.add_argument("--lr", type=float, default=1e-3)
    p.add_argument("--batch", type=int, default=1024)
    p.add_argument("--scale", type=float, default=100.0, help="points per output unit")
    p.add_argument("--aux", type=float, default=0.25, help="weight of the first-out and double-victory heads")
    p.add_argument("--no-augment", action="store_true", help="no suit-permutation augmentation")
    p.add_argument("--val-files", type=int, default=1, help="files held out (whole files: whole matches)")
    args = p.parse_args()
    select_device()
    files = sorted(glob.glob(args.data))
    if len(files) < 2:
        raise SystemExit("need at least two files (one is held out)")
    parts = [np.load(f) for f in files]
    nval = max(1, min(args.val_files, len(files) - 1))

    def cat(ps, k):
        return torch.from_numpy(np.concatenate([d[k] for d in ps]))

    # Features are built per batch: s stays float16 and h int8 (a few
    # hundred bytes per row instead of 2 KB).
    tr = {k: cat(parts[nval:], k) for k in "shyfd"}
    va = {k: cat(parts[:nval], k) for k in "shyfd"}
    del parts
    n_tr, n_va = len(tr["y"]), len(va["y"])
    print(f"{len(files)} files: {n_tr} train / {n_va} held-out positions", flush=True)
    diff_va = va["y"][:, 0] - va["y"][:, 1]
    print(f"held-out round difference: mean {float(diff_va.mean()):.1f}, sd {float(diff_va.std()):.1f} points", flush=True)

    model = ValueNet([int(x) for x in args.hidden.split(",")])
    opt = torch.optim.AdamW(model.parameters(), lr=args.lr, weight_decay=1e-5)
    steps = (n_tr + args.batch - 1) // args.batch
    sched = torch.optim.lr_scheduler.OneCycleLR(opt, max_lr=args.lr, total_steps=args.epochs * steps)
    best = float("inf")
    t0 = time.time()
    for epoch in range(args.epochs):
        model.train()
        order = torch.randperm(n_tr)
        for i in range(steps):
            idx = order[i * args.batch : (i + 1) * args.batch]
            x = features(tr["s"][idx], tr["h"][idx], augment=not args.no_augment)
            loss, *_ = losses(model(x), tr["y"][idx], tr["f"][idx], tr["d"][idx], args.scale, args.aux)
            opt.zero_grad(set_to_none=True)
            loss.backward()
            opt.step()
            sched.step()
        model.eval()
        with torch.no_grad():
            out = torch.cat([model(features(va["s"][i : i + 8192], va["h"][i : i + 8192]))
                             for i in range(0, n_va, 8192)])
            loss, _, first, double = losses(out, va["y"], va["f"], va["d"], args.scale, args.aux)
            pred = (out[:, 0] - out[:, 1]) * args.scale
            rmse = float(((pred - diff_va) ** 2).mean().sqrt())
            acc = float((out[:, 2:6].argmax(1) == va["f"].long()).float().mean())
        print(
            f"  epoch {epoch + 1}: held-out loss {float(loss):.4f}, difference RMSE {rmse:.1f} points, "
            f"first-out CE {float(first):.3f} (acc {100 * acc:.1f} %), double CE {float(double):.3f} "
            f"[{time.time() - t0:.0f}s]",
            flush=True,
        )
        if float(loss) < best:
            best = float(loss)
            export_safetensors(
                model, Path(args.output), target_mean=0.0, target_std=args.scale,
                metadata={
                    "algorithm": "value",
                    "outputs": "us, them (x target_std points); first out logits (self, left, partner, right); "
                    "double victory logits (us, them, neither)",
                },
            )
    print(f"saved {args.output} (held-out loss {best:.4f})")


if __name__ == "__main__":
    main()
