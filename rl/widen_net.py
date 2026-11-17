#!/usr/bin/env python3
"""Convert a play policy from the v4 feature layout (252 inputs) to the v5
layout (318: the 66 `history` features inserted before the action group).

The new input weights are zero, so the converted net plays exactly like the
original one; training then learns to use the history.

  rl/.venv/bin/python rl/widen_net.py assets/bots/tichu_q_v4.safetensors out.safetensors
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

import torch
from safetensors import safe_open
from safetensors.torch import load_file, save_file

from schema import ACTION_OFFSET, SPEC, TOTAL_FEATURE_COUNT

LEGACY_STATE = SPEC.group("history").offset  # 201: state prefix of layout v4


def widen(src: Path, dst: Path) -> None:
    with safe_open(str(src), framework="pt", device="cpu") as reader:
        meta = dict(reader.metadata() or {})
    tensors = load_file(str(src))
    sizes = json.loads(meta["layer_sizes"])
    if sizes[0] == TOTAL_FEATURE_COUNT:
        raise SystemExit(f"{src} already has {TOTAL_FEATURE_COUNT} inputs")
    action = sizes[0] - LEGACY_STATE
    if action != TOTAL_FEATURE_COUNT - ACTION_OFFSET:
        raise SystemExit(f"{src}: unexpected input size {sizes[0]}")
    w = tensors["layer.0.weight"]
    new = torch.zeros(w.shape[0], TOTAL_FEATURE_COUNT, dtype=w.dtype)
    new[:, :LEGACY_STATE] = w[:, :LEGACY_STATE]
    new[:, ACTION_OFFSET:] = w[:, LEGACY_STATE:]
    tensors["layer.0.weight"] = new.contiguous()
    meta["layer_sizes"] = json.dumps([TOTAL_FEATURE_COUNT] + sizes[1:])
    meta["builder.widened_from"] = str(src)
    save_file(tensors, str(dst), metadata=meta)
    print(f"{dst}: {sizes[0]} -> {TOTAL_FEATURE_COUNT} inputs")


if __name__ == "__main__":
    widen(Path(sys.argv[1]), Path(sys.argv[2]))
