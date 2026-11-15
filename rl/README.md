# RL Workflow

This folder uses `uv` + PyTorch and persists artifacts only as `.safetensors`.

**Linux is the only supported dev environment for the RL tooling.** The uv
project is locked for Linux only, and PyTorch comes from the CPU-only wheel
index (no CUDA download). All commands below are run from the repo root.

One-time setup:

```bash
uv sync --project rl
```

If `download.pytorch.org` / `download-r2.pytorch.org` are not reachable (e.g.
a restricted cloud sandbox), install from PyPI instead (pulls CUDA libs, but
runs on CPU) and call `rl/.venv/bin/python` instead of `uv run`:

```bash
uv venv rl/.venv
VIRTUAL_ENV=rl/.venv uv pip install "torch>=2.15.0" "numpy>=2.5.4" "safetensors>=0.8.0"
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

To regenerate from scratch (`bc_pretrain.py`, `evaluate_policy.py`,
`self_play.py` and `call_train.py` accept `--shards=N` to fan headless work
across CPU cores; default `0` = `cpu_count - 1`):

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
- Training stays on **CPU**: the ~100k-param net is too small to benefit from
  a GPU, so the project installs the CPU-only PyTorch build.

## Background: how similar games are learned

Tichu is a 4-player, 2-team climbing ("shedding") card game with hidden
hands — the same family as Dou Dizhu, Guandan and Big Two. What works there:

- **DouZero** (Dou Dizhu, ICML 2021): Deep Monte Carlo — a Q(s, a) network
  with an explicit action encoding, trained on whole-game returns from
  massive ε-greedy self-play. Simple, and it beat every earlier Dou Dizhu AI.
  `q_train.py` is one step of this.
- **PerfectDou** (NeurIPS 2022): perfect-training / imperfect-execution — the
  critic sees all hands during training, the policy does not. That removes
  card luck from the learning signal; it beat DouZero with ~10× fewer
  samples. Here: the `oracle` field and oracle baselines (`oracle.py`) in
  `awr_train.py`, `call_train.py`, `schupf_train.py`, `q_train.py`.
- **GuanZero** (Guandan, a 2-team climbing game): DMC plus features for
  cooperation between partners.
- **Tichu thesis (Wyss, Bern 2024)**: DQN / PPO for Tichu; behaviour cloning
  first helps a lot (our `bc_pretrain.py` warm start).
- Search (IS-MCTS, PIMC as in Skat/Bridge bots) needs a value function over
  *post-move* states; our current V(s) is only trained on own-turn states,
  so one-ply search with it is unsound (it passes far too much).

Specific to this repo: because the bots are deterministic and the deal is
known in self-play, a call decision can be labelled **exactly** —
`headless --counterfactual-calls` forks the round and plays it out with and
without the call (`cf` = R(call) − R(no call)). Measured that way, the
heuristic's Tichu calls are break-even (about −1 pt per call, 43 % of its
calls lose), while a perfect caller would gain about +40 pts per player and
round — calls are the biggest lever against the heuristic.

Schupf conventions: odd ranks to the left opponent, even ranks to the right
(specials anywhere) so an opponent never receives two cards of the same rank
from one team (no bomb gifts); give the partner the best card unless my own
hand is a Tichu hand (then keep strength and pass low), always support a
partner who called.

Hardware used so far: 4 CPU cores (Xeon), 15 GB RAM, no GPU. Data
generation dominates the run time (counterfactual call labels make games
several times slower); the nets are small MLPs, so training stays on CPU.

## Architecture

### Feature schema (single source of truth)

`rl/schema/feature_spec.json` (v4) defines the 252-dim feature vector
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
| action          | 51   | 201-251 | type, strength, beaters, cards used, hand after  |

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

Python entry points:

1. **`bc_pretrain.py`** — behavioural cloning. Generates heuristic-vs-heuristic
   episodes, then teaches the Q-net to assign the highest Q-value among
   legal actions to the action the heuristic chose. Produces a policy
   roughly at heuristic-parity (~50 % win rate vs heuristic).

   - `--episodes`, `--epochs`, `--hidden`, `--lr`, `--decisions-per-batch`
   - `--init-from=prev.safetensors` warm-start from a previous policy
   - `--anchor-policy=prev.safetensors --kl-weight=0.5` add a KL pull to a
     previous policy (use to prevent catastrophic forgetting when fine-tuning)
   - `--winners-only` filters to the winning team's decisions only
     (currently makes things worse — winning teams just got lucky cards)
   - `--jsonl=...` reuse an existing JSONL instead of regenerating
   - `--shards=N` parallel headless workers for the data-gen phase

2. **`self_play.py`** — iterative self-play loop. Per iteration: candidate
   plays vs current best, fine-tune with KL anchor to best, duplicate-evaluate
   vs heuristic, promote on a significant paired gain. `--algo=awr` (default)
   trains with `awr_train.py`; `--algo=bc` is the old winners-only BC.

3. **`awr_train.py`** — advantage-weighted regression. Fits a value net
   V(s) on the 201 state features to the round point difference (own team
   minus opponents, incl. Tichu bonuses, /100), then fine-tunes the policy
   with cross-entropy weighted by `min(exp((R - V(s)) / beta), max_weight)`
   plus a KL anchor. Uses all decisions, exploration moves included.
   `--value-output` saves V(s) (`target_std=100`, so Dart reads points);
   `headless --ismcts --value-net=value.safetensors` uses it as the leaf
   evaluator instead of heuristic rollouts.

4. **`call_train.py`** — call-value nets. Data comes from
   `headless --call-epsilon=p`, which flips Tichu / Grand Tichu decisions
   with probability p (first Tichu opportunity per player and round) and
   logs `{"call": "tichu"|"grand", "called", "state_features", ...}` rows.

   ```bash
   rl/.venv/bin/python rl/call_train.py --generate --episodes=1500 \
       --target-score=500 --call-epsilon=0.15 \
       --nn-policy=rl/outputs/best_policy.safetensors --output-dir=rl/outputs
   rl/.venv/bin/python rl/evaluate_policy.py \
       --nn-policy=rl/outputs/best_policy.safetensors \
       --tichu-net=rl/outputs/tichu_net.safetensors \
       --grand-net=rl/outputs/grand_net.safetensors \
       --output=rl/outputs/eval_calls.safetensors --episodes=200 --target-score=500
   ```

5. **`schupf_train.py`** — schupf value net Q(hand, pass) on
   `SchupfFeatures` (232: hand bitmap, one-hot card to left / partner /
   right, `[grand, tichu]` call flags for me / partner / left / right).
   Data: `headless --schupf-epsilon=p` (mostly one card swapped). Dart's
   `NnSchupfStrategy` scores all 2184 assignments with an incremental first
   layer.

6. **`train_loop.py`** — the joint loop for the whole bot. Each iteration
   generates exploration data with the *current* bot (calls, schupf, plays),
   retrains call nets, schupf net and play policy (AWR), and tries each
   component group (play / calls / schupf) on top of the best bot, promoting
   it only on a significant paired gain (duplicate, 100 deals, target 1000).
   Because everything is retrained on the current bot's games, components
   adapt to each other (e.g. passing to a partner who announced Tichu).

   ```bash
   rl/.venv/bin/python rl/train_loop.py --iterations=4 --shards=4
   # best bot: rl/outputs/bot_best/*.safetensors
   ```

7. **`q_train.py`** — experimental Monte-Carlo Q fine-tune of the play net.

8. **`analyze_games.py`** — duplicate games vs the heuristic with
   `--shadow-heuristic`: round stats per side (going out first, double wins,
   call rates and success) and where / how often the policy's moves differ
   from what the heuristic would have played.

### One bot definition for app and training

- `lib/agents/bot_config.dart` — `BotConfig` (+ `LoadedNet`) builds every bot:
  heuristic, or any mix of learned play / Tichu / Grand Tichu / pre-schupf
  Tichu / schupf nets. The app's default agent factory and the headless
  runner both use it; it has no `dart:io`, so the app can load nets from
  asset bytes.
- `lib/game/agent_decisions.dart` — `AgentDecisions.next` finds the pending
  decision (schupf receipt, Grand Tichu, pre-schupf Tichu, schupf, Dragon
  gift, turn) and `AgentDecisions.resolve` asks the agent. The app's
  `AiTurnRunner` and the headless simulator both drive bots through it; the
  simulator only adds exploration and logging around it.

### Decision order per round

Grand Tichu (8 cards) → **pre-schupf Tichu** (14 cards, every player before
anyone passes; the heuristic never calls here) → schupf → play, with a Tichu
opportunity before the first card.

### What the NN controls

`NnPlaySelectionStrategy` is a `FullTurnPolicy`: `SmartAiAgent` hands it
every legal play plus pass, and only keeps the hard rules (play out when a
finishing turn exists; wish enforcement). The heuristic's tactical shortcuts
(partner-support pass, lead tactics, singleton responses) are bypassed for
NN players. Dragon gift and wish choice are still heuristic.

Tichu / Grand Tichu calls can come from call-value nets
(`NnTichuCallStrategy`, `headless --tichu-net=.. --grand-net=..
--pre-tichu-net=..`): Q(s, call)
on `[state, flag, flag × state]` (201 state features, call flag), predicting
the round point difference. The agent calls when Q(s, 1) − Q(s, 0) > margin.
Without nets the heuristic decides (it never calls Grand Tichu).

### Evaluation

`evaluate_policy.py` is duplicate by default: every deal sequence is played
twice with the same deals (`--deal-seed`), once with the policy on team 0
and once swapped. It reports the per-deal win rate with its standard error
and stores per-deal results, so `self_play.py` promotes a candidate only if
its paired gain over the best policy exceeds `--promote-z` SEs; a rejected
candidate is discarded (unless `--keep-rejected`).

### Headless output formats

Only two RL-relevant formats remain:

- **`--format=summary`** — one JSONL line per finished match.
  `evaluate_policy.py` consumes this. ~50 lines for a 50-match eval.
- **`--format=bc-jsonl`** — one JSONL line per play-phase decision with
  ≥2 legal actions: `episode`, `round`, `team`, `state_features` (201 floats),
  `legal_play_action_features` (n × 51 floats), `legal_play_chosen_index`,
  and `explore: true` when the move came from ε-exploration (BC skips those).
  The legal set is exactly what the NN scores at inference: wish-filtered
  plays plus pass when legal. Bookkeeping rows without features:
  `{"round_end": true, "round", "team_one_round", "team_two_round"}` and
  `{"episode_end": true, "winner", "team_one_total", "team_two_total"}`.
  `bc_pretrain.py` consumes this.

(`csv` and `none` are still around for ad-hoc debugging and dry runs.)

### Other headless flags

- `--schupf-net`, `--pre-tichu-net`, `--schupf-epsilon`, `--skip-play-rows`,
  `--shadow-heuristic`: see the scripts above. `TICHU_HEADLESS=path` makes
  the Python scripts use another runner binary.

- `--mixed` uses team0 = NN, team1 = heuristic (for evaluation).
- `--swap-teams` puts the policy on the odd seats instead (duplicate eval).
- `--deal-seed=N` deals from `Random(mix(N, episode))`, so deals depend only
  on the seed and episode number, not on agent decisions or shard count.
- `--episode-offset=N` numbers episodes from N+1 (set per shard by
  `headless_runner.py` so episode ids are unique in merged output).
- Unknown arguments are rejected (exit 64).
- `--nn-policy=path.safetensors` loads a trained policy.
- `--opponent-policy=path.safetensors` (with `--mixed`) lets team1 be a
  separate NN — used by self-play to pit candidate vs best.
- `--epsilon=0.1` ε-greedy exploration during dataset generation (play
  phase only; Grand Tichu calls and Dragon gifts are never randomised).
- `--ismcts`, `--ismcts-simulations=N` Information-Set MCTS player.

## Results (2026-11-15, CPU, 4 cores)

All evaluations: duplicate, 200 deal sequences (400 matches), target 500,
seed 12345, vs the heuristic. ± is one standard error.

| Policy | Win rate | Paired vs AWR best |
|--------|----------|--------------------|
| BC (1500 heuristic games, 30 epochs, 94 % imitation) | 46.6 % ± 2.1 | — |
| AWR self-play, 4 iterations × 800 games (2 promoted) | **51.4 % ± 2.2** | baseline |
| + Tichu call net (1500 games, call-ε 0.15) | 49.8 % ± 2.2 | −1.6 ± 2.1 pp |
| + Grand Tichu call net | 51.1 % ± 2.2 | −0.3 ± 1.3 pp |

A/B from call exploration: the heuristic's Tichu calls are worth
+8.4 ± 5.2 pts/round vs not calling; a Grand Tichu call on an arbitrary
hand costs ≈ 71 pts. The call nets match the heuristic but do not beat it
yet (the round outcome is very noisy; they need more data).

## Next steps

To beat the heuristic by a wider margin requires one of:

1. A search head at inference (IS-MCTS with the policy as prior; the value
   net already replaces rollouts at the leaves).
2. More AWR self-play iterations / data (see `self_play.py`).
3. NN decisions for schupf, Dragon gift and wish (still heuristic).

## Output contract

- `rl/outputs/` keeps only `*.safetensors` artifacts.
- Intermediate JSONL is written to the OS temp dir and removed.

## Notes

- Targets are normalised before MSE training using `target_mean` and
  `target_std` (stored in safetensors metadata; Dart `Mlp.fromSafetensorsBytes`
  reads them back). BC pretrain uses `mean=0`, `std=1` and trains on raw
  Q-logits via cross-entropy.
