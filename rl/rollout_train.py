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
      --init-from=assets/bots/tichu_q_v10.safetensors \
      --output=rl/outputs/rollout_policy.safetensors
"""

from __future__ import annotations

import argparse
import json
import re
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
from data_upgrade import upgrade
from schema import SPEC, ACTION_FEATURE_COUNT, ACTION_OFFSET, LEGACY_ACTION_FEATURE_COUNT, TOTAL_FEATURE_COUNT, pad_action, pad_state

SCALE = 100.0
HAND_OFFSET = 0
PLAYED_OFFSET = 56
# Old caches carry no match ids: their decisions are split into contiguous
# blocks of this many decisions instead (about one match of labelled data), so
# held-out decisions still come from other deals than the training ones.
OLD_CACHE_GAME_BLOCK = 256


class RolloutData:
    """Decisions with their labelled legal actions.

    The state features are stored once per decision (float16) and the action
    features once per labelled action: a row of the net's input is
    ``concat(s[decision], a[row])``. That is ~7x smaller than one full input
    row per action, so millions of decisions fit in memory.
    """

    def __init__(self, s, a, q, starts, chosen, explore, game, weight, pos=None):
        self.s = s  # (D, ACTION_OFFSET) float16
        self.a = a  # (rows, ACTION_FEATURE_COUNT) float16
        self.q = q  # (rows,) round point difference / SCALE
        self.starts = starts  # (D + 1,) long
        self.chosen = chosen  # (D,) row index of the behaviour action, -1 = unlabelled
        self.explore = explore  # (D,) bool
        self.game = game  # (D,) long, match id (unique across files)
        self.weight = weight  # (D,) float32 loss weight (recency of the data)
        # (D, 2) int32 (round, step) of each decision in its match's game
        # record (--record-games), -1 when the data has none: the position
        # can be rebuilt by replay (lib/headless/replay_game_records.dart).
        self.pos = pos

    @property
    def num_decisions(self) -> int:
        return int(self.starts.numel() - 1)

    def inputs(self, rows: torch.Tensor, group_decisions: torch.Tensor) -> torch.Tensor:
        return torch.cat([self.s[group_decisions].float(), self.a[rows].float()], dim=1)


def _parse_jsonl(path: Path, max_decisions: int):
    ss, aa, qs, lens, chosen, explore, games, pos = [], [], [], [], [], [], [], []
    with path.open("r", encoding="utf-8") as fh:
        for line in fh:
            if '"q_rollout"' not in line:
                continue
            row = json.loads(line)
            q = row["q_rollout"]
            worlds = row.get("q_rollout_worlds")
            if worlds:
                # --rollout-worlds: the label is the mean over the real deal
                # and the re-dealt worlds (what the endgame search computes).
                q = [
                    None if v is None else (v + sum(w[i] for w in worlds if w[i] is not None))
                    / (1 + sum(1 for w in worlds if w[i] is not None))
                    for i, v in enumerate(q)
                ]
            keep = [i for i, v in enumerate(q) if v is not None]
            if len(keep) < 2:
                continue
            ss.append(np.asarray(row["state_features"], dtype=np.float16))
            # Rows of an older layout (51 action features): padded below.
            aa.append(np.asarray(row["legal_play_action_features"], dtype=np.float16)[keep])
            qs.append(np.asarray([q[i] for i in keep], dtype=np.float32) / SCALE)
            c = int(row["legal_play_chosen_index"])
            chosen.append(keep.index(c) if c in keep else -1)
            explore.append(bool(row.get("explore")))
            games.append(int(row.get("episode", 0)))
            pos.append((int(row.get("round", -1)), int(row.get("step", -1))))
            lens.append(len(keep))
            if max_decisions and len(lens) >= max_decisions:
                break
    starts = np.zeros(len(lens) + 1, dtype=np.int64)
    np.cumsum(lens, out=starts[1:])
    ch = np.asarray(chosen, dtype=np.int64)
    ch = np.where(ch >= 0, starts[:-1] + ch, -1)
    d = {
        "s": np.stack(ss),
        "a": np.concatenate(aa),
        "q": np.concatenate(qs),
        "starts": starts,
        "chosen": ch,
        "explore": np.asarray(explore, dtype=bool),
        "game": np.asarray(games, dtype=np.int64),
        "pos": np.asarray(pos, dtype=np.int32).reshape(-1, 2),
    }
    d, notes = upgrade(d)
    for n in notes:
        _MISSING.setdefault(n, []).append(path.name)
    return d


# Unrecoverable feature groups seen while loading -> file names (reported once).
_MISSING: dict[str, list[str]] = {}


def _read_npz(path: Path) -> dict:
    """An npz cache; columns of removed experiments (``own``, ``label_p``,
    ``stakes``) are ignored."""
    d = dict(np.load(path))
    if "x" in d:  # old cache: one full input row per action (layout <= v6)
        starts = d["starts"]
        x = d["x"]
        cut = x.shape[1] - LEGACY_ACTION_FEATURE_COUNT
        d = {
            "s": x[starts[:-1], :cut].astype(np.float16),
            "a": x[:, cut:].astype(np.float16),
            "q": d["q"],
            "starts": starts,
            "chosen": d["chosen"],
            "explore": d["explore"],
        }
    d, notes = upgrade(d)
    for n in notes:
        _MISSING.setdefault(n, []).append(path.name)
    if "game" not in d:
        d["game"] = np.arange(len(d["chosen"]), dtype=np.int64) // OLD_CACHE_GAME_BLOCK
    return d


def file_iteration(path: Path) -> int | None:
    """rollout_loop data files are named itNN_<kind>.npz."""
    m = re.match(r"it(\d+)_", path.name)
    return int(m.group(1)) if m else None


def load(paths: list[Path], *, max_decisions: int = 0, recency: float = 1.0) -> RolloutData:
    """Load rollout rows from bc-jsonl files (or ``.npz`` caches of them).

    ``recency`` < 1 down-weights older rollout_loop iterations: a file of
    iteration k gets loss weight ``recency ** (newest - k)``. Their labels
    are values under the policy of their own iteration, not the current one.

    Memory: the big arrays are allocated once at their final size and each
    file is copied in and released, so the peak is the data plus one file
    (concatenating all parts at the end needed twice the data: 5M decisions
    were ~14 GB).
    """
    its = [file_iteration(p) for p in paths]
    newest = max((i for i in its if i is not None), default=0)
    # Pass 1: sizes (and the small per-decision columns).
    meta = []
    for p in paths:
        if p.suffix == ".npz":
            with np.load(p) as z:
                if "x" in z.files:  # old full-row cache: convert in memory
                    d = _read_npz(p)
                    meta.append(("mem", d))
                    continue
                starts = z["starts"]
                meta.append(("npz", {"starts": starts, "chosen": z["chosen"], "explore": z["explore"],
                                      "game": z["game"] if "game" in z.files else None,
                                      "rows": int(starts[-1])}))
        else:
            meta.append(("mem", _parse_jsonl(p, max_decisions)))
    n_dec = sum(len(m[1]["chosen"]) for m in meta)
    n_rows = sum(int(m[1]["starts"][-1]) for m in meta)
    s_all = np.empty((n_dec, ACTION_OFFSET), np.float16)
    a_all = np.empty((n_rows, ACTION_FEATURE_COUNT), np.float16)
    q_all = np.empty(n_rows, np.float32)
    starts, chosen, games, weights, explore, pos = [np.zeros(1, dtype=np.int64)], [], [], [], [], []
    cursor = game_cursor = dec = 0
    for (kind, m), p, it in zip(meta, paths, its):
        if kind == "npz":
            d = _read_npz(p)
        else:
            d = m
        k, r = len(d["chosen"]), int(d["starts"][-1])
        s_all[dec : dec + k] = d["s"]
        a_all[cursor : cursor + r] = d["a"]
        q_all[cursor : cursor + r] = d["q"]
        starts.append(d["starts"][1:] + cursor)
        chosen.append(np.where(d["chosen"] >= 0, d["chosen"] + cursor, -1))
        explore.append(d["explore"])
        pos.append(d["pos"] if "pos" in d else np.full((k, 2), -1, np.int32))
        g = np.unique(d["game"], return_inverse=True)[1].astype(np.int64)
        games.append(g + game_cursor)
        game_cursor += int(g.max()) + 1 if g.size else 0
        w = 1.0 if it is None else recency ** (newest - it)
        weights.append(np.full(k, w, dtype=np.float32))
        cursor += r
        dec += k
        del d
    for what, names in _MISSING.items():
        print(f"  note: {len(names)} file(s) predate the features '{what}' (zeros)", flush=True)
    _MISSING.clear()
    return RolloutData(
        torch.from_numpy(s_all),
        torch.from_numpy(a_all),
        torch.from_numpy(q_all),
        torch.from_numpy(np.concatenate(starts)),
        torch.from_numpy(np.concatenate(chosen)),
        torch.from_numpy(np.concatenate(explore)),
        torch.from_numpy(np.concatenate(games)),
        torch.from_numpy(np.concatenate(weights)),
        torch.from_numpy(np.concatenate(pos)) if pos else None,
    )


def save_npz(data: RolloutData, path: Path) -> None:
    """Compact cache of parsed rollout rows (JSON parsing dominates load time).

    Compressed (the bitmaps are sparse): about 4x smaller, small enough to
    keep every iteration in Supabase Storage (rl/training_data_store.py).
    """
    np.savez_compressed(
        path,
        s=data.s.numpy(),
        a=data.a.numpy(),
        q=data.q.numpy(),
        starts=data.starts.numpy(),
        chosen=data.chosen.numpy(),
        explore=data.explore.numpy(),
        game=data.game.numpy().astype(np.int32),
        schema_version=np.int16(SPEC.version),
        **({"pos": data.pos.numpy().astype(np.int32)} if data.pos is not None else {}),
    )


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
):
    rows, group, _ = gather_batch_indices(idx, data.starts)
    k = int(idx.numel())
    st = permute_suits(data.s[idx].float())
    x = torch.cat([st[group], data.a[rows].float()], dim=1)
    out = model(x).squeeze(-1)
    per_row = nn.functional.huber_loss(
        _centred(out, group, k), _centred(data.q[rows], group, k), delta=huber, reduction="none"
    )
    w = data.weight[idx][group]
    return (per_row * w).sum() / w.sum()


@torch.no_grad()
def evaluate(model: nn.Module, data: RolloutData, idx: torch.Tensor) -> dict[str, float]:
    """Value of the greedy policy on held-out decisions, in round points."""
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
    q = data.q[rows]
    greedy = torch.zeros(k).scatter_add_(0, group, q * is_best) / den
    mean_q = torch.zeros(k).scatter_add_(0, group, q) / n
    oracle = torch.full((k,), float("-inf")).scatter_reduce(0, group, q, reduce="amax")
    beh = data.q[chosen.clamp_min(0)]
    m["gain_pts"] = float(((greedy - beh)[has]).mean() * SCALE)
    m["vs_uniform_pts"] = float((greedy - mean_q).mean() * SCALE)
    m["clairvoyant_pts"] = float(((oracle - beh)[has]).mean() * SCALE)
    m["mse"] = float(nn.functional.mse_loss(_centred(out, group, k), _centred(q, group, k)))
    m["var"] = float(_centred(q, group, k).var())
    return m


def widen_hidden(model: QNetwork, sizes: list[int], seed: int = 0) -> QNetwork:
    """Function-preserving widening (Net2Net-style) of every hidden layer.

    Old units keep their weights; new units get small random incoming weights
    and zero outgoing weights, so the wider net plays exactly like the old one
    and training can start from it instead of from scratch.
    """
    old = [m for m in model.net if isinstance(m, nn.Linear)]
    if len(sizes) != len(old) - 1:
        raise ValueError(f"--widen-hidden needs {len(old) - 1} sizes, got {sizes}")
    gen = torch.Generator().manual_seed(seed)
    wide = QNetwork(old[0].in_features, sizes)
    new = [m for m in wide.net if isinstance(m, nn.Linear)]
    with torch.no_grad():
        for o, n in zip(old, new):
            if n.out_features < o.out_features:
                raise ValueError("--widen-hidden can only grow layers")
            n.weight.zero_()
            n.bias.zero_()
            if n is not new[-1]:
                extra = n.out_features - o.out_features
                fan_in = n.in_features
                n.weight[o.out_features :, :] = (
                    torch.randn(extra, fan_in, generator=gen) * (0.5 / fan_in**0.5)
                )
            n.weight[: o.out_features, : o.in_features] = o.weight
            n.bias[: o.out_features] = o.bias
    return wide


def split_by_match(data: RolloutData, val_fraction: float, seed: int):
    """(held-out, train) decision indices, whole matches on either side."""
    rng = np.random.default_rng(seed)
    n_games = int(data.game.max()) + 1
    val_games = torch.from_numpy(rng.random(n_games) < val_fraction)
    is_val = val_games[data.game]
    if not bool(is_val.any()):
        is_val[0] = True
    val = torch.nonzero(is_val).squeeze(1)
    tr = torch.nonzero(~is_val).squeeze(1)
    tr = tr[torch.from_numpy(rng.permutation(tr.numel()))]
    return val, tr


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
    data = load([Path(p) for p in args.jsonl.split(",") if p], recency=args.recency)
    if args.save_cache:
        save_npz(data, Path(args.save_cache))
    if args.zero_action_features:
        # Control runs: these action inputs are always 0, so (starting from a
        # net whose weights for them are zero) the net never uses them.
        lo, hi = (int(x) for x in args.zero_action_features.split(":"))
        data.a[:, lo:hi] = 0
    d = data.num_decisions
    print(f"rollout data: decisions={d} rows={data.a.shape[0]} ({time.time()-t0:.0f}s)", flush=True)
    if args.hidden:
        model = QNetwork(TOTAL_FEATURE_COUNT, [int(h) for h in args.hidden.split(",")])
    else:
        model = load_qnetwork_from_safetensors(Path(args.init_from), device)
        if args.widen_hidden:
            model = widen_hidden(model, [int(h) for h in args.widen_hidden.split(",")], args.seed)

    # Held-out decisions come from held-out *matches*: decisions of one
    # round share the deal, i.e. most of the label noise, so a per-decision
    # split leaks it and early stopping would keep overfitted epochs.
    val, tr = split_by_match(data, args.val_fraction, args.seed)
    print(f"  split: {tr.numel()} train / {val.numel()} held-out decisions "
          f"({int(data.game.max()) + 1} matches)", flush=True)
    m0 = evaluate(model, data, val)
    print("  start: " + "  ".join(f"{k}={v:.3f}" for k, v in m0.items()), flush=True)

    opt = torch.optim.AdamW(model.parameters(), lr=args.lr, weight_decay=args.weight_decay)
    steps_per_epoch = (tr.numel() + args.batch_decisions - 1) // args.batch_decisions
    sched = torch.optim.lr_scheduler.OneCycleLR(
        opt, max_lr=args.lr, total_steps=args.epochs * steps_per_epoch, pct_start=0.1
    )
    ema = torch.optim.swa_utils.AveragedModel(
        model, multi_avg_fn=torch.optim.swa_utils.get_ema_multi_avg_fn(args.ema)
    ) if args.ema > 0 else None
    # The starting net counts as epoch 0: training never exports a net
    # that is worse on the held-out decisions than the one it started from.
    init_state = {k: v.clone() for k, v in model.state_dict().items()}
    # (--allow-worse: when the starting net was trained on these same
    # decisions its held-out score is in-sample, and a duel gate judges.)
    best_state = None
    best_gain = float("-inf") if args.allow_worse else m0["vs_uniform_pts"]
    metrics = m0
    for epoch in range(args.epochs):
        model.train()
        order = tr[torch.randperm(tr.numel())]
        for i in range(steps_per_epoch):
            idx = order[i * args.batch_decisions : (i + 1) * args.batch_decisions]
            loss = batch_loss(model, data, idx, args.huber)
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
        if m["vs_uniform_pts"] > best_gain:
            best_gain, metrics = m["vs_uniform_pts"], m
            best_state = {k: v.clone() for k, v in final.state_dict().items()}
            # Keep the best epoch on disk, so a job stopped mid-run keeps it.
            _export(final, Path(args.output), d)
    model = final
    # No epoch beat the starting net: export the starting net.
    model.load_state_dict(best_state if best_state is not None else init_state)

    _export(model, Path(args.output), d)
    print(f"Saved {args.output}  " + "  ".join(f"{k}={v:.3f}" for k, v in metrics.items()))
    return metrics


def main() -> None:
    p = argparse.ArgumentParser(description="Rollout policy-iteration step for the play net")
    p.add_argument("--jsonl", required=True, help="comma-separated rollout jsonl files")
    p.add_argument("--init-from", default="")
    p.add_argument("--hidden", default="", help="train a fresh net of this size instead of --init-from")
    p.add_argument(
        "--widen-hidden",
        default="",
        help="grow --init-from's hidden layers to these sizes (same play at the start)",
    )
    p.add_argument("--output", required=True)
    p.add_argument(
        "--allow-worse",
        action="store_true",
        help="export the best epoch even if the starting net scores higher (rollout_loop: its duels gate)",
    )
    p.add_argument(
        "--zero-action-features",
        default="",
        help="lo:hi action-feature columns set to 0 (ablation control, e.g. 54:58)",
    )
    p.add_argument("--epochs", type=int, default=4, help="held-out gain peaks after 3-4 epochs")
    p.add_argument("--lr", type=float, default=3e-4)
    p.add_argument("--weight-decay", type=float, default=1e-4)
    p.add_argument("--batch-decisions", type=int, default=256)
    p.add_argument("--huber", type=float, default=2.0)
    p.add_argument("--val-fraction", type=float, default=0.1)
    p.add_argument("--save-cache", default="", help="write the parsed rows to this .npz")
    p.add_argument("--ema", type=float, default=0.999, help="EMA decay of the exported weights (0 = off)")
    p.add_argument(
        "--recency",
        type=float,
        default=0.8,
        help="loss weight factor per rollout_loop iteration of age (1 = all data equal)",
    )
    p.add_argument("--seed", type=int, default=0)
    # No-op, accepted only so that rollout_loop.py processes started before
    # the 2026-11-23 cleanup (which passed it) can finish; remove later.
    train(p.parse_args())


if __name__ == "__main__":
    main()
