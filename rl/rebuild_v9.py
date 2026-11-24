#!/usr/bin/env python3
"""Bring rollout npz caches to the current feature layout (schema v9).

Older caches are padded with zeros for the groups they lack. The v9
beatability features (end of the action group) do not need the game: they
are a function of features every cache already has, the unseen-card counts
(``unseen``), each opponent's card count (``seats``) and the action's type,
value and card count. This computes them exactly as
``CardKnowledge.beaterCount`` / ``FeatureEncoder.actionFeatures`` do, so old
data teaches the beatability inputs too. (The v8 ``passed`` group cannot be
recovered: which card went to whom is not in the old features; it stays 0.)

  # check against caches written by the Dart encoder (schema v9 runner)
  rl/.venv/bin/python rl/rebuild_v9.py --check rl/outputs/exp_beat/c00.npz
  # rebuild in place (atomic per file)
  rl/.venv/bin/python rl/rebuild_v9.py rl/outputs/v8/data/*.npz
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))

from schema import ACTION_FEATURE_COUNT, SPEC, pad_action, pad_state  # noqa: E402

from data_upgrade import BEAT, beat_features, groups, upgrade  # noqa: E402,F401


def rebuild(path: Path) -> int:
    d = dict(np.load(path))
    if "s" not in d:
        raise ValueError(f"{path}: not a rollout cache (old 'x' layout: load once with rollout_train first)")
    d, notes = upgrade(d)
    for n in notes:
        print(f"  {path.name}: no {n}")
    tmp = path.with_suffix(".tmp.npz")
    np.savez_compressed(tmp, **d)
    tmp.rename(path)
    return int(d["starts"].size - 1)


def check(path: Path) -> None:
    d = np.load(path)
    if d["a"].shape[1] != ACTION_FEATURE_COUNT:
        raise SystemExit(f"{path}: {d['a'].shape[1]} action features, need {ACTION_FEATURE_COUNT} written by the Dart encoder")
    got = beat_features(pad_state(d["s"]), d["a"], groups(d["starts"]))
    want = d["a"][:, BEAT : BEAT + 4].astype(np.float32)
    err = np.abs(got - want)
    bad = (err > 2e-3).any(1)
    print(f"{path}: {bad.sum()} of {len(bad)} action rows differ (max abs error {err.max():.4f})")
    if bad.any():
        i = np.nonzero(bad)[0][:5]
        print("  got ", got[i])
        print("  want", want[i])


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--check", action="store_true", help="compare against Dart-written v9 caches instead of rebuilding")
    p.add_argument("files", nargs="+")
    args = p.parse_args()
    for f in args.files:
        if args.check:
            check(Path(f))
        else:
            print(f"{f}: {rebuild(Path(f))} decisions", flush=True)


if __name__ == "__main__":
    main()
