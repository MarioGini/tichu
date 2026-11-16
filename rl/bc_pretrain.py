#!/usr/bin/env python3
"""Behavioural cloning pretrain for the Tichu Q-network.

Teaches the Q-network to assign the highest Q-value among legal actions to
the action a heuristic agent actually chose. After this pretrain, argmax
over Q values approximates the heuristic policy (≈ 50 % win rate vs heuristic
by definition); subsequent RL fine-tuning can then improve from a sane
baseline instead of from a noisy off-policy regression.

Reads headless ``--format=bc-jsonl`` output: pre-encoded ``state_features``
plus ``legal_play_action_features`` and the chosen index per decision.

Loss: cross-entropy over Q(state, legal_action_i) with target = chosen index.
"""

from __future__ import annotations

import argparse
import shutil
import tempfile
import time
from pathlib import Path

import numpy as np
import torch
import torch.nn as nn

from bc_data import build_bc_dataset
from qnet import (
    QNetwork,
    bc_step,
    export_safetensors,
    load_qnetwork_from_safetensors,
    select_device,
)
from schema import TOTAL_FEATURE_COUNT


# ── Main ─────────────────────────────────────────────────────────────────────


def _generate_jsonl(
    *, seed: int, episodes: int, target_score: int, output: Path, shards: int = 0
) -> None:
    from headless_runner import run_headless_sharded

    run_headless_sharded(
        base_args=[f"--target-score={target_score}", "--format=bc-jsonl"],
        seed=seed,
        episodes=episodes,
        output_path=output,
        shards=shards or None,
    )


