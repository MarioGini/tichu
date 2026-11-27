"""Loader for the canonical feature layout shared with Dart.

This module reads ``feature_spec.json`` and exposes typed constants that are
the single source of truth for ``rl/data.py``. The same file is consumed by
the Dart side (see ``lib/agents/nn/feature_encoder.dart`` and the schema test
under ``test/agents/feature_layout_test.dart``).

Adding or renaming a feature: edit ``feature_spec.json`` only, then run the
Dart layout test — it will fail loudly if Dart drifts from the spec.
"""

from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path


_SPEC_PATH = Path(__file__).resolve().parent / "feature_spec.json"


@dataclass(frozen=True)
class FeatureGroup:
    name: str
    offset: int
    size: int
    feature_names: tuple[str, ...]

    def index(self, name: str) -> int:
        """Return the absolute index of ``name`` within the full vector."""
        rel = self.feature_names.index(name)
        return self.offset + rel


@dataclass(frozen=True)
class FeatureSpec:
    version: int
    groups: tuple[FeatureGroup, ...]
    total: int

    def group(self, name: str) -> FeatureGroup:
        for g in self.groups:
            if g.name == name:
                return g
        raise KeyError(f"unknown feature group: {name}")


def _load() -> FeatureSpec:
    with _SPEC_PATH.open("r", encoding="utf-8") as fh:
        raw = json.load(fh)

    offset = 0
    groups: list[FeatureGroup] = []
    for g in raw["groups"]:
        size = int(g["size"])
        names = tuple(g["features"])
        if len(names) != size:
            raise ValueError(
                f"feature_spec group '{g['name']}': size={size} but "
                f"{len(names)} feature names listed"
            )
        groups.append(
            FeatureGroup(name=g["name"], offset=offset, size=size, feature_names=names)
        )
        offset += size

    return FeatureSpec(version=int(raw["version"]), groups=tuple(groups), total=offset)


SPEC = _load()

ACTION_GROUP = SPEC.group("action")

# Every group before "action" is part of the per-decision state prefix.
STATE_GROUPS = tuple(g for g in SPEC.groups if g.name != "action")

ACTION_FEATURE_COUNT = ACTION_GROUP.size
ACTION_OFFSET = ACTION_GROUP.offset
STATE_FEATURE_COUNT = ACTION_OFFSET
TOTAL_FEATURE_COUNT = SPEC.total

# Action features of the layouts up to v6; v7 appends the claim analysis of
# the hand after the action, so they are a prefix of the current action part.
LEGACY_ACTION_FEATURE_COUNT = 51

# Older data layouts (training caches; nets of older layouts are not
# supported), by row width -> length of their state prefix. Each layout is
# the current one with later groups missing at the end of the state prefix:
# v4 (252: before `history`), v5 (318: before `turn`), v6 (319: before
# `claim` / `received`) with the first LEGACY_ACTION_FEATURE_COUNT action
# features; v7 (376: before `passed`) and v8 with 54 of them.
LEGACY_STATE_PREFIX = {
    SPEC.group(g).offset + LEGACY_ACTION_FEATURE_COUNT: SPEC.group(g).offset
    for g in ("history", "turn", "claim")
}
# Action features of the v7-v8 layouts (before the v9 beatability group).
V8_ACTION_FEATURE_COUNT = 54
LEGACY_STATE_PREFIX[SPEC.group("passed").offset + V8_ACTION_FEATURE_COUNT] = SPEC.group("passed").offset
LEGACY_STATE_PREFIX[STATE_FEATURE_COUNT + V8_ACTION_FEATURE_COUNT] = STATE_FEATURE_COUNT


def pad_state(s):
    """Pad state-feature rows of an older layout (fewer columns) with zeros
    for the missing trailing groups (e.g. ``off_turn`` = 0: data recorded
    before out-of-turn bombs existed; the v7 claim / received groups).
    Works for numpy arrays."""
    import numpy as np

    n = s.shape[1]
    if n == STATE_FEATURE_COUNT:
        return s
    if n not in LEGACY_STATE_PREFIX.values():
        raise ValueError(f"state rows have {n} features, expected {STATE_FEATURE_COUNT}")
    out = np.zeros((s.shape[0], STATE_FEATURE_COUNT), dtype=s.dtype)
    out[:, :n] = s
    return out


def pad_action(a):
    """Pad action-feature rows of an older layout (51 columns, up to v6) with
    zeros for the v7 after-action claim features. Works for numpy arrays."""
    import numpy as np

    n = a.shape[1]
    if n == ACTION_FEATURE_COUNT:
        return a
    if n not in (LEGACY_ACTION_FEATURE_COUNT, V8_ACTION_FEATURE_COUNT):
        raise ValueError(f"action rows have {n} features, expected {ACTION_FEATURE_COUNT}")
    out = np.zeros((a.shape[0], ACTION_FEATURE_COUNT), dtype=a.dtype)
    out[:, :n] = a
    return out
