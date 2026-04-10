#!/usr/bin/env python3
"""PyTorch training script for Tichu Q-value network.

Trains an MLP from a pre-packed safetensors dataset and exports model
weights as safetensors consumable by the Dart inference MLP.

Usage (via uv):
    uv run python rl/train.py \
        --input=outputs/train_dataset.safetensors \
        --output=outputs/nn_policy.safetensors \
        --epochs=100 --lr=1e-3 --hidden=128,64
"""

from __future__ import annotations

import argparse
import json
import sys
import time
import warnings
from pathlib import Path

import numpy as np
import torch
import torch.nn as nn
from torch.utils.data import DataLoader, random_split

# Suppress DirectML CPU-fallback warnings for ops that have negligible cost
# on CPU (e.g. Adam's lerp on small optimizer state tensors).
warnings.filterwarnings(
    "ignore",
    message=r".*is not currently supported on the DML backend.*",
    category=UserWarning,
)

from data import (
    PreEncodedTransitionDataset,
    load_training_tensors_safetensors,
    TOTAL_FEATURE_COUNT,
)


# ── Model ────────────────────────────────────────────────────────────────────

class QNetwork(nn.Module):
    """MLP Q-value estimator: (state, action) features → scalar Q-value.

    Architecture matches the Dart Mlp class so weights transfer directly.
    Hidden layers use ReLU; output is linear.
    """

    def __init__(self, input_dim: int, hidden_sizes: list[int]) -> None:
        super().__init__()
        layers: list[nn.Module] = []
        prev = input_dim
        for h in hidden_sizes:
            layers.append(nn.Linear(prev, h))
            layers.append(nn.ReLU())
            prev = h
        layers.append(nn.Linear(prev, 1))
        self.net = nn.Sequential(*layers)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        return self.net(x)


# ── Weight export ────────────────────────────────────────────────────────────

def export_safetensors(
    model: QNetwork,
    path: Path,
    *,
    target_mean: float,
    target_std: float,
    metadata: dict | None = None,
) -> None:
    """Export trained model weights as safetensors for Dart's Mlp to load.

    Safetensors stores named tensors as contiguous binary data with a JSON
    header for metadata.  This is ~10× smaller and ~100× faster to load than
    the nested JSON format, and is the standard weight exchange format in
    the HuggingFace / ML ecosystem.

    Tensor naming convention:
        ``layer.{l}.weight``  — shape (out_features, in_features)
        ``layer.{l}.bias``    — shape (out_features,)

    Metadata (in the safetensors header):
        ``layer_sizes``, ``target_mean``, ``target_std``, plus any builder info.
    """
    from safetensors.torch import save_file as st_save

    linear_layers = [m for m in model.net if isinstance(m, nn.Linear)]
    layer_sizes: list[int] = []
    tensors: dict[str, torch.Tensor] = {}

    for i, layer in enumerate(linear_layers):
        w = layer.weight.detach().cpu().contiguous()
        b = layer.bias.detach().cpu().contiguous()
        if i == 0:
            layer_sizes.append(w.shape[1])
        layer_sizes.append(w.shape[0])
        tensors[f"layer.{i}.weight"] = w
        tensors[f"layer.{i}.bias"] = b

    # Metadata goes into the safetensors header (string values only).
    meta: dict[str, str] = {
        "layer_sizes": json.dumps(layer_sizes),
        "target_mean": str(target_mean),
        "target_std": str(target_std),
    }
    if metadata:
        for k, v in metadata.items():
            meta[f"builder.{k}"] = json.dumps(v) if not isinstance(v, str) else v

    path.parent.mkdir(parents=True, exist_ok=True)
    st_save(tensors, str(path), metadata=meta)


# ── Device selection ─────────────────────────────────────────────────────────

