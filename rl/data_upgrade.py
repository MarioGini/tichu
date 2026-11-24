"""Bring rollout data of any older feature layout to the current one.

Every cache written by ``rollout_train.save_npz`` records ``schema_version``;
older untagged caches are recognised by their widths. ``upgrade`` pads the
groups a cache lacks and then fills those that are a function of features it
has (registered in ``UPGRADES``); groups that cannot be recovered stay 0 and
are reported, never silently.

When a new schema version adds features:
  * derivable from existing features -> add a function to ``UPGRADES``
    (old data then teaches the new inputs too: what made v10 work);
  * not derivable -> add the group to ``UNRECOVERABLE`` (needs the game
    records, ``--record-games``, to be rebuilt by replay).
"""

from __future__ import annotations

import numpy as np

from schema import ACTION_FEATURE_COUNT, SPEC, STATE_FEATURE_COUNT, pad_action, pad_state

CURRENT = SPEC.version

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



def infer_version(s_width: int, a_width: int) -> int:
    """Schema version of an untagged cache from its widths."""
    if a_width >= ACTION_FEATURE_COUNT and s_width >= STATE_FEATURE_COUNT:
        return 9
    if s_width >= SPEC.group("passed").offset + 51:
        return 8
    if s_width >= SPEC.group("passed").offset:
        return 7
    return 6


def _beat(d: dict) -> None:
    g = groups(d["starts"])
    for i in range(0, d["a"].shape[0], 2_000_000):
        sl = slice(i, i + 2_000_000)
        d["a"][sl, BEAT : BEAT + 4] = beat_features(d["s"], d["a"][sl], g[sl]).astype(d["a"].dtype)


# (version that introduced the features, function filling them in place)
UPGRADES = [(9, _beat)]

# (version, group): features older data cannot provide.
UNRECOVERABLE = [(8, "passed: which card I passed to whom (not in the old features)")]


def upgrade(d: dict) -> tuple[dict, list[str]]:
    """Pad ``d`` (keys s, a, starts, ...) to the current layout and fill the
    derivable new features. Returns (d, notes on unrecoverable groups)."""
    version = int(d["schema_version"]) if "schema_version" in d else infer_version(d["s"].shape[1], d["a"].shape[1])
    d["s"] = pad_state(d["s"])
    d["a"] = pad_action(d["a"])
    for v, fn in UPGRADES:
        if version < v:
            if not d["a"].flags.writeable:
                d["a"] = d["a"].copy()
            fn(d)
    notes = [what for v, what in UNRECOVERABLE if version < v]
    d["schema_version"] = np.int16(CURRENT)
    return d, notes
