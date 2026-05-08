# RL Workflow

This folder uses `uv` + PyTorch and persists artifacts only as `.safetensors`.

All commands below are run from repo root `c:\repos\tichu`.

## Quick start

The shipped policy at `rl/outputs/policy.safetensors` was produced by
behavioural cloning of the heuristic agent. It currently beats the heuristic
~53 % of the time over multi-hundred-game evals (see "Results" below).

**Before any RL command, compile the Dart headless runner once.** Every
Python script auto-detects `build/bin/headless.exe` and uses it; without
this you pay a 2.5 s VM cold-start per invocation.

```powershell
dart compile exe lib\headless\headless.dart -o build\bin\headless.exe
```

To regenerate from scratch (all RL scripts accept `--shards=N` to fan
headless work across CPU cores; default `0` = `cpu_count - 1`):

```powershell
$env:PYTHONIOENCODING='utf-8'
uv run --project rl python rl\bc_pretrain.py `
    --output=rl\outputs\policy.safetensors `
    --episodes=200 --epochs=15 `
    --hidden=256,128,64 --seed=2024 --target-score=100 `
    --shards=7
```

To evaluate against the heuristic:

```powershell
uv run --project rl python rl\evaluate_policy.py `
    --nn-policy=rl\outputs\policy.safetensors `
    --output=rl\outputs\eval.safetensors `
    --seed=12345 --episodes=300 --target-score=1000 `
    --shards=7
```

### Performance notes

- The compiled `headless.exe` is roughly 12× faster on cold start than
  `dart run lib/headless/headless.dart` (250 ms vs 2.5 s) and ~2.5× faster
  in steady state.
- `headless_runner.py` shards an episode count across N processes (one per
  shard, distinct seed), then concatenates the JSONL output. On an 8-core
  box this is ~6× wallclock for typical 300+ episode jobs.
- Training stays on **CPU**. On hardware without a real CUDA GPU
  (Intel UHD via DirectML in this repo), DirectML is both slower than
  MKL/MKLDNN for our 58k-param net AND crashes inside autograd's
  ready-queue lookup when fused Adam ops fall back to CPU mid-step. CPU is
  the safe default; opt back into DirectML with `TICHU_TRAIN_DEVICE=directml`.

## Architecture

### Feature schema (single source of truth)

`rl/schema/feature_spec.json` defines the 66-dim feature vector consumed by
both Python (training) and Dart (inference). Layout:

| Group           | Size | Indices |
|-----------------|------|---------|
| state           | 32   | 0-31    |
| hand_structure  |  8   | 32-39   |
| opponent        |  6   | 40-45   |
| action          | 20   | 46-65   |

The Python loader is `rl/schema/__init__.py`; the Dart constants live in
`lib/agents/nn/feature_encoder.dart` and are asserted against the JSON spec
by `test/agents/feature_layout_test.dart`. **Edit the JSON, run the Dart
test, then update both encoders.** Mismatches caused a silent, catastrophic
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

The legacy MC-RL trainer (`generate_train_dataset.py`, `train.py`,
`iterate.py`) is gone — that pipeline produced policies that
catastrophically forgot BC and never improved on heuristic.

### Headless output formats

Only two RL-relevant formats remain:

- **`--format=summary`** — one JSONL line per finished match.
  `evaluate_policy.py` consumes this. ~50 lines for a 50-match eval.
- **`--format=bc-jsonl`** — one JSONL line per play-phase decision with
  ≥2 legal actions: `state_features` (46 floats), `legal_play_action_features`
  (n × 20 floats), `legal_play_chosen_index`. `bc_pretrain.py` consumes this.

(`csv` and `none` are still around for ad-hoc debugging and dry runs.)

### Other headless flags

- `--mixed` uses team0 = NN, team1 = heuristic (for evaluation).
- `--nn-policy=path.safetensors` loads a trained policy.
- `--opponent-policy=path.safetensors` (with `--mixed`) lets team1 be a
  separate NN — used by self-play to pit candidate vs best.
- `--epsilon=0.1` ε-greedy exploration during dataset generation.
- `--ismcts`, `--ismcts-simulations=N` Information-Set MCTS player.
- `--mcts`, `--mcts-determinizations=N` plain MCTS player.

## Results (May 2026)

Across cumulative evaluation matches:

| Policy          | Matches | Wins | Win rate | Avg margin |
|-----------------|---------|------|----------|------------|
| BC (256,128,64) |     580 |  309 |   53.3 % |       +50  |
| BC (384,192,96) |     300 |  152 |   50.7 % |       −23  |
| BC winners-only |     300 |  133 |   44.3 % |       −55  |

The winning recipe is the **smaller** BC net trained on **fewer** episodes:
when you push validation accuracy past 99.9 %, the model literally is the
heuristic (which is by design 50/50 against itself). The 53.3 % comes from
the small accuracy gap allowing the net to generalise away from heuristic
edge-case mistakes.

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
- DirectML is auto-detected for GPU acceleration on Windows.
