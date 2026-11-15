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
