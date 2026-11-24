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

The shipped bot is play net `assets/bots/tichu_q_v8.safetensors` with schupf
net `assets/bots/tichu_schupf_v4.safetensors` and endgame search (see
`rl/models/README.md`). The play net is trained by **rollout policy iteration**
(`rollout_loop.py`, see "Rollout policy iteration" below).

**Before any RL command, compile the Dart headless runner once.** Every
Python script auto-detects `build/bin/headless` and uses it; without
this you pay a 2.5 s VM cold-start per invocation.

```bash
dart compile exe lib/headless/headless.dart -o build/bin/headless
```

Continue training the current policy (restart-safe, ~50 min per iteration on
4 cores; everything goes to `rl/outputs/rollout_loop/`):

```bash
rl/hill_climb.sh                              # start / resume in the background
tail -f rl/outputs/rollout_loop/loop.log
```

Measure any two bots against each other (duplicate deals, both seatings):

```bash
rl/.venv/bin/python rl/duel.py --a="--nn-policy=assets/bots/tichu_q_v7.safetensors" \
    --b="--opponent-policy=old_policy.safetensors" --deals=1000
rl/.venv/bin/python rl/duel.py --a="--heuristic=latest,lowLeadPreference:4" \
    --b="--opponent-heuristic=latest" --deals=5000     # heuristic A/B
```

To regenerate a policy from scratch, start with behaviour cloning
(`bc_pretrain.py`, below) and run `rollout_loop.py --init-policy=...` on it.

### Performance notes

- Heuristic games run at ~25 matches (to 1000) per second and core, games of
  the play net at ~10: a 2000-match duplicate duel takes one to two minutes
  on 4 cores, a rollout-labelled play decision ~10 ms.
- This is 20x (heuristic) / 10x (net) faster than before 2026-11-16. Three
  things did it: bots used to brute-force every subset of the hand before
  passing (`LegalPlayGuard.firstLegalTurnBruteForce`, 90 % of the run time);
  the net now shares the state prefix of the first layer across the legal
  actions and skips zero inputs (`Mlp.prefixScorer`); and the headless runner
  uses 4-wide float32 SIMD (`Mlp.simdPrefixScorer`, `--no-simd` to turn off).
- Rollout labels got 2x cheaper on 2026-11-20 with byte-identical output
  (19.2 -> 9.3 ms per labelled decision, 10 v7 self-play matches at
  `--rollout-rate=0.5`, one process on a loaded machine): an exact bit-mask
  bomb check before the full bomb search (the snapshot's UI-only bomb maps
  were 18 % of the time), a register-blocked SIMD scorer without bounds
  checks (same float32 operation order), typed feature buffers, and leads
  that build straight candidates once. Where the time goes now: NN scoring
  ~52 % (`score` + `setPrefix`), move generation ~11 %, feature encoding
  ~17 %, snapshots ~6 %; fork copies, agent construction and JSON rows are
  each under 2 %.
- `headless_runner.py` shards an episode count across N processes (one per
  shard, distinct seed), then concatenates the JSONL output.
- Training stays on **CPU**: the ~100k-param net is too small to benefit from
  a GPU, so the project installs the CPU-only PyTorch build.

## Background: how similar games are learned

Tichu is a 4-player, 2-team climbing ("shedding") card game with hidden
hands — the same family as Dou Dizhu, Guandan and Big Two. What works there:

- **DouZero** (Dou Dizhu, ICML 2021): Deep Monte Carlo — a Q(s, a) network
  with an explicit action encoding, trained on whole-game returns from
  massive ε-greedy self-play. Simple, and it beat every earlier Dou Dizhu AI.
  (`q_train.py`, removed, was one step of this.)
- **PerfectDou** (NeurIPS 2022): perfect-training / imperfect-execution — the
  critic sees all hands during training, the policy does not. That removes
  card luck from the learning signal; it beat DouZero with ~10× fewer
  samples. Here: the `oracle` field and oracle baselines (`oracle.py`) in
  `call_train.py`, `schupf_train.py`.
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
generation dominates the run time; the nets are small MLPs, so training
stays on CPU.

## Architecture

### Feature schema (single source of truth)

`rl/schema/feature_spec.json` (v7) defines the 376-dim feature vector
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
| history         | 66   | 201-266 | per other player: cards played, passes (below)   |
| turn            | 1    | 267     | `off_turn`: deciding out of turn (v6)            |
| claim           | 3    | 268-270 | safe-finish analysis of my hand (v7, below)      |
| received        | 51   | 271-321 | schupf card received per sender, by rank (v7)    |
| action          | 54   | 322-375 | type, strength, beaters, cards used, hand after; |
|                 |      |         | 373-375: claim analysis of the hand after (v7)   |

`history` (new in v5) comes from the engine's public round log
(`lib/game/round_log.dart`: every play and pass with the trick it answered).
Per other player (left, partner, right; 22 each): the cards they played this
round as a rank histogram, the lowest single and the lowest pair they passed
on while one of their opponents was winning the trick, and the number of such
passes. Before v5 the net could not tell who played or passed on what, so it
could not read hands from the play.

`claim` (v7, `lib/agents/claim_analysis.dart`): a claim partition splits the
hand into legal leads (the move generator's combinations, the Phoenix as a
wildcard where it allows) such that all but at most one are unbeatable, so
holding the lead the player cashes the unbeatable ones and goes out with the
last. Unbeatable = no unseen non-bomb combination beats it (the action
feature `unbeatable`, recomputed every decision, so a pair of kings becomes
unbeatable once no two aces / ace + Phoenix are unseen); bombs and the Dragon
count as unbeatable, the Dog as beatable (it gives the lead away, so it is
only safe as the last play). Features: `claim_min_beatable` = the minimum
over partitions of the beatable combinations, capped at 4 (/4);
`claim_unbeatable` = the unbeatable combinations in such a best partition
(capped at 7, /7; 0 when the cap 4 is reached); `claimable` = min beatable
<= 1. The action group ends with the same three for the hand after the
action (`after_claim_*`; pass = the current hand). Exact search: a
rank-count dynamic programme (straight flushes chosen first), memoised
across decisions per unseen-threshold signature, pruned by a lower bound
(ranks held once that no unbeatable combination can contain) wherever 4
beatable combinations are certain; a brute force over the generator's leads
agrees on 1500 random positions (`test/agents/claim_analysis_test.dart`).

