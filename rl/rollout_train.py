#!/usr/bin/env python3
"""Rollout policy iteration: fit the play Q-net on exact all-action values.

Data comes from ``headless --rollout-rate=p``: for a sampled play decision
the round is forked once per legal action and played out by the current
bots, so every legal action has the exact round result that follows it
(``q_rollout``, same deal, same policies — no card luck in the differences).

The net is trained on *advantages*: per decision both the targets and the
net outputs are centred over the labelled actions,

    loss = Huber( Q(s,a) - mean_b Q(s,b) ,  (R(a) - mean_b R(b)) / 100 )

so the state value (card luck) never enters the loss. argmax_a Q is the
greedy policy w.r.t. the rollout values = one policy-improvement step; the
exported net plugs straight into ``NnPlaySelectionStrategy``.

  rl/.venv/bin/python rl/rollout_train.py --jsonl=a.jsonl,b.jsonl \
      --init-from=assets/bots/tichu_q_v3.safetensors \
      --output=rl/outputs/rollout_policy.safetensors
"""

from __future__ import annotations

import argparse
import json
import time
from pathlib import Path

import numpy as np
import torch
import torch.nn as nn

from qnet import (
    QNetwork,
    export_safetensors,
    gather_batch_indices,
    load_qnetwork_from_safetensors,
    select_device,
)
from schema import ACTION_OFFSET, SPEC, TOTAL_FEATURE_COUNT

SCALE = 100.0
HAND_OFFSET = 0
PLAYED_OFFSET = 56


class RolloutData:
    """Flat rows grouped by decision (only actions with a rollout value)."""

    def __init__(self, x, q, starts, chosen, explore):
        self.x = x  # (rows, F) float32
        self.q = q  # (rows,) rollout value / SCALE
        self.starts = starts  # (D + 1,) long
        self.chosen = chosen  # (D,) row index of the behaviour action, -1 = unlabelled
        self.explore = explore  # (D,) bool

    @property
    def num_decisions(self) -> int:
        return int(self.starts.numel() - 1)


def load(paths: list[Path], *, max_decisions: int = 0) -> RolloutData:
    """Load rollout rows from bc-jsonl files (or ``.npz`` caches of them)."""
    xs: list[np.ndarray] = []
    qs: list[np.ndarray] = []
    starts = [0]
    chosen: list[int] = []
    explore: list[bool] = []
    cursor = 0
    for path in paths:
        if path.suffix == ".npz":
            d = np.load(path)
            xs.append(d["x"])
            qs.append(d["q"])
            chosen.extend(int(c) + cursor if c >= 0 else -1 for c in d["chosen"])
            explore.extend(bool(e) for e in d["explore"])
            starts.extend(int(v) + cursor for v in d["starts"][1:])
            cursor += int(d["starts"][-1])
            continue
        with path.open("r", encoding="utf-8") as fh:
            for line in fh:
                if '"q_rollout"' not in line:
                    continue
                row = json.loads(line)
                q = row["q_rollout"]
                keep = [i for i, v in enumerate(q) if v is not None]
                if len(keep) < 2:
                    continue
                legal = np.asarray(row["legal_play_action_features"], dtype=np.float32)[keep]
                block = np.empty((len(keep), TOTAL_FEATURE_COUNT), dtype=np.float32)
                block[:, :ACTION_OFFSET] = np.asarray(row["state_features"], dtype=np.float32)
                block[:, ACTION_OFFSET:] = legal
                xs.append(block)
                qs.append(np.asarray([q[i] for i in keep], dtype=np.float32) / SCALE)
                c = int(row["legal_play_chosen_index"])
                chosen.append(cursor + keep.index(c) if c in keep else -1)
                explore.append(bool(row.get("explore")))
                cursor += len(keep)
                starts.append(cursor)
                if max_decisions and len(chosen) >= max_decisions:
                    break
    return RolloutData(
        torch.from_numpy(np.concatenate(xs)),
        torch.from_numpy(np.concatenate(qs)),
        torch.tensor(starts, dtype=torch.long),
        torch.tensor(chosen, dtype=torch.long),
        torch.tensor(explore, dtype=torch.bool),
    )


def save_npz(data: RolloutData, path: Path) -> None:
    """Compact cache of parsed rollout rows (JSON parsing dominates load time)."""
    starts = data.starts.numpy()
    chosen = data.chosen.numpy().copy()
    # Store the chosen action relative to this file's rows.
    np.savez(
        path,
        x=data.x.numpy(),
        q=data.q.numpy(),
        starts=starts,
        chosen=chosen,
        explore=data.explore.numpy(),
    )


