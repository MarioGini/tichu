#!/usr/bin/env python3
"""Advantage-weighted regression (AWR) fine-tune for the Tichu policy net.

Replaces "winners-only BC" in self-play. Instead of copying every move of
the team that happened to win the match, each decision is weighted by how
much better its *round* turned out than expected:

  R(s)   = (own team round points - opponent round points) / 100
           (card points, double-win 200, Tichu / Grand Tichu bonuses)
  V(s)   = value net on the 201 state features, fit to R by MSE
  A      = R - V(s)
  w      = min(exp(A / beta), max_weight)
  loss   = sum_d w_d * CE(policy logits over legal actions, chosen_d) / sum w
           + kl_weight * KL(policy || anchor)

All recorded decisions are used, including ε-exploration moves (AWR needs
the off-policy alternatives to learn from) and both teams.

Outputs:
  --output         policy (same layout as bc_pretrain, Dart-loadable)
  --value-output   optional value net V(s): 201 -> hidden -> 1, same
                   safetensors layout (layer.{i}.weight/bias); target_std=100
                   so Dart's denormalisation yields round points. Usable as
                   `headless --ismcts --value-net=...` leaf evaluator.
"""

from __future__ import annotations

import argparse
import json
import time
from pathlib import Path

import numpy as np
import torch
import torch.nn as nn

from bc_pretrain import (
    FlatBcData,
    QNetwork,
    _bc_step,
    _export_safetensors,
    _load_qnetwork_from_safetensors,
    _select_device,
)
from schema import ACTION_FEATURE_COUNT, ACTION_OFFSET, SPEC, TOTAL_FEATURE_COUNT

RETURN_SCALE = 100.0


