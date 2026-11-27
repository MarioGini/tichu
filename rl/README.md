# RL workflow

Python (`uv` + CPU PyTorch, Linux only) trains the nets; Dart encodes every
feature and plays every game (`lib/headless/`). Artifacts are
`.safetensors`. Run everything from the repo root. Past results and
findings are in `rl/REVIEW.md`, and the shipped nets are listed in
`rl/models/README.md`.

## Setup

```bash
uv sync --project rl
# without access to download.pytorch.org (cloud sandbox):
uv venv rl/.venv
VIRTUAL_ENV=rl/.venv uv pip install "torch>=2.15.0" "numpy>=2.5.4" "safetensors>=0.8.0"

dart compile exe lib/headless/headless.dart -o build/bin/headless   # before any RL command
```

The Python scripts use `build/bin/headless`; set `TICHU_HEADLESS=path` to
use another binary. `TICHU_TORCH_THREADS` limits the trainer's threads, for
example when it shares the 4 cores with game generation.

## The bots

| | Play net | Schupf | Search |
|---|---|---|---|
| shipped (app) | `tichu_q_v10` (431 inputs, schema v9) | `tichu_schupf_v5`, extended candidates | search ≤ 12 cards with belief worlds (`tichu_belief_v1`), 1-on-1 solver |
| previous | `tichu_q_v8` (376 inputs) | `tichu_schupf_v4` | search ≤ 8 cards, 1-on-1 solver |

`lib/agents/bot_config.dart` (`BotConfig`) builds every bot, in both the
app and the headless runner. The play net scores every legal play plus pass
(`NnPlaySelectionStrategy`). Hard rules stay in `SmartAiAgent`: go out when
you can, and honour the wish. The Tichu and Grand Tichu calls and the
choice of wish are heuristic (`DefaultTichuCallStrategy`). Dragon gifts go
to the solver when it applies; otherwise the heuristic picks.

## Feature schema

`rl/schema/feature_spec.json` (v9) is the single source of truth. It
defines 431 inputs, 373 for the state and 58 for each action. Dart
(`lib/agents/nn/feature_encoder*.dart`) is the only encoder, and
`test/agents/feature_layout_test.dart` asserts that Dart matches the spec.
To change the schema: **edit the JSON, then the Dart encoder, then run the
Dart tests.**

State groups:

- hand, played, unseen, trick, seats, self, hand_structure;
- history: per opponent and partner, the cards played and what they passed on;
- off_turn;
- claim: the safe-finish analysis;
- received: the schupf cards received;
- passed: the cards I passed that the receiver still holds.

Action features cover:

- the type and strength of the play;
- the cards it uses and the hand it leaves;
- the claim of the hand after the play;
- beatability: how many unseen plays beat it, the share of unseen cards
  that beat it as a single, and whether the left or right opponent can
  answer.

Older nets still load as a prefix of the current layout (Dart
`playNetLayout`: 427 / 376 / 319 / 318 / 252 inputs). For example, v8
plays exactly the same games as before.

## Training: rollout policy iteration

```bash
rl/.venv/bin/python rl/rollout_loop.py --out-dir=rl/outputs/v10 --iterations=6 \
  --init-policy=<net> --schupf-net=assets/bots/tichu_schupf_v4.safetensors \
  --opponent-nets="assets/bots/tichu_q_v8.safetensors;<older net>" \
  --mixed-episodes=1700 --self-episodes=500 --shards=2 \
  --gate=panel --duel-deals=600 --epochs=3 --upload-run=v10
```

How one iteration works:

1. **Labels.** `headless --rollout-rate=0.5` forks the round once for each
   legal action and plays each fork to the end with the current bots. Only
   the net sees partial information; the rollouts see every hand.
2. **Training.** `rollout_train.py` regresses the advantages, centred over
   the legal actions.
   - It trains on **all** caches and weights older iterations less
     (`--recency`, from the `itNN_` prefix).
   - It holds out whole matches.
   - It applies suit-permutation augmentation.
   - It warm-starts from the previous net.
3. **Gate.** The candidate is promoted when its mean gain over a panel of
   opponents clears `--promote-z`. The panel is the best net, the league and
   the fixed opponent nets; `--gate=panel` turns this gate on. Duels go
   through a duel cache. In the loop, `--allow-worse` is set, so the duels
   decide, not the held-out score.
