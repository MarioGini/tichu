#!/usr/bin/env python3
"""Fine-tune the play net on cheap Monte-Carlo labels (rl/dmc_data.py).

Loss: MSE (Huber) of Q(s, a_chosen) against the round result that followed
(DouZero's deep Monte Carlo), optionally mixed with the exact all-action
rollout loss of rollout_train.py (``--rollout`` files, weight
``--rollout-weight``). Progress is measured on held-out *rollout* decisions
(gain of the greedy policy over the average action, in round points), the
same metric rollout_train.py reports, so both kinds of training compare.

  rl/.venv/bin/python rl/dmc_train.py --dmc='rl/outputs/dmc/*.npz' \\
      --rollout=rl/outputs/v8/data/it06_self.npz \\
      --init-from=assets/bots/tichu_q_v8.safetensors --output=dmc.safetensors
"""

from __future__ import annotations

import argparse
import glob
import time
from pathlib import Path

import numpy as np
import torch
import torch.nn as nn

from qnet import load_qnetwork_from_safetensors
from rollout_train import (
    _export,
    batch_loss,
    evaluate,
    load,
    permute_suits,
    split_by_match,
)


def load_dmc(pattern: str):
    files = sorted(p for pat in pattern.split(",") for p in glob.glob(pat))
    parts = [np.load(f) for f in files]
    s = torch.from_numpy(np.concatenate([d["s"] for d in parts]))
    a = torch.from_numpy(np.concatenate([d["a"] for d in parts]))
    y = torch.from_numpy(np.concatenate([d["y"] for d in parts]))
    return s, a, y, len(files)


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--dmc", required=True, help="glob(s) of dmc_data.py shards")
    p.add_argument("--rollout", default="", help="comma-separated rollout npz/jsonl (mixed loss + held-out metric)")
    p.add_argument("--rollout-weight", type=float, default=1.0)
    p.add_argument("--init-from", required=True)
    p.add_argument("--output", required=True)
    p.add_argument("--epochs", type=int, default=2)
    p.add_argument("--lr", type=float, default=1e-4)
    p.add_argument("--batch", type=int, default=4096, help="DMC rows per step")
    p.add_argument("--batch-decisions", type=int, default=256, help="rollout decisions per step")
    p.add_argument("--huber", type=float, default=2.0)
    p.add_argument("--ema", type=float, default=0.999)
    p.add_argument("--seed", type=int, default=0)
    args = p.parse_args()
    torch.manual_seed(args.seed)
    t0 = time.time()
    s, a, y, nf = load_dmc(args.dmc)
    print(f"dmc: {y.numel()} decisions from {nf} files, target mean {float(y.mean()):+.3f} sd {float(y.std()):.3f} ({time.time()-t0:.0f}s)", flush=True)
    model = load_qnetwork_from_safetensors(Path(args.init_from), torch.device("cpu"))
    roll = load([Path(x) for x in args.rollout.split(",") if x]) if args.rollout else None
    best = float("-inf")
    if roll is not None:
        val, tr = split_by_match(roll, 0.2, args.seed)
        m0 = evaluate(model, roll, val)
        print("  start (held-out rollout): " + "  ".join(f"{k}={v:.3f}" for k, v in m0.items()), flush=True)
        best = m0["vs_uniform_pts"]  # keep the starting net unless an evaluation beats it
        _export(model, Path(args.output), 0)
    opt = torch.optim.AdamW(model.parameters(), lr=args.lr, weight_decay=1e-5)
    ema = torch.optim.swa_utils.AveragedModel(
        model, multi_avg_fn=torch.optim.swa_utils.get_ema_multi_avg_fn(args.ema)
    )
    n = y.numel()
    steps = (n + args.batch - 1) // args.batch
    for epoch in range(args.epochs):
        model.train()
        order = torch.randperm(n)
        rt = tr[torch.randperm(tr.numel())] if roll is not None else None
        for i in range(steps):
            idx = order[i * args.batch : (i + 1) * args.batch]
            x = torch.cat([permute_suits(s[idx].float()), a[idx].float()], dim=1)
            loss = nn.functional.huber_loss(model(x).squeeze(-1), y[idx], delta=args.huber)
            if roll is not None and args.rollout_weight > 0:
                j = (i * args.batch_decisions) % max(1, rt.numel() - args.batch_decisions)
                loss = loss + args.rollout_weight * batch_loss(model, roll, rt[j : j + args.batch_decisions], args.huber)
            opt.zero_grad(set_to_none=True)
            loss.backward()
            nn.utils.clip_grad_norm_(model.parameters(), 5.0)
            opt.step()
            ema.update_parameters(model)
            if (i + 1) % max(1, steps // 4) == 0 and roll is not None:
                m = evaluate(ema.module, roll, val)
                print(f"  epoch {epoch+1} step {i+1}/{steps}: " + "  ".join(f"{k}={v:.3f}" for k, v in m.items())
                      + f"  [{time.time()-t0:.0f}s]", flush=True)
                if m["vs_uniform_pts"] > best:
                    best = m["vs_uniform_pts"]
                    _export(ema.module, Path(args.output), n)
    if roll is None:
        _export(ema.module, Path(args.output), n)
    print(f"Saved {args.output} (best held-out vs_uniform_pts {best:.3f})")


if __name__ == "__main__":
    main()
