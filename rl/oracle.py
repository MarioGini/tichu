"""Perfect-information ("oracle") baselines, as in PerfectDou.

Training rows carry ``"oracle": [[slots of left], [partner], [right]]`` —
the other players' hands at decision time. A baseline B(x, oracle) fitted
to the round result R removes most card luck from the target; since B does
not depend on the action taken, using R - B as the target keeps every
action comparison (argmax Q, call vs no call, AWR advantages) unbiased
while cutting the variance a lot. The acting policy never sees the oracle.
"""

from __future__ import annotations

import numpy as np
import torch

ORACLE_SIZE = 3 * 56


def oracle_onehot(oracle: list[list[int]] | None) -> np.ndarray:
    out = np.zeros(ORACLE_SIZE, dtype=np.float32)
    if oracle:
        for block, slots in enumerate(oracle[:3]):
            for s in slots:
                if 0 <= s < 56:
                    out[block * 56 + s] = 1.0
    return out


def fit_baseline(
    x: torch.Tensor,
    y: torch.Tensor,
    *,
    hidden: tuple[int, ...] = (128, 64),
    epochs: int = 10,
    seed: int = 0,
    label: str = "baseline",
) -> torch.Tensor:
    """Fit B(x) ≈ y and return out-of-fold predictions (2 folds), so a row's
    baseline never saw its own outcome."""
    from call_train import train

    n = x.shape[0]
    perm = torch.from_numpy(np.random.default_rng(seed).permutation(n))
    folds = [perm[: n // 2], perm[n // 2 :]]
    pred = torch.empty(n)
    for k in range(2):
        train_idx, pred_idx = folds[1 - k], folds[k]
        model, _ = train(x[train_idx], y[train_idx], hidden=list(hidden), epochs=epochs, lr=1e-3, seed=seed + k)
        with torch.no_grad():
            pred[pred_idx] = model(x[pred_idx]).squeeze(-1)
    resid = y - pred
    print(
        f"  [{label}] oracle baseline explains "
        f"{100 * (1 - float(resid.var()) / max(float(y.var()), 1e-8)):.1f}% of variance",
        flush=True,
    )
    return pred
