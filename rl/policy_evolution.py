#!/usr/bin/env python3
"""How each shipped play net chooses on the same positions.

Reads bc-jsonl decision rows written with ``--describe --rollout-rate=p``
(exact round values of every legal action, the rest of the round played by
the generating bot) and evaluates several nets on exactly those positions:

  * agreement matrix: share of decisions where two nets pick the same move;
  * per net and situation (lead / follow, hand size, pass vs play): the
    mean rollout value of the net's choice relative to the action average
    ("gain") and to the best action ("regret").

Paired on identical positions and labels, so differences between nets are
far less noisy than duels. The continuation is the generating bot, so this
measures single-move quality inside that bot's play.

  rl/.venv/bin/python rl/policy_evolution.py --jsonl=positions.jsonl \\
      --nets=v3=q_v3.safetensors,v8=q_v8.safetensors
"""

from __future__ import annotations

import argparse
import collections
import json
import sys
from pathlib import Path

import numpy as np
import torch

sys.path.insert(0, str(Path(__file__).resolve().parent))

from qnet import load_qnetwork_from_safetensors  # noqa: E402
from rollout_train import pad_action, pad_state  # noqa: E402


def situation(desc: dict, acts: list[str]) -> list[str]:
    n = len(desc["hand"].split())
    lead = "pass" not in acts and desc["trick_type"] in ("empty", "none")
    tags = ["all", "lead" if lead else "follow", "cards>=10" if n >= 10 else ("cards5-9" if n >= 5 else "cards<=4")]
    if not lead:
        tags.append("follow_partner_trick" if desc["winner"] == "P" else "follow_opp_trick")
    if desc.get("calls"):
        tags.append("some_tichu_called")
    return tags


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--jsonl", required=True)
    p.add_argument("--nets", required=True, help="name=path,name=path,...")
    args = p.parse_args()

    nets = {}
    for spec in args.nets.split(","):
        name, path = spec.split("=", 1)
        net = load_qnetwork_from_safetensors(Path(path), torch.device("cpu"))
        net.eval()
        nets[name] = net
    names = list(nets)

    rows = []
    with open(args.jsonl, encoding="utf-8") as fh:
        for line in fh:
            if '"q_rollout"' not in line:
                continue
            r = json.loads(line)
            q = r["q_rollout"]
            if any(v is None for v in q) or len(q) < 2:
                continue
            rows.append(r)
    print(f"{len(rows)} labelled decisions with >= 2 actions\n")

    picks = {n: [] for n in names}
    with torch.no_grad():
        for r in rows:
            s = torch.from_numpy(pad_state(np.asarray([r["state_features"]], dtype=np.float32)).astype(np.float32))
            a = torch.from_numpy(pad_action(np.asarray(r["legal_play_action_features"], dtype=np.float32)).astype(np.float32))
            x = torch.cat([s.expand(a.shape[0], -1), a], dim=1)
            for n in names:
                picks[n].append(int(nets[n](x).squeeze(-1).argmax()))

    # Agreement matrix.
    print("agreement (% same move)")
    print("      " + "".join(f"{n:>7s}" for n in names))
    for a in names:
        line = f"{a:6s}"
        for b in names:
            same = sum(x == y for x, y in zip(picks[a], picks[b]))
            line += f"{100 * same / len(rows):7.1f}"
        print(line)

    # Gain / regret by situation.
    gain = collections.defaultdict(lambda: collections.defaultdict(list))
    regret = collections.defaultdict(lambda: collections.defaultdict(list))
    passes = collections.defaultdict(lambda: collections.defaultdict(list))
    for i, r in enumerate(rows):
        q = np.asarray(r["q_rollout"], dtype=np.float64)
        acts = r["desc"]["acts"]
        tags = situation(r["desc"], acts)
        for n in names:
            v = q[picks[n][i]]
            for t in tags:
                gain[t][n].append(v - q.mean())
                regret[t][n].append(q.max() - v)
                if "pass" in acts:
                    passes[t][n].append(acts[picks[n][i]] == "pass")
    print("\nmean value of the chosen move minus the action average (round points; higher = better)")
    print(f"{'situation':22s}{'n':>7s}" + "".join(f"{n:>8s}" for n in names))
    for t in sorted(gain, key=lambda k: -len(gain[k][names[0]])):
        n_t = len(gain[t][names[0]])
        print(f"{t:22s}{n_t:7d}" + "".join(f"{np.mean(gain[t][n]):8.2f}" for n in names))
    ref = names[-1]
    print(f"\npaired difference to {ref} (chosen-move value, +- standard error)")
    for t in sorted(gain, key=lambda k: -len(gain[k][names[0]])):
        cells = []
        for n in names:
            d = np.asarray(gain[t][n]) - np.asarray(gain[t][ref])
            cells.append(f"{d.mean():+6.2f}±{d.std(ddof=1) / max(1, len(d)) ** 0.5:4.2f}")
        print(f"{t:22s}" + " ".join(cells))
    print("\npass rate when passing is legal (%)")
    for t in sorted(passes, key=lambda k: -len(passes[k][names[0]])):
        print(f"{t:22s}" + "".join(f"{100 * np.mean(passes[t][n]):8.1f}" for n in names))


if __name__ == "__main__":
    main()
