# RL Workflow (Safetensors-Only)

This folder uses `uv` + PyTorch and persists artifacts only as `.safetensors` (and optional `.pt` checkpoints).

All commands below are run from repo root `C:\repos\tichu`.

## 1) Regenerate Train Dataset (from scratch)

```powershell
$env:PYTHONIOENCODING='utf-8'; uv run --project c:\repos\tichu\rl python c:\repos\tichu\rl\generate_train_dataset.py --output=c:\repos\tichu\rl\outputs\train_dataset.safetensors --seed=42 --episodes=500 --target-score=100 --gamma=0.99
```

## 2) Train Policy

```powershell
$env:PYTHONIOENCODING='utf-8'; uv run --project c:\repos\tichu\rl python c:\repos\tichu\rl\train.py --input=c:\repos\tichu\rl\outputs\train_dataset.safetensors --output=c:\repos\tichu\rl\outputs\policy.safetensors --epochs=100 --hidden=128,64
```

## 3) Evaluate Policy vs Heuristic (1000-point matches)

```powershell
$env:PYTHONIOENCODING='utf-8'; uv run --project c:\repos\tichu\rl python c:\repos\tichu\rl\evaluate_policy.py --nn-policy=c:\repos\tichu\rl\outputs\policy.safetensors --output=c:\repos\tichu\rl\outputs\eval_1000.safetensors --seed=7777 --episodes=100 --target-score=1000
```

## RL-Specific Headless Flags

Use these when generating RL transition streams or evaluating learned policies
with the Dart headless runner:

- `--format=rl-jsonl`: emit RL transition records.
- `--rl-legal-count`: include legal-turn counts in transitions.
- `--nn-policy=model.safetensors`: load a trained NN policy for play selection.
- `--mixed`: team 0 uses the loaded policy, team 1 uses the heuristic agent.

`eval_1000.safetensors` metadata contains:
- matches
- team0_wins
- team1_wins
- ties
- team0_win_rate_non_tie
- avg_margin_t0_minus_t1
- median_margin_t0_minus_t1

## 4) Iterative Training Loop (Safetensors-Only)

```powershell
$env:PYTHONIOENCODING='utf-8'; uv run --project c:\repos\tichu\rl python c:\repos\tichu\rl\iterate.py --iterations=3 --episodes=500 --eval-episodes=100 --epochs=100 --epsilon=0.1 --bootstrap=c:\repos\tichu\rl\outputs\train_dataset.safetensors
```

## Output Contract

- Keep only:
  - `*.safetensors` datasets, policies, eval summaries
- Do not keep non-safetensors data artifacts in `rl/outputs`.

## Notes

- Safetensors IO uses native ML bindings via `safetensors.torch` for high-throughput tensor serialization.
- Dataset generation/evaluation scripts use transient internal logs and clean them up automatically.
