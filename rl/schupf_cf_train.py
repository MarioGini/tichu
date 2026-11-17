#!/usr/bin/env python3
"""Train the schupf value net on exact candidate labels.

Data: headless ``--schupf-rollout-rate`` rows. For each labelled decision,
up to 16 candidate passes (index 0 = the bot's own pass) with the exact
round result of each on the same deal. As in ``rollout_train.py`` the net
is fitted to per-decision advantages (outputs and targets centred over the
decision's candidates), so card luck never enters the loss. The exported
net plugs into ``NnSchupfStrategy`` (``headless --schupf-net=...``), which
scores the same candidate set (``SchupfFeatures.candidates``).

  rl/.venv/bin/python rl/schupf_cf_train.py --jsonl='rl/outputs/schupf/cf_*.jsonl' \\
      --output=rl/outputs/schupf/schupf_net.safetensors
"""

from __future__ import annotations

import argparse
import glob
import json
from pathlib import Path

import numpy as np
import torch
import torch.nn as nn

from qnet import QNetwork, gather_batch_indices
from schupf_train import SIZE, _export, encode

SCALE = 100.0


def load(pattern: str):
    xs, qs, starts, n = [], [], [0], 0
    for f in sorted(p for pat in pattern.split(",") for p in glob.glob(pat)):
        with open(f) as fh:
            for line in fh:
                if '"schupf_cf"' not in line:
                    continue
                r = json.loads(line)
                keep = [i for i, o in enumerate(r["out"]) if o is not None]
                if len(keep) < 3 or 0 not in keep:
                    continue
                keep.remove(0)
                keep = [0] + keep  # the bot's own pass stays first
                hand, ctx = r["hands"][0], r["context"]
                for i in keep:
                    left, partner, right = r["cands"][i]
                    xs.append(encode(hand, left, partner, right, ctx))
                    qs.append(r["out"][i][0] / SCALE)
                n += len(keep)
                starts.append(n)
    return (torch.from_numpy(np.stack(xs)), torch.tensor(qs, dtype=torch.float32),
            torch.tensor(starts, dtype=torch.long))


def permute_suits(x: torch.Tensor, group: torch.Tensor, k: int) -> torch.Tensor:
    """Same random suit relabelling for the hand and the three passed cards."""
    perms = torch.argsort(torch.rand(k, 4), dim=1)[group]
    idx = perms[:, :, None].expand(-1, 4, 13)
    x = x.clone()
    for start in (0, 56, 112, 168):
        block = x[:, start : start + 52].reshape(-1, 4, 13)
        x[:, start : start + 52] = block.gather(1, idx).reshape(-1, 52)
    return x


def centred(v: torch.Tensor, group: torch.Tensor, k: int) -> torch.Tensor:
    s = torch.zeros(k).scatter_add_(0, group, v)
    c = torch.zeros(k).scatter_add_(0, group, torch.ones_like(v))
    return v - (s / c)[group]


@torch.no_grad()
def evaluate(model, x, q, starts, idx):
    rows, group, offset = gather_batch_indices(idx, starts)
    out = model(x[rows]).squeeze(-1)
    k = int(idx.numel())
    best = torch.full((k,), float("-inf")).scatter_reduce(0, group, out, reduce="amax")
    pick = out >= best[group] - 1e-9
    num = torch.zeros(k).scatter_add_(0, group, q[rows] * pick)
    den = torch.zeros(k).scatter_add_(0, group, pick.float())
    chosen = num / den
    own = q[starts[idx]]
    mean = torch.zeros(k).scatter_add_(0, group, q[rows]) / (starts[idx + 1] - starts[idx]).float()
    agree = pick[offset]
    g = (chosen - own) * SCALE
    # Deviate from the bot's own pass only when the net prefers another one
    # by more than a margin (points).
    own_out = out[offset]
    margins = {}
    for m in (5, 10, 20):
        dev = (best - own_out) * SCALE > m
        margins[m] = float(torch.where(dev, chosen - own, torch.zeros_like(own)).mean() * SCALE)
    return {
        "gain_vs_own_pass": float(g.mean()),
        "se": float(g.std() / np.sqrt(k)),
        "own_vs_mean": float((own - mean).mean() * SCALE),
        "agree": float(agree.float().mean()),
        "margins": margins,
    }


def main() -> None:
    p = argparse.ArgumentParser(description="Schupf net on exact candidate labels")
    p.add_argument("--jsonl", required=True)
    p.add_argument("--output", required=True)
    p.add_argument("--hidden", default="256,128")
    p.add_argument("--epochs", type=int, default=30)
    p.add_argument("--lr", type=float, default=1e-3)
    p.add_argument("--batch-decisions", type=int, default=256)
    p.add_argument("--val-fraction", type=float, default=0.15)
    p.add_argument("--seed", type=int, default=0)
    p.add_argument("--weight-decay", type=float, default=1e-4)
    args = p.parse_args()
    torch.manual_seed(args.seed)
    x, q, starts = load(args.jsonl)
    d = starts.numel() - 1
    print(f"schupf decisions {d}, candidate rows {x.shape[0]}", flush=True)
    perm = torch.from_numpy(np.random.default_rng(args.seed).permutation(d))
    nv = int(d * args.val_fraction)
    val, tr = perm[:nv], perm[nv:]
    model = QNetwork(SIZE, [int(h) for h in args.hidden.split(",")])
    opt = torch.optim.AdamW(model.parameters(), lr=args.lr, weight_decay=args.weight_decay)
    steps = (tr.numel() + args.batch_decisions - 1) // args.batch_decisions
    sched = torch.optim.lr_scheduler.OneCycleLR(opt, max_lr=args.lr, total_steps=args.epochs * steps)
    best, best_state = -1e9, None
    for epoch in range(args.epochs):
        model.train()
        order = tr[torch.randperm(tr.numel())]
        for i in range(steps):
            idx = order[i * args.batch_decisions : (i + 1) * args.batch_decisions]
            rows, group, _ = gather_batch_indices(idx, starts)
            k = int(idx.numel())
            out = model(permute_suits(x[rows], group, k)).squeeze(-1)
            loss = nn.functional.huber_loss(centred(out, group, k), centred(q[rows], group, k), delta=2.0)
            opt.zero_grad(set_to_none=True)
            loss.backward()
            opt.step()
            sched.step()
        model.eval()
        m = evaluate(model, x, q, starts, val)
        if epoch % 5 == 4 or epoch == args.epochs - 1:
            print(f"  epoch {epoch + 1}: held-out gain over the bot's own pass {m['gain_vs_own_pass']:+.1f} ± {m['se']:.1f} "
                  f"pts/round, agrees {100 * m['agree']:.0f}%, with margin 5/10/20: "
                  + "/".join(f"{v:+.1f}" for v in m["margins"].values()), flush=True)
        if m["gain_vs_own_pass"] > best:
            best, best_state = m["gain_vs_own_pass"], {k: v.clone() for k, v in model.state_dict().items()}
    model.load_state_dict(best_state)
    _export(model, Path(args.output), 0.0, x.shape[0])
    print(f"saved {args.output} (best held-out gain {best:+.1f} pts/round; own pass vs average candidate "
          f"{m['own_vs_mean']:+.1f})")


if __name__ == "__main__":
    main()
