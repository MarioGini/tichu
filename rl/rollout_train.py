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
      --init-from=assets/bots/tichu_q_v5.safetensors \
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
_SELF = SPEC.group("self")
# Round-start match totals, from the state features (target 1000):
# own_to_target = (target - own total) / target, likewise for the opponents.
OWN_TO_TARGET = _SELF.offset + 12
OPP_TO_TARGET = _SELF.offset + 13
# Average sum of both teams' round points (card points + bonuses), used for
# rows from before the runner wrote q_rollout_own.
MEAN_ROUND_SUM = 158.0


class RolloutData:
    """Decisions with their labelled legal actions.

    The state features are stored once per decision (float16) and the action
    features once per labelled action: a row of the net's input is
    ``concat(s[decision], a[row])``. That is ~7x smaller than one full input
    row per action, so millions of decisions fit in memory.
    """

    def __init__(self, s, a, q, own, starts, chosen, explore):
        self.s = s  # (D, ACTION_OFFSET) float16
        self.a = a  # (rows, ACTION_FEATURE_COUNT) float16
        self.q = q  # (rows,) training target (points / SCALE by default)
        self.q_pts = q.clone()  # (rows,) round point difference / SCALE
        self.own = own  # (rows,) own team's round points, NaN = unknown
        self.starts = starts  # (D + 1,) long
        self.chosen = chosen  # (D,) row index of the behaviour action, -1 = unlabelled
        self.explore = explore  # (D,) bool
        self.q_win = None  # (rows,) match-win probability after the round, if computed

    @property
    def num_decisions(self) -> int:
        return int(self.starts.numel() - 1)

    def inputs(self, rows: torch.Tensor, group_decisions: torch.Tensor) -> torch.Tensor:
        return torch.cat([self.s[group_decisions].float(), self.a[rows].float()], dim=1)


def _parse_jsonl(path: Path, max_decisions: int):
    ss, aa, qs, owns, lens, chosen, explore = [], [], [], [], [], [], []
    with path.open("r", encoding="utf-8") as fh:
        for line in fh:
            if '"q_rollout"' not in line:
                continue
            row = json.loads(line)
            q = row["q_rollout"]
            keep = [i for i, v in enumerate(q) if v is not None]
            if len(keep) < 2:
                continue
            own = row.get("q_rollout_own")
            ss.append(np.asarray(row["state_features"], dtype=np.float16))
            aa.append(np.asarray(row["legal_play_action_features"], dtype=np.float16)[keep])
            qs.append(np.asarray([q[i] for i in keep], dtype=np.float32) / SCALE)
            owns.append(
                np.asarray([own[i] for i in keep], dtype=np.float32)
                if own is not None
                else np.full(len(keep), np.nan, dtype=np.float32)
            )
            c = int(row["legal_play_chosen_index"])
            chosen.append(keep.index(c) if c in keep else -1)
            explore.append(bool(row.get("explore")))
            lens.append(len(keep))
            if max_decisions and len(lens) >= max_decisions:
                break
    starts = np.zeros(len(lens) + 1, dtype=np.int64)
    np.cumsum(lens, out=starts[1:])
    ch = np.asarray(chosen, dtype=np.int64)
    ch = np.where(ch >= 0, starts[:-1] + ch, -1)
    return {
        "s": np.stack(ss),
        "a": np.concatenate(aa),
        "q": np.concatenate(qs),
        "own": np.concatenate(owns),
        "starts": starts,
        "chosen": ch,
        "explore": np.asarray(explore, dtype=bool),
    }


def _read_npz(path: Path) -> dict:
    d = dict(np.load(path))
    if "x" in d:  # old cache: one full input row per action
        starts = d["starts"]
        x = d["x"]
        d = {
            "s": x[starts[:-1], :ACTION_OFFSET].astype(np.float16),
            "a": x[:, ACTION_OFFSET:].astype(np.float16),
            "q": d["q"],
            "own": np.full(len(d["q"]), np.nan, dtype=np.float32),
            "starts": starts,
            "chosen": d["chosen"],
            "explore": d["explore"],
        }
    return d