def permute_suits(x: torch.Tensor, group: torch.Tensor, k: int) -> torch.Tensor:
    """Random suit relabelling per decision (the game is suit-symmetric).

    The hand and played bitmaps are 4 x 13 (suit x rank) blocks; all other
    features do not depend on suit identity.
    """
    perms = torch.argsort(torch.rand(k, 4), dim=1)[group]  # (rows, 4)
    idx = perms[:, :, None].expand(-1, 4, 13)
    x = x.clone()
    for start in (HAND_OFFSET, PLAYED_OFFSET):
        block = x[:, start : start + 52].reshape(-1, 4, 13)
        x[:, start : start + 52] = block.gather(1, idx).reshape(-1, 52)
    return x


def _centred(values: torch.Tensor, group: torch.Tensor, k: int) -> torch.Tensor:
    sums = torch.zeros(k, dtype=values.dtype).scatter_add_(0, group, values)
    counts = torch.zeros(k, dtype=values.dtype).scatter_add_(0, group, torch.ones_like(values))
    return values - (sums / counts)[group]


def batch_loss(
    model: nn.Module,
    data: RolloutData,
    idx: torch.Tensor,
    huber: float,
    *,
    augment: bool = True,
):
    rows, group, _ = gather_batch_indices(idx, data.starts)
    k = int(idx.numel())
    x = data.x[rows]
    if augment:
        x = permute_suits(x, group, k)
    out = model(x).squeeze(-1)
    return nn.functional.huber_loss(
        _centred(out, group, k), _centred(data.q[rows], group, k), delta=huber
    )


@torch.no_grad()
def evaluate(model: nn.Module, data: RolloutData, idx: torch.Tensor) -> dict[str, float]:
    """Value of the greedy policy on held-out decisions, in round points."""
    rows, group, offset = gather_batch_indices(idx, data.starts)
    out = model(data.x[rows]).squeeze(-1)
    q = data.q[rows]
    k = int(idx.numel())
    best = torch.full((k,), float("-inf")).scatter_reduce(0, group, out, reduce="amax")
    is_best = out >= best[group] - 1e-9
    # Mean rollout value of the net's top action(s).
    num = torch.zeros(k).scatter_add_(0, group, q * is_best)
    den = torch.zeros(k).scatter_add_(0, group, is_best.float())
    greedy = num / den
    mean_q = torch.zeros(k).scatter_add_(0, group, q) / (data.starts[idx + 1] - data.starts[idx])
    oracle = torch.full((k,), float("-inf")).scatter_reduce(0, group, q, reduce="amax")
    chosen = data.chosen[idx]
    has = (chosen >= 0) & ~data.explore[idx]
    beh = data.q[chosen.clamp_min(0)]
    agree = is_best[(offset + chosen - data.starts[idx]).clamp(0, rows.numel() - 1)]
    return {
        "gain_vs_behaviour": float(((greedy - beh)[has]).mean() * SCALE),
        "gain_vs_uniform": float((greedy - mean_q).mean() * SCALE),
        "clairvoyant_gain": float(((oracle - beh)[has]).mean() * SCALE),
        "agree": float(agree[has].float().mean()),
        "mse": float(nn.functional.mse_loss(_centred(out, group, k), _centred(q, group, k))),
        "var": float(_centred(q, group, k).var()),
    }


def _export(model: nn.Module, path: Path, decisions: int) -> None:
    lin = [mod for mod in model.net if isinstance(mod, nn.Linear)]
    export_safetensors(
        model,
        path,
        target_mean=0.0,
        target_std=SCALE,
        metadata={
            "algorithm": "rollout_pi",
            "architecture": [TOTAL_FEATURE_COUNT] + [m_.out_features for m_ in lin],
            "decisions": str(decisions),
        },
    )