def _select_device() -> torch.device:
    """Pick the best available compute device: CUDA > DirectML > CPU (MKL)."""
    if torch.cuda.is_available():
        name = torch.cuda.get_device_name(0)
        print(f"device: cuda ({name})", flush=True)
        return torch.device("cuda")

    # DirectML — GPU acceleration for Intel/AMD/NVIDIA on Windows.
    try:
        import torch_directml  # type: ignore[import-untyped]
        dml = torch_directml.device()
        print(f"device: directml ({torch_directml.device_name(0)})", flush=True)
        return dml
    except (ImportError, RuntimeError):
        pass

    accel = []
    if torch.backends.mkl.is_available():
        accel.append("MKL")
    if torch.backends.mkldnn.is_available():
        accel.append("MKLDNN")
    suffix = f" ({', '.join(accel)})" if accel else ""
    print(f"device: cpu{suffix}  (no CUDA GPU detected)", flush=True)
    return torch.device("cpu")


# ── Training loop ────────────────────────────────────────────────────────────

def train(args: argparse.Namespace) -> None:
    device = _select_device()

    # Load data.
    print(f"Loading {args.input} ...", flush=True)
    input_path = Path(args.input)
    if input_path.suffix.lower() != ".safetensors":
        raise ValueError(
            "--input must be a .safetensors dataset. "
            "Regenerate dataset with generate_train_dataset.py first."
        )

    features, returns, dataset_meta = load_training_tensors_safetensors(input_path)
    if features.numel() == 0 or returns.numel() == 0:
        print("No samples — exiting.", file=sys.stderr)
        return
    if features.shape[1] != TOTAL_FEATURE_COUNT:
        raise ValueError(
            f"Feature count mismatch: expected {TOTAL_FEATURE_COUNT}, "
            f"got {features.shape[1]}"
        )
    print(
        f"  pre-encoded dataset: {features.shape[0]} samples, "
        f"{features.shape[1]} features"
    )
    if dataset_meta:
        gamma_meta = dataset_meta.get("gamma")
        if gamma_meta:
            print(f"  dataset gamma={gamma_meta}")
    dataset = PreEncodedTransitionDataset(features, returns)

    target_mean = dataset.target_mean
    target_std = dataset.target_std
    print(f"  target stats: mean={target_mean:.3f}, std={target_std:.3f}")

    val_size = max(1, int(len(dataset) * 0.1))
    train_size = len(dataset) - val_size
    train_ds, val_ds = random_split(
        dataset, [train_size, val_size],
        generator=torch.Generator().manual_seed(args.seed),
    )

    use_pin_memory = device.type == "cuda"
    train_loader = DataLoader(
        train_ds, batch_size=args.batch_size, shuffle=True,
        pin_memory=use_pin_memory, num_workers=0,
    )
    val_loader = DataLoader(
        val_ds, batch_size=args.batch_size, shuffle=False,
        pin_memory=use_pin_memory, num_workers=0,
    )

    # Build model.
    hidden = [int(s) for s in args.hidden.split(",")]
    model = QNetwork(TOTAL_FEATURE_COUNT, hidden).to(device)
    param_count = sum(p.numel() for p in model.parameters())
    print(f"Network: {TOTAL_FEATURE_COUNT} → {' → '.join(map(str, hidden))} → 1  ({param_count:,} params)")

    # Disable foreach for non-CUDA devices (DirectML lacks some fused ops).
    use_foreach = device.type == "cuda"
    optimizer = torch.optim.Adam(
        model.parameters(), lr=args.lr, weight_decay=args.weight_decay,
        foreach=use_foreach,
    )
    scheduler = torch.optim.lr_scheduler.ReduceLROnPlateau(
        optimizer, mode="min", factor=0.5, patience=10,
    )
    criterion = nn.MSELoss()

    # Optional TensorBoard.
    writer = None
    if args.tensorboard:
        from torch.utils.tensorboard import SummaryWriter
        writer = SummaryWriter(log_dir=args.tensorboard)

    best_val_loss = float("inf")
    best_state: dict | None = None
    t0 = time.time()

    for epoch in range(args.epochs):
        # ── Train ──
        model.train()
        train_loss_sum = 0.0
        train_batches = 0
        for features, targets in train_loader:
            features = features.to(device, non_blocking=True)
            targets = targets.to(device, non_blocking=True)
            pred = model(features)
            loss = criterion(pred, targets)
            optimizer.zero_grad(set_to_none=True)
            loss.backward()
            nn.utils.clip_grad_norm_(model.parameters(), max_norm=args.grad_clip)
            optimizer.step()
            train_loss_sum += loss.item()
            train_batches += 1

        avg_train = train_loss_sum / max(1, train_batches)

        # ── Validate ──
        model.eval()
        val_loss_sum = 0.0
        val_batches = 0
        with torch.no_grad():
            for features, targets in val_loader:
                features = features.to(device, non_blocking=True)
                targets = targets.to(device, non_blocking=True)
                pred = model(features)
                val_loss_sum += criterion(pred, targets).item()
                val_batches += 1

        avg_val = val_loss_sum / max(1, val_batches)
        scheduler.step(avg_val)

        if avg_val < best_val_loss:
            best_val_loss = avg_val
            best_state = {k: v.cpu().clone() for k, v in model.state_dict().items()}

        if writer:
            writer.add_scalar("loss/train", avg_train, epoch)
            writer.add_scalar("loss/val", avg_val, epoch)
            writer.add_scalar("lr", optimizer.param_groups[0]["lr"], epoch)

        if epoch % 10 == 0 or epoch == args.epochs - 1:
            elapsed = time.time() - t0
            lr = optimizer.param_groups[0]["lr"]
            print(
                f"  epoch {epoch+1:4d}/{args.epochs}  "
                f"train={avg_train:.5f}  val={avg_val:.5f}  "
                f"best={best_val_loss:.5f}  lr={lr:.1e}  "
                f"[{elapsed:.1f}s]",
                flush=True,
            )

    # Restore best weights.
    if best_state is not None:
        model.load_state_dict(best_state)
        model.to(device)

    # Export.
    metadata = {
        "algorithm": "pytorch_mc_returns",
        "architecture": [TOTAL_FEATURE_COUNT] + hidden + [1],
        "dataset_input": str(input_path),
        "epochs": args.epochs,
        "learning_rate": args.lr,
        "weight_decay": args.weight_decay,
        "batch_size": args.batch_size,
        "training_samples": len(dataset),
        "best_val_loss": best_val_loss,
    }

    output = Path(args.output)
    export_safetensors(
        model, output,
        target_mean=target_mean,
        target_std=target_std,
        metadata=metadata,
    )
    print(f"Saved to {output}  (val_loss={best_val_loss:.5f})")

    if writer:
        writer.close()


# ── CLI ──────────────────────────────────────────────────────────────────────

def main() -> None:
    p = argparse.ArgumentParser(description="Train Tichu Q-network (PyTorch + GPU)")
    p.add_argument("--input", required=True, help="Safetensors dataset file")
    p.add_argument("--output", default="outputs/nn_policy.safetensors", help="Safetensors weight file")
    p.add_argument("--epochs", type=int, default=100)
    p.add_argument("--lr", type=float, default=1e-3)
    p.add_argument("--weight-decay", type=float, default=1e-4)
    p.add_argument("--grad-clip", type=float, default=5.0)
    p.add_argument("--batch-size", type=int, default=256)
    p.add_argument("--hidden", default="128,64", help="Comma-separated hidden layer sizes")
    p.add_argument("--seed", type=int, default=42)
    p.add_argument("--tensorboard", default="", help="TensorBoard log dir (empty = disabled)")
    args = p.parse_args()

    torch.manual_seed(args.seed)
    np.random.seed(args.seed)

    train(args)


if __name__ == "__main__":
    main()
