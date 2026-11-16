#!/usr/bin/env python3
"""Monte-Carlo Q fine-tune: one step of policy iteration.

Fits Q(s, a) ≈ R — the round point difference (own team minus opponents,
/100) that followed taking action ``a`` in state ``s`` — on self-play data
with ε-exploration (so non-greedy actions are observed too). The greedy
policy argmax_a Q(s, a) is a policy-improvement step over the behaviour
policy, and the exported net plugs straight into ``NnPlaySelectionStrategy``
(same input layout as the policy net).

To keep the policy's sensible defaults where Q is uncertain, the net is
warm-started from the current policy's logits and trained with a mix of

  MSE(Q(s, a_taken), R)   +   anchor_weight * CE(softmax_legal Q, behaviour action)

Only the taken action's row and the legal set of a sampled subset of
decisions are kept in memory.

  rl/.venv/bin/python rl/q_train.py --jsonl=selfplay.jsonl \
      --init-from=rl/outputs/best_policy.safetensors \
      --output=rl/outputs/q_policy.safetensors
"""

from __future__ import annotations

import argparse
import json
import time
from pathlib import Path

import numpy as np
import torch
import torch.nn as nn

from bc_data import FlatBcData
from qnet import (
    bc_step,
    export_safetensors,
    load_qnetwork_from_safetensors,
    select_device,
)
from oracle import fit_baseline, oracle_onehot
from schema import ACTION_OFFSET, TOTAL_FEATURE_COUNT

SCALE = 100.0


def load(
    jsonl: Path, *, ce_fraction: float, seed: int
) -> tuple[torch.Tensor, torch.Tensor, FlatBcData, torch.Tensor]:
    """Return (taken-action inputs (N, F), returns (N,), CE subset data,
    oracle one-hot (N, 168))."""
    rounds: dict[tuple[int, int], tuple[int, int]] = {}
    with jsonl.open("r", encoding="utf-8") as fh:
        for line in fh:
            if '"round_end"' in line:
                r = json.loads(line)
                rounds[(int(r["episode"]), int(r["round"]))] = (
                    int(r["team_one_round"]),
                    int(r["team_two_round"]),
                )
    rng = np.random.default_rng(seed)
    taken: list[np.ndarray] = []
    orc: list[np.ndarray] = []
    rets: list[float] = []
    chunks: list[np.ndarray] = []
    starts = [0]
    chosen_global: list[int] = []
    cursor = 0
    with jsonl.open("r", encoding="utf-8") as fh:
        for line in fh:
            if '"legal_play_action_features"' not in line:
                continue
            row = json.loads(line)
            key = (int(row["episode"]), int(row["round"]))
            if key not in rounds:
                continue
            legal = row["legal_play_action_features"]
            chosen = int(row["legal_play_chosen_index"])
            t1, t2 = rounds[key]
            own, opp = (t1, t2) if int(row["team"]) == 0 else (t2, t1)
            state = np.asarray(row["state_features"], dtype=np.float32)
            x = np.empty(TOTAL_FEATURE_COUNT, dtype=np.float32)
            x[:ACTION_OFFSET] = state
            x[ACTION_OFFSET:] = legal[chosen]
            taken.append(x)
            rets.append((own - opp) / SCALE)
            orc.append(oracle_onehot(row.get("oracle")))
            # Behaviour-cloning anchor on a subset (non-explored moves only).
            if not row.get("explore") and len(legal) > 1 and rng.random() < ce_fraction:
                block = np.empty((len(legal), TOTAL_FEATURE_COUNT), dtype=np.float32)
                block[:, :ACTION_OFFSET] = state
                block[:, ACTION_OFFSET:] = np.asarray(legal, dtype=np.float32)
                chunks.append(block)
                chosen_global.append(cursor + chosen)
                cursor += len(legal)
                starts.append(cursor)
    ce = FlatBcData(
        torch.from_numpy(np.concatenate(chunks)),
        torch.tensor(starts, dtype=torch.long),
        torch.tensor(chosen_global, dtype=torch.long),
    )
    return (
        torch.from_numpy(np.stack(taken)),
        torch.tensor(rets),
        ce,
        torch.from_numpy(np.stack(orc)),
    )


