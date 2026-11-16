"""Flat behaviour-cloning dataset built from headless ``bc-jsonl`` output."""

from __future__ import annotations

import json
from pathlib import Path

import numpy as np
import torch

from schema import ACTION_FEATURE_COUNT, ACTION_OFFSET, SPEC, TOTAL_FEATURE_COUNT


# ── Flat BC dataset ──────────────────────────────────────────────────────────


class FlatBcData:
    """Decision-grouped BC data laid out for vectorised scatter ops.

    All rows are sorted by ``decision_id`` (0..D-1, contiguous). For each
    decision we keep its row range in the flat ``inputs`` tensor, which lets
    us gather batch rows without any Python per-decision loops.

    Fields (all on the same device):
      inputs            (N_rows, F)  float32 — concatenated state+action vec
      decision_starts   (D + 1,)     long    — row range per decision
      chosen_global     (D,)         long    — global row index of chosen action
      decision_size     (D,)         long    — equivalent to diff(decision_starts)
    """

    def __init__(
        self,
        inputs: torch.Tensor,
        decision_starts: torch.Tensor,
        chosen_global: torch.Tensor,
    ) -> None:
        self.inputs = inputs.contiguous()
        self.decision_starts = decision_starts.contiguous()
        self.chosen_global = chosen_global.contiguous()
        self.decision_size = decision_starts[1:] - decision_starts[:-1]

    @property
    def num_rows(self) -> int:
        return int(self.inputs.shape[0])

    @property
    def num_decisions(self) -> int:
        return int(self.chosen_global.shape[0])

    def to(self, device: torch.device) -> "FlatBcData":
        return FlatBcData(
            self.inputs.to(device),
            self.decision_starts.to(device),
            self.chosen_global.to(device),
        )


def build_bc_dataset(jsonl: Path, *, winners_only: bool = False) -> FlatBcData:
    """Load a BC dataset from a JSONL file produced by the headless runner.

    Requires ``--format=bc-jsonl`` rows carrying pre-encoded
    ``state_features`` for the current schema version.
    """
    # Two-pass build: first decide which episodes count, then accumulate.
    winning_team_by_episode: dict[int, int] = {}
    if winners_only:
        with jsonl.open("r", encoding="utf-8") as fh:
            last_by_ep: dict[int, dict] = {}
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                row = json.loads(line)
                if row.get("episode_end"):
                    last_by_ep[int(row.get("episode", 0))] = row
        for ep, row in last_by_ep.items():
            if not row.get("episode_end"):
                continue
            t1 = float(row.get("team_one_total", 0.0))
            t2 = float(row.get("team_two_total", 0.0))
            if t1 > t2:
                winning_team_by_episode[ep] = 0
            elif t2 > t1:
                winning_team_by_episode[ep] = 1

    inputs_chunks: list[np.ndarray] = []
    decision_starts_list: list[int] = [0]
    chosen_global_list: list[int] = []

    cursor = 0
    skipped_no_legal = 0
    skipped_single_action = 0
    skipped_loser = 0
    skipped_explore = 0

    with jsonl.open("r", encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            row = json.loads(line)
            if row.get("episode_end") or row.get("round_end"):
                continue
            if row.get("explore"):
                # ε-exploration moves are not the behaviour policy's choice.
                skipped_explore += 1
                continue

            if winners_only:
                ep = int(row.get("episode", 0))
                wteam = winning_team_by_episode.get(ep)
                if wteam is None:
                    continue
                if int(row.get("team", -1)) != wteam:
                    skipped_loser += 1
                    continue

            legal = row.get("legal_play_action_features")
            chosen = row.get("legal_play_chosen_index")
            if not isinstance(legal, list) or not isinstance(chosen, int):
                skipped_no_legal += 1
                continue
            if len(legal) <= 1:
                skipped_single_action += 1
                continue

            pre_state = row.get("state_features")
            if not isinstance(pre_state, list) or len(pre_state) != ACTION_OFFSET:
                raise ValueError(
                    f"row has no state_features of length {ACTION_OFFSET} "
                    f"(feature schema v{SPEC.version}); regenerate with "
                    "--format=bc-jsonl"
                )
            state_part = np.asarray(pre_state, dtype=np.float32)

            # Build (n_actions, F) block for this decision.
            block = np.empty((len(legal), TOTAL_FEATURE_COUNT), dtype=np.float32)
            for i, action_feats in enumerate(legal):
                if not isinstance(action_feats, list) or len(action_feats) != ACTION_FEATURE_COUNT:
                    raise ValueError(
                        f"action features dim mismatch: got {len(action_feats) if isinstance(action_feats, list) else type(action_feats)}, "
                        f"schema expects {ACTION_FEATURE_COUNT}"
                    )
                block[i, :ACTION_OFFSET] = state_part
                block[i, ACTION_OFFSET:] = np.asarray(action_feats, dtype=np.float32)

            inputs_chunks.append(block)
            chosen_global_list.append(cursor + int(chosen))
            cursor += len(legal)
            decision_starts_list.append(cursor)

    if not inputs_chunks:
        raise ValueError(
            f"No usable BC rows in {jsonl}. Hints: skipped_no_legal="
            f"{skipped_no_legal}, skipped_single_action={skipped_single_action},"
            f" skipped_loser={skipped_loser}, skipped_explore={skipped_explore}"
        )

    inputs_np = np.concatenate(inputs_chunks, axis=0)
    inputs_t = torch.from_numpy(inputs_np)
    decision_starts_t = torch.tensor(decision_starts_list, dtype=torch.long)
    chosen_global_t = torch.tensor(chosen_global_list, dtype=torch.long)
    return FlatBcData(inputs_t, decision_starts_t, chosen_global_t)


# ── Q-network ────────────────────────────────────────────────────────────────