def train(args: argparse.Namespace) -> dict[str, float]:
    device = select_device()
    torch.manual_seed(args.seed)
    t0 = time.time()
    data = load([Path(p) for p in args.jsonl.split(",") if p])
    if args.zero_history:
        # A/B control: same data and net, but the per-player history inputs
        # are always zero (what a net without them would see).
        hist = SPEC.group("history")
        data.x[:, hist.offset : hist.offset + hist.size] = 0.0
    if args.save_cache:
        save_npz(data, Path(args.save_cache))
    d = data.num_decisions
    print(f"rollout data: decisions={d} rows={data.x.shape[0]} ({time.time()-t0:.0f}s)", flush=True)

    if args.hidden:
        model = QNetwork(TOTAL_FEATURE_COUNT, [int(h) for h in args.hidden.split(",")])
    else:
        model = load_qnetwork_from_safetensors(Path(args.init_from), device)

    perm = torch.from_numpy(np.random.default_rng(args.seed).permutation(d))
    n_val = max(1, int(d * args.val_fraction))
    val, tr = perm[:n_val], perm[n_val:]
    m0 = evaluate(model, data, val)
    print("  start: " + "  ".join(f"{k}={v:.3f}" for k, v in m0.items()), flush=True)

    opt = torch.optim.AdamW(model.parameters(), lr=args.lr, weight_decay=args.weight_decay)
    # L2-SP: pull towards the starting weights, so a noisy step cannot wipe
    # out what the previous policy already knows.
    anchor = [p_.detach().clone() for p_ in model.parameters()] if args.l2sp > 0 else None
    steps_per_epoch = (tr.numel() + args.batch_decisions - 1) // args.batch_decisions
    sched = torch.optim.lr_scheduler.OneCycleLR(
        opt, max_lr=args.lr, total_steps=args.epochs * steps_per_epoch, pct_start=0.1
    )
    best_state, best_gain, metrics = None, float("-inf"), m0
    for epoch in range(args.epochs):
        model.train()
        order = tr[torch.randperm(tr.numel())]
        for i in range(steps_per_epoch):
            idx = order[i * args.batch_decisions : (i + 1) * args.batch_decisions]
            loss = batch_loss(model, data, idx, args.huber, augment=not args.no_augment)
            if anchor is not None:
                loss = loss + args.l2sp * sum(
                    ((p_ - a_) ** 2).sum() for p_, a_ in zip(model.parameters(), anchor)
                )
            opt.zero_grad(set_to_none=True)
            loss.backward()
            nn.utils.clip_grad_norm_(model.parameters(), 5.0)
            opt.step()
            sched.step()
        model.eval()
        m = evaluate(model, data, val)
        print(
            f"  epoch {epoch+1}/{args.epochs} "
            + "  ".join(f"{k}={v:.3f}" for k, v in m.items())
            + f"  [{time.time()-t0:.0f}s]",
            flush=True,
        )
        if args.save_epochs:
            _export(model, Path(f"{args.output}.ep{epoch+1}"), d)
        if m["gain_vs_uniform"] > best_gain:
            best_gain, metrics = m["gain_vs_uniform"], m
            best_state = {k: v.clone() for k, v in model.state_dict().items()}
    if best_state is not None and not args.keep_last:
        model.load_state_dict(best_state)
    else:
        metrics = m

    _export(model, Path(args.output), d)
    print(f"Saved {args.output}  " + "  ".join(f"{k}={v:.3f}" for k, v in metrics.items()))
    return metrics


def main() -> None:
    p = argparse.ArgumentParser(description="Rollout policy-iteration step for the play net")
    p.add_argument("--jsonl", required=True, help="comma-separated rollout jsonl files")
    p.add_argument("--init-from", default="")
    p.add_argument("--hidden", default="", help="train a fresh net of this size instead of --init-from")
    p.add_argument("--output", required=True)
    p.add_argument("--epochs", type=int, default=12)
    p.add_argument("--lr", type=float, default=1e-3)
    p.add_argument("--weight-decay", type=float, default=1e-4)
    p.add_argument("--batch-decisions", type=int, default=256)
    p.add_argument("--huber", type=float, default=2.0)
    p.add_argument("--val-fraction", type=float, default=0.1)
    p.add_argument("--keep-last", action="store_true")
    p.add_argument("--l2sp", type=float, default=0.0, help="L2 pull towards the initial weights")
    p.add_argument("--no-augment", action="store_true", help="disable suit-permutation augmentation")
    p.add_argument("--save-epochs", action="store_true", help="also export OUTPUT.epN after every epoch")
    p.add_argument("--save-cache", default="", help="write the parsed rows to this .npz")
    p.add_argument("--zero-history", action="store_true", help="A/B control: zero the history inputs")
    p.add_argument("--seed", type=int, default=0)
    train(p.parse_args())


if __name__ == "__main__":
    main()
