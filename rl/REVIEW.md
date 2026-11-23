# RL setup review (2026-11-20)

A review of the play-net pipeline after v7 stalled at 58.4 % against v6
(rollout policy iteration, `rl/rollout_loop.py`). It combines a new label
noise measurement, a code review and the literature review in
`reports/Tichu AI next steps.md` (local, not in git). Status markers:
**measured** (numbers from this repo), **verified** (read in the code),
**suspected** (reasoned, not measured).

## Summary

1. **The labels re-measure the same luck many times.** With deterministic
   bots every bit of label noise is hidden-card noise, and the errors of the
   labels taken in one round are strongly correlated (+0.49, +0.46, +0.35
   between successive labelled decisions of a team). We label ~11 decisions
   per team and round; they carry far less independent information than 11
   labels from 11 deals. Simulating a match without labels costs ~2 % of
   labelling it, so spreading the same label budget over 5x more deals is
   nearly free. **This is the first thing to fix** (A/B running).
2. **More worlds per label and flat search are not the cheap win they
   looked like.** v7's own move beats a move chosen from 5 rollout worlds,
   and adding 8 re-dealt worlds on top of the net does not beat the net
   (+0.3 ± 1.1 points per early decision at best).
3. **The other components were trained against older play nets.** Schupf v2
   is a best response to v5's play and the call thresholds were tuned with
   v5; both are cheap to redo for v7 (schupf v1 -> v2 was worth 54 %).
4. **The promotion gate cannot see the steps we now make** (1000 deals,
   ± 0.9 pp, steps of ~1 pp), and the held-out training metric does not
   predict duel results. Use a sequential test or bigger duels.
5. **Blind spot: humans.** Every number is bot-versus-bot within one
   lineage. The app now saves game records to Supabase; nothing reads them.

## The label-noise measurement (measured)

`headless --rollout-worlds=9 --worlds-min-cards=10`: for 5,636 decisions
with 10+ cards in hand (v7 self-play, 240 matches, 8.5 legal actions on
average) every legal action was rolled out on the real deal and on 8
re-deals that keep the decider's hand, the played cards, all hand sizes and
the decider's passed cards. Labels are centred over the actions.

| Quantity | Value |
|----------|-------|
| SD of one world's label of an action, across worlds | **90.6** points |
| SD across actions of the expected label (the signal, debiased) | 32.8 points |
| corr(one re-deal, another re-deal) | 0.154 |
| corr(real deal, one re-deal) | 0.127 |
| corr(mean of 4 re-deals, mean of 4 others) | 0.380 |
| corr(real deal, mean of 8 re-deals) | 0.257 |

Value of the move chosen by each method, judged on 4 held-out re-deals
(points above the average legal move; 62 = picking the best move with
hindsight on those re-deals):