def main() -> None:
    p = argparse.ArgumentParser(description="Monte-Carlo Q fine-tune")
    p.add_argument("--jsonl", required=True)
    p.add_argument("--init-from", required=True)
    p.add_argument("--output", required=True)
    p.add_argument("--epochs", type=int, default=6)
    p.add_argument("--lr", type=float, default=3e-4)
    p.add_argument("--batch-size", type=int, default=2048)
    p.add_argument("--anchor-weight", type=float, default=0.3)
    p.add_argument("--ce-fraction", type=float, default=0.2)
    p.add_argument("--seed", type=int, default=0)
    p.add_argument("--no-oracle", action="store_true")
    args = p.parse_args()

    device = select_device()
    t0 = time.time()
    x, y, ce, orc = load(Path(args.jsonl), ce_fraction=args.ce_fraction, seed=args.seed)
    if not args.no_oracle and bool(orc.any()):
        # Oracle baseline (state + other hands, no action): R - B keeps
        # argmax_a Q unchanged in expectation but removes most card luck.
        y = y - fit_baseline(torch.cat([x[:, :ACTION_OFFSET], orc], dim=1), y, label="q")
    print(
        f"Q data: taken={x.shape[0]} R std={float(y.std()):.3f}  "
        f"CE decisions={ce.num_decisions}  ({time.time()-t0:.0f}s)",
        flush=True,
    )

    model = load_qnetwork_from_safetensors(Path(args.init_from), device)
    # Policy logits are not on the return scale: fit an affine head offset
    # first so MSE does not wreck the ranking in the first steps.
    lin = [m for m in model.net if isinstance(m, nn.Linear)]
    with torch.no_grad():
        logits = model(x[:20000]).squeeze(-1)
        a = float(((logits - logits.mean()) * (y[:20000] - y[:20000].mean())).mean()
                  / logits.var().clamp_min(1e-6))
        a = max(a, 0.05)
        b = float(y[:20000].mean() - a * logits.mean())
        lin[-1].weight.mul_(a)
        lin[-1].bias.mul_(a).add_(b)
    print(f"  head rescaled: a={a:.3f} b={b:+.3f}")

    n = x.shape[0]
    perm = torch.from_numpy(np.random.default_rng(args.seed).permutation(n))
    n_val = max(1, n // 20)
    val, tr = perm[:n_val], perm[n_val:]
    opt = torch.optim.Adam(model.parameters(), lr=args.lr, weight_decay=1e-5)
    ce_idx = torch.arange(ce.num_decisions)
    for epoch in range(args.epochs):
        model.train()
        order = tr[torch.randperm(tr.numel())]
        steps = (order.numel() + args.batch_size - 1) // args.batch_size
        ce_perm = ce_idx[torch.randperm(ce_idx.numel())]
        ce_bs = max(1, ce_perm.numel() // max(1, steps))
        for i in range(steps):
            idx = order[i * args.batch_size : (i + 1) * args.batch_size]
            loss = nn.functional.mse_loss(model(x[idx]).squeeze(-1), y[idx])
            if args.anchor_weight > 0:
                ce_loss, _, _ = bc_step(
                    model=model,
                    data=ce,
                    decision_idx=ce_perm[i * ce_bs : (i + 1) * ce_bs],
                    require_grad=True,
                )
                loss = loss + args.anchor_weight * ce_loss
            opt.zero_grad(set_to_none=True)
            loss.backward()
            nn.utils.clip_grad_norm_(model.parameters(), 5.0)
            opt.step()
        model.eval()
        with torch.no_grad():
            mse = float(nn.functional.mse_loss(model(x[val]).squeeze(-1), y[val]))
            _, correct, _ = bc_step(
                model=model, data=ce, decision_idx=ce_idx[:5000], require_grad=False
            )
        print(
            f"  epoch {epoch+1}/{args.epochs} val_mse={mse:.4f} (var={float(y[val].var()):.4f}) "
            f"agrees with behaviour {100*float(correct.float().mean()):.1f}%  [{time.time()-t0:.0f}s]",
            flush=True,
        )

    hidden = [m.out_features for m in lin][:-1]
    export_safetensors(
        model.cpu(),
        Path(args.output),
        target_mean=0.0,
        target_std=SCALE,
        metadata={
            "algorithm": "mc_q",
            "architecture": [TOTAL_FEATURE_COUNT] + hidden + [1],
            "init_from": args.init_from,
            "anchor_weight": str(args.anchor_weight),
        },
    )
    print(f"Saved {args.output}")


if __name__ == "__main__":
    main()
