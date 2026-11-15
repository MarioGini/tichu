#!/usr/bin/env python3
"""Train Tichu / Grand Tichu call-value networks.

Reads headless ``--format=bc-jsonl`` output generated with
``--call-epsilon=p`` (decisions flipped with probability p, so both "call"
and "no call" are observed for similar hands). For each logged decision

  x = [state (201), called, called * state]   y = round point diff / 100

(own team minus opponents, incl. Tichu bonuses / penalties). A small MLP is
fit by MSE, giving Q(s, call) and Q(s, no call); Dart's
``NnTichuCallStrategy`` calls when Q(s, 1) - Q(s, 0) > margin.

Usage:
  python rl/call_train.py --jsonl=calls.jsonl --kind=tichu \
      --output=rl/outputs/tichu_net.safetensors
  python rl/call_train.py --generate --episodes=3000 --call-epsilon=0.2 \
      --output-dir=rl/outputs          # both nets, data generated here

The exported nets use target_std=100 so Dart reads round points directly.
"""

from __future__ import annotations

import argparse
import json
import shutil
import tempfile
from pathlib import Path

import numpy as np
import torch
import torch.nn as nn

from bc_pretrain import QNetwork, _select_device
from schema import ACTION_OFFSET, SPEC

SCALE = 100.0


def call_input(state: list[float], called: bool) -> list[float]:
    """[state, flag, flag * state] — must match Dart ``callNetInput``."""
    f = 1.0 if called else 0.0
    return state + [f] + [v * f for v in state]


def _with_flag(x: torch.Tensor, flag: float) -> torch.Tensor:
    n = ACTION_OFFSET
    out = x.clone()
    out[:, n] = flag
    out[:, n + 1 :] = x[:, :n] * flag
    return out


def load_calls(jsonl: Path, kind: str) -> tuple[torch.Tensor, torch.Tensor, torch.Tensor]:
    """Return (inputs (N, 403), targets (N,), heuristic_called (N,) bool)."""
    rounds: dict[tuple[int, int], tuple[int, int]] = {}
    rows: list[dict] = []
    with jsonl.open("r", encoding="utf-8") as fh:
        for line in fh:
            if '"round_end"' in line:
                r = json.loads(line)
                rounds[(int(r["episode"]), int(r["round"]))] = (
                    int(r["team_one_round"]),
                    int(r["team_two_round"]),
                )
            elif f'"call":"{kind}"' in line:
                rows.append(json.loads(line))
    xs, ys, heur = [], [], []
    for r in rows:
        key = (int(r["episode"]), int(r["round"]))
        if key not in rounds:
            continue
        t1, t2 = rounds[key]
        own, opp = (t1, t2) if int(r["team"]) == 0 else (t2, t1)
        state = r["state_features"]
        if len(state) != ACTION_OFFSET:
            raise ValueError(f"state_features len {len(state)} != {ACTION_OFFSET}")
        called = bool(r["called"])
        xs.append(call_input(state, called))
        ys.append((own - opp) / SCALE)
        # The heuristic's own choice: flipped back for explored rows.
        heur.append(called != bool(r.get("explore", False)))
    if not xs:
        raise ValueError(f"no '{kind}' call rows with finished rounds in {jsonl}")
    return (
        torch.tensor(xs, dtype=torch.float32),
        torch.tensor(ys, dtype=torch.float32),
        torch.tensor(heur, dtype=torch.bool),
    )


