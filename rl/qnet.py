"""The Q(s, a) MLP shared by all trainers: model, loading, batched BC loss
and safetensors export (read by Dart ``Mlp.fromSafetensorsBytes``)."""

from __future__ import annotations

import json
import os
from pathlib import Path

import torch
import torch.nn as nn

from bc_data import FlatBcData
from schema import ACTION_OFFSET, LEGACY_STATE_PREFIX, TOTAL_FEATURE_COUNT


class QNetwork(nn.Module):
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


def select_device() -> torch.device:
    """Pick the best compute device for our tiny MLP.

    The net is tiny (~100k params, ~14k-row batches; ~80 ms/step on an
    8-core CPU with MKL), so CPU is the right default unless a real CUDA GPU
    is present.
    """
    if torch.cuda.is_available():
        return torch.device("cuda")
    # All CPU threads by default; TICHU_TORCH_THREADS limits them when
    # headless runners share the machine (oversubscribed threads spin).
    torch.set_num_threads(int(os.environ.get("TICHU_TORCH_THREADS", 0)) or max(1, os.cpu_count() or 1))
    return torch.device("cpu")


def load_qnetwork_from_safetensors(path: Path, device: torch.device) -> QNetwork:
    """Reconstruct a QNetwork and load weights from a previous policy file."""
    from safetensors import safe_open
    from safetensors.torch import load_file as st_load

    with safe_open(str(path), framework="pt", device="cpu") as reader:
        meta = dict(reader.metadata() or {})
    layer_sizes = json.loads(meta.get("layer_sizes", "[]"))
    if len(layer_sizes) < 2:
        raise ValueError(f"{path}: invalid layer_sizes={layer_sizes}")
    legacy_prefix = LEGACY_STATE_PREFIX.get(layer_sizes[0])
    if legacy_prefix is not None:
        # Older layout: insert zero weights for the missing state groups, so
        # the net computes exactly what it did (and can be trained further).
        layer_sizes = [TOTAL_FEATURE_COUNT] + list(layer_sizes[1:])
    if layer_sizes[0] != TOTAL_FEATURE_COUNT:
        raise ValueError(
            f"{path}: input_dim={layer_sizes[0]} != current TOTAL_FEATURE_COUNT={TOTAL_FEATURE_COUNT}"
        )
    if layer_sizes[-1] != 1:
        raise ValueError(f"{path}: output_dim={layer_sizes[-1]} != 1")

    hidden = list(layer_sizes[1:-1])
    model = QNetwork(TOTAL_FEATURE_COUNT, hidden)

    incoming = st_load(str(path))
    if legacy_prefix is not None:
        w = incoming["layer.0.weight"]
        new = torch.zeros(w.shape[0], TOTAL_FEATURE_COUNT, dtype=w.dtype)
        new[:, :legacy_prefix] = w[:, :legacy_prefix]
        new[:, ACTION_OFFSET:] = w[:, legacy_prefix:]
        incoming["layer.0.weight"] = new
    # Map model.net's Linear modules in order to safetensors layer.{i}.* keys.
    linear_layers = [m for m in model.net if isinstance(m, nn.Linear)]
    for i, linear in enumerate(linear_layers):
        w_src = incoming.get(f"layer.{i}.weight")
        b_src = incoming.get(f"layer.{i}.bias")
        if w_src is None or b_src is None:
            raise ValueError(f"missing layer.{i}.* tensors in {path}")
        if w_src.shape != linear.weight.shape:
            raise ValueError(
                f"shape mismatch layer.{i}.weight: "
                f"{tuple(w_src.shape)} vs {tuple(linear.weight.shape)}"
            )
        if b_src.shape != linear.bias.shape:
            raise ValueError(
                f"shape mismatch layer.{i}.bias: "
                f"{tuple(b_src.shape)} vs {tuple(linear.bias.shape)}"
            )
        with torch.no_grad():
            linear.weight.copy_(w_src.to(linear.weight.dtype))
            linear.bias.copy_(b_src.to(linear.bias.dtype))
    return model.to(device)


# ── Vectorised batched loss / accuracy ──────────────────────────────────────


def gather_batch_indices(
    decision_idx: torch.Tensor,
    decision_starts: torch.Tensor,
) -> tuple[torch.Tensor, torch.Tensor, torch.Tensor]:
    """Gather row indices for a batch of decisions.

    Args:
      decision_idx: (K,) long — selected decision IDs (in any order).
      decision_starts: (D + 1,) long — global decision row ranges.

    Returns:
      row_indices:  (M,) long — global row indices to gather from inputs.
      row_to_local_decision: (M,) long — 0..K-1 mapping each row to its
        position within the batch.
      chosen_in_batch: (K,) long — index into ``row_indices`` of the chosen
        action for each decision in the batch (provided by caller via
        chosen_global; this helper only returns the gather plumbing).
    """
    starts = decision_starts[decision_idx]
    ends = decision_starts[decision_idx + 1]
    lengths = ends - starts                       # (K,)
    cum = torch.cumsum(lengths, dim=0)            # (K,)
    decision_offset = torch.cat(
        [torch.zeros(1, dtype=torch.long, device=decision_idx.device), cum[:-1]]
    )                                              # (K,) where each decision starts in the batch
    total = int(cum[-1].item()) if cum.numel() > 0 else 0

    row_to_local_decision = torch.repeat_interleave(
        torch.arange(decision_idx.numel(), device=decision_idx.device), lengths
    )                                              # (M,)
    arr = torch.arange(total, device=decision_idx.device)
    local_offset_in_decision = arr - decision_offset[row_to_local_decision]
    row_indices = starts[row_to_local_decision] + local_offset_in_decision  # (M,)
    return row_indices, row_to_local_decision, decision_offset


