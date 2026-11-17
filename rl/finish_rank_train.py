#!/usr/bin/env python3
"""Finishing-rank model: P(finish 1st / 2nd / 3rd / 4th) from a hand.

Data: headless bc-jsonl with call rows (``--counterfactual-calls``, ``--skip-
play-rows``): every player's state at a call decision, joined with the
round's ``finish_seats``. Decision points:
  --kind=tichu  first Tichu opportunity: 14 cards after the schupf (+ the
                received cards, the table, the score, whether they called);
  --kind=grand  Grand Tichu decision: the first 8 cards.
In a double win the two losers are both labelled 4th (the round stops).

  rl/.venv/bin/python rl/finish_rank_train.py --jsonl='rl/outputs/calls_v6/cf_*.jsonl'
"""

from __future__ import annotations

import argparse
import glob
import json
from pathlib import Path

import numpy as np
import torch
import torch.nn as nn

from call_data import received_onehot
from qnet import QNetwork, export_safetensors


def load(pattern: str, kind: str):
    xs, ys, strength = [], [], []
    for f in sorted(glob.glob(pattern)):
        rounds, rows = {}, []
        with open(f) as fh:
            for line in fh:
                if '"round_end"' in line:
                    r = json.loads(line)
                    rounds[(r["episode"], r["round"])] = r["finish_seats"]
                elif f'"call":"{kind}"' in line:
                    rows.append(json.loads(line))
        for r in rows:
            order = rounds.get((r["episode"], r["round"]))
            if order is None:
                continue
            double = len(order) >= 2 and order[0] % 2 == order[1] % 2
            seat = r["seat"]
            if seat in order[:2]:
                rank = order.index(seat)
            elif double:
                rank = 3
            elif seat in order:
                rank = order.index(seat)
            else:
                rank = 3
            feats = r["state_features"] + received_onehot(r.get("received")) + [float(r["called"])]
            xs.append(np.asarray(feats, dtype=np.float32))
            ys.append(rank)
            strength.append(r.get("strength", 0.0))
    return torch.from_numpy(np.stack(xs)), torch.tensor(ys), np.array(strength)


def fit(x, y, hidden, epochs, seed):
    torch.manual_seed(seed)
    m = QNetwork.__new__(QNetwork)
    nn.Module.__init__(m)
    layers, prev = [], x.shape[1]
    for h in hidden:
        layers += [nn.Linear(prev, h), nn.ReLU()]
        prev = h
    layers.append(nn.Linear(prev, 4))
    m.net = nn.Sequential(*layers)
    opt = torch.optim.AdamW(m.parameters(), lr=1e-3, weight_decay=1e-3)
    for _ in range(epochs):
        order = torch.randperm(x.shape[0])
        for i in range(0, x.shape[0], 512):
            idx = order[i : i + 512]
            loss = nn.functional.cross_entropy(m.net(x[idx]), y[idx])
            opt.zero_grad(set_to_none=True)
            loss.backward()
            opt.step()
    return m


def main() -> None:
    a = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    a.add_argument("--jsonl", required=True)
    a.add_argument("--kind", default="tichu", choices=["tichu", "grand"])
    a.add_argument("--hidden", default="128,64")
    a.add_argument("--epochs", type=int, default=8)
    a.add_argument("--output", default="")
    args = a.parse_args()
    x, y, strength = load(args.jsonl, args.kind)
    n = len(y)
    perm = np.random.default_rng(0).permutation(n)
    te, tr = perm[: n // 5], perm[n // 5 :]
    m = fit(x[tr], y[tr], [int(h) for h in args.hidden.split(",")], args.epochs, 0)
    with torch.no_grad():
        p = torch.softmax(m.net(x[te]), -1).numpy()
    yt = y[te].numpy()
    prior = np.bincount(y[tr].numpy(), minlength=4) / len(tr)
    ll = -np.log(p[np.arange(len(yt)), yt] + 1e-9).mean()
    ll0 = -np.log(prior[yt]).mean()
    exp_rank = p @ np.arange(1, 5)
    print(f"[{args.kind}] {n} hands; rank frequencies 1st..4th "
          + " ".join(f"{100 * v:.1f}%" for v in prior))
    print(f"  held-out ({len(yt)}): log-loss {ll:.3f} vs {ll0:.3f} for the base rates "
          f"(information gained {100 * (1 - ll / ll0):.1f}%); accuracy {100 * (p.argmax(1) == yt).mean():.1f}% "
          f"vs {100 * prior.max():.1f}%")
    print(f"  expected rank vs actual: mean abs error {np.abs(exp_rank - (yt + 1)).mean():.2f} "
          f"(base rates {np.abs(prior @ np.arange(1, 5) - (yt + 1)).mean():.2f}); "
          f"correlation {np.corrcoef(exp_rank, yt + 1)[0, 1]:.2f} "
          f"(Tichu strength formula {np.corrcoef(-strength[te], yt + 1)[0, 1]:.2f})")
    print("  calibration of P(1st): predicted -> observed")
    for lo in np.arange(0, 1, 0.1):
        msk = (p[:, 0] >= lo) & (p[:, 0] < lo + 0.1)
        if msk.sum() >= 100:
            print(f"    {lo:.1f}-{lo + 0.1:.1f}: n={msk.sum():6d}  observed {100 * (yt[msk] == 0).mean():5.1f}%"
                  f"   P(4th) predicted {100 * p[msk, 3].mean():4.1f}% observed {100 * (yt[msk] == 3).mean():4.1f}%")
    print("  by expected rank: observed distribution 1st/2nd/3rd/4th")
    for lo, hi in ((1, 1.8), (1.8, 2.2), (2.2, 2.6), (2.6, 3.0), (3.0, 4.1)):
        msk = (exp_rank >= lo) & (exp_rank < hi)
        if msk.sum() >= 100:
            d = np.bincount(yt[msk], minlength=4) / msk.sum()
            print(f"    expected {lo:.1f}-{hi:.1f}: n={msk.sum():6d}  " + " / ".join(f"{100 * v:4.1f}%" for v in d))
    if args.output:
        export_safetensors(m, Path(args.output), target_mean=0.0, target_std=1.0,
                           metadata={"algorithm": "finish_rank", "kind": args.kind, "hands": str(n)})
        print(f"saved {args.output}")


if __name__ == "__main__":
    main()