def main() -> None:
    p = argparse.ArgumentParser(description="Behavioural cloning pretrain")
    p.add_argument("--output", required=True, help="Safetensors policy output")
    p.add_argument("--episodes", type=int, default=200)
    p.add_argument("--seed", type=int, default=2024)
    p.add_argument("--target-score", type=int, default=100)
    p.add_argument("--epochs", type=int, default=20)
    p.add_argument("--lr", type=float, default=1e-3)
    p.add_argument("--weight-decay", type=float, default=1e-4)
    p.add_argument(
        "--decisions-per-batch",
        type=int,
        default=2048,
        help="How many decisions to put in one gradient step",
    )
    p.add_argument("--hidden", default="256,128,64")
    p.add_argument(
        "--device",
        choices=["auto", "cpu", "cuda"],
        default="auto",
        help="Force compute device. 'auto' picks CUDA > CPU.",
    )
    p.add_argument(
        "--jsonl",
        default="",
        help="Reuse an existing JSONL instead of regenerating from headless",
    )
    p.add_argument(
        "--shards",
        type=int,
        default=0,
        help="Parallel headless workers for data generation (0 = cpu_count - 1)",
    )
    p.add_argument(
        "--winners-only",
        action="store_true",
        help="Train BC on decisions made by the winning team only",
    )
    p.add_argument(
        "--init-from",
        default="",
        help="Optional safetensors policy to warm-start the network from",
    )
    p.add_argument(
        "--anchor-policy",
        default="",
        help=(
            "Optional safetensors policy. When set, adds a KL term to the loss "
            "that pulls the trained policy toward this anchor's softmax over "
            "legal actions. Use to prevent catastrophic forgetting of BC."
        ),
    )
    p.add_argument(
        "--kl-weight",
        type=float,
        default=0.1,
        help="Weight on the KL(current || anchor) term when --anchor-policy set",
    )
    args = p.parse_args()

    cleanup_jsonl: Path | None = None
    if args.jsonl:
        jsonl_path = Path(args.jsonl)
        if not jsonl_path.exists():
            raise FileNotFoundError(jsonl_path)
    else:
        td = Path(tempfile.mkdtemp(prefix="tichu_bc_"))
        jsonl_path = td / "transitions.jsonl"
        cleanup_jsonl = jsonl_path
        print(f"Generating {args.episodes} episodes -> {jsonl_path}", flush=True)
        _generate_jsonl(
            seed=args.seed,
            episodes=args.episodes,
            target_score=args.target_score,
            output=jsonl_path,
            shards=args.shards,
        )

    print("Building BC dataset...", flush=True)
    t_build = time.time()
    cpu_data = build_bc_dataset(jsonl_path, winners_only=args.winners_only)
    print(
        f"  rows={cpu_data.num_rows} decisions={cpu_data.num_decisions}  "
        f"({time.time() - t_build:.1f}s)"
    )

    if args.device == "auto":
        device = select_device()
    elif args.device == "cuda":
        device = torch.device("cuda")
    else:
        device = torch.device("cpu")
    print(f"device: {device}")

    data = cpu_data.to(device)

    hidden = [int(s) for s in args.hidden.split(",")]
    model = QNetwork(TOTAL_FEATURE_COUNT, hidden).to(device)
    n_params = sum(p.numel() for p in model.parameters())
    print(f"net: {TOTAL_FEATURE_COUNT} -> {hidden} -> 1  ({n_params:,} params)")

    if args.init_from:
        init_path = Path(args.init_from)
        if init_path.exists():
            try:
                init_model = load_qnetwork_from_safetensors(init_path, device)
                init_sizes = [
                    m.in_features for m in init_model.net if isinstance(m, nn.Linear)
                ] + [
                    [m.out_features for m in init_model.net if isinstance(m, nn.Linear)][-1]
                ]
                if init_sizes == [TOTAL_FEATURE_COUNT] + hidden + [1]:
                    model.load_state_dict(init_model.state_dict())
                    print(f"  warm-started from {init_path}")
                else:
                    print(
                        f"  warm-start skipped: architecture mismatch "
                        f"({init_sizes} vs {[TOTAL_FEATURE_COUNT] + hidden + [1]})"
                    )
            except Exception as exc:  # noqa: BLE001
                print(f"  warm-start skipped ({init_path}): {exc}")
        else:
            print(f"  warm-start skipped (missing): {init_path}")

    anchor_model: nn.Module | None = None
    if args.anchor_policy:
        anchor_path = Path(args.anchor_policy)
        if anchor_path.exists():
            try:
                anchor_model = load_qnetwork_from_safetensors(anchor_path, device)
                anchor_model.eval()
                for p in anchor_model.parameters():
                    p.requires_grad_(False)
                print(f"  anchor: {anchor_path}  (kl_weight={args.kl_weight})")
            except Exception as exc:  # noqa: BLE001
                print(f"  anchor disabled ({anchor_path}): {exc}")
        else:
            print(f"  anchor disabled (missing): {anchor_path}")

    optimizer = torch.optim.Adam(
        model.parameters(),
        lr=args.lr,
        weight_decay=args.weight_decay,
        foreach=(device.type == "cuda"),
    )

    # 90/10 train/val split on decisions.
    rng = np.random.default_rng(args.seed)
    perm = rng.permutation(data.num_decisions)
    val_size = max(1, data.num_decisions // 10)
    val_decisions = torch.from_numpy(perm[:val_size]).to(device).long()
    train_decisions = torch.from_numpy(perm[val_size:]).to(device).long()

    best_val_acc = 0.0
    best_state: dict | None = None
    bs = args.decisions_per_batch
    t0 = time.time()
    for epoch in range(args.epochs):
        model.train()
        # Shuffle training decisions each epoch.
        epoch_perm = torch.randperm(train_decisions.numel(), device=device)
        shuffled = train_decisions[epoch_perm]

        train_loss_sum = 0.0
        train_kl_sum = 0.0
        train_correct = 0
        train_total = 0
        n_batches = 0
        for start in range(0, shuffled.numel(), bs):
            batch = shuffled[start : start + bs]
            loss, correct, kl = bc_step(
                model=model,
                data=data,
                decision_idx=batch,
                require_grad=True,
                anchor_model=anchor_model,
                kl_weight=args.kl_weight if anchor_model is not None else 0.0,
            )
            optimizer.zero_grad(set_to_none=True)
            loss.backward()
            nn.utils.clip_grad_norm_(model.parameters(), 5.0)
            optimizer.step()
            train_loss_sum += float(loss.detach())
            train_kl_sum += float(kl.detach())
            train_correct += int(correct.sum().item())
            train_total += int(correct.numel())
            n_batches += 1

        # Validation in one big batch (with no_grad, fits easily).
        model.eval()
        val_loss, val_correct, val_kl = bc_step(
            model=model,
            data=data,
            decision_idx=val_decisions,
            require_grad=False,
            anchor_model=anchor_model,
            kl_weight=args.kl_weight if anchor_model is not None else 0.0,
        )
        val_loss_v = float(val_loss.detach())
        val_kl_v = float(val_kl.detach())
        v_correct = int(val_correct.sum().item())
        v_total = int(val_correct.numel())

        train_acc = 100.0 * train_correct / max(1, train_total)
        val_acc = 100.0 * v_correct / max(1, v_total)
        kl_str = (
            f" kl={train_kl_sum/max(1,n_batches):.4f}/{val_kl_v:.4f}"
            if anchor_model is not None
            else ""
        )
        print(
            f"  epoch {epoch+1:3d}/{args.epochs}  "
            f"train_loss={train_loss_sum/max(1,n_batches):.4f} acc={train_acc:.2f}%  "
            f"val_loss={val_loss_v:.4f} acc={val_acc:.2f}%{kl_str}  "
            f"[{time.time()-t0:.1f}s]",
            flush=True,
        )

        if val_acc > best_val_acc:
            best_val_acc = val_acc
            best_state = {k: v.detach().cpu().clone() for k, v in model.state_dict().items()}

    if best_state is not None:
        model.load_state_dict(best_state)

    output = Path(args.output)
    export_safetensors(
        model.cpu(),
        output,
        target_mean=0.0,
        target_std=1.0,
        metadata={
            "algorithm": (
                "bc_with_kl_anchor" if anchor_model is not None else "behavioural_cloning"
            ),
            "architecture": [TOTAL_FEATURE_COUNT] + hidden + [1],
            "best_val_acc": f"{best_val_acc:.4f}",
            "training_decisions": str(data.num_decisions),
            "training_rows": str(data.num_rows),
            "init_from": args.init_from or "",
            "anchor_policy": args.anchor_policy or "",
            "kl_weight": str(args.kl_weight) if anchor_model is not None else "0",
            "winners_only": "1" if args.winners_only else "0",
        },
    )
    print(f"Saved {output}  best_val_acc={best_val_acc:.2f}%  total={time.time()-t0:.1f}s")

    if cleanup_jsonl is not None:
        try:
            shutil.rmtree(cleanup_jsonl.parent, ignore_errors=True)
        except Exception:
            pass


if __name__ == "__main__":
    main()