def bc_step(
    *,
    model: nn.Module,
    data: FlatBcData,
    decision_idx: torch.Tensor,
    require_grad: bool,
    anchor_model: nn.Module | None = None,
    kl_weight: float = 0.0,
    weights: torch.Tensor | None = None,
) -> tuple[torch.Tensor, torch.Tensor, torch.Tensor]:
    """One forward pass over the chosen batch of decisions.

    ``weights`` (D,) optionally weights each decision's cross-entropy term
    (advantage-weighted regression); it is indexed by ``decision_idx``.

    Returns (total_loss, per-decision boolean correctness, kl_loss).
    """
    row_indices, row_to_local_decision, decision_offset = gather_batch_indices(
        decision_idx, data.decision_starts
    )
    batch_inputs = data.inputs[row_indices]                 # (M, F)

    if require_grad:
        logits = model(batch_inputs).squeeze(-1)            # (M,)
    else:
        with torch.no_grad():
            logits = model(batch_inputs).squeeze(-1)

    K = int(decision_idx.numel())

    # Numerically-stable scatter-LSE giving us BOTH max-per and lse.
    neg_inf = torch.full(
        (K,), float("-inf"), dtype=logits.dtype, device=logits.device
    )
    max_per = neg_inf.scatter_reduce(
        0, row_to_local_decision, logits, reduce="amax", include_self=True
    )
    safe_max = torch.where(torch.isfinite(max_per), max_per, torch.zeros_like(max_per))
    shifted = logits - safe_max[row_to_local_decision]
    sum_per = torch.zeros(
        K, dtype=logits.dtype, device=logits.device
    ).scatter_add_(0, row_to_local_decision, torch.exp(shifted))
    lse = safe_max + torch.log(sum_per.clamp_min(1e-30))    # (K,)

    # Position of the chosen row inside the batch.
    starts = data.decision_starts[decision_idx]             # (K,)
    chosen_offset_within_decision = data.chosen_global[decision_idx] - starts
    chosen_in_batch = decision_offset + chosen_offset_within_decision  # (K,)
    chosen_logits = logits[chosen_in_batch]                 # (K,)

    losses = lse - chosen_logits                            # (K,)
    if weights is None:
        bc_loss = losses.mean()
    else:
        w = weights[decision_idx]
        bc_loss = (losses * w).sum() / w.sum().clamp_min(1e-8)
    correct = (chosen_logits >= max_per - 1e-6)             # (K,) bool

    # Optional KL anchor: KL(current || anchor) over the legal-action softmax.
    # current_softmax[i] = exp(logits[i] - lse[batch_of(i)])
    # KL = sum_i current_softmax[i] * (log_current_softmax[i] - log_anchor_softmax[i])
    kl_loss = torch.zeros((), device=logits.device, dtype=logits.dtype)
    if anchor_model is not None and kl_weight > 0:
        with torch.no_grad():
            anchor_logits = anchor_model(batch_inputs).squeeze(-1)
        anchor_max = neg_inf.scatter_reduce(
            0, row_to_local_decision, anchor_logits, reduce="amax", include_self=True
        )
        anchor_safe_max = torch.where(
            torch.isfinite(anchor_max), anchor_max, torch.zeros_like(anchor_max)
        )
        anchor_shifted = anchor_logits - anchor_safe_max[row_to_local_decision]
        anchor_sum = torch.zeros(
            K, dtype=anchor_logits.dtype, device=anchor_logits.device
        ).scatter_add_(0, row_to_local_decision, torch.exp(anchor_shifted))
        anchor_lse = anchor_safe_max + torch.log(anchor_sum.clamp_min(1e-30))

        log_p_current = logits - lse[row_to_local_decision]            # (M,)
        log_p_anchor = anchor_logits - anchor_lse[row_to_local_decision]
        p_current = torch.exp(log_p_current)
        kl_per_row = p_current * (log_p_current - log_p_anchor)        # (M,)
        kl_per_decision = torch.zeros(
            K, dtype=logits.dtype, device=logits.device
        ).scatter_add_(0, row_to_local_decision, kl_per_row)
        kl_loss = kl_per_decision.mean()

    total_loss = bc_loss + kl_weight * kl_loss
    return total_loss, correct, kl_loss


# ── Export ───────────────────────────────────────────────────────────────────


def export_safetensors(
    model: QNetwork,
    path: Path,
    *,
    target_mean: float,
    target_std: float,
    metadata: dict[str, str],
) -> None:
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

    meta: dict[str, str] = {
        "layer_sizes": json.dumps(layer_sizes),
        "target_mean": str(target_mean),
        "target_std": str(target_std),
    }
    for k, v in metadata.items():
        meta[f"builder.{k}"] = v if isinstance(v, str) else json.dumps(v)

    path.parent.mkdir(parents=True, exist_ok=True)
    st_save(tensors, str(path), metadata=meta)
