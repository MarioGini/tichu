#!/usr/bin/env python3
"""Convert a play policy of an older feature layout to the current one.

Older layouts are the current one with state groups missing at the end of
the state prefix and only the first 51 action features: v4 (252 inputs,
before `history`), v5 (318, before the `turn` flag of out-of-turn bombs) and
v6 (319, before the v7 `claim` / `received` groups and the after-action
claim features). The new input weights are zero, so the
converted net plays exactly like the original one; training then learns to
use the new features. (`load_qnetwork_from_safetensors` does the same in
memory, so training can also start from the old file directly.)

  rl/.venv/bin/python rl/widen_net.py old_layout.safetensors out.safetensors
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

from safetensors import safe_open
from safetensors.torch import load_file, save_file

from schema import LEGACY_STATE_PREFIX, TOTAL_FEATURE_COUNT, widen_first_layer


def widen(src: Path, dst: Path) -> None:
    with safe_open(str(src), framework="pt", device="cpu") as reader:
        meta = dict(reader.metadata() or {})
    tensors = load_file(str(src))
    sizes = json.loads(meta["layer_sizes"])
    if sizes[0] == TOTAL_FEATURE_COUNT:
        raise SystemExit(f"{src} already has {TOTAL_FEATURE_COUNT} inputs")
    if sizes[0] not in LEGACY_STATE_PREFIX:
        raise SystemExit(f"{src}: unexpected input size {sizes[0]}")
    tensors["layer.0.weight"] = widen_first_layer(tensors["layer.0.weight"], sizes[0]).contiguous()
    meta["layer_sizes"] = json.dumps([TOTAL_FEATURE_COUNT] + sizes[1:])
    meta["builder.widened_from"] = str(src)
    save_file(tensors, str(dst), metadata=meta)
    print(f"{dst}: {sizes[0]} -> {TOTAL_FEATURE_COUNT} inputs")


if __name__ == "__main__":
    widen(Path(sys.argv[1]), Path(sys.argv[2]))