4. **Restart-safe.** Every step whose output exists is skipped, so the
   loop can be killed and restarted at any time. Background jobs here are
   limited to 2 hours.

`--schupf-episodes=N` retrains the schupf net after an iteration.

Other trainers:

- `schupf_cf_train.py`: exact counterfactual schupf labels.
- `schupf_train.py`: the base trainer.
- `call_train.py`: call-value nets; `call_labels.sh` generates their labels.
- `belief_data.py` / `belief_train.py`: the belief net, which maps the state
  to a holder probability for each card.

## Data: always the latest layout

- **Caches record `schema_version`.** On load, `rl/data_upgrade.py` pads
  missing groups and computes the ones that follow from older features
  (`UPGRADES`). Groups it cannot recover are listed in `UNRECOVERABLE` and
  reported (today: `passed` for data from before v8).
- **When you add features**, either write an upgrade function or list them
  as unrecoverable. Never train new inputs on fresh data alone: v9 stalled
  that way, and v10 took off once all the old data was rebuilt.
- **Every data run records its games** (`--record-games`): one row per round
  with the deal and every action. The caches keep `pos` (round, step). The
  loop stores `<file>.games.jsonl.xz` next to each cache and uploads both.
- **Replay** recomputes any future feature from these records:
  `lib/headless/replay_game_records.dart` replays a records file and checks
  that the features and round results are identical.

Storage is Supabase Storage: bucket `rl-training-data` (private) plus the
manifest table `rl_training_files`. Arrays are stored uncompressed inside
xz, which is about 2.3× smaller than a zipped npz. Usage is about 0.43 of
the 1 GB free tier.

```bash
rl/.venv/bin/python rl/training_data_store.py list
rl/.venv/bin/python rl/training_data_store.py upload --run=v10 rl/outputs/v10/data/*.npz
rl/.venv/bin/python rl/training_data_store.py download --run=v10 --dest=rl/outputs/v10/data
rl/.venv/bin/python rl/training_data_store.py delete --run=<run>
```

Only the secret key can access the store. In a cloud session it is a
network secret for the project host (header `apikey`).

## Evaluation

```bash
rl/.venv/bin/python rl/duel.py --a="--nn-policy=A.safetensors --endgame-search" \
    --b="--opponent-policy=assets/bots/tichu_q_v8.safetensors --opponent-endgame-search" --deals=600
```

Duels are duplicate: every deal sequence is played once with each seating
(`--deal-seed`). The result is the share of matches won and the margin per
match, each with its standard error. Ship rule: the new bot wins 60–70 % of
duplicate matches against the shipped one.

Diagnostics:

| Script | Shows |
|---|---|
| `style_report.py` | style metrics |
| `policy_evolution.py` | nets compared on the same positions |
| `schupf_report.py` | what is passed to whom |
| `call_audit.py` | call rates and outcomes |
| `review_1v1.py` + `lib/headless/review_one_on_one.dart` | one-on-one play compared with the solver |

## Search at decision time

The drivers run the search (headless `_selectAction`, the app's
`AiTurnRunner`) through `EndgameSearcher` (`lib/agents/endgame_search.dart`),
after the bot has chosen its move.

- **Worlds.** Re-deal the unseen cards consistently with what is known.
  With `beliefWorlds` the deal is weighted by the belief net. Play every
  candidate move out in 8 worlds, and deviate from the net's move only if
  another move is no worse in every world and better by a margin.
- **Solver.** `OneOnOneSolver` (`lib/agents/endgame_solver.dart`) plays
  one-on-one endgames exactly by minimax, up to 10 cards and a position
  budget, and also decides the Dragon gift.

Headless flags for search:

- `--endgame-search`, `--endgame-max-cards`, `--endgame-worlds`,
  `--endgame-margin`;
- `--endgame-solve`, `--solve-budget`, `--solve-max-cards`;
- `--belief-net`, `--endgame-belief`;
- every flag has an `--opponent-*` twin for the other team.

Other headless flags:

- `--format=summary|bc-jsonl`;
- `--rollout-rate`;
- `--schupf-net`, `--schupf-extended`;
- `--record-games`;
- `--describe`;
- `--deal-seed`.

The runner rejects unknown arguments.

Speed: about 10 net matches per second per core without search. Searching
makes a match 4–10× slower, so training data is generated without search.