def train(
    x: torch.Tensor,
    y: torch.Tensor,
    *,
    hidden: list[int],
    epochs: int,
    lr: float,
    seed: int,
) -> tuple[QNetwork, float]:
    torch.manual_seed(seed)
    model = QNetwork(x.shape[1], hidden)
    opt = torch.optim.Adam(model.parameters(), lr=lr, weight_decay=1e-4)
    perm = torch.from_numpy(np.random.default_rng(seed).permutation(x.shape[0]))
    n_val = max(1, x.shape[0] // 10)
    val, tr = perm[:n_val], perm[n_val:]
    best, best_state = float("inf"), None
    for epoch in range(epochs):
        model.train()
        order = tr[torch.randperm(tr.numel())]
        for i in range(0, order.numel(), 512):
            idx = order[i : i + 512]
            loss = nn.functional.mse_loss(model(x[idx]).squeeze(-1), y[idx])
            opt.zero_grad(set_to_none=True)
            loss.backward()
            opt.step()
        model.eval()
        with torch.no_grad():
            mse = float(nn.functional.mse_loss(model(x[val]).squeeze(-1), y[val]))
        if mse < best:
            best, best_state = mse, {k: v.clone() for k, v in model.state_dict().items()}
    if best_state is not None:
        model.load_state_dict(best_state)
    return model, best


def export(model: QNetwork, path: Path, *, kind: str, val_mse: float, n: int) -> None:
    from safetensors.torch import save_file

    linear = [m for m in model.net if isinstance(m, nn.Linear)]
    tensors: dict[str, torch.Tensor] = {}
    sizes = [linear[0].in_features]
    for i, layer in enumerate(linear):
        tensors[f"layer.{i}.weight"] = layer.weight.detach().cpu().contiguous()
        tensors[f"layer.{i}.bias"] = layer.bias.detach().cpu().contiguous()
        sizes.append(layer.out_features)
    path.parent.mkdir(parents=True, exist_ok=True)
    save_file(
        tensors,
        str(path),
        metadata={
            "layer_sizes": json.dumps(sizes),
            "kind": f"call_value_{kind}",
            "target": "round_points_diff",
            "target_mean": "0.0",
            "target_std": str(SCALE),
            "val_mse": f"{val_mse:.6f}",
            "training_rows": str(n),
            "schema_version": str(SPEC.version),
        },
    )


def fit_kind(jsonl: Path, kind: str, output: Path, args: argparse.Namespace) -> None:
    x, y, heur = load_calls(jsonl, kind)
    called = x[:, ACTION_OFFSET] > 0.5
    print(
        f"[{kind}] rows={x.shape[0]}  called={int(called.sum())}  "
        f"mean R | call={float(y[called].mean()) if called.any() else float('nan'):+.3f}  "
        f"| no call={float(y[~called].mean()):+.3f}  (×{SCALE:.0f} pts)"
    )
    # Unbiased value of the heuristic's choice: exploration flips decisions
    # at random, so within "heuristic says call" (and "says no") hands the
    # called / not-called outcome difference is a fair A/B estimate.
    for label, mask in (("heuristic calls", heur), ("heuristic passes", ~heur)):
        c, nc = y[mask & called], y[mask & ~called]
        if c.numel() > 1 and nc.numel() > 1:
            d = float(c.mean() - nc.mean()) * SCALE
            se = float((c.var() / c.numel() + nc.var() / nc.numel()).sqrt()) * SCALE
            print(
                f"[{kind}] {label} ({int(mask.sum())}): calling is worth "
                f"{d:+.1f} ± {se:.1f} pts vs not calling"
            )
    hidden = [int(h) for h in args.hidden.split(",") if h]
    model, mse = train(x, y, hidden=hidden, epochs=args.epochs, lr=args.lr, seed=args.seed)
    with torch.no_grad():
        adv = (model(_with_flag(x, 1.0)) - model(_with_flag(x, 0.0))).squeeze(-1) * SCALE
    nn_calls = adv > args.margin
    agree = float((nn_calls == heur).float().mean())
    print(
        f"[{kind}] val_mse={mse:.4f} (var={float(y.var()):.4f})  "
        f"NN would call {100*float(nn_calls.float().mean()):.1f}% "
        f"(heuristic {100*float(heur.float().mean()):.1f}%), agreement {100*agree:.1f}%  "
        f"adv median={float(adv.median()):+.1f} pts"
    )
    export(model, output, kind=kind, val_mse=mse, n=x.shape[0])
    print(f"[{kind}] saved {output}")


def main() -> None:
    p = argparse.ArgumentParser(description="Train Tichu / Grand Tichu call-value nets")
    p.add_argument("--jsonl", default="", help="bc-jsonl with call rows (else --generate)")
    p.add_argument("--keep-jsonl", default="", help="Copy generated data here for reuse")
    p.add_argument("--generate", action="store_true")
    p.add_argument("--episodes", type=int, default=3000)
    p.add_argument("--target-score", type=int, default=1000)
    p.add_argument("--call-epsilon", type=float, default=0.2)
    p.add_argument("--nn-policy", default="", help="Play policy used during data generation")
    p.add_argument("--seed", type=int, default=4242)
    p.add_argument("--shards", type=int, default=0)
    p.add_argument(
        "--kind",
        choices=["tichu", "grand", "pre", "all"],
        default="all",
        help="pre = Tichu before the schupf",
    )
    p.add_argument("--output", default="", help="Output file (single --kind)")
    p.add_argument("--output-dir", default="rl/outputs")
    p.add_argument("--hidden", default="128,64")
    p.add_argument("--epochs", type=int, default=30)
    p.add_argument("--lr", type=float, default=1e-3)
    p.add_argument("--margin", type=float, default=0.0, help="Report threshold (pts)")
    args = p.parse_args()
    _select_device()

    cleanup: Path | None = None
    if args.jsonl:
        jsonl = Path(args.jsonl)
    else:
        if not args.generate:
            p.error("pass --jsonl or --generate")
        from headless_runner import run_headless_sharded

        cleanup = Path(tempfile.mkdtemp(prefix="tichu_calls_"))
        jsonl = cleanup / "calls.jsonl"
        base = [
            f"--target-score={args.target_score}",
            "--format=bc-jsonl",
            f"--call-epsilon={args.call_epsilon}",
        ]
        if args.nn_policy:
            base.append(f"--nn-policy={args.nn_policy}")
        print(f"Generating {args.episodes} episodes with call-epsilon={args.call_epsilon}...")
        run_headless_sharded(
            base_args=base,
            seed=args.seed,
            episodes=args.episodes,
            output_path=jsonl,
            shards=args.shards or None,
        )

    if cleanup is not None and args.keep_jsonl:
        Path(args.keep_jsonl).parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(jsonl, args.keep_jsonl)

    kinds = ["tichu", "grand", "pre"] if args.kind == "all" else [args.kind]
    try:
        for kind in kinds:
            out = (
                Path(args.output)
                if args.output and len(kinds) == 1
                else Path(args.output_dir) / f"{kind}_net.safetensors"
            )
            fit_kind(jsonl, kind, out, args)
    finally:
        if cleanup is not None:
            shutil.rmtree(cleanup, ignore_errors=True)


if __name__ == "__main__":
    main()
