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

The shipped play policy is `assets/bots/tichu_q_v4.safetensors` (see
`rl/models/README.md`). It is trained by **rollout policy iteration**
(`rollout_loop.py`, see "Rollout policy iteration" below).

**Before any RL command, compile the Dart headless runner once.** Every
Python script auto-detects `build/bin/headless` and uses it; without
this you pay a 2.5 s VM cold-start per invocation.

```bash
dart compile exe lib/headless/headless.dart -o build/bin/headless
```

Continue training the current policy (restart-safe, ~30 min per iteration on
4 cores; everything goes to `rl/outputs/rollout_loop/`):

```bash
rl/hill_climb.sh                              # start / resume in the background
tail -f rl/outputs/rollout_loop/loop.log
```

Measure any two bots against each other (duplicate deals, both seatings):

```bash
rl/.venv/bin/python rl/duel.py --a="--nn-policy=assets/bots/tichu_q_v4.safetensors" \
    --b="--opponent-policy=assets/bots/tichu_q_v3.safetensors" --deals=1000
rl/.venv/bin/python rl/duel.py --a="--heuristic=latest,-early_dog" \
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
  `q_train.py` is one step of this.
- **PerfectDou** (NeurIPS 2022): perfect-training / imperfect-execution — the
  critic sees all hands during training, the policy does not. That removes
  card luck from the learning signal; it beat DouZero with ~10× fewer
  samples. Here: the `oracle` field and oracle baselines (`oracle.py`) in
  `call_train.py`, `schupf_train.py`, `q_train.py`.
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

`rl/schema/feature_spec.json` (v5) defines the 318-dim feature vector
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
| action          | 51   | 267-317 | type, strength, beaters, cards used, hand after  |

`history` (new in v5) comes from the engine's public round log
(`lib/game/round_log.dart`: every play and pass with the trick it answered).
Per other player (left, partner, right; 22 each): the cards they played this
round as a rank histogram, the lowest single and the lowest pair they passed
on while one of their opponents was winning the trick, and the number of such
passes. Before v5 the net could not tell who played or passed on what, so it
could not read hands from the play.

Nets of the v4 layout (252 inputs: v3, v4) still load and play unchanged;
they read the first 201 state features. `rl/widen_net.py` converts them to
the v5 layout with zero weights for the history features (identical play),
which is how training warm-starts from them.

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
- `q_train.py` saw one return for one action per decision and explored 5 %
  of moves at random, on 600 games per iteration: far too little signal to
  rank the actions it rarely tried, so the policy stayed close to its
  behaviour-cloning start.
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
3. `rollout_loop.py`: iterate. Data comes from games against the heuristic
   variants in `--opponents` (both seatings) and from self-play; the data of
   earlier iterations is kept (training on all 318k decisions beat training
   on the newest 121k by 4 pp). A candidate is promoted when it beats the
   best net in a duplicate duel by more than 2 standard errors.

The exported net has the same inputs and layers as before and plugs into
`NnPlaySelectionStrategy` unchanged.

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
       --nn-policy=rl/outputs/best_policy.safetensors --output-dir=rl/outputs
   rl/.venv/bin/python rl/evaluate_policy.py \
       --nn-policy=rl/outputs/best_policy.safetensors \
       --tichu-net=rl/outputs/tichu_net.safetensors \
       --grand-net=rl/outputs/grand_net.safetensors \
       --output=rl/outputs/eval_calls.safetensors --episodes=200 --target-score=500
   ```

3. **`schupf_train.py`** — schupf value net Q(hand, pass) on
   `SchupfFeatures` (232: hand bitmap, one-hot card to left / partner /
   right, `[grand, tichu]` call flags for me / partner / left / right).
   Data: `headless --schupf-epsilon=p` (mostly one card swapped). Dart's
   `NnSchupfStrategy` scores all 2184 assignments with an incremental first
   layer.

4. **`train_loop.py`** — the joint loop for the whole bot. Each iteration
   generates exploration data with the *current* bot (calls, schupf, plays),
   retrains call nets, schupf net and play policy (Q step), and tries each
   component group (play / calls / schupf) on top of the best bot, promoting
   it only on a significant paired gain (duplicate, 100 deals, target 1000).
   Because everything is retrained on the current bot's games, components
   adapt to each other (e.g. passing to a partner who announced Tichu).

   ```bash
   rl/.venv/bin/python rl/train_loop.py --iterations=4 --shards=4
   # best bot: rl/outputs/bot_best/*.safetensors
   ```

5. **`q_train.py`** — DouZero-style Monte-Carlo Q fine-tune of the play net
   (oracle baseline); the play learner used by `train_loop.py`. Superseded
   for the play net by `rollout_train.py` / `rollout_loop.py` (above).

6. **`analyze_games.py`** — duplicate games vs the heuristic with
   `--shadow-heuristic`: round stats per side (going out first, double wins,
   call rates and success) and where / how often the policy's moves differ
   from what the heuristic would have played.

7. **`duel.py`** — duplicate duel between any two bot configurations
   (nets and / or heuristic variants).

8. **`call_labels.sh`** — background generation of exact counterfactual
   call labels with the current best policy, for `call_train.py`.

### Heuristic lab

The same rollout labels score heuristic rules exactly:

- `headless --shadow-heuristics=specA|specB|...` logs, for every labelled
  decision, what each heuristic variant would have played. One dataset then
  gives the exact one-step value (points per decision) of all variants.
- `--heuristic=` specs: `latest` (the heuristic as written), `-name` to
  switch a rule off (`partner_pass`, `mahjong_lead`, `partner_finish_lead`,
  `early_dog`, `singleton_response`, `cheap_combos`, `guard`) and
  `weight:value` to override a `TurnScorer` weight, e.g.
  `latest,-early_dog,lowLeadPreference:4`.
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

`evaluate_policy.py` is duplicate by default: every deal sequence is played
twice with the same deals (`--deal-seed`), once with the policy on team 0
and once swapped. It reports the per-deal win rate with its standard error
and stores per-deal results, so `train_loop.py` promotes a candidate only if
its paired gain over the best bot exceeds `--promote-z` SEs.

### Headless output formats

Only two RL-relevant formats remain:

- **`--format=summary`** — one JSONL line per finished match.
  `evaluate_policy.py` consumes this. ~50 lines for a 50-match eval.
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

Joint loop (`train_loop.py`) from a BC policy of the improved heuristic
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

## Next steps

1. Keep iterating `rollout_loop.py`; shift the data towards self-play as the
   heuristics stop being a challenge.
2. Learned calls on exact counterfactual labels from the best policy
   (`call_labels.sh` + `call_train.py`); then the same for the schupf.
3. ~~Delete the dead heuristic rules listed above.~~ Done 2026-11-17:
   1,200 lines removed, the remaining heuristic beats the previous one
   50.9 % ± 0.3 (see `lib/agents/ai_strategy.md`).
4. A truncated rollout with a perfect-information value net (PerfectDou's
   critic) would make labels several times cheaper once more data is needed.

## Output contract

- `rl/outputs/` keeps only `*.safetensors` artifacts.
- Intermediate JSONL is written to the OS temp dir and removed.

## Notes

- Targets are normalised before MSE training using `target_mean` and
  `target_std` (stored in safetensors metadata; Dart `Mlp.fromSafetensorsBytes`
  reads them back). BC pretrain uses `mean=0`, `std=1` and trains on raw
  Q-logits via cross-entropy.