`received` (v7): the card received in this round's exchange from left,
partner and right, one-hot over the 17 rank classes (2..A, Mah Jong, Dog,
Phoenix, Dragon); zero before the exchange (outside the play phase).

Older layouts keep loading and playing unchanged. Each is a prefix of the
current state part plus the first 51 action features: v4 (252 inputs: state
0-200), v5 (318: state 0-266; the v5-v7 policies), v6 (319: state 0-267).
Dart (`playNetLayout`) gives such a net exactly those inputs and skips the
claim search; Python (`rl/schema` `widen_first_layer`, used by
`load_qnetwork_from_safetensors` and `rl/widen_net.py`) widens them with
zero weights for every new input (identical play), and `pad_state` /
`pad_action` pad old data (state 201 / 267 / 268 wide, action 51 wide) with
zeros. Verified: v7 widened to 376 inputs plays the same games as v7.
The call nets' input (`callFeatureCount` = state + received cards) follows
the state part, so call nets / call data of v6 and earlier need retraining
(none is shipped).
Speed (one process, 5 v7 self-play matches, `--rollout-rate=0.5`, median
CPU ms per labelled decision over 5 interleaved runs on a loaded machine):
before v7 12.3; v7 with the new encoder 12.4 (older nets skip the claim
search); a v7-layout net (v7 widened, which computes and reads every new
input) 13.6, i.e. +11 %, about two thirds of it the claim search (the
lower-bound pruning, the cross-decision memo and memo lookups of the
after-action hands by key arithmetic took it down from +17 %).

Only Dart encodes features (`lib/agents/nn/feature_encoder.dart`); the
headless `--format=bc-jsonl` output carries them pre-encoded, so Python never
re-encodes. Python rejects nets of another layout at load time.

The Python loader is `rl/schema/__init__.py`; the Dart constants live in
`lib/agents/nn/feature_encoder.dart` and are asserted against the JSON spec
by `test/agents/feature_layout_test.dart`. **Edit the JSON, then the Dart
encoder, then run the Dart tests.** Mismatches caused a silent, catastrophic
bug in the previous iteration (action features ended up at different
indices on each side, so trained nets saw zero action information at
inference time).

### Rollout policy iteration (the current trainer)

Why the earlier loop stalled, measured with exact rollouts:

- Per decision, the round result differs between two legal actions by about
  ±80 points on a single deal (who wins a trick cascades into Tichu bonuses
  and double wins), while the *expected* difference a policy can exploit is
  a few points. v3's whole edge over the heuristic (74.6 % of matches) is
  +1.5 points per decision; they agree on 82 % of moves.
- The old DMC step (`q_train.py`, removed) saw one return for one action
  per decision and explored 5 % of moves at random, on 600 games per
  iteration: far too little signal to rank the actions it rarely tried, so
  the policy stayed close to its behaviour-cloning start.
- Promotion was decided on 100 deals (± 2.8 pp), which cannot see the
  2-5 pp steps that add up.

The fix is to label **every** legal action exactly, and a lot of them:

1. `headless --rollout-rate=p`: for a sampled play decision the round is
   forked once per legal action and played out by the current bots
   (`q_rollout`, same deal, deterministic policies — no card luck in the
   differences). The rollout sees the true hidden hands, the net only public
   information: perfect-information training, imperfect-information
   execution as in PerfectDou, with a rollout instead of a learned critic.
   Averaged over deals the net learns E[Q | information state].
2. `rollout_train.py`: regression on per-decision **advantages** (targets
   and outputs centred over the legal actions, so the value of the deal
   never enters the loss), suit-permutation augmentation, warm start from
   the previous net. Greedy play on the result is one exact
   policy-improvement step.
3. `rollout_loop.py`: iterate. Data comes from games against fixed nets
   (`--opponent-nets`), the league and, optionally, heuristic variants
   (`--opponents`, none by default), both seatings, and from self-play; the data of
   earlier iterations is kept (training on all 318k decisions beat training
   on the newest 121k by 4 pp). A candidate is promoted when it beats the
   best net in a duplicate duel by more than 2 standard errors.

The exported net has the same inputs and layers as before and plugs into
`NnPlaySelectionStrategy` unchanged.

Trainer details since v7 (2026-11-19):

- **Held-out split by match.** Decisions of one round share the deal and so
  most of the label noise; a per-decision split leaked it into the held-out
  set and early stopping kept overfitted epochs. `rollout_train.py` now holds
  out whole matches (the `game` column of the cache; old caches fall back to
  contiguous blocks of 256 decisions).
- **Recency weights** (`--recency=r`): data of an earlier iteration is a
  value under an older policy; a file `itNN_*` gets loss weight
  `r ** (newest - NN)`. Default 0.8.
- **League** (`rollout_loop.py --league=K`, default 2): every net replaced
  by a promotion joins `pool/` and the K newest pool nets become extra fixed
  opponents for data and measurements.
- **Confirmation duel** (`--confirm-deals=N`, default 1000): a candidate that
  passes the gate must also win a second duel on fresh deals, and the pooled
  result must clear `--promote-z`.
- **Wider nets from a warm start** (`rollout_train.py
  --widen-hidden=512,256,128`): Net2Net-style growth of the hidden layers,
  the wide net plays exactly like the narrow one before training.
- Two-sided comparison: `compare_policies.py --jsonl-b=...` also measures the
  gain on B's games with B continuing (A-continued rollouts flatter A).

### Stakes-weighted rollout labels (2026-11-20, removed)

Tried: label probability by a stakes class from public information (high:
the race to go out, someone out, a player with 1-3 cards or own hand <= 5;
mid: a caller still in, a lead or a trick worth >= 20; low: the rest), at
the same label budget as a uniform `--rollout-rate=0.5` (~74 / 20 / 6 % of
the labels instead of 52 / 30 / 18 %), optionally with 1/p importance
weights in the trainer. A/B on the same iteration (v7 iteration 5, same
seeds, start net, league and label budget), duplicate duels, 2000 fresh
deals x 2:

| Candidate | vs iteration 4 |
|-----------|----------------|
| uniform labels (rate 0.5) | 50.9 % ± 0.6 |
| stakes labels, no importance weights | 51.1 % ± 0.6 |
| stakes labels, importance weights 1/p | 50.4 % ± 0.6 |
| stakes vs uniform, head to head | 50.5 % ± 0.6 |

Held-out gain moved as expected (high +0.57 vs +0.48 points per decision,
low -0.21 vs +0.23), but the duels did not: the extra high-stakes labels are
worth no more than the quiet ones they replace. The code (`--stakes-rollouts`,
`--stakes-rates`, `rollout_train.py --importance`, the `stakes` / `label_p`
columns) was deleted on 2026-11-22; npz caches that still carry those
columns load and ignore them.

### Training data in Supabase Storage

Data caches are compressed npz (~115 bytes per decision, ~28 MB per
iteration of 245k decisions), so all iterations fit in the free 1 GB of
Supabase Storage. Bucket `rl-training-data` (private) plus a manifest table
`public.rl_training_files` (`supabase/migrations/20261119000000_rl_training_data.sql`):

```bash
export SUPABASE_SECRET_KEY=sb_secret_...       # Dashboard -> Settings -> API Keys
rl/.venv/bin/python rl/training_data_store.py upload --run=v7 rl/outputs/v7/data/*.npz
rl/.venv/bin/python rl/training_data_store.py list
rl/.venv/bin/python rl/training_data_store.py download --run=v7 --dest=rl/outputs/v7/data
rl/.venv/bin/python rl/rollout_loop.py ... --upload-run=v7   # upload while training
```

Only the secret key can read or write the bucket and the table (RLS on, no
policies). In a cloud session, store the key as a network secret for the
project host (header `apikey`) instead of the environment variable.

### Training pipelines

Shared modules: `qnet.py` (the Q(s, a) MLP, batched BC loss, safetensors
load/export), `bc_data.py` (flat dataset from bc-jsonl), `oracle.py`,
`headless_runner.py`, `schema/`.

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

2. **`call_train.py`** — call-value nets. Data comes from
   `headless --call-epsilon=p`, which flips Tichu / Grand Tichu decisions
   with probability p (first Tichu opportunity per player and round) and
   logs `{"call": "tichu"|"grand", "called", "state_features", ...}` rows.

   ```bash
   rl/.venv/bin/python rl/call_train.py --generate --episodes=1500 \
       --target-score=500 --call-epsilon=0.15 \
       --nn-policy=assets/bots/tichu_q_v7.safetensors --output-dir=rl/outputs
   ```

3. **`schupf_train.py`** — schupf value net Q(hand, pass) on
   `SchupfFeatures` (232: hand bitmap, one-hot card to left / partner /
   right, `[grand, tichu]` call flags for me / partner / left / right).
   Data: `headless --schupf-epsilon=p` (mostly one card swapped). Dart's
   `NnSchupfStrategy` scores all 2184 assignments with an incremental first
   layer.

4. **`rollout_loop.py`** / **`rollout_train.py`** — rollout policy
   iteration for the play net (above).

5. **`analyze_games.py`** — duplicate games vs the heuristic with
   `--shadow-heuristic`: round stats per side (going out first, double wins,
   call rates and success) and where / how often the policy's moves differ
   from what the heuristic would have played.

6. **`duel.py`** — duplicate duel between any two bot configurations
   (nets and / or heuristic variants).

7. **`call_labels.sh`** — background generation of exact counterfactual
   call labels with the current best policy, for `call_train.py`.

### Heuristic lab

The same rollout labels score heuristic rules exactly:

- `headless --shadow-heuristics=specA|specB|...` logs, for every labelled
  decision, what each heuristic variant would have played. One dataset then
  gives the exact one-step value (points per decision) of all variants.
- `--heuristic=` specs: `latest` (the heuristic as written) and
  `weight:value` to override a `TurnScorer` weight, e.g.
  `latest,lowLeadPreference:4`. The heuristic's rules are unconditional
  (the rule switches were removed on 2026-11-22).
- `--describe` adds a readable position (hands, trick, legal actions) to
  labelled rows; `--label-seats=policy|opponent|all` chooses whose decisions
  are labelled.

Calibration: +0.1 points per decision is worth about +1.5 pp match win rate.

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

`duel.py` is duplicate: every deal sequence is played twice with the same
deals (`--deal-seed`), once per seating, and the result is the per-deal
average with its standard error. `rollout_loop.py` promotes a candidate only
if it beats the best net by more than `--promote-z` SEs.

### Headless output formats

Only two RL-relevant formats remain:

- **`--format=summary`** — one JSONL line per finished match.
  `duel.py` consumes this. ~50 lines for a 50-match eval.
- **`--format=bc-jsonl`** — one JSONL line per play-phase decision with
  ≥2 legal actions: `episode`, `round`, `team`, `state_features` (267 floats),
  `legal_play_action_features` (n × 51 floats), `legal_play_chosen_index`,
  and `explore: true` when the move came from ε-exploration (BC skips those).
  The legal set is exactly what the NN scores at inference: wish-filtered
  plays plus pass when legal. Bookkeeping rows without features:
  `{"round_end": true, "round", "team_one_round", "team_two_round"}` and
  `{"episode_end": true, "winner", "team_one_total", "team_two_total"}`.
  `bc_pretrain.py` consumes this.

(`csv` and `none` are still around for ad-hoc debugging and dry runs.)

### Other headless flags

- `--rollout-rate=p`, `--rollout-max-actions=N` (default 12): exact values
  of every legal action for a share p of the labelled seats' play decisions
  (`q_rollout`; only labelled play rows are written then).
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

## Results v3 (2026-11-16): Q-learning beats the heuristic

Joint loop (`train_loop.py`, since removed) from a BC policy of the improved heuristic
(hand-strength Tichu calls, partner guard, plan-aware play, fixed scoring).
All numbers: duplicate, matches to 1000, vs the latest heuristic.