| Chosen by | Value |
|-----------|-------|
| the real-deal rollout (today's training label) | +8.1 ± 0.7 |
| 4 re-deals | +14.2 ± 0.7 |
| real deal + 4 re-deals | +15.5 ± 0.7 |
| **v7's own move** | **+20.4 ± 0.7** |

Judged on the real deal (an exact sample of the hidden cards, unbiased),
minus v7's move:

| Chosen by | Gain vs v7 |
|-----------|------------|
| 1 re-deal | -13.6 ± 1.7 |
| 4 re-deals | -8.5 ± 1.6 |
| 8 re-deals | -3.4 ± 1.6 |
| 4 x net Q + mean of 8 re-deals | +0.3 ± 1.1 |
| net's top 2, then 8 re-deals | +0.4 ± 1.2 |

Label errors (real-deal label minus the 8-re-deal mean, for v7's move) of
labelled decisions of the same team in the same round, at rate 0.1:

| Lag between labelled decisions | Correlation |
|--------------------------------|-------------|
| 1 | +0.49 |
| 2 | +0.46 |
| 3 | +0.35 |
| random pairs | -0.01 |

What follows from it:

- **All label noise is about the hidden cards.** The bots are deterministic,
  so given a deal the outcome is fixed; "chaotic continuation" is not a
  separate noise source that a value-net control variate could remove
  without also knowing the hidden cards.
- **One label is worth little; the net's generalisation is worth a lot.**
  A single world's label has reliability ~0.15. The net, trained on 2.5M
  such labels, chooses better than 5 rollout worlds of the very position.
  So K-world labels buy at K times the cost what K labels from K other
  deals also buy, and those are unbiased (re-deals are slightly
  miscalibrated: 0.127 vs 0.154, because the bots' play reveals cards that a
  uniform re-deal ignores).
- **Correlated errors within a round** mean the current budget (~231
  labels per self-play match, ~11 per team and round at rate 0.5, 10.6
  rounds per match) re-measures each deal's luck many times. If the measured
  correlation held for all pairs in a round, 11 labels would be worth about
  2-3 labels from different deals. This also explains why "more data beat
  fresher data" and why stakes weighting (same deals, different positions)
  did not help.
- **Flat decision-time search with few uniform worlds does not beat v7 in
  the early game.** It might with 32+ worlds or belief-weighted worlds, but
  that is not cheap; the endgame (few unseen cards, short rollouts) is the
  place to try search first (not yet measured).

Reproduce: `headless --format=bc-jsonl --rollout-rate=0.1
--rollout-max-actions=60 --rollout-worlds=9 --worlds-min-cards=10
--epsilon=0 --nn-policy=assets/bots/tichu_q_v7.safetensors
--schupf-net=rl/outputs/bench/schupf_v2.safetensors ...` (240 matches,
~10 minutes on 4 cores).

### Follow-up: more deals per label budget (measured 2026-11-20)

Same iteration (v7 iteration 5: same seeds, start net, league, ~500k
labels), `--rollout-rate=0.1` over 5x the matches. Duels, 2000 fresh deals x
2:

| Candidate | Result |
|-----------|--------|
| low rate, trained on all data, vs iteration 4 | 50.8 % ± 0.6 |
| (uniform 50.9 %, stakes 51.1 % on the same test) | |
| trained on the new iteration only: low rate vs uniform | 50.7 % ± 0.6 |
| trained on the new iteration only: stakes vs uniform | 50.7 % ± 0.6 |
| trained on the new iteration only: uniform vs iteration 4 | 49.6 % ± 0.6 |

The first A/Bs changed only a quarter of the training signal (the other ~2M
labels of iterations 1-4 are shared), so the clean comparison trains each
arm on its own 500k labels. Spreading labels over more deals gives at most
+0.7 pp (1 SE, not significant), the same as stakes weighting; 500k labels
from iteration 4's own play do not improve on iteration 4 at all. **The
plateau is not about how the labels are spent.** One iteration's labels
carry too little signal to move a policy that is already greedy with
respect to what the net learned from 2M of them; the next gains must come
from the other levers (side decisions, inputs, ensembles), not the label
budget. Low-rate generation costs ~30 % more time per label (5x main games).

## Where the round points come from (measured, v7 self-play, 10,503 rounds)

Calls (any of the 4 players; the bots call with the strength rule):

| | Called | Success | Net per call |
|-|--------|---------|--------------|
| Tichu | 50.9 % of rounds (12.7 % of players) | 67.3 % | +35 |
| Grand Tichu | 16.5 % of rounds (4.1 % of players) | 73.3 % | +93 |

- Failed calls are almost always an opponent going out first (29 % of
  Tichus, 25 % of Grand Tichus); the caller's own partner going out first
  costs only 3.5 % / 2 %.
- In 54 % of rounds the first player out had not called. These are mostly
  hands that do not go out first often enough to call: just below the
  threshold (strength -0.5 to -0.1) 36-40 % go out first uncalled, and a
  call needs > 50 %. Called hands just above the threshold succeed 60 %,
  similar uncalled ones 40 %: the call itself (the partner's support, the
  schupf) is worth about 20 points of success rate. The threshold is near
  break-even; a re-tune for v7 is worth little.

The last player and the double win:

- Double wins end 26 % of rounds (200 points, card points void).
- In the other rounds the last player has won 23.8 card points of tricks
  on average (>= 20 in 59 % of rounds). They go to the first player out,
  which is the last player's partner in 52 % of these rounds. The cards
  left in the last player's hand (5.7 on average) go to the opponents.
  The last player's team loses 16.7 card points per round by the
  transfer, and ends with 32.2 of the 100 (43.1 before it).
- The first player's team scores 74.7 card points when the opponents
  finish 2nd and last (A-B-A-B), but only 38.6 when its own second player
  is last (A-B-B-A): avoiding last place is worth ~36 card points to a team
  in every round without a double win.
- Consequence for play: once a player will clearly finish last, every point
  trick they still win goes to the first player out. The net can learn
  this from its inputs (card counts, who went out first, points won per
  seat) and the round-point labels; it is a useful check for the human-game
  review and the endgame search (ideas 8 and 9).

## Side decisions and the partner guard (measured 2026-11-22)

Exact labels (`headless --side-rollout-rate=1`, `rl/side_analysis.py`), v7 +
schupf v3 self-play, 3000 matches:

- **Dragon gift** (30,244 decisions): the two recipients differ in 39 % of
  gifts, by 86 points when they do (14 points per gift with hindsight). The
  rule (opponent without a call, else the one with more cards = likely
  last) is as good as any simple alternative: "more cards" +0.1 ± 0.1,
  "fewer points won" -1.3, "left opponent" -3.9, "fewer cards" -4.9. A
  small net on the decider's state (held-out matches) +0.9 ± 0.6 at best,
  falling with more training: no reliable gain.
- **Mah Jong wish** (30,635): the rule (wish the rank passed to the left
  opponent, else the highest unheld A-10) beats every fixed wish by 3.6
  (wish 3) to 12 points (no wish); a learned net is -0.5 to -3.5. The
  hindsight spread (139 points) is hidden-card luck.
- **Partner guard `guard_single`** (do not play down to one card while the
  partner's Tichu is live): changes the move in 54 positions per 800
  matches, always to a pass, which costs -18 ± 20 points on exact
  rollouts; duel 49.8 % ± 0.1 (-2 ± 1 per match). Passing hands the trick and
  the lead to the opponents, a bigger threat to the Tichu than the forced
  single-card lead it avoids (1 % of calls). Removed.

## Is v7 too aggressive? (measured 2026-11-23)

Seen in Watch AI: the bots spend their strong cards early and are left with
weak cards. Two tests, against v7 itself (no human data yet):

1. **Exact rollouts** (800 matches of v7 self-play): when the bot played on a
   trick although it could pass (58 % of such decisions), passing instead
   was worse in every situation tried: -19.9 ± 0.5 points overall, -15 with
   10-14 cards, -33 with 1-4 cards, -24.5 when the play spent an Ace, -35
   for the Dragon, -12 on the partner's trick.
2. **Style biases** (`headless --style=`), v7 + schupf v3 with a uniform
   tilt against plain v7 + schupf v3, 1000 deals x 2:

   | Tilt | Result |
   |------|--------|
   | +10 points for passing | 29.8 % |
   | +25 for passing | 1.2 % |
   | -15 per control card spent (hand >= 8) | 41.1 % |
   | -30 per control card spent | 27.9 % |
   | both (+15 pass, -15 spend) | 6.7 % |
   | -10 for passing (more aggressive) | 44.9 % |

   v7 sits at the optimum of this axis; patience loses about 4x faster than
   more aggression. If its style is exploitable, it is situational, not a
   global "pass more". The pure best-response exploiter against frozen v7
   (`rl/outputs/v7b`, no self-play, labels with v7's own replies) gained
   nothing in its first iteration (49.2 % gate, 51.4 % ± 0.9 vs v7 on fresh
   deals). Its second iteration was promoted (55.0 % ± 0.6 vs v7), but it
   plays exactly as strong as v8 (league training with the new schema v7
   inputs): v8 vs v7b 50.6 % ± 0.9, v8 vs v6 63.3 %, v7b vs v6 62.8 %. The
   gain is the new inputs (both nets have them), not an exploit of v7's
   style; no exploitable weakness was found.

Note: until the web net-loading fix (PR 30) the website's bots were the
heuristic, not v7, which is a likely source of the aggressive look there.

## How the play evolved from v3 to v8 (measured 2026-11-23)

Tools: `rl/style_report.py` (style metrics from `--describe` rows),
`rl/policy_evolution.py` (every net on the same exact-labelled positions),
`rl/outputs/evolution/round_robin.py`. Each bot with its own shipped schupf
net (v3/v4: heuristic schupf).

**No collapse.** Round robin, duplicate, 600 deals x 2 (row beats column):

| | heur | v3 | v4 | v5 | v6 | v7 | v8 |
|---|---|---|---|---|---|---|---|
| v3 | 59.5 | - | 24.0 | 18.2 | 13.5 | 7.9 | 5.1 |
| v4 | 87.6 | 76.0 | - | 38.6 | 28.2 | 21.7 | 13.9 |
| v5 | 89.7 | 81.8 | 61.4 | - | 35.6 | 24.0 | 17.5 |
| v6 | 93.9 | 86.5 | 71.8 | 64.4 | - | 39.5 | 25.3 |
| v7 | 95.3 | 92.1 | 78.3 | 76.0 | 60.5 | - | 36.8 |
| v8 | 97.5 | 94.9 | 86.1 | 82.5 | 74.7 | 63.2 | - |

Perfectly transitive: every version beats every older one, by more the
older it is. No cycle (rock-paper-scissors) and no forgotten opponent, the
two signatures of self-play collapse. Each version changes 21-25 % of the
previous version's moves (agreement 67, 76, 78, 79, 79 %), v8 still agrees
with v3 on 60 %: steady refinement, not jumps between strategies. The lead
shape entropy is constant (1.6-1.7 bits): no narrowing to one move type.

**What changed** (style against a fixed v8 opponent):

| | heur | v3 | v4 | v5 | v6 | v7 | v8 |
|---|---|---|---|---|---|---|---|
| pass when it could beat an opponent's trick | 0.2 % | 13 | 24 | 30 | 30 | 30 | 32 |
| pass when it could beat, hand >= 10 | 17 % | 35 | 41 | 46 | 47 | 46 | 49 |
| overtake a partner with a live Tichu | 63 % | 14 | 15 | 10 | 14 | 19 | 18 |
| share of bombs played with >= 10 cards | 89 % | 86 | 68 | 57 | 52 | 49 | 46 |
| plays that break a pair / triple | 12 % | 9 | 15 | 17 | 18 | 18 | 18 |
| cheapest single that beats | 79 % | 77 | 68 | 69 | 69 | 70 | 67 |
| Dog to a partner with <= 2 cards | 98 % | 94 | 80 | 67 | 74 | 78 | 73 |
| goes out first / finishes last | 35 / 72 % | 36 / 69 | 41 / 61 | 39 / 58 | 43 / 56 | 47 / 53 | 49 / 50 |
| Tichu / Grand success | 51 / 46 % | 51 / 44 | 60 / 40 | 54 / 59 | 57 / 56 | 62 / 60 | 63 / 63 |

- Every version is *more patient* than the one before, not more
  aggressive: the heuristic beats every trick it can, v8 lets a third of
  the beatable opponent tricks go (half of them with a full hand), and
  bombs are kept for later. The "aggressive" bots seen on the website were
  the heuristic (the web build could not load the nets before PR 30).
- Partner play: from overtaking a Tichu-calling partner 63 % of the time
  (heuristic) to 10-19 %.
- Flexible hands: more set breaking, less "cheapest card that beats"; the
  net plays a higher card or splits a pair when it keeps a better hand.
- The calls are the same heuristic rule throughout; their success rises
  with the play (Tichu 51 -> 63 %, Grand 46 -> 63 % against v8).

**Where the moves improved** (5,757 v8 self-play decisions with exact
values of every legal move, rest of the round played by v8; value of the
chosen move minus the action average, round points; v8 continuation, so
slightly in v8's favour):

| situation | n | v3 | v4 | v5 | v6 | v7 | v8 |
|---|---|---|---|---|---|---|---|
| all | 5757 | 11.7 | 16.4 | 17.9 | 18.7 | 18.0 | 19.9 |
| follow, opponent's trick | 3694 | 5.2 | 11.5 | 12.9 | 14.6 | 13.5 | 16.0 |
| some Tichu called | 3363 | 13.0 | 18.1 | 20.0 | 21.2 | 21.2 | 23.8 |
| hand >= 10 | 3030 | 8.3 | 15.2 | 17.2 | 18.0 | 16.8 | 19.5 |
| hand 5-9 | 1855 | 16.5 | 19.3 | 20.0 | 21.3 | 20.4 | 22.0 |
| follow, partner's trick | 1217 | 19.0 | 24.0 | 23.7 | 23.2 | 23.6 | 24.6 |
| hand <= 4 | 872 | 13.3 | 14.6 | 16.1 | 15.8 | 17.3 | 16.3 |
| **lead** | 846 | 29.4 | 27.0 | 31.4 | 30.3 | 29.7 | 30.0 |

The whole gain since v3 (+8.2 ± 1.2 per decision) is in following: the
play-or-pass and which-card decisions on opponents' tricks, early in the
round and around Tichu calls. **Leads have not improved since v3**
(v3 - v8 = -0.6 ± 2.4). A lead fixes the trick type for everyone; its
label is the noisiest (the whole rest of the round follows) and leads are
only 15 % of decisions. Small hands (<= 4) barely move either; the endgame
search covers them at decision time.

## Plan for v9 (2026-11-23)

What moved the bot from v7 to v8 (all duplicate duels): the new inputs
(safe-finish and received schupf cards, +5 pp over v7 after two
iterations), retraining the schupf net on the new play net (+3.4 pp for v3,
+4.2 pp for v4), and decision-time endgame search (+7 pp at <= 8 cards).
What did not: label budget tricks (stakes, more deals, multi-world labels),
style tilts, the v7 exploiter, out-of-turn bombs, the partner guard,
learned Dragon / wish / call models, a wider net with 4 epochs.

In order of expected value:

1. **Teach the net what the search finds (expert iteration).** The endgame
   search improves the net's move in ~9 % of endgame decisions (+1.2 points
   each). Two uses: (a) train on the search's choices for endgame states
   (cheap: the search already runs at <= 8 cards in the duels), so the net
   plays the endgame better without search; (b) rollout continuations are
   played by the plain net, so a stronger plain endgame makes every earlier
   label more accurate too. Measure: v9 without search vs v8 without search.

   **Pilot (2026-11-23): no gain.** 50k endgame decisions (<= 8 cards) of
   v8 self-play labelled with the mean over 8 worlds (what the search
   computes; `rollout_train.py` now averages `q_rollout_worlds`), counted
   twice, added to the v8 data; four epochs from v8. Against v8 without
   search, 1000 deals x 2, same deals: distilled 51.5 % ± 0.9, control
   (same training without the endgame labels) 51.1 % ± 0.8. Per move on
   5,757 exact-labelled positions: +0.3 ± 0.6 overall, +0.9 ± 1.3 at <= 4
   cards. The plain net's endgame is not where it loses, or 50k labels
   against ~600k single-world endgame labels are too few to move it; the
   search keeps its value at decision time. Leads (see "How the play
   evolved") are the larger target.
2. **Extend the search earlier with belief-weighted worlds.** Uniform
   re-deals lose at 10+ cards (-3.4 points per decision vs v7) because they
   ignore what the play revealed. Weight each world by how likely the
   other bots' observed moves are under the net (softmax of Q), and add an
   auxiliary output that predicts who holds each unseen card (labels are
   free in self-play). Then retest the "all worlds agree" rule at <= 10-12
   cards.
3. **Gate on a panel, not one opponent.** v8 iterations 5 and 6 lost their
   gate against iteration 4 (49.8 %, 51.4 %) but beat v7 59.3 % and v6
   67.4 %, better than iteration 4. Promote on the average result against
   {current best, previous shipped, v6, exploiter}, with a sequential test
   (SPRT) instead of fixed 1000-deal duels.
4. **Retrain the side nets after every promotion, automatically.** Each
   schupf retrain on the new play net was worth 3-4 pp. Add a loop step:
   after a promotion, label ~60k schupf decisions with the new net and
   retrain; re-tune the Tichu / Grand Tichu thresholds on exact
   counterfactual call labels (calls succeed more with stronger play).
5. **Style-diverse league and style tracking.** Add patient variants
   (`--style`), a bomb-holder and the heuristic as league opponents; report
   per version the pass rate and when control cards are spent, to catch
   drift towards a bot-only style.
6. **Human games.** Once the Pages build has the Supabase secrets, every
   game is saved: replay them with exact rollouts (human vs bot moves),
   and clone a human-like opponent for the league.
7. **Capacity, once the labels are better.** Retry a wider net
   (e.g. 512-256-128) with 8-12 epochs on the full v8 data; it lost only
   with 4 epochs.

Process: background jobs stop at 2 hours, so long duels (especially with
search) run in chunks of <= 600 deals; and cap torch threads
(`TICHU_TORCH_THREADS`) when two loops share the 4 cores.

## Flaws in the setup

**F1. Labels concentrated on few deals** (measured, above). Fix: label a
smaller share of decisions in many more matches (`--rollout-rate=0.1` and 5x
`--mixed-episodes` / `--self-episodes`; label count unchanged, est. +15-20 %
run time). A/B running against the uniform iteration 5.

**F2. The policy iteration has reached its fixed point** (measured). Steps
against the previous best on fresh deals: +4.2, +1.6, +0.6, +0.6 pp, then
+0.9 (rejected). One improvement step per iteration on noisy labels with a
fixed function class converges to "greedy with respect to what the net can
learn from these labels". Only less label noise per independent deal (F1),
better inputs (F9) or better side decisions (F6) move the fixed point.

**F3. The promotion gate is too coarse** (measured). 1000 deals x 2 has an
SE of 0.9 pp against steps of 0.5-1 pp: real gains get rejected and lucky
ones promoted (each gate duel was ~1 pp more optimistic than its fresh-deal
confirmation, the winner's curse). Fix: a sequential probability ratio test
(SPRT, as chess engines use to accept +1-2 Elo patches) on duplicate deals,
or 3000-deal gates now that a candidate is a small step.

**F4. The held-out training metric does not predict duels** (measured). The
wide net had the higher held-out gain and lost the duel (48.5 %); stakes
labels moved per-class gains and not the duel. Early stopping and epoch
choice run on this metric. Fix: keep it for diagnostics, choose between
methods only by duels.

**F5. One state, many opponents** (verified). League data labels the same
features with Q under v5, v6, older iterations and self-play continuations;
the net cannot see which opponent produced a label and learns a best
response to the mixture. Reasonable for unknown opponents, but the share of
data against weaker, older nets (2/3 of the league games) pulls towards
exploiting them. Test: one iteration with self-play only.

**F6. Side decisions were optimised against older play** (verified). Schupf
v2 was trained on v5's play; the call thresholds were calibrated with v5;
v7 makes calls succeed more often (Grand Tichu 76 % vs 68 % for v6, Tichu
68 % vs 65 %), so the best thresholds have moved. The Mah Jong wish is
"highest of A-K-Q-J-10 not in my hand" (it can force the partner to play or
break a bomb); the Dragon gift is "opponent without a call, else the one
with more cards" (`lib/agents/wish_strategy.dart`,
`dragon_give_strategy.dart`). Fix: retrain the schupf net on v7 games
(`--schupf-rollout-rate`, `schupf_cf_train.py`), re-tune the call thresholds
on exact counterfactual call labels (`call_labels.sh`, `call_analysis.py`),
label wish and Dragon gift exactly (every option rolled out).

**F7. Only bot opponents from one lineage** (blind spot). Humans call much
more (an expert guide: Grand Tichu in ~17 % of hands), follow conventions
and pass differently; the history features read passes as bots make them.
Nothing measures the bot against people. Fix: read the app's game records
(`public.tichu_game_records`, live since 2026-11-19), replay them headless
and roll out the human moves against the bot's moves (like
`compare_policies.py`); add league members with more aggressive call
thresholds.

**F8. Stale labels in the training mix** (verified, low impact). Older
iterations' labels are values under older policies; recency 0.8 vs 1.0
made no measurable difference (50.0 %).

**F9. Missing inputs** (verified). The play net does not see which card it
received from whom (the partner's pass tells whether the partner plans to
call; opponents' passes are low cards and say what they kept), has no
per-card ownership estimate (only per-rank unseen counts and a crude
history), and no estimate of bomb threats beyond `unseen_bomb_possible`.
Fix: received-card features (schema v7, zero-initialised weights as with
`history` and `turn`), and an auxiliary head that predicts who holds each
unseen card (labels are free in self-play).

**F10. No state value** (verified). The net learns advantages only, so
there is no value function for truncated rollouts or one-ply search. Given
the measurement (outcomes are chaotic even with all hands known: call
success AUC 0.797 -> 0.812 with perfect information), an all-hands value
net would be inaccurate early in the round, where rollouts are expensive.
Lower priority than F1.

**F11. Cost structure** (measured). Per iteration (~50 min on 4 cores):
data generation 82 % (~20 ms CPU per labelled decision: up to 12
full-round playouts), duels ~14 %, training a few minutes. A profiling
review of the headless hot path is under way (separate branch).

**F12. Process** (verified). Method changes are judged on one training
lineage (a 2026 Guandan study found duel gains that did not replicate);
`pool/itNN` holds the net replaced at iteration NN, so "vs it01" in the logs
is v6 (confusing); 2 % epsilon exploration in data games is unnecessary for
all-action labels and only perturbs the states (minor).

## Ideas, in order

| # | Idea | Expected | Cost (4 cores) | Status |
|---|------|----------|----------------|--------|
| 1 | Same label budget over 5x more deals (`--rollout-rate=0.1`) | measured: +0.7 ± 0.6 pp | +30 % per label | done, not adopted |
| 2 | Schupf v3 trained on v7 play | +1-3 pp (v1 -> v2: 54 %) | ~1 h | |
| 3 | Re-tune Tichu / Grand Tichu thresholds for v7 | +0.5 pp | ~1 h | |
| 4 | Ensemble of 3-5 nets trained with different seeds (average Q) | +0.5-2 pp, lower estimator variance | training x3-5, 0.4 ms per decision | |
| 5 | SPRT or 3000-deal promotion gate | fewer wrong promotions | +10 min per iteration | |
| 6 | Received-card features + card-ownership auxiliary head | unknown, likely small to medium | schema change + 2 iterations | |
| 7 | Exact labels for wish and Dragon gift | measured: rules already at the learnable level | done | |
| 8 | Endgame search (PIMC with short rollouts, few unseen cards) | measured: +1.17 ± 0.20 points per endgame decision (8 re-deals, unanimity + margin); duel **54.5 % ± 0.5**, +59 ± 4 per match; with <= 8 cards **57.2 % ± 0.8**, +89 ± 7 | 22.5 ms (<= 8 cards: 31 ms) per searched decision, matches 4-11x slower | **done, on in the app with <= 8 cards** (`AppBots.endgameSearch`; rl/README.md "Endgame search") |
| 9 | Human-game review from the app's records | finds what bot-vs-bot cannot | replay tool | |
| 10 | Belief-weighted worlds (softmax-Q likelihood of observed plays) for search or labels | needed if 8 or K-world labels are used | medium | |

Parked, measured or argued above: stakes-weighted labels (no gain),
out-of-turn bombs (-50 points per bomb), a wider net (48.5 %), match-win
targets (lost), learned call nets (no gain), multi-world labels (more deals
are cheaper and unbiased), flat early-game PIMC with <= 8 uniform worlds
(+0.3 ± 1.1 at best). Endgame search with <= 5 cards does win (idea 8:
54.5 % in a duel, 57.2 % with <= 8 cards) and is on in the app.

Suggested order towards 60 % against v6: 2 -> 3 -> 4, then
the loop with the winning settings and an SPRT gate; the bot that counts is
the play net plus its schupf net, so 2 and 3 count towards the bar.
