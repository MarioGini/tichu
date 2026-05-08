#!/usr/bin/env python3
"""Behavioural cloning pretrain for the Tichu Q-network.

Teaches the Q-network to assign the highest Q-value among legal actions to
the action a heuristic agent actually chose. After this pretrain, argmax
over Q values approximates the heuristic policy (≈ 50 % win rate vs heuristic
by definition); subsequent RL fine-tuning can then improve from a sane
baseline instead of from a noisy off-policy regression.

Reads the same JSONL as ``generate_train_dataset.py`` (use
``--include-legal-features`` is implicit: the Dart writer emits
``legal_play_action_features`` whenever it can).

Loss: cross-entropy over Q(state, legal_action_i) with target = chosen index.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import tempfile
import time
import warnings
from pathlib import Path

import numpy as np
import torch
import torch.nn as nn

warnings.filterwarnings(
    "ignore",
    message=r".*is not currently supported on the DML backend.*",
    category=UserWarning,
)

from data import encode_transition, TOTAL_FEATURE_COUNT  # noqa: E402
from schema import ACTION_FEATURE_COUNT, ACTION_OFFSET  # noqa: E402


REPO = Path(__file__).resolve().parent.parent
RL_DIR = Path(__file__).resolve().parent
OUTPUTS = RL_DIR / "outputs"


def _ensure_dart_on_path() -> None:
    if shutil.which("dart") or shutil.which("dart.bat"):
        return
    for candidate in [Path(r"C:\flutter\flutter\bin"), Path.home() / "flutter" / "bin"]:
        if (candidate / "dart").exists() or (candidate / "dart.bat").exists():
            os.environ["PATH"] = str(candidate) + os.pathsep + os.environ.get("PATH", "")
            return
    raise RuntimeError("'dart' not found on PATH")


# ── Flat BC dataset ──────────────────────────────────────────────────────────


class FlatBcData:
    """Decision-grouped BC data laid out for vectorised scatter ops.

    All rows are sorted by ``decision_id`` (0..D-1, contiguous). For each
    decision we keep its row range in the flat ``inputs`` tensor, which lets
    us gather batch rows without any Python per-decision loops.

    Fields (all on the same device):
      inputs            (N_rows, F)  float32 — concatenated state+action vec
      decision_starts   (D + 1,)     long    — row range per decision
      chosen_global     (D,)         long    — global row index of chosen action
      decision_size     (D,)         long    — equivalent to diff(decision_starts)
    """

    def __init__(
        self,
        inputs: torch.Tensor,
        decision_starts: torch.Tensor,
        chosen_global: torch.Tensor,
    ) -> None:
        self.inputs = inputs.contiguous()
        self.decision_starts = decision_starts.contiguous()
        self.chosen_global = chosen_global.contiguous()
        self.decision_size = decision_starts[1:] - decision_starts[:-1]

    @property
    def num_rows(self) -> int:
        return int(self.inputs.shape[0])

    @property
    def num_decisions(self) -> int:
        return int(self.chosen_global.shape[0])

    def to(self, device: torch.device) -> "FlatBcData":
        return FlatBcData(
            self.inputs.to(device),
            self.decision_starts.to(device),
            self.chosen_global.to(device),
        )


def _build_bc_dataset(jsonl: Path, *, winners_only: bool = False) -> FlatBcData:
    """Load a BC dataset from a JSONL file produced by the headless runner.

    Accepts both:
      - ``--format=bc-jsonl``  (preferred, ~5× smaller, ~5× faster to write):
        each row already contains a pre-encoded ``state_features`` array.
      - ``--format=rl-jsonl``  (legacy): full transition rows; this loader
        re-encodes the state via :func:`data.encode_transition`.

    Selection between the two is done per-row, so mixed inputs work too.
    """
    # Two-pass build: first decide which episodes count, then accumulate.
    winning_team_by_episode: dict[int, int] = {}
    if winners_only:
        with jsonl.open("r", encoding="utf-8") as fh:
            last_by_ep: dict[int, dict] = {}
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                row = json.loads(line)
                last_by_ep[int(row.get("episode", 0))] = row
        for ep, row in last_by_ep.items():
            t1 = float(row.get("team_one_total", 0.0))
            t2 = float(row.get("team_two_total", 0.0))
            if t1 > t2:
                winning_team_by_episode[ep] = 0
            elif t2 > t1:
                winning_team_by_episode[ep] = 1

    inputs_chunks: list[np.ndarray] = []
    decision_starts_list: list[int] = [0]
    chosen_global_list: list[int] = []

    cursor = 0
    skipped_no_legal = 0
    skipped_single_action = 0
    skipped_loser = 0

    with jsonl.open("r", encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            row = json.loads(line)

            if winners_only:
                ep = int(row.get("episode", 0))
                wteam = winning_team_by_episode.get(ep)
                if wteam is None:
                    continue
                if int(row.get("team", -1)) != wteam:
                    skipped_loser += 1
                    continue

            legal = row.get("legal_play_action_features")
            chosen = row.get("legal_play_chosen_index")
            if not isinstance(legal, list) or not isinstance(chosen, int):
                skipped_no_legal += 1
                continue
            if len(legal) <= 1:
                skipped_single_action += 1
                continue

            # Prefer the bc-jsonl pre-encoded state vector; fall back to
            # re-encoding for legacy rl-jsonl rows.
            pre_state = row.get("state_features")
            if isinstance(pre_state, list) and len(pre_state) == ACTION_OFFSET:
                state_part = np.asarray(pre_state, dtype=np.float32)
            else:
                full_vec = encode_transition(row)
                if full_vec is None:
                    continue
                state_part = full_vec[:ACTION_OFFSET].astype(np.float32)

            # Build (n_actions, F) block for this decision.
            block = np.empty((len(legal), TOTAL_FEATURE_COUNT), dtype=np.float32)
            for i, action_feats in enumerate(legal):
                if not isinstance(action_feats, list) or len(action_feats) != ACTION_FEATURE_COUNT:
                    raise ValueError(
                        f"action features dim mismatch: got {len(action_feats) if isinstance(action_feats, list) else type(action_feats)}, "
                        f"schema expects {ACTION_FEATURE_COUNT}"
                    )
                block[i, :ACTION_OFFSET] = state_part
                block[i, ACTION_OFFSET:] = np.asarray(action_feats, dtype=np.float32)

            inputs_chunks.append(block)
            chosen_global_list.append(cursor + int(chosen))
            cursor += len(legal)
            decision_starts_list.append(cursor)

    if not inputs_chunks:
        raise ValueError(
            f"No usable BC rows in {jsonl}. Hints: skipped_no_legal="
            f"{skipped_no_legal}, skipped_single_action={skipped_single_action},"
            f" skipped_loser={skipped_loser}"
        )

    inputs_np = np.concatenate(inputs_chunks, axis=0)
    inputs_t = torch.from_numpy(inputs_np)
    decision_starts_t = torch.tensor(decision_starts_list, dtype=torch.long)
    chosen_global_t = torch.tensor(chosen_global_list, dtype=torch.long)
    return FlatBcData(inputs_t, decision_starts_t, chosen_global_t)


# ── Q-network ────────────────────────────────────────────────────────────────


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


def _select_device() -> torch.device:
    """Pick the best compute device for our tiny MLP.

    On this hardware (~58k-param net, ~14k-row batches), measured times:
      - CPU (8 cores, MKL): ~80 ms/step
      - DirectML on Intel UHD: 200+ ms/step AND crashes in autograd on
        small backward passes (foreach Adam ops fall back to CPU mid-step,
        which trips an internal assert in autograd's ready-queue lookup).

    So CPU is the right default unless a real CUDA GPU is present.
    """
    if torch.cuda.is_available():
        return torch.device("cuda")
    # Use all available CPU threads for MKL/MKLDNN.
    torch.set_num_threads(max(1, (os.cpu_count() or 1)))
    return torch.device("cpu")


def _load_qnetwork_from_safetensors(path: Path, device: torch.device) -> QNetwork:
    """Reconstruct a QNetwork and load weights from a previous policy file."""
    from safetensors import safe_open
    from safetensors.torch import load_file as st_load

    with safe_open(str(path), framework="pt", device="cpu") as reader:
        meta = dict(reader.metadata() or {})
    layer_sizes = json.loads(meta.get("layer_sizes", "[]"))
    if len(layer_sizes) < 2:
        raise ValueError(f"{path}: invalid layer_sizes={layer_sizes}")
    if layer_sizes[0] != TOTAL_FEATURE_COUNT:
        raise ValueError(
            f"{path}: input_dim={layer_sizes[0]} != current TOTAL_FEATURE_COUNT={TOTAL_FEATURE_COUNT}"
        )
    if layer_sizes[-1] != 1:
        raise ValueError(f"{path}: output_dim={layer_sizes[-1]} != 1")

    hidden = list(layer_sizes[1:-1])
    model = QNetwork(TOTAL_FEATURE_COUNT, hidden)

    incoming = st_load(str(path))
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


def _gather_batch_indices(
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


def _bc_step(
    *,
    model: nn.Module,
    data: FlatBcData,
    decision_idx: torch.Tensor,
    require_grad: bool,
    anchor_model: nn.Module | None = None,
    kl_weight: float = 0.0,
) -> tuple[torch.Tensor, torch.Tensor, torch.Tensor]:
    """One forward pass over the chosen batch of decisions.

    Returns (total_loss, per-decision boolean correctness, kl_loss).
    """
    row_indices, row_to_local_decision, decision_offset = _gather_batch_indices(
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
    bc_loss = losses.mean()
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


def _export_safetensors(
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
        choices=["auto", "cpu", "cuda", "directml"],
        default="auto",
        help="Force compute device. 'auto' picks CUDA > DirectML > CPU.",
    )
    p.add_argument(
        "--jsonl",
        default="",
        help="Reuse an existing JSONL instead of regenerating from headless",
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

    _ensure_dart_on_path()

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
        )

    print("Building BC dataset...", flush=True)
    t_build = time.time()
    cpu_data = _build_bc_dataset(jsonl_path, winners_only=args.winners_only)
    print(
        f"  rows={cpu_data.num_rows} decisions={cpu_data.num_decisions}  "
        f"({time.time() - t_build:.1f}s)"
    )

    if args.device == "auto":
        device = _select_device()
    elif args.device == "cuda":
        device = torch.device("cuda")
    elif args.device == "directml":
        import torch_directml  # type: ignore[import-untyped]
        device = torch_directml.device()
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
                init_model = _load_qnetwork_from_safetensors(init_path, device)
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
                anchor_model = _load_qnetwork_from_safetensors(anchor_path, device)
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
            loss, correct, kl = _bc_step(
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
        val_loss, val_correct, val_kl = _bc_step(
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
    _export_safetensors(
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