def load(paths: list[Path], *, max_decisions: int = 0) -> RolloutData:
    """Load rollout rows from bc-jsonl files (or ``.npz`` caches of them)."""
    parts = [
        _read_npz(p) if p.suffix == ".npz" else _parse_jsonl(p, max_decisions) for p in paths
    ]
    starts, chosen, cursor = [np.zeros(1, dtype=np.int64)], [], 0
    for d in parts:
        starts.append(d["starts"][1:] + cursor)
        chosen.append(np.where(d["chosen"] >= 0, d["chosen"] + cursor, -1))
        cursor += int(d["starts"][-1])
    cat = lambda k: torch.from_numpy(np.concatenate([d[k] for d in parts]))  # noqa: E731
    return RolloutData(
        cat("s"),
        cat("a"),
        cat("q"),
        cat("own"),
        torch.from_numpy(np.concatenate(starts)),
        torch.from_numpy(np.concatenate(chosen)),
        cat("explore"),
    )


def save_npz(data: RolloutData, path: Path) -> None:
    """Compact cache of parsed rollout rows (JSON parsing dominates load time)."""
    np.savez(
        path,
        s=data.s.numpy(),
        a=data.a.numpy(),
        q=data.q_pts.numpy(),
        own=data.own.numpy(),
        starts=data.starts.numpy(),
        chosen=data.chosen.numpy(),
        explore=data.explore.numpy(),
    )


def win_targets(data: RolloutData, table_path: Path) -> torch.Tensor:
    """Match-win probability after the round, per labelled action.

    Round-start totals come from the state features, the round result from
    the rollout (own points and the difference; the own points are
    approximated from the difference for old rows without them).
    """
    from win_prob import WinTable

    table = WinTable.load(table_path)
    dec = torch.repeat_interleave(
        torch.arange(data.num_decisions), data.starts[1:] - data.starts[:-1]
    ).numpy()
    s = data.s.numpy()
    a_tot = table.target * (1.0 - s[dec, OWN_TO_TARGET].astype(np.float64))
    b_tot = table.target * (1.0 - s[dec, OPP_TO_TARGET].astype(np.float64))
    diff = data.q_pts.numpy().astype(np.float64) * SCALE
    own = data.own.numpy().astype(np.float64)
    own = np.where(np.isnan(own), (MEAN_ROUND_SUM + diff) / 2, own)
    w = table.after_round(a_tot, b_tot, own, own - diff)
    return torch.from_numpy(w.astype(np.float32))


def permute_suits(s: torch.Tensor) -> torch.Tensor:
    """Random suit relabelling per decision (the game is suit-symmetric).

    The hand and played bitmaps are 4 x 13 (suit x rank) blocks; all other
    features (including the action features) do not depend on suit identity.
    """
    k = s.shape[0]
    perms = torch.argsort(torch.rand(k, 4), dim=1)  # (k, 4)
    idx = perms[:, :, None].expand(-1, 4, 13)
    s = s.clone()
    for start in (HAND_OFFSET, PLAYED_OFFSET):
        block = s[:, start : start + 52].reshape(-1, 4, 13)
        s[:, start : start + 52] = block.gather(1, idx).reshape(-1, 52)
    return s


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
    st = data.s[idx].float()
    if augment:
        st = permute_suits(st)
    x = torch.cat([st[group], data.a[rows].float()], dim=1)
    out = model(x).squeeze(-1)
    return nn.functional.huber_loss(
        _centred(out, group, k), _centred(data.q[rows], group, k), delta=huber
    )


