#!/usr/bin/env python3
"""Train the card-location (belief) model: who holds each unseen card.

Input: the decider's state features. Output: 56 x 3 logits (card slot x
left opponent / partner / right opponent); the loss is the cross entropy
over the three holders for every card the decider cannot see. Reported
against the uniform re-deal the endgame search uses today (a card is with
each other player in proportion to the cards that player still holds).

  rl/.venv/bin/python rl/belief_train.py --data='rl/outputs/belief/*.npz' \\
      --output=rl/outputs/belief/belief.safetensors
"""

from __future__ import annotations

import argparse
import glob
import math
import time
from pathlib import Path

import numpy as np
import torch
import torch.nn as nn

from qnet import export_safetensors, select_device
from schema import SPEC, STATE_FEATURE_COUNT

SEATS = SPEC.group("seats").offset


class BeliefNet(nn.Module):
    def __init__(self, hidden: list[int]) -> None:
        super().__init__()
        layers: list[nn.Module] = []
        prev = STATE_FEATURE_COUNT
        for h in hidden:
            layers += [nn.Linear(prev, h), nn.ReLU()]
            prev = h
        layers.append(nn.Linear(prev, 56 * 3))
        self.net = nn.Sequential(*layers)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        return self.net(x).view(-1, 56, 3)


def baseline_logp(s: torch.Tensor) -> torch.Tensor:
    """log P(holder) of the uniform re-deal: proportional to hand sizes."""
    counts = torch.stack([s[:, SEATS + 9 * k] * 14 for k in range(3)], 1).clamp_min(0)
    p = counts / counts.sum(1, keepdim=True).clamp_min(1e-6)
    return torch.log(p.clamp_min(1e-6))[:, None, :].expand(-1, 56, -1)


def nll(logits: torch.Tensor, h: torch.Tensor) -> tuple[torch.Tensor, int]:
    mask = h >= 0
    lp = torch.log_softmax(logits, -1)
    picked = lp.gather(-1, h.clamp_min(0).long().unsqueeze(-1)).squeeze(-1)
    return -(picked * mask).sum(), int(mask.sum())


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--data", required=True)
    p.add_argument("--output", required=True)
    p.add_argument("--hidden", default="512,256")
    p.add_argument("--epochs", type=int, default=6)
    p.add_argument("--lr", type=float, default=1e-3)
    p.add_argument("--batch", type=int, default=1024)
    p.add_argument("--val-files", type=int, default=2)
    args = p.parse_args()
    select_device()
    files = sorted(glob.glob(args.data))
    parts = [np.load(f) for f in files]
    nval = max(1, min(args.val_files, len(files) - 1))
    def cat(ps, k):
        return torch.from_numpy(np.concatenate([d[k] for d in ps]))
    s_tr, h_tr = cat(parts[nval:], "s").float(), cat(parts[nval:], "h")
    s_va, h_va = cat(parts[:nval], "s").float(), cat(parts[:nval], "h")
    print(f"{len(files)} files: {len(h_tr)} train / {len(h_va)} held-out positions", flush=True)
    base, nb = nll(baseline_logp(s_va), h_va)
    print(f"uniform re-deal: {base / nb:.4f} nats per unseen card (3-way uniform {math.log(3):.4f})", flush=True)
    model = BeliefNet([int(x) for x in args.hidden.split(",")])
    opt = torch.optim.AdamW(model.parameters(), lr=args.lr, weight_decay=1e-5)
    steps = (len(h_tr) + args.batch - 1) // args.batch
    sched = torch.optim.lr_scheduler.OneCycleLR(opt, max_lr=args.lr, total_steps=args.epochs * steps)
    best = float("inf")
    t0 = time.time()
    for epoch in range(args.epochs):
        model.train()
        order = torch.randperm(len(h_tr))
        for i in range(steps):
            idx = order[i * args.batch : (i + 1) * args.batch]
            loss, n = nll(model(s_tr[idx]), h_tr[idx])
            opt.zero_grad(set_to_none=True)
            (loss / max(1, n)).backward()
            opt.step()
            sched.step()
        model.eval()
        with torch.no_grad():
            tot, n = 0.0, 0
            for i in range(0, len(h_va), 8192):
                l, k = nll(model(s_va[i : i + 8192]), h_va[i : i + 8192])
                tot += float(l)
                n += k
        v = tot / n
        print(f"  epoch {epoch + 1}: held-out {v:.4f} nats per unseen card ({100 * (1 - v / (float(base) / nb)):.1f} % below the uniform re-deal) [{time.time() - t0:.0f}s]", flush=True)
        if v < best:
            best = v
            export_safetensors(model, Path(args.output), target_mean=0.0, target_std=1.0,
                               metadata={"algorithm": "belief", "outputs": "56x3 logits: card slot x (left, partner, right)"})
    print(f"saved {args.output} (held-out {best:.4f} nats, uniform re-deal {float(base) / nb:.4f})")


if __name__ == "__main__":
    main()
