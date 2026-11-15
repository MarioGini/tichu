# RL Workflow

This folder uses `uv` + PyTorch and persists artifacts only as `.safetensors`.

**Linux is the only supported dev environment for the RL tooling.** The uv
project is locked for Linux only, and PyTorch comes from the CPU-only wheel
index (no CUDA download). All commands below are run from the repo root.

One-time setup:

```bash
uv sync --project rl
```

## Quick start

There is currently no trained policy: the feature schema moved to v4 and all
older policies were deleted. Train a new one with the commands below.

**Before any RL command, compile the Dart headless runner once.** Every
Python script auto-detects `build/bin/headless` and uses it; without
this you pay a 2.5 s VM cold-start per invocation.

```bash
dart compile exe lib/headless/headless.dart -o build/bin/headless
```

To regenerate from scratch (`evaluate_policy.py` and `self_play.py` accept
`--shards=N` to fan headless work across CPU cores; default `0` =
`cpu_count - 1`; `bc_pretrain.py` generates its data in a single process):

```bash
uv run --project rl python rl/bc_pretrain.py \
    --output=rl/outputs/policy.safetensors \
    --episodes=200 --epochs=15 \
    --hidden=256,128,64 --seed=2024 --target-score=100
```

To evaluate against the heuristic:

```bash
uv run --project rl python rl/evaluate_policy.py \
    --nn-policy=rl/outputs/policy.safetensors \
    --output=rl/outputs/eval.safetensors \
    --seed=12345 --episodes=300 --target-score=1000 \
    --shards=7
```

### Performance notes

- The compiled `build/bin/headless` is roughly 12× faster on cold start than
  `dart run lib/headless/headless.dart` (250 ms vs 2.5 s) and ~2.5× faster
  in steady state.
- `headless_runner.py` shards an episode count across N processes (one per
  shard, distinct seed), then concatenates the JSONL output. On an 8-core
  box this is ~6× wallclock for typical 300+ episode jobs.
- Training stays on **CPU**: the 58k-param net is too small to benefit from
  a GPU, so the project installs the CPU-only PyTorch build.

## Architecture

### Feature schema (single source of truth)

`rl/schema/feature_spec.json` (v4) defines the 253-dim feature vector
consumed by both Python (training) and Dart (inference). Layout:

| Group           | Size | Indices | Content                                          |
|-----------------|------|---------|--------------------------------------------------|
| hand            | 56   | 0-55    | my cards (bitmap)                                |
| played          | 56   | 56-111  | cards out of play this round (bitmap)            |
| unseen          | 17   | 112-128 | per-rank count held by the other three players   |
| trick           | 20   | 129-148 | trick type/value/points, winner seat, wish       |
| seats           | 27   | 149-175 | left/partner/right: cards, finish, calls, points |
| self            | 15   | 176-190 | own calls, round and match score context         |
| hand_structure  | 10   | 191-200 | singles/pairs/runs/bombs, est. plays to finish   |
| action          | 52   | 201-252 | type, strength, beaters, cards used, hand after  |

Only Dart encodes features (`lib/agents/nn/feature_encoder.dart`); the
headless `--format=bc-jsonl` output carries them pre-encoded, so Python never
re-encodes. Policies trained on an older schema are rejected at load time.

The Python loader is `rl/schema/__init__.py`; the Dart constants live in
`lib/agents/nn/feature_encoder.dart` and are asserted against the JSON spec
by `test/agents/feature_layout_test.dart`. **Edit the JSON, then the Dart
encoder, then run the Dart tests.** Mismatches caused a silent, catastrophic
bug in the previous iteration (action features ended up at different
indices on each side, so trained nets saw zero action information at
inference time).

### Training pipelines

There are now two Python entry points:

1. **`bc_pretrain.py`** — behavioural cloning. Generates heuristic-vs-heuristic
   episodes, then teaches the Q-net to assign the highest Q-value among
   legal actions to the action the heuristic chose. Produces a policy
   roughly at heuristic-parity (~50 % win rate vs heuristic).

   - `--episodes`, `--epochs`, `--hidden`, `--lr`, `--batch-size`
   - `--init-from=prev.safetensors` warm-start from a previous policy
   - `--anchor-policy=prev.safetensors --kl-weight=0.5` add a KL pull to a
     previous policy (use to prevent catastrophic forgetting when fine-tuning)
   - `--winners-only` filters to the winning team's decisions only
     (currently makes things worse — winning teams just got lucky cards)
   - `--jsonl=...` reuse an existing JSONL instead of regenerating
   - `--shards=N` parallel headless workers for the data-gen phase

2. **`self_play.py`** — iterative self-play loop. Per iteration: candidate
   plays vs current best, BC train on winners-only with KL anchor, evaluate
   the new policy vs heuristic, promote if better.

### Headless output formats

Only two RL-relevant formats remain:

- **`--format=summary`** — one JSONL line per finished match.
  `evaluate_policy.py` consumes this. ~50 lines for a 50-match eval.
- **`--format=bc-jsonl`** — one JSONL line per play-phase decision with
  ≥2 legal actions: `state_features` (201 floats), `legal_play_action_features`
  (n × 52 floats), `legal_play_chosen_index`. `bc_pretrain.py` consumes this.

(`csv` and `none` are still around for ad-hoc debugging and dry runs.)

### Other headless flags

- `--mixed` uses team0 = NN, team1 = heuristic (for evaluation).
- `--nn-policy=path.safetensors` loads a trained policy.
- `--opponent-policy=path.safetensors` (with `--mixed`) lets team1 be a
  separate NN — used by self-play to pit candidate vs best.
- `--epsilon=0.1` ε-greedy exploration during dataset generation.
- `--ismcts`, `--ismcts-simulations=N` Information-Set MCTS player.
- `--mcts`, `--mcts-determinizations=N` plain MCTS player.

## Next steps

To beat the heuristic by a wider margin requires one of:

1. A search head at inference (MCTS / IS-MCTS with the BC policy as prior).
2. RL fine-tuning that does not catastrophically overwrite the BC anchor —
   e.g. KL-regularised policy gradient or AWR.
3. A trained value head (currently the network is Q(s, a) only;
   `lib/agents/mcts/{ismcts,mcts}_search.dart` therefore disable
   value-leaf evaluation and fall back to heuristic rollouts).

## Output contract

- `rl/outputs/` keeps only `*.safetensors` artifacts.
- Intermediate JSONL is written to the OS temp dir and removed.

## Notes

- Targets are normalised before MSE training using `target_mean` and
  `target_std` (stored in safetensors metadata; Dart `Mlp.fromSafetensorsBytes`
  reads them back). BC pretrain uses `mean=0`, `std=1` and trains on raw
  Q-logits via cross-entropy.