@torch.no_grad()
def evaluate(model: nn.Module, data: RolloutData, idx: torch.Tensor) -> dict[str, float]:
    """Value of the greedy policy on held-out decisions: round points, and
    match-win percentage points when win targets are loaded."""
    rows, group, offset = gather_batch_indices(idx, data.starts)
    out = torch.cat(
        [
            model(data.inputs(rows[i : i + 65536], idx[group[i : i + 65536]])).squeeze(-1)
            for i in range(0, rows.numel(), 65536)
        ]
    )
    k = int(idx.numel())
    best = torch.full((k,), float("-inf")).scatter_reduce(0, group, out, reduce="amax")
    is_best = out >= best[group] - 1e-9
    den = torch.zeros(k).scatter_add_(0, group, is_best.float())
    n = (data.starts[idx + 1] - data.starts[idx]).float()
    chosen = data.chosen[idx]
    has = (chosen >= 0) & ~data.explore[idx]
    agree = is_best[(offset + chosen - data.starts[idx]).clamp(0, rows.numel() - 1)]
    m = {"agree": float(agree[has].float().mean())}
    targets = [("pts", data.q_pts, SCALE)]
    if data.q_win is not None:
        targets.append(("win", data.q_win, 100.0))
    for name, qall, unit in targets:
        q = qall[rows]
        greedy = torch.zeros(k).scatter_add_(0, group, q * is_best) / den
        mean_q = torch.zeros(k).scatter_add_(0, group, q) / n
        oracle = torch.full((k,), float("-inf")).scatter_reduce(0, group, q, reduce="amax")
        beh = qall[chosen.clamp_min(0)]
        m[f"gain_{name}"] = float(((greedy - beh)[has]).mean() * unit)
        m[f"vs_uniform_{name}"] = float((greedy - mean_q).mean() * unit)
        m[f"clairvoyant_{name}"] = float(((oracle - beh)[has]).mean() * unit)
    q = data.q[rows]
    m["mse"] = float(nn.functional.mse_loss(_centred(out, group, k), _centred(q, group, k)))
    m["var"] = float(_centred(q, group, k).var())
    return m


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
        data.s[:, hist.offset : hist.offset + hist.size] = 0.0
    if args.save_cache:
        save_npz(data, Path(args.save_cache))
    d = data.num_decisions
    print(f"rollout data: decisions={d} rows={data.a.shape[0]} ({time.time()-t0:.0f}s)", flush=True)
    if args.objective != "points" or args.win_table_metrics:
        data.q_win = win_targets(data, Path(args.win_table))
    if args.objective == "win":
        # Same spread as the point targets, so the Huber delta and learning
        # rate keep their meaning.
        rows, group, _ = gather_batch_indices(torch.arange(d), data.starts)
        sp = _centred(data.q_pts, group, d).std()
        sw = _centred(data.q_win, group, d).std()
        data.q = data.q_win * (sp / sw)
        print(f"  win targets: 1 win-% = {float(sp / sw) * SCALE / 100:.2f} points", flush=True)

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
    ema = torch.optim.swa_utils.AveragedModel(
        model, multi_avg_fn=torch.optim.swa_utils.get_ema_multi_avg_fn(args.ema)
    ) if args.ema > 0 else None
    best_state, best_gain, metrics = None, float("-inf"), m0
    key = "vs_uniform_win" if args.objective == "win" else "vs_uniform_pts"
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
            if ema is not None:
                ema.update_parameters(model)
        model.eval()
        final = ema.module if ema is not None else model
        m = evaluate(final, data, val)
        print(
            f"  epoch {epoch+1}/{args.epochs} "
            + "  ".join(f"{k}={v:.3f}" for k, v in m.items())
            + f"  [{time.time()-t0:.0f}s]",
            flush=True,
        )
        if args.save_epochs:
            _export(final, Path(f"{args.output}.ep{epoch+1}"), d)
        if m[key] > best_gain:
            best_gain, metrics = m[key], m
            best_state = {k: v.clone() for k, v in final.state_dict().items()}
    model = final
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
    p.add_argument(
        "--objective",
        choices=["points", "win"],
        default="points",
        help="regress on round points or on the match-win probability after the round",
    )
    p.add_argument("--win-table", default=str(Path(__file__).resolve().parent / "win_table.npz"))
    p.add_argument("--win-table-metrics", action="store_true", help="also report win-% gains")
    p.add_argument("--ema", type=float, default=0.0, help="EMA decay of the exported weights (0 = off)")
    p.add_argument("--seed", type=int, default=0)
    train(p.parse_args())


if __name__ == "__main__":
    main()