| Bot | Win rate | Avg margin |
|-----|----------|-----------|
| BC of the heuristic | 44.2 % ± 2.8 | −27 |
| + Q step (DouZero-style, oracle baseline), iteration 1 | 72.4 % ± 2.0 (fresh deals) | +303 |
| + second promoted Q step | 74.2 % ± 2.6 (loop eval) | +277 |
| **Final: Q play net, heuristic calls + schupf** | **70.8 % ± 1.9** (fresh deals, 400 matches) | **+280** |

- AWR steps never beat the Q steps (AWR was removed); the Q step is the
  learner that works.
- Learned call nets *hurt* (−6.0 ± 2.2 pp vs heuristic calls on fresh
  deals; an earlier promotion at +1 SE was a false positive — promotion now
  needs 2 SE). Learned schupf nets were always clearly worse (−13 to −31 pp).
- The policy plateaus around 74–75 % at ~600 play games per iteration.

## Results v4 (2026-11-17): rollout policy iteration

Duplicate duels (`duel.py`), 1000 deal sequences x 2 seatings, matches to
1000. "Classic" is the heuristic v3 was trained against, "latest" the tuned
heuristic of 2026-11-17 (both from before the rule deletion below; build the
runner from commit 92aed27 to reproduce them).

| Net | vs classic | vs latest | vs v3 | vs previous |
|-----|-----------|-----------|-------|-------------|
| v3 | 74.6 % ± 0.9 | 64.1 % ± 1.0 | — | — |
| iteration 1 (197k decisions, vs classic) | 81.9 % ± 0.8 | | 57.3 % ± 0.9 | 57.3 % |
| iteration 2 (+121k, a third self-play) | 92.7 % ± 0.6 | 86.3 % ± 0.7 | 74.3 % ± 0.9 | 67.3 % |
| iteration 3 (+120k, classic / latest / self-play) | 94.2 % ± 0.5 | 90.5 % ± 0.6 | 79.2 % ± 0.8 | 56.8 % |

Later iterations: `rl/outputs/rollout_loop/history.json` and
`rl/models/README.md`.

Heuristic (6000-match duels): latest beats classic 61.6 % ± 0.5 (the
cheapest-combo rule alone 58.9 %), but still loses to v3 (35.9 %). What the
lab showed:

- Classic wasted strength: A-A-A-x-x on a full house that Q-Q-Q-x-x beats,
  K-K on a pair of fives when 6-6 is enough, 4-4-4-J-J led instead of
  4-4-4-9-9. Playing the cheapest multi-card combination of the chosen type
  is worth +0.3 points per decision both leading and following.
- About half of the 23 `TurnScorer` weights and several shortcuts
  (`valuable_bomb`, `plan_bombs`, `wish_pref`, the Phoenix bonuses, the
  opponent-low terms, `trickPointCapture`, `supportPartnerTichu`,
  `givePartnerLead`, ...) change fewer than 1 in 2000 decisions and have no
  measurable value: they can be deleted.
- No further coarse rule helped. "Always pass on the partner's trick",
  "save Aces / Dragon / Phoenix early", "lowest single first", "block an
  opponent with one card" all lose points with the heuristic behind them.
  The net's edge over the heuristic (+2.4 points per decision) is selective:
  it passes on 9 % of the opponents' singles where the heuristic plays, but
  no simple condition separates those positions.
- Calls: refitting the Tichu rule on 39k exact counterfactual labels gives
  at most +1 point per decision (needs interaction terms); a linear Grand
  Tichu rule is worth +1.1 ± 0.45 (the heuristic never calls it).

## Review of v4's games (2026-11-17)

`rl/review_games.py` labels v4's own decisions with exact rollouts (every
legal move played out on the same deal) and breaks them down. On 28,000
decisions of v4 against itself:

- **The endgame is not where v4 loses.** With 3 cards or fewer it plays the
  best move on the actual deal 77 % of the time and this phase holds 5 % of
  the total regret; most of the rest needs the hidden cards. Twelve simple
  endgame rules (lead the highest single against a one-card opponent, never
  pass after calling Tichu, pass on the partner's trick, ...) were all equal
  or worse than v4's own choice.
- 82 % of the regret is with 7+ cards in hand, the largest per decision on
  early leads (best move only 31 % of the time). That is mostly hidden
  information: v4 had no way to read hands from the play (see `history`).
- One improvement step on v4's self-play gains +3.2 points per round,
  spread thinly: +2.6 card points, +0.5 % double wins, +0.9 % Tichu success.
- Nobody called Grand Tichu. A simple rule (strength >= 5 in eight cards)
  is worth +2.0 pp for the heuristic and +0.9 pp with v4's play.

Best response to v4 (layout v4, `rollout_loop.py --opponent-nets`): one step
on v4's self-play 53.2 % ± 0.9 against v4, a second step on games against v4
57.9 % ± 0.9 (margin +88).

History features, A/B on identical data (143k decisions of games against
v4, same start net, history inputs zeroed for the control). With the Grand
Tichu rule both teams now call it, which adds variance, so all numbers below
are from the new runner:

| Net | vs v4 | vs heuristic |
|-----|-------|--------------|
| start (the 57.9 % net, widened) | 54.9 % ± 0.9 | |
| + step, without history | **57.3 % ± 0.9** | 89.7 % ± 0.6 |
| + step, with history | 55.6 % ± 0.9 | |
| v4 | — | 88.2 % ± 0.7 |

Head to head, with history vs without: 48.7 % ± 0.9. At this data size the
history features do not help yet; their 66 inputs start at zero weight and
the advantage targets are noisy (± 90 points per action and deal). The best
net is shipped as `assets/bots/tichu_q_v5.safetensors` (v4 removed).

## Schupf and calls (2026-11-17)

Exact labels for the exchange: `headless --schupf-rollout-rate=1` plays each
labelled round out once per candidate pass (16 of the ~150 sensible passes
from `SchupfFeatures.candidates`). `rl/schupf_analysis.py` on 25,820 decisions
of v5 self-play (values = points per round relative to the deal's average
candidate):

- To the opponents: low cards 2-6 +2, the Dog +5.5 (opponent Tichus succeed
  2 pp less, my own Tichu calls +3 pp; +39 when my hand is strong and my
  partner's weak), J or higher -9.
- To the partner, "concentrate on the strong hand": with a strong hand of my
  own, keep the strength and pass a low card (+31); passing the Phoenix then
  costs -33 because it moves the Tichu from me to my partner (my calls -22 pp,
  partner's +13 pp). With a weak hand, give the partner my best card (Phoenix
  +12..19, Ace +3..5). The Dog to the partner costs -10 overall.
- The heuristic's pass is already +22 points per round better than an
  average sensible pass; the learned net (`schupf_cf_train.py`) adds +7 ± 2.5
  on held-out deals and wins 55.0 % ± 0.8 in duels against the same bot with
  the heuristic schupf. Retrained on 51,600 decisions (half generated with
  the learned schupf in place) it beats that bot again, 54.0 % ± 0.7:
  shipped as `assets/bots/tichu_schupf_v2.safetensors`.
- Against an opponent's Grand Tichu (2,012 decisions): the Dog to the caller
  +29 points (their success 75 % -> 65 %), the lowest card +8, J or higher
  -23, the Mahjong -14; strength to the partner (Phoenix +19). The heuristic
  already passes the Dog to the caller; the learned schupf beats the
  heuristic's pass by +17 points per round in these deals.
- Comparisons now default to the shipped bot (`rl/duel.py` side B =
  v5 + learned schupf); the heuristic is too weak to tell strong bots apart.

Calls, exact counterfactual labels from 34k Grand Tichu and 33k Tichu
decisions with v5 playing (`rl/call_analysis.py`):

- Grand Tichu: the rule (strength >= 5) is worth +0.97 ± 0.28 points per
  decision; 4.5 is equal (+1.12). A conservative rule (>= 7) wins +55 per call
  but calls 0.9 % of the time and is worth half as much (+0.49). Hands of
  strength 3-4 lose 46 points per call. After a Grand Tichu the heuristic
  already passes the caller's partner a low card and the partner passes the
  caller their best card.
- Tichu: the current rule +4.14 ± 0.34; the best threshold tried +4.49.
- Learned call nets on the same labels (decision-focused training in
  `call_train.py`) do not beat the rules (Tichu +2.8, Grand Tichu +0.9).
  Perfect calling would be worth +50 / +82: the rest depends on cards the
  caller cannot see.

Why better Tichu calls are worth so little (2026-11-17 review). Exact call
values on the real deal; current rule (strength >= -0.1) +3.99 to +4.12
points per decision:

| Call method | value vs the rule (pts/decision) |
|-------------|----------------------------------|
| success model P(first \| call) on the hand after the schupf, 65k decisions (`call_success_train.py`) | +0.41 ± 0.23 |
| same model also given all four hands (`--oracle`) | +0.55 ± 0.26 |
| decision-time simulation: both branches played on 16 guessed deals of the unseen cards (`--pimc-worlds`, `pimc_calls.py`) | -1.9 ± 0.8 (best variant +0.7 ± 0.3, rule and simulation agreeing) |
| knowing the outcome | +44 |

Deciding at the last moment (the call is made in the turn the
bot plays its first card; 75 % of these decisions see at least one card
played, 22 % see 11 or more) does not change this: the success model there is
+0.39 ± 0.26 over the rule (AUC 0.802, 48.6k decisions), and with the rule the
delay itself is neutral (49.9 % ± 0.4).

Seeing every hand barely helps (AUC 0.797 -> 0.812), and simulating on
guessed deals correlates only 0.27 with the real value: whether a call
succeeds is decided by how the round is played (it is chaotic), not by
information a player could have. The strength rule is already near the
practical ceiling, so learned call models were dropped (a +0.4 model was
briefly shipped and removed).

## Results v6 (2026-11-18): best response to v5, better trainer

Three iterations of `rollout_loop.py` against v5 (outputs in
`rl/outputs/v6/`, not in git). Per iteration ~245k labelled decisions:
2400 matches against v5 (both seatings, only the learner's seats labelled)
and 1000 self-play matches; training uses the data of all iterations.
Duplicate duels, 2000 deals x 2 seatings, matches to 1000, both sides with
the learned schupf v2:

| Net | vs previous best | vs v5 |
|-----|------------------|-------|
| iteration 1, old trainer (8 epochs, last epoch kept) | | 53.9 % ± 0.6 |
| iteration 1 data, same start, win-probability targets + EMA | | 54.9 % ± 0.6 |
| iteration 1 data, same start, EMA + best of 4 epochs | | 56.2 % ± 0.6 |
| iteration 2 (+243k decisions) | 53.9 % ± 0.6 | 59.6 % ± 0.7 |
| **iteration 3 = v6** (+245k) | 51.7 % ± 0.6 | 60.3 % ± 0.6 |

Fresh deals (seed 9001): v6 beats v5 **60.2 % ± 0.5** (3000 deals x 2,
margin +137 per match) and the heuristic 93.9 % ± 0.5 (v5: 91.4 % ± 0.6).

What changed in the setup:

- **The learner now plays with the learned schupf.** Before, the loop trained
  and gated the play net with the heuristic schupf, although the app and
  every comparison use schupf v2: it learned for hands it never gets.
- **Early stopping and EMA weights.** The rollout labels are noisy (± 58
  points of clairvoyant regret per decision against ~1 point of learnable
  gain): held-out gain peaked after 3-4 epochs and halved by epoch 8. The
  trainer now runs 4 epochs, keeps the epoch with the best held-out gain and
  exports an exponential moving average of the weights (`--ema`, default
  0.999).
  Same data, same start: +2.3 pp against v5.
- **Match-win targets** (DouZero's win-probability objective, P(win |
  totals) from 16k rounds of v5 self-play): the round result is mapped
  through the match-win probability after the round. It lost to the point
  targets (54.9 % vs 56.2 %); the code (`--objective`, `win_prob.py`) was
  deleted on 2026-11-22. The runner still writes each team's own rollout
  points (`q_rollout_own`); the trainer ignores them.
- Compact data cache: the state is stored once per decision (float16), ~7x
  less memory than one full input row per action.

Gains per iteration shrink (+3.4 pp, then +0.7 pp against v5); a fourth
iteration was cut off by a container restart.

### How v6 plays differently

`rl/compare_policies.py` scores v5 and v6 on the same positions (66k v6
decisions from v6-vs-v5 games, every legal move rolled out on the real deal,
v6 continuing) and measures, where they disagree, how many round points v6's
move gains over v5's. They disagree on 23 % of decisions; v6's move is
worth +2.1 ± 1.0 points per disagreement (+0.5 per decision). That is a
one-move swap; the full effect compounds over a round (+137 per match).

Where the gain comes from (points per differing move):

| Situation | gain |
|-----------|------|
| following an opponent's trick (13 % of all decisions) | +2.7 ± 1.4 |
| endgame, 1-4 cards in hand | +5.9 ± 2.1 |
| an opponent has one card left | +6.8 ± 2.4 |
| partner called (Grand) Tichu | +5.2 ± 2.4 |
| partner already out | +3.0 ± 1.0 |
| following a pair / a triplet | +11.5 ± 4.5 / +53 ± 16 |
| following the partner's trick | -2.4 ± 3.4 (no gain) |

Style, on the same positions (share of decisions where the move is possible):

| | v5 | v6 |
|-|----|----|
| bombs when it can | 15.5 % | 10.3 % |
| plays the Dragon with 8+ cards | 10.7 % | 8.4 % |
| plays the Phoenix with 8+ cards | 13.1 % | 11.5 % |
| passes on an opponent's trick | 28.3 % | 30.3 % |
| leads a single / triplet / pair straight | 53 / 4.4 / 6.6 % | 56 / 2.9 / 5.0 % |

- **It keeps its bombs and high cards for later.** v6 bombs a third less
  often. Where v5 bombs and v6 does not, v6 gains +22 ± 11 (it passes) and
  +40 ± 25 (it plays something else); keeping the Phoenix where v5 spends it
  +23 ± 12.
- **It leads more singles and fewer fixed combinations** (triplets, pair
  straights): leading a single where v5 leads a pair straight +18 ± 9, a
  triplet +10 ± 9.
- When both follow with a single, playing the lower one helps (+2.6 ± 2.4)
  and the higher one costs a little (-2.8 ± 2.2): the net edge is in the
  endgame and against short opponent hands, not in a simple rule.

## Results v7 candidate (2026-11-19): league, match split, confirmation duels

Four iterations of `rollout_loop.py --league=2 --opponent-nets=v5
--train-args="--ema=0.999 --recency=0.8"` from v6 (2400 league matches + 1000
self-play matches per iteration, ~500k labelled decisions each, 2.0M in all;
data in Supabase Storage, run `v7`). All four were promoted (gate duel and
confirmation duel on fresh deals, 1000 deals x 2 each):

| Iteration | vs previous best (gate / fresh) | vs v5 | vs v6 |
|-----------|---------------------------------|-------|-------|
| 1 | 52.9 / 54.2 % | 63.9 % | (= previous best) |
| 2 | 52.7 / 51.6 % | 65.5 % | 54.8 % |
| 3 | 52.3 / 50.6 % | 68.1 % | 57.6 % |
| 4 | 53.3 / 50.6 % | 68.7 % | **58.4 % ± 0.5** (3000 fresh deals x 2, seed 9001) |

Iteration 4 (`assets/bots/tichu_q_v7.safetensors`)
beats the heuristic 95.4 % ± 0.3 (v6: 93.9 %). 58.4 % is just under the
60 % bar for a PR on its own. **Shipped 2026-11-20 together with schupf v3**
(trained on 67k exact schupf decisions of v7 self-play): v7 + schupf v3 beats
v6 + schupf v2 **62.3 % ± 0.6** (3000 fresh deals x 2, +167 per match); schupf
v3 alone is worth 53.4 % ± 0.7.

A/Bs on the same data, same start (the iteration-4 starting net), duels
against the iteration-4 net (2000 deals x 2):

- **Recency 1.0 instead of 0.8**: 50.0 % ± 0.6. No measurable effect; 0.8 is
  kept (harmless, and it matters more as the data of old policies grows).
- **Wider net 512-256-128** (`--widen-hidden`, function-preserving): 48.5 %
  ± 0.6, *worse*, although its held-out gain was higher (+0.44 vs +0.39
  points per decision). With 4 epochs the extra units are undertrained; and
  the held-out gain does not predict duel results at this resolution.
- Each gate duel was ~1 pp more optimistic than its fresh-deal confirmation
  (52.3-53.3 % vs 50.6-54.2 %): the confirmation duel is worth keeping.

### Where v7 plays better, and where it is still weak (2026-11-19)

`compare_policies.py` both ways (1000 matches v7 vs v6 each, every legal move
of 30 % of the decisions rolled out; 68k decisions per side). v7 and v6
differ on 22 % of decisions; v7's move is worth **+1.8 ± 0.7** points per
differing move (+2.1 with v7 continuing, +1.4 with v6 continuing).

Per differing move, mean of both directions where both agree in sign:

| Situation | v7 gain |
|-----------|---------|
| partner called (Grand) Tichu | +5.0 |
| endgame, 1-4 cards in hand | +5.3 |
| an opponent has one card left | +4.7 |
| an opponent called (Grand) Tichu | +2.9 |
| partner already out | +2.5 |
| leading | +2.4 |
| following singles in the middle game | +1.3 (not significant) |

Moves: playing the lower of two singles (+2.8), playing a single instead of a
pair (+19 with v7 continuing, -3 with v6), passing instead of spending a
single on an opponent's trick (+3.9 / -0.5).

What the *last* iteration still learned (v7 vs its starting net, same data):
only the endgame, play around (Grand) Tichu calls and leads move (+1 to +3.5
per differing move); the middle-game following decisions (63 % of all
decisions) no longer improve (-1.5 ± 1.6). With one rollout per action the
label noise (mean clairvoyant regret 56 points) swamps what is left there.

Points at stake per situation (clairvoyant regret of v7's own moves, mostly
card luck, so only a relative weight): decisions with 10-14 cards in hand are
51 % of all decisions but carry 67 % of the regret, endgame decisions (1-4
cards) only 6 %. The early, long-horizon decisions are where the most is at
stake and where the current labels are too noisy to learn from.

Not learned at all yet:

- **Out-of-turn bombs.** The engine accepts them (`trick_resolution.dart`,
  `isInterruptingBomb`), but `AgentDecisions.next` only ever asks the player
  whose turn it is, so a bot can never bomb after it passed or before an
  opponent goes out.
- Dragon gift and wish choice are heuristic; schupf v2 was trained on v5's
  play; calls are the strength rule (near its ceiling, see "Schupf and calls").

The heuristic no longer gives a useful signal: v7 wins 95.4 % against it, a
1 pp step is barely measurable there, and v7's data used no heuristic games.
It stays only as a regression check; progress is measured against the league
nets and with exact rollouts.

### Out-of-turn bombs (2026-11-20)

The decision loop offered every player holding a bomb that beats the trick
an out-of-turn bomb between any two plays/passes (removed for bots on
2026-11-22, see below). Feature schema v6 added one input, `off_turn`
(1 = deciding out of turn), at the end of the state prefix; it stays in the
layout and is always 0 for bots. v5-layout nets (v5-v7, 318 inputs) still
load and play unchanged in Dart and are widened with zero weights in
Python.

Measured with v7, exact rollouts of 25,447 interrupt decisions (bomb now vs
wait, `--interrupt-rollout-rate=1`):

- Bombing out of turn costs **-50 points** per decision on average and wins
  in 27 % of cases. It is negative in every slice tried: who wins the trick
  (opponent -30 to -43, partner -70), the winner's or any opponent's card
  count, Tichu calls, an opponent already out, trick points, passes so far.
- Why: every player gets a turn before a trick comes back to its winner, so
  an interrupt only changes *when* the bot bombs; waiting keeps the bomb and
  the in-turn option. The cases where early bombing helps depend on hidden
  cards.
- A rule (bomb against an opponent with <= 3 cards / a Tichu caller / a
  double-win threat / 20+ points) loses: v7 with it vs v7 without
  **47.0 % ± 0.4** (2000 deals x 2).
- A net trained on the interrupt decisions (v7 start, held-out matches) does
  not beat "never": -1.7 points per decision vs always waiting.

So the bot side was deleted on 2026-11-22 (the rule, the net's interrupt
decision, the decline action, `--no-bomb-interrupts` and
`--interrupt-rollout-rate`): bots are never asked to bomb out of turn.
Humans in the app still can (the engine accepts an out-of-turn bomb on a
trick).

### Endgame search (2026-11-22)

**Measured first** (`headless --rollout-worlds=9 --worlds-min-cards=0
--label-max-cards=5`, `rl/endgame_review.py`): on 27,012 endgame play
decisions of the shipped bot (decider holds <= 5 cards) every legal move was
played out on the real deal and on 8 re-deals of the unseen cards. Rule:
deviate from the bot's move only if another legal move is no worse in all 8
re-dealt worlds and better on average by more than a margin. Judged on the
real deal (an exact sample of the hidden cards) this is worth **+1.17 ±
0.20** points per endgame decision with margin 0-10 (changes 9-12 % of the
decisions), +1.07 ± 0.15 with margin 40 (3.6 %). With 4 worlds, or without
the unanimity condition, it loses.

**Implementation** (`lib/agents/endgame_search.dart`):

- `BotConfig.endgameSearch: EndgameSearch(worlds: 8, maxCards: 5, margin:
  10, maxActions: 7)` (null = off; only bots with a play net get it). The
  search needs a game state to fork, which agents do not have (they see a
  `GameSnapshot`), so the **drivers** run it: `EndgameSearcher.refine` is
  called after the bot chose its turn, by the headless `_selectAction`
  (not after an ε-explored move) and by the app's `AiTurnRunner`.
- It applies to on-turn play decisions with <= `maxCards` cards, >= 2
  actions and no finishing move (`SmartAiAgent.searchableActions`: the same
  set `selectTurn` chooses from, after the partner-Tichu guard; going out
  stays a hard rule). Above `maxActions` actions it rolls out the bot's
  move, pass and the plays with the highest Q (rare with <= 5 cards).
- Worlds: `redealWorld` keeps the decider's hand, the played cards, every
  hand size and the decider's own passed cards still held by the receiver,
  and deals the other unseen cards uniformly. Every action is applied in
  each world and the round is played to the end by fresh bots (the same
  configs as at the table, without exploration), via the shared
  `playOutRound`. Rollouts call the agents directly, never the searcher, so
  the search cannot recurse.
- Rule: `pickEndgameAction` (unanimity + margin, highest mean advantage).
  The real deal is never used, only the 8 re-deals.
- Deterministic: the worlds' `Random` is seeded from what the decider knows
  (own hand, the round log, hand sizes, round and score; 30-bit arithmetic,
  so dart2js gives the same seed), and the unseen cards are sorted before
  shuffling, so the worlds do not depend on where the hidden cards really
  are. Same state, same move.
- Headless: `--endgame-search` (policy team), `--opponent-endgame-search`,
  `--endgame-worlds=8`, `--endgame-max-cards=5`, `--endgame-margin=10`,
  `--endgame-max-actions=7`. A stderr line `endgame_search_stats` gives
  searches, switches, rollouts and ms per search.
- App: `AppBots.useEndgameSearch` (on, <= 8 cards). The app runner yields to the event
  loop between rollouts and drops the move if the game moved on meanwhile.

**Duel** (duplicate, `rl/duel.py --deals=2000 --seed=9001 --shards=2`), A =
v7 + schupf v3 + endgame search, B = v7 + schupf v3:

| A | Result |
|---|--------|
| search, <= 5 cards, 8 worlds, margin 10 | **54.5 % ± 0.5**, margin **+59 ± 4** per match (2000 deals x 2) |
| search, **<= 8 cards**, 8 worlds, margin 10 | **57.2 % ± 0.8**, margin **+89 ± 7** per match (1000 deals x 2) |

The rule was measured on <= 5 cards, but it also pays with 6-8 cards in hand
(twice as many searched decisions, +30 points per match more). The app uses
<= 8 cards (`AppBots.endgameSearch`); `EndgameSearch()` defaults to 5.
Not tried yet: more worlds, other margins, <= 10 cards, belief-weighted
worlds.

**Cost** (headless, one process, simd, 4 cores shared with a training
job at load ~9): **22.5 ms per searched decision** (27.6 rollouts of ~0.8 ms:
~3.5 actions x 8 worlds), ~45 searched decisions per match for the searching
team, 8.4 % of them changed. A match with one team searching takes 1.29 s
instead of 0.29 s (4.4x). With <= 8 cards: 31 ms per search, ~90 searches
per match, 2.8 s extra per match (3.1 s instead of 0.27 s) (8.4 % -> 9.3 % changed). The app uses float64 inference (~3.4x slower than
simd in the same test, ~75 ms per search here) and the web build (dart2js,
node) is ~1.7x slower than the native float64 build (242 vs 145 ms per
search in a run with all four seats searching at load ~12): expect ~0.1-0.4 s
per searched decision on a phone, ~20 times per bot and match (the UI stays
responsive: the runner yields between rollouts); with <= 8 cards ~1.5x
that, twice as often. Duels and data generation with search are 4-8x slower, so training runs keep it off (labels are rollouts of the plain
bots); it is a playing-strength add-on for the app and evaluations.

Side fix: `Mlp.fromSafetensorsBytes` read the header length with
`getUint64`, which dart2js does not support, so the web build could not load
the nets and fell back to the heuristic bots; it now reads two uint32s.

## Results v8 (2026-11-23): schema v7 inputs, schupf v4, shipped

v8 is the rollout loop (`--out-dir=rl/outputs/v8`, data restorable with
`training_data_store.py download --run=v8`) on feature schema v7 (376
inputs: safe-finish / claim features recomputed after every card, the
received schupf cards, and the claim after each candidate move), started
from v7 widened with zero weights. League of replaced nets plus self-play.

| Iteration | Gate vs best | vs v6 | Promoted |
|-----------|--------------|-------|----------|
| 1 | 50.1 % | 60.9 % | no |
| 2 | 55.5 % (pooled 54.9 %) | 62.8 % | yes |
| 3 | 51.3 % | 65.5 % | no |
| 4 | 53.0 % (pooled 52.7 %) | 65.6 % | yes |
| 5 | 49.8 % | 66.9 % | no |
| 6 | 51.4 % | 67.4 % | no |

Iterations 5 and 6 lost their gate against iteration 4 by noise, yet beat
it 54.5 % on the league duel and are stronger against every other
opponent, so the shipped net is iteration 5 (the gate should use a panel,
see `rl/REVIEW.md`, "Plan for v9"). Schupf v4: `schupf_cf_train.py` on
62,540 exact schupf decisions of v8 self-play.

Against the previous shipped bot (v7 + schupf v3), duplicate, fresh deals:

| Bot | Search | Result |
|-----|--------|--------|
| v8 it5 + schupf v4 | both sides, <= 8 cards (as in the app) | **61.3 % ± 1.0** (1000 deals x 2), +164 per match |
| v8 it5 + schupf v4 | none | 63.6 % ± 0.9 |
| v8 it4 + schupf v4 | both sides | 58.6 % ± 1.0 |

## Data format: always the latest layout, never missing information

Rules (2026-11-24, after v9 stalled on its own small data and v10 took off
once all old data was rebuilt):

* **Every cache is loaded in the current feature layout.** Caches record
  `schema_version`; `rl/data_upgrade.py` pads missing groups and computes
  the ones that are a function of older features (`UPGRADES`, e.g. the v9
  beatability). Groups that cannot be recovered are listed in
  `UNRECOVERABLE` and reported on load (today: the v8 `passed` group for
  pre-v8 data). `rl/rebuild_v9.py` rewrites caches on disk the same way.
* **When you add features**, add an upgrade function if they follow from
  existing features, or list them as unrecoverable. Never train new inputs
  on fresh data alone: one iteration (~0.4M decisions) cannot move a net
  trained on millions.
* **Every new data run records its games.** `headless --record-games`
  writes one bc-jsonl row per round with the deal (all 14 cards per seat)
  and every action; play rows carry `round` / `step`, kept in the caches as
  `pos`. `rollout_loop.py` stores them as `<file>.games.jsonl.xz` next to
  each cache and uploads both. `lib/headless/replay_game_records.dart`
  replays them in the engine: identical state features for every logged
  decision and the recorded round results (checked on 372 decisions / 28
  rounds), so any future feature can be computed for this data.

## Next steps

The review of 2026-11-20 (`rl/REVIEW.md`) measures the label noise, lists
the flaws of this setup and orders the next ideas; it supersedes the list
below where they differ.

1. ~~Out-of-turn bombs for bots~~ Done 2026-11-20: no gain, removed
   (see "Out-of-turn bombs").
2. Less noisy labels for the early game: several rollouts per action with
   the hidden cards re-dealt consistently with the public history, or a
   perfect-information value net to truncate rollouts (item 6).
3. ~~Continue the v7 run~~ Done: v7 shipped 2026-11-19, v8 2026-11-23
   (see "Results v8"); the v9 plan is in `rl/REVIEW.md`.
4. Learned calls on exact counterfactual labels from the best policy
   (`call_labels.sh` + `call_train.py`); then the same for the schupf.
5. ~~Delete the dead heuristic rules listed above.~~ Done 2026-11-17:
   1,200 lines removed, the remaining heuristic beats the previous one
   50.9 % ± 0.3 (see `lib/agents/ai_strategy.md`).
6. A truncated rollout with a perfect-information value net (PerfectDou's
   critic) would make labels several times cheaper once more data is needed.
7. ~~Endgame search~~ Done 2026-11-22: 54.5 % (<= 5 cards) / 57.2 %
   (<= 8 cards) against the same bot without it; on in the app (see
   "Endgame search"). Next: tune worlds / margin / max cards.

## Output contract

- `rl/outputs/` keeps only `*.safetensors` artifacts.
- Intermediate JSONL is written to the OS temp dir and removed.

## Notes

- Targets are normalised before MSE training using `target_mean` and
  `target_std` (stored in safetensors metadata; Dart `Mlp.fromSafetensorsBytes`
  reads them back). BC pretrain uses `mean=0`, `std=1` and trains on raw
  Q-logits via cross-entropy.
