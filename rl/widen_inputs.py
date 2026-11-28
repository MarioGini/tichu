#!/usr/bin/env python3
"""Bring a net to a feature layout with new input groups, unchanged.

A new state group (e.g. v10 ``convention``) inserts input columns; old nets
no longer load. This inserts zero-weight first-layer columns at the new
group's position, so the net computes exactly what it did before (the new
inputs are ignored until training moves the weights) and loads in the new
layout: the shipped nets keep playing and the next training warm-starts
from them.

  rl/.venv/bin/python rl/widen_inputs.py --net=assets/bots/tichu_q_v10.safetensors \\
      --group=convention --output=assets/bots/tichu_q_v10.safetensors
"""

from __future__ import annotations

import argparse
import json

import torch
from safetensors import safe_open
from safetensors.torch import save_file

from schema import SPEC


def widen(path: str, group: str, output: str) -> None:
    g = SPEC.group(group)
    with safe_open(path, "pt") as f:
        meta = dict(f.metadata() or {})
        tensors = {k: f.get_tensor(k) for k in f.keys()}
    w = tensors["layer.0.weight"]
    if w.shape[1] + g.size not in (SPEC.total, SPEC.group("action").offset):
        raise ValueError(f"{path}: {w.shape[1]} inputs + {g.size} fit neither the full layout "
                         f"({SPEC.total}) nor the state prefix ({SPEC.group('action').offset})")
    zeros = torch.zeros((w.shape[0], g.size), dtype=w.dtype)
    tensors["layer.0.weight"] = torch.cat([w[:, : g.offset], zeros, w[:, g.offset :]], 1).contiguous()
    sizes = json.loads(meta["layer_sizes"])
    sizes[0] = int(tensors["layer.0.weight"].shape[1])
    meta["layer_sizes"] = json.dumps(sizes)
    if "builder.architecture" in meta:
        meta["builder.architecture"] = json.dumps(sizes)
    meta["builder.widened"] = f"{group} (+{g.size} zero inputs at {g.offset}, schema v{SPEC.version})"
    save_file(tensors, output, metadata=meta)
    print(f"{path}: {w.shape[1]} -> {sizes[0]} inputs -> {output}")


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    p.add_argument("--net", required=True)
    p.add_argument("--group", required=True, help="the new input group (rl/schema/feature_spec.json)")
    p.add_argument("--output", required=True)
    a = p.parse_args()
    widen(a.net, a.group, a.output)


if __name__ == "__main__":
    main()
