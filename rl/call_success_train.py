#!/usr/bin/env python3
"""Hand-strength model for Tichu calls: P(go out first | call).

Ground truth from exact call labels (``headless --counterfactual-calls
--counterfactual-rate=1``): every labelled decision is played out with and
without the call, and the rows carry ``call_first`` (did this player go out
first in the call branch) besides ``cf`` = points(call) - points(no call).
So every hand at the decision has a success label, not only the hands the
bot happened to call with.

1. A classifier on the decision state (hand after the schupf, received
   cards, table, score) predicts p = P(success | call).
2. The decision is "call if p >= t"; t is chosen on the training folds by the
   exact call value mean(cf * [p >= t]) and reported on held-out folds next to
   the current rule (the bot's own decisions in the data).

  rl/.venv/bin/python rl/call_success_train.py --jsonl='rl/outputs/calls_v6/cf_*.jsonl' --kind=tichu
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

PARTNER_CALL = (158 + 5, 158 + 6)  # partner's Tichu / Grand Tichu flags in `seats`


def load(pattern: str, kind: str):
    xs, first, cf, own, partner = [], [], [], [], []
    for f in sorted(glob.glob(pattern)):
        with open(f) as fh:
            for line in fh:
                if f'"call":"{kind}"' not in line or '"call_first"' not in line:
                    continue
                r = json.loads(line)
                s = r["state_features"]
                xs.append(np.asarray(s + received_onehot(r.get("received")), dtype=np.float32))
                first.append(float(r["call_first"]))
                cf.append(float(r["cf"]))
                own.append(bool(r["called"]) != bool(r.get("explore", False)))
                partner.append(s[PARTNER_CALL[0]] > 0.5 or s[PARTNER_CALL[1]] > 0.5)
    return (torch.from_numpy(np.stack(xs)), torch.tensor(first), torch.tensor(cf),
            torch.tensor(own), torch.tensor(partner))


def fit(x, y, hidden, epochs, lr, seed):
    torch.manual_seed(seed)
    model = QNetwork(x.shape[1], hidden)
    opt = torch.optim.AdamW(model.parameters(), lr=lr, weight_decay=1e-3)
    for _ in range(epochs):
        order = torch.randperm(x.shape[0])
        for i in range(0, x.shape[0], 512):
            idx = order[i : i + 512]
            loss = nn.functional.binary_cross_entropy_with_logits(model(x[idx]).squeeze(-1), y[idx])
            opt.zero_grad(set_to_none=True)
            loss.backward()
            opt.step()
    return model


def best_threshold(p, cf, allowed):
    ts = np.arange(0.40, 0.70, 0.01)  # break-even is near 0.5; a wider range overfits
    vals = [float((cf * ((p >= t) & allowed)).mean()) for t in ts]
    i = int(np.argmax(vals))
    return float(ts[i]), vals[i]


def main() -> None:
    a = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    a.add_argument("--jsonl", required=True)
    a.add_argument("--kind", default="tichu", choices=["tichu", "grand"])
    a.add_argument("--hidden", default="128,64")
    a.add_argument("--epochs", type=int, default=8)
    a.add_argument("--lr", type=float, default=1e-3)
    a.add_argument("--folds", type=int, default=4)
    a.add_argument("--output", default="")
    args = a.parse_args()
    x, first, cf, own, partner = load(args.jsonl, args.kind)
    n = x.shape[0]
    allowed = ~partner.numpy()
    print(f"[{args.kind}] {n} decisions; success rate if called {100 * float(first.mean()):.1f}%; "
          f"bot calls {100 * float(own.float().mean()):.1f}%")
    hidden = [int(h) for h in args.hidden.split(",") if h]
    perm = np.random.default_rng(0).permutation(n)
    p_all = np.zeros(n)
    gains, rules = [], []
    for k in range(args.folds):
        te = perm[k :: args.folds]
        tr = np.setdiff1d(perm, te)
        m = fit(x[tr], first[tr], hidden, args.epochs, args.lr, k)
        with torch.no_grad():
            p_tr = torch.sigmoid(m(x[tr]).squeeze(-1)).numpy()
            p_te = torch.sigmoid(m(x[te]).squeeze(-1)).numpy()
        t, _ = best_threshold(p_tr, cf.numpy()[tr], allowed[tr])
        p_all[te] = p_te
        g = cf.numpy()[te] * ((p_te >= t) & allowed[te])
        r = cf.numpy()[te] * own.numpy()[te]
        gains.append(g)
        rules.append(r)
        print(f"  fold {k}: threshold p >= {t:.2f}: held-out {g.mean():+.2f} pts/decision "
              f"(calls {100 * ((p_te >= t) & allowed[te]).mean():.1f}%), current rule {r.mean():+.2f}")
    g, r = np.concatenate(gains), np.concatenate(rules)
    d = g - r
    print(f"[{args.kind}] held-out: success model {g.mean():+.2f} ± {g.std() / np.sqrt(len(g)):.2f}, "
          f"current rule {r.mean():+.2f}; difference {d.mean():+.2f} ± {d.std() / np.sqrt(len(d)):.2f} pts/decision")
    # calibration
    bins = np.clip((p_all * 10).astype(int), 0, 9)
    print("  calibration (held-out): predicted p -> observed success, value of calling")
    for b in range(10):
        msk = bins == b
        if msk.sum() >= 50:
            print(f"    p {b / 10:.1f}-{(b + 1) / 10:.1f}: n={msk.sum():6d}  success {100 * first.numpy()[msk].mean():5.1f}%  "
                  f"cf {cf.numpy()[msk].mean():+7.1f}")
    if args.output:
        m = fit(x, first, hidden, args.epochs, args.lr, 99)
        with torch.no_grad():
            p = torch.sigmoid(m(x).squeeze(-1)).numpy()
        t, v = best_threshold(p, cf.numpy(), allowed)
        # Bake the threshold into the output: logit(p) - logit(t) > 0 <=> p > t.
        last = [l for l in m.net if isinstance(l, nn.Linear)][-1]
        with torch.no_grad():
            last.bias -= float(np.log(t / (1 - t)))
        export_safetensors(m, Path(args.output), target_mean=0.0, target_std=1.0,
                           metadata={"algorithm": "call_success", "kind": args.kind,
                                     "threshold": f"{t:.3f}", "decisions": str(n)})
        print(f"saved {args.output} (threshold {t:.2f})")


if __name__ == "__main__":
    main()