def build_awr_dataset(
    jsonl: Path, *, include_explore: bool = True
) -> tuple[FlatBcData, torch.Tensor, torch.Tensor]:
    """Return (decision data, per-decision state features (D, 201),
    per-decision round return R (D,) from the actor team's perspective)."""
    round_scores: dict[tuple[int, int], tuple[int, int]] = {}
    with jsonl.open("r", encoding="utf-8") as fh:
        for line in fh:
            if '"round_end"' not in line:
                continue
            row = json.loads(line)
            round_scores[(int(row["episode"]), int(row["round"]))] = (
                int(row["team_one_round"]),
                int(row["team_two_round"]),
            )

    chunks: list[np.ndarray] = []
    states: list[np.ndarray] = []
    returns: list[float] = []
    starts = [0]
    chosen_global: list[int] = []
    cursor = 0
    skipped_unfinished = 0
    with jsonl.open("r", encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            row = json.loads(line)
            if row.get("episode_end") or row.get("round_end"):
                continue
            if row.get("explore") and not include_explore:
                continue
            legal = row.get("legal_play_action_features")
            chosen = row.get("legal_play_chosen_index")
            if not isinstance(legal, list) or not isinstance(chosen, int) or len(legal) <= 1:
                continue
            key = (int(row["episode"]), int(row["round"]))
            if key not in round_scores:
                # Round cut off (rounds limit / abandoned episode).
                skipped_unfinished += 1
                continue
            t1, t2 = round_scores[key]
            own, opp = (t1, t2) if int(row["team"]) == 0 else (t2, t1)

            state = np.asarray(row["state_features"], dtype=np.float32)
            if state.shape[0] != ACTION_OFFSET:
                raise ValueError(
                    f"state_features length {state.shape[0]} != {ACTION_OFFSET} "
                    f"(schema v{SPEC.version}); regenerate the JSONL"
                )
            block = np.empty((len(legal), TOTAL_FEATURE_COUNT), dtype=np.float32)
            block[:, :ACTION_OFFSET] = state
            acts = np.asarray(legal, dtype=np.float32)
            if acts.shape[1] != ACTION_FEATURE_COUNT:
                raise ValueError("action feature dim mismatch with schema")
            block[:, ACTION_OFFSET:] = acts

            chunks.append(block)
            states.append(state)
            returns.append((own - opp) / RETURN_SCALE)
            chosen_global.append(cursor + chosen)
            cursor += len(legal)
            starts.append(cursor)

    if not chunks:
        raise ValueError(f"no usable decisions with round results in {jsonl}")
    if skipped_unfinished:
        print(f"  skipped {skipped_unfinished} decisions from unfinished rounds")
    data = FlatBcData(
        torch.from_numpy(np.concatenate(chunks, axis=0)),
        torch.tensor(starts, dtype=torch.long),
        torch.tensor(chosen_global, dtype=torch.long),
    )
    return (
        data,
        torch.from_numpy(np.stack(states)),
        torch.tensor(returns, dtype=torch.float32),
    )


def fit_value(
    states: torch.Tensor,
    returns: torch.Tensor,
    *,
    hidden: list[int],
    epochs: int,
    lr: float,
    batch_size: int,
    seed: int,
    init: nn.Module | None = None,
) -> tuple[nn.Module, float]:
    """Fit V(s) ≈ R by MSE; returns (model, validation MSE)."""
    torch.manual_seed(seed)
    model = init if init is not None else QNetwork(states.shape[1], hidden)
    opt = torch.optim.Adam(model.parameters(), lr=lr, weight_decay=1e-4)
    n = states.shape[0]
    perm = torch.from_numpy(np.random.default_rng(seed).permutation(n))
    n_val = max(1, n // 10)
    val, tr = perm[:n_val], perm[n_val:]
    best_mse, best_state = float("inf"), None
    for epoch in range(epochs):
        model.train()
        order = tr[torch.randperm(tr.numel())]
        for i in range(0, order.numel(), batch_size):
            idx = order[i : i + batch_size]
            loss = nn.functional.mse_loss(model(states[idx]).squeeze(-1), returns[idx])
            opt.zero_grad(set_to_none=True)
            loss.backward()
            opt.step()
        model.eval()
        with torch.no_grad():
            mse = float(nn.functional.mse_loss(model(states[val]).squeeze(-1), returns[val]))
        if mse < best_mse:
            best_mse = mse
            best_state = {k: v.clone() for k, v in model.state_dict().items()}
        print(f"  value epoch {epoch+1:3d}/{epochs}  val_mse={mse:.4f}", flush=True)
    if best_state is not None:
        model.load_state_dict(best_state)
    return model, best_mse


def main() -> None:
    p = argparse.ArgumentParser(description="AWR fine-tune of the policy net")
    p.add_argument("--jsonl", required=True, help="bc-jsonl with round_end rows")
    p.add_argument("--output", required=True)
    p.add_argument("--init-from", required=True, help="Policy to fine-tune")
    p.add_argument("--anchor-policy", default="", help="KL anchor (default: init)")
    p.add_argument("--kl-weight", type=float, default=0.5)
    p.add_argument("--beta", type=float, default=1.0, help="AWR temperature (×100 pts)")
    p.add_argument("--max-weight", type=float, default=20.0)
    p.add_argument("--epochs", type=int, default=10)
    p.add_argument("--lr", type=float, default=2e-4)
    p.add_argument("--decisions-per-batch", type=int, default=512)
    p.add_argument("--value-hidden", default="128,64")
    p.add_argument("--value-epochs", type=int, default=15)
    p.add_argument("--value-init", default="", help="Warm-start the value net")
    p.add_argument("--value-output", default="")
    p.add_argument("--no-explore", action="store_true", help="Drop ε-exploration moves")
    p.add_argument("--seed", type=int, default=0)
    args = p.parse_args()

    device = _select_device()
    t0 = time.time()
    data, states, returns = build_awr_dataset(
        Path(args.jsonl), include_explore=not args.no_explore
    )
    print(
        f"AWR data: decisions={data.num_decisions} rows={data.num_rows} "
        f"R mean={float(returns.mean()):+.3f} std={float(returns.std()):.3f}  "
        f"({time.time()-t0:.1f}s)"
    )

    value_hidden = [int(x) for x in args.value_hidden.split(",") if x]
    value_init = None
    if args.value_init and Path(args.value_init).exists():
        value_init = _load_value(Path(args.value_init), value_hidden)
    value, val_mse = fit_value(
        states,
        returns,
        hidden=value_hidden,
        epochs=args.value_epochs,
        lr=1e-3,
        batch_size=1024,
        seed=args.seed,
        init=value_init,
    )
    with torch.no_grad():
        adv = returns - value(states).squeeze(-1)
    weights = torch.clamp(torch.exp(adv / args.beta), max=args.max_weight)
    var_r = float(returns.var())
    print(
        f"  value: val_mse={val_mse:.4f} (R var={var_r:.4f}, "
        f"explained={1 - val_mse / max(var_r, 1e-8):.1%})  "
        f"adv std={float(adv.std()):.3f}  "
        f"weights mean={float(weights.mean()):.2f} max={float(weights.max()):.1f} "
        f"ess={float(weights.sum()**2 / (weights**2).sum()) / weights.numel():.1%}"
    )

    model = _load_qnetwork_from_safetensors(Path(args.init_from), device)
    anchor_path = Path(args.anchor_policy or args.init_from)
    anchor = _load_qnetwork_from_safetensors(anchor_path, device).eval()
    for q in anchor.parameters():
        q.requires_grad_(False)
    hidden = [m.out_features for m in model.net if isinstance(m, nn.Linear)][:-1]

    data = data.to(device)
    weights = weights.to(device)
    opt = torch.optim.Adam(model.parameters(), lr=args.lr, weight_decay=1e-4)
    rng = np.random.default_rng(args.seed)
    perm = rng.permutation(data.num_decisions)
    n_val = max(1, data.num_decisions // 10)
    val = torch.from_numpy(perm[:n_val]).long().to(device)
    tr = torch.from_numpy(perm[n_val:]).long().to(device)
    best_loss, best_state = float("inf"), None
    for epoch in range(args.epochs):
        model.train()
        order = tr[torch.randperm(tr.numel(), device=device)]
        for i in range(0, order.numel(), args.decisions_per_batch):
            loss, _, _ = _bc_step(
                model=model,
                data=data,
                decision_idx=order[i : i + args.decisions_per_batch],
                require_grad=True,
                anchor_model=anchor,
                kl_weight=args.kl_weight,
                weights=weights,
            )
            opt.zero_grad(set_to_none=True)
            loss.backward()
            nn.utils.clip_grad_norm_(model.parameters(), 5.0)
            opt.step()
        model.eval()
        vloss, vcorrect, vkl = _bc_step(
            model=model,
            data=data,
            decision_idx=val,
            require_grad=False,
            anchor_model=anchor,
            kl_weight=args.kl_weight,
            weights=weights,
        )
        vl = float(vloss)
        print(
            f"  policy epoch {epoch+1:3d}/{args.epochs}  val_wloss={vl:.4f} "
            f"kl={float(vkl):.4f} acc={100*float(vcorrect.float().mean()):.1f}%",
            flush=True,
        )
        if vl < best_loss:
            best_loss = vl
            best_state = {k: v.detach().cpu().clone() for k, v in model.state_dict().items()}
    if best_state is not None:
        model.load_state_dict(best_state)

    _export_safetensors(
        model.cpu(),
        Path(args.output),
        target_mean=0.0,
        target_std=1.0,
        metadata={
            "algorithm": "awr",
            "architecture": [TOTAL_FEATURE_COUNT] + hidden + [1],
            "init_from": args.init_from,
            "anchor_policy": str(anchor_path),
            "kl_weight": str(args.kl_weight),
            "beta": str(args.beta),
            "training_decisions": str(data.num_decisions),
        },
    )
    print(f"Saved {args.output}  [{time.time()-t0:.1f}s]")
    if args.value_output:
        _export_value(value, Path(args.value_output), val_mse)
        print(f"Saved value net {args.value_output}")


def _export_value(model: nn.Module, path: Path, val_mse: float) -> None:
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
            "kind": "state_value",
            "target": "round_points_diff",
            "value_scale": str(RETURN_SCALE),
            # Dart denormalises as value * target_std + target_mean, so ISMCTS
            # gets round points directly.
            "target_mean": "0.0",
            "target_std": str(RETURN_SCALE),
            "val_mse": f"{val_mse:.6f}",
            "schema_version": str(SPEC.version),
        },
    )


def _load_value(path: Path, hidden: list[int]) -> nn.Module | None:
    from safetensors.torch import load_file

    t = load_file(str(path))
    model = QNetwork(ACTION_OFFSET, hidden)
    linear = [m for m in model.net if isinstance(m, nn.Linear)]
    try:
        with torch.no_grad():
            for i, layer in enumerate(linear):
                layer.weight.copy_(t[f"layer.{i}.weight"])
                layer.bias.copy_(t[f"layer.{i}.bias"])
    except (KeyError, RuntimeError) as exc:
        print(f"  value warm-start skipped: {exc}")
        return None
    return model


if __name__ == "__main__":
    main()
