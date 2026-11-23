#!/usr/bin/env python3
"""Tichu calls valued in match-win probability instead of round points.

From headless bc-jsonl with ``--counterfactual-calls`` (call rows with the
caller team's round point difference with and without the call; round_end
and episode_end rows): fits P(win the match | scores at the start of a
round) on the same matches, then values each call decision by
dW = W(after the round with the call) - W(without), and compares the best
call threshold per match situation in points and in dW.

  rl/.venv/bin/python rl/call_match_value.py rl/outputs/calls_v8/cf_*.jsonl
"""

from __future__ import annotations

import json
import sys
from collections import defaultdict

import numpy as np
import torch


def feats(us: np.ndarray, them: np.ndarray, target: float = 1000.0) -> np.ndarray:
    lead = (us - them) / 200.0
    prog = np.maximum(us, them) / target
    return np.stack([lead, lead * prog, lead * prog**2, prog, np.ones_like(lead)], 1)


def main(paths: list[str]) -> None:
    starts, wins, calls = [], [], []
    for p in paths:
        cur: dict[int, list[int]] = defaultdict(lambda: [0, 0])
        pending: dict[int, list[dict]] = defaultdict(list)
        for line in open(p, encoding="utf-8"):
            r = json.loads(line)
            ep = r.get("episode")
            if r.get("round_end"):
                s = cur[ep]
                starts.append((p, ep, s[0], s[1]))
                s[0] += r["team_one_round"]
                s[1] += r["team_two_round"]
            elif r.get("episode_end"):
                w = r.get("winner")
                for (pp, e, a, b) in [x for x in starts if x[0] == p and x[1] == ep]:
                    wins.append((a, b, w))
            elif r.get("call") == "tichu" and "cf" in r and not r.get("explore"):
                s = cur[ep]
                us, them = (s[0], s[1]) if r["team"] == 0 else (s[1], s[0])
                calls.append((us, them, r["call_points"], r["nocall_points"], r["strength"], r["opp_called"]))
        starts = [x for x in starts if x[0] != p]  # only finished episodes kept above
    # W model (team 0 view + mirrored team 1 view).
    a = np.array([w[0] for w in wins], float); b = np.array([w[1] for w in wins], float)
    y0 = np.array([1.0 if w[2] == 0 else 0.0 for w in wins])
    X = np.concatenate([feats(a, b), feats(b, a)]); Y = np.concatenate([y0, 1 - y0])
    # Small MLP on (us, them) / 1000: the win chance bends sharply near the target.
    S = np.concatenate([np.stack([a, b], 1), np.stack([b, a], 1)]) / 1000.0
    St = torch.tensor(S, dtype=torch.float32); Yt = torch.tensor(Y, dtype=torch.float32)
    torch.manual_seed(0)
    net = torch.nn.Sequential(torch.nn.Linear(2, 32), torch.nn.Tanh(), torch.nn.Linear(32, 32), torch.nn.Tanh(), torch.nn.Linear(32, 1))
    opt = torch.optim.Adam(net.parameters(), lr=3e-3, weight_decay=1e-4)
    for _ in range(3000):
        opt.zero_grad()
        loss = torch.nn.functional.binary_cross_entropy_with_logits(net(St).squeeze(1), Yt)
        loss.backward()
        opt.step()

    def W(us, them):
        with torch.no_grad():
            x = torch.tensor(np.stack([np.asarray(us, float), np.asarray(them, float)], 1) / 1000.0, dtype=torch.float32)
            p_us = torch.sigmoid(net(x).squeeze(1)).numpy()
            p_them = torch.sigmoid(net(x.flip(1)).squeeze(1)).numpy()
        return (p_us + 1 - p_them) / 2  # symmetric

    print(f"{len(wins)} round starts in finished matches; W fitted")
    for us, them in [(0, 0), (500, 400), (800, 600), (900, 700), (600, 800), (700, 900), (950, 950)]:
        print(f"  W({us} vs {them}) = {W(np.array([us], float), np.array([them], float))[0]:.2f}")

    c = np.array(calls, float)
    us, them, cp, ncp, st, oppc = c.T
    sel = oppc == 0
    us, them, cp, ncp, st = us[sel], them[sel], cp[sel], ncp[sel], st[sel]
    # Round points split: total ~ 100 card points plus the difference.
    def after(d):
        return W(us + (100 + d) / 2, them + (100 - d) / 2)
    dW = after(cp) - after(ncp)
    dP = cp - ncp
    prog = np.maximum(us, them)
    lead = us - them
    situations = {
        "early (both < 500)": prog < 500,
        "late, level (|lead| < 150)": (prog >= 700) & (np.abs(lead) < 150),
        "late, leading by 150+": (prog >= 700) & (lead >= 150),
        "late, trailing by 150+": (prog >= 700) & (lead <= -150),
        "all": np.ones_like(prog, bool),
    }
    ths = np.quantile(st, np.linspace(0.5, 0.995, 80))
    print(f"\n{sel.sum()} Tichu decisions (no opponent call). Best threshold on the strength score:")
    print(f"{'situation':28s} {'n':>6s} | {'by points':>22s} | {'by win probability':>30s}")
    for name, m in situations.items():
        if m.sum() < 200:
            continue
        bp = max(ths, key=lambda t: (dP * (st >= t))[m].mean())
        bw = max(ths, key=lambda t: (dW * (st >= t))[m].mean())
        rule = -0.1
        def val(t, arr):
            return (arr * (st >= t))[m].mean()
        print(f"{name:28s} {m.sum():6d} | t={bp:5.2f} calls {100*(st>=bp)[m].mean():4.1f}% | "
              f"t={bw:5.2f} calls {100*(st>=bw)[m].mean():4.1f}%  dW/decision {100*val(bw,dW):+.3f} pp "
              f"(rule {100*val(rule,dW):+.3f} pp)")


if __name__ == "__main__":
    main(sys.argv[1:])
