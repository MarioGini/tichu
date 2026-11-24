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

UNSEEN = SPEC.group("unseen").offset
SEATS = SPEC.group("seats").offset
BEAT = 54  # offset of the beatability features in the action group


def beat_features(s: np.ndarray, a: np.ndarray, group: np.ndarray) -> np.ndarray:
    """(rows, 4) beatability features for action rows ``a`` whose decision
    state is ``s[group]``."""
    st = s[group].astype(np.float32)
    act = a.astype(np.float32)
    rows = act.shape[0]
    # u[:, r] for r = 0..14 (index = rank; 1 = Mah Jong, 2..14 = 2..Ace).
    u = np.zeros((rows, 15), np.int32)
    u[:, 2:15] = np.rint(st[:, UNSEEN : UNSEEN + 13] * 4).astype(np.int32)
    u[:, 1] = np.rint(st[:, UNSEEN + 13]).astype(np.int32)
    dog = st[:, UNSEEN + 14] > 0.5
    phx = st[:, UNSEEN + 15] > 0.5
    dragon = st[:, UNSEEN + 16] > 0.5
    v = act[:, 9] * 25.0
    n = np.rint(act[:, 10] * 14).astype(np.int32)
    kind = np.argmax(act[:, 0:9], axis=1)  # pass single pair triplet fh straight pairstr bomb dog
    has_type = act[:, 0:9].max(axis=1) > 0.5
    uses_dragon = act[:, 13] > 0.5
    ranks = np.arange(15)[None, :]
    # Values are whole or .5 (Phoenix): a quarter-point margin absorbs the
    # float16 rounding of value / 25.
    higher = ranks > v[:, None] + 0.25
    higher[:, :2] = False  # beaters of pairs etc. are ranks 2..14
    count = np.zeros(rows, np.int32)

    single = has_type & (kind == 1) & ~uses_dragon
    c1 = (u * higher).sum(1) + phx + dragon
    count = np.where(single, c1, count)
    for k, t in ((2, 2), (3, 3)):
        m = has_type & (kind == t)
        ok = (u >= k) | (phx[:, None] & (u == k - 1))
        count = np.where(m, (ok & higher).sum(1), count)
    fh = has_type & (kind == 4)
    ok = (u >= 3) | (phx[:, None] & (u == 2))
    count = np.where(fh, (ok & higher).sum(1), count)

    # Straights: windows [low, top] of length n above the value.
    miss = (u < 1).astype(np.int32)  # rank 1 = Mah Jong
    pre = np.concatenate([np.zeros((rows, 1), np.int32), np.cumsum(miss, 1)], 1)  # pre[:, r+1] = sum miss[0..r]
    st_m = has_type & (kind == 5)
    if st_m.any():
        cnt = np.zeros(rows, np.int32)
        vfloor = np.floor(v + 0.25).astype(np.int32)
        for top in range(2, 15):
            low = top - n + 1
            valid = st_m & (top >= vfloor + 1) & (low >= 1)
            lowc = np.clip(low, 1, 14)
            missing = pre[:, top + 1] - pre[np.arange(rows), lowc]
            mj_missing = (lowc == 1) & (u[:, 1] < 1)
            good = (missing == 0) | ((missing == 1) & phx & ~mj_missing)
            cnt += (valid & good).astype(np.int32)
        count = np.where(st_m, cnt, count)
    ps_m = has_type & (kind == 6)
    if ps_m.any():
        need = np.clip(2 - u, 0, None)
        pre2 = np.concatenate([np.zeros((rows, 1), np.int32), np.cumsum(need, 1)], 1)
        cnt = np.zeros(rows, np.int32)
        vfloor = np.floor(v + 0.25).astype(np.int32)
        pairs = n // 2
        for top in range(2, 15):
            low = top - pairs + 1
            valid = ps_m & (top >= vfloor + 1) & (low >= 2)
            lowc = np.clip(low, 2, 14)
            missing = pre2[:, top + 1] - pre2[np.arange(rows), lowc]
            good = (missing == 0) | ((missing == 1) & phx)
            cnt += (valid & good).astype(np.int32)
        count = np.where(ps_m, cnt, count)

    out = np.zeros((rows, 4), np.float32)
    pos = count > 0
    out[:, 0] = np.where(pos, np.clip(count / np.where(kind == 1, 16.0, 13.0), 0, 1), 0)
    total = u[:, 1:15].sum(1) + phx + dragon + dog
    out[:, 1] = np.where(pos & (kind == 1) & (total > 0), np.clip(count / np.maximum(total, 1), 0, 1), 0)
    left = np.rint(st[:, SEATS] * 14).astype(np.int32)
    right = np.rint(st[:, SEATS + 18] * 14).astype(np.int32)
    out[:, 2] = (pos & (left >= n)).astype(np.float32)
    out[:, 3] = (pos & (right >= n)).astype(np.float32)
    return out


def groups(starts: np.ndarray) -> np.ndarray:
    lens = np.diff(starts)
    return np.repeat(np.arange(lens.size), lens)


def rebuild(path: Path) -> int:
    d = dict(np.load(path))
    if "s" not in d:
        raise ValueError(f"{path}: not a rollout cache (old 'x' layout: load once with rollout_train first)")
    d["s"] = pad_state(d["s"])
    d["a"] = pad_action(d["a"]).copy()
    g = groups(d["starts"])
    for i in range(0, d["a"].shape[0], 2_000_000):
        sl = slice(i, i + 2_000_000)
        d["a"][sl, BEAT : BEAT + 4] = beat_features(d["s"], d["a"][sl], g[sl]).astype(d["a"].dtype)
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
