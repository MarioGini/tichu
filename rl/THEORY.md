# Beyond v10: what tichuengine.com does, and the plan to beat v10

Status 2026-11-27. This note reviews the bot behind tichuengine.com,
compares it with ours (v10 + schupf v5 + belief search ≤ 12 + solver, see
`rl/REVIEW.md`), and sets out the groundwork added for the next step. The
ship rule is unchanged: a new bot must win 60–70 % of duplicate matches
against the shipped one.

## 1. What tichuengine.com runs

Sources: the site's About page ("How the bots work under the hood", "How
the bots' neural nets are trained", "Partner-Passing Conventions") and the
fields its assessment panel shows. Strength levels: *Adept* plays the
policy net alone, *Expert* thinks for about 0.04 s, *Master* about 0.2 s,
and *Grandmaster* about 1 s per move. In its default mode, bombs and Tichu
calls out of turn are off. Out-of-turn play is an option with its own nets.

**Five components on every turn:**

1. **Belief net (recurrent).**
   - It folds the public action sequence into a *spectator belief state*:
     an init step from the grand calls and who holds the 1, then one step
     per action.
   - A prediction head combines that state with one player's private
     information.
   - It predicts per player: rank counts, high-card counts, special cards,
     which combination types they hold, the number of "singles" (cards in
     no pair or straight), and how many opponents each player goes out
     before ("race level").
2. **Policy net.**
   - Input: one player's view plus the belief predictions.
   - Output: action probabilities.
3. **Value net.**
   - Input: the full state plus the belief predictions *from each player's
     perspective*.
   - Output: the round point difference under the policy. The panel also
     shows point-split, call-outcome and exit-order distributions.
4. **Sampler (handwritten).**
   - It draws about 80 values for each predicted variable and combines them
     at random.
   - It swaps incompatible outcomes between samples until they are
     consistent.
   - It then greedily picks about 20 layouts that best match all predicted
     probabilities.
5. **Tree search.**
   - Each sampled layout is the root of its own tree.
   - At the root, the iterations follow **sequential halving**: every pass
     visits each remaining action equally, then the worst half is dropped.
   - The root statistics are **averaged across all layouts** (multi-root);
     below the root, each tree is independent.
   - A new node runs the belief step, the policy net (prior) and the value
     net (leaf value), and backs the value up.
   - The final move is the best average across roots. The panel shows the
     selection as "ln prior + σ·mean" (Gumbel AlphaZero), paired per-world
     Δ ± σ against the incumbent, and a knowledge-gradient VOI budget.

**Training.**
- About 9 M self-play games, inspired by AlphaGo, AlphaZero and Gumbel
  AlphaZero.
- The policy, value and belief nets are trained together:
  - belief: to predict the real layouts;
  - value: toward a mix of later value-net estimates and the final result
    (TD-λ style);
  - policy: toward the actions the search prefers.
- **Stage 1 (fast):**
  - the value net learns from plain policy playouts, which give volume;
  - the policy net learns from search on the *true* state, which is
    omniscient but cheap. The net does not see the hidden cards, so it
    does not learn to cheat.
- **Stage 2:** the same, with search over sampled worlds as in play.
- Earlier versions had a single policy+value net trained on face-up games.
  They were good in endgames but "always overconfident that they knew the
  full hand layout".

**Grand Tichu net.**
- Deal the 8-card hands and let the earlier players decide.
- Deal 15 layouts of the rest that are consistent with those earlier
  decisions.
- Play each with and without the call; the label is the mean difference.
- Result: calls with PD, AAP or better; AAD 60–90 %; AP 48–70 %;
  AD 10–23 %.

**Schupf (trade) net.**
- Candidates: one card to the partner plus two non-high cards to the
  opponents (suits handled by a rule).
- Each candidate is scored by the value net right after the trade,
  averaged over 9 deals consistent with the view.
- The other players pass with a recent trade net.

**Conventions.**
- Partner conventions are an *overlay* on the trade net's scores. A
  conforming pass gets so much extra weight that the bots break the
  convention only about 1 % of the time. The trade net itself is trained
  without a convention, so the main nets adapt to any convention of this
  kind.
- The partner **makes inferences** from the card: its belief net and
  sampler impute the promised high-card count.
- **2+HC Odd** (the author's own): with 2+ high cards (A, Phoenix,
  Dragon) pass odd (3, 5, 7, 9, J, K, the 1, the Dog); with 0 pass even;
  with exactly 1 pass that card. It was designed to stay as close as
  possible to the trade net's favourite pass within the three buckets
  0 / 1 / 2+.
- Variants: 2+HC Even, 2+HC Low, Give 1 HC, and "Free choice" (no
  convention).
- Exceptions:
  - when one's own team called Grand, the convention is off and the
    caller gets a high card;
  - after a right-hand opponent's Grand, one high card may already count
    as "odd";
  - a Tichu called right after the trade *reverses* the promise (and the
    bots use that).
- An **opponent** convention (Odd Left / Even Left) orders the two
  opponent cards so that partners do not both pass the same rank to the
  same opponent.

**Duplicate.** Humans play sets of 8 hands that the bots played four times
(par games A–D with different opponent conventions) and are scored against
the par average.

## 1b. The DouZero lineage (Dou Dizhu), and where we and tichuengine sit

DouZero (Zha et al., ICML 2021; code at github.com/kwai/DouZero, read
from the code since arxiv is not reachable from the training sandbox) is
the reference for climbing card games with huge action spaces.

- **Deep Monte-Carlo (DMC).** It learns Q(s, a) with the action as an
  *input*: a 4 x 15 card matrix of the play, scored by one network per
  legal action, as our play net does. Every (s, a) of an episode is
  regressed with MSE on the episode's final return: no bootstrapping, no
  search, ε = 0.01 exploration, many parallel actors.
- **Network.** An LSTM over the recent moves (162-dim per step, 128 units)
  plus 5 x 512 dense layers, one network per position (landlord and the
  two peasants).
- **Objective.** `adp` (points, ×2 per bomb) or `wp` (win probability),
  a choice like our points vs `MatchUtility`.
- **Cooperation.** The two peasants are not modelled explicitly; each has
  its own net trained on the shared team return.

Follow-ups: DouZero+ (arXiv 2204.02558) adds *opponent modelling*, a head
that predicts the other players' hands and feeds the Q net. It also adds a
*coach* network that chooses training deals by difficulty. AlphaDou
(arXiv 2407.10279) brings the bidding into the same end-to-end training.

How it maps:

- **We started as DouZero.** v1–v3 were DMC-style, Q(s, a) with action
  features. REVIEW: "Deep Monte-Carlo labels (4 M one-outcome labels):
  worse than the rollout labels at every evaluation". All-action rollout
  labels are a policy-improvement step that DMC lacks, and they carried v4
  past the heuristic. Our hand-made history group plays the role of
  DouZero's LSTM.
- **tichuengine is not DouZero.** Its About page names AlphaGo, AlphaZero
  and Gumbel AlphaZero as the inspiration. Its first bots were a single
  policy+value net trained on face-up games. It added a recurrent belief
  net, a sampler and multi-root search for the hidden information.
- **The idea all three later systems share** is the one we still lack:
  *the policy sees the belief.* DouZero+ feeds the predicted opponent
  hands into Q; tichuengine's policy and value nets take the belief
  predictions as input. Our belief net only shapes the search worlds, and
  the play net never sees it. Since `tichu_belief_v1` is a function of the
  state features alone, its outputs can be computed for every cached
  training row in Python. That makes the change a pure `data_upgrade.py`
  step: no replay, and all old data is kept (the lesson of v9 → v10).

## 2. Where we stand against that

| | tichuengine | ours (v10) |
|---|---|---|
| Policy | net (prior) | play net Q, strong and coherent over several moves (REVIEW) |
| Search scope | every decision | ≤ 12 cards in hand, plus the 1-on-1 solver |
| Search shape | ~20 sampled roots, a tree per root, sequential halving at the shared root, value-net leaves | depth 1: 8 worlds × ≤ 7 actions, full rollouts with the net |
| Budget | VOI / knowledge gradient, paired Δ ± σ | fixed grid, unanimity + margin 10 |
| Leaf | value net on the true state | full rollout to the end of the round |
| Belief | recurrent, marginals **and** hand structure, consistent sampler matching all of them | per-card marginals (`tichu_belief_v1`), sampled card by card |
| Objective | match-win probability | round points |
| Calls | gate → probe → search | heuristic (`DefaultTichuCallStrategy`) |
| Schupf | value-net-scored slates + partner/opponent conventions with inference | schupf net v5 over candidates, no convention |

Our strengths are the play net and the exact one-on-one solver. The gaps
are all on the search side:

1. **No search before 12 cards.** REVIEW: "leads have not improved since
   v3", and v10 is no better than v8 one move at a time. Full rollouts
   cost too much for 14-card hands. A value-net leaf removes that cost.
2. **The budget is spent evenly.** 8 worlds per action can neither tell 1
   point from noise nor use more worlds where it matters. That is why the
   unanimity rule, bomb strata and `minBetterWorlds` exist.
3. **Points are the wrong objective at the end of a match.** At 950 : 700,
   a 100 : 0 round is worth no more than 60 : 40.
4. **The belief is a set of marginals.** Dealing card by card from
   marginals × room is not the posterior over deals, and it misses joint
   structure (who holds the bomb, the partner's long straight).

## 3. Theory, briefly

- **PIMC (determinization)** averages perfect-information values over
  sampled deals. Its known faults are *strategy fusion* (it assumes it can
  play differently in each world) and *non-locality*. Depth-1 search with
  imperfect-information rollout bots (ours) avoids most of the fusion. A
  tree per world (theirs) goes deeper and fuses more. Deeper search needs
  the belief to carry the inference about what the opponents' moves
  revealed.
- **Sequential halving** (Karnin et al. 2013; used for the root of Gumbel
  AlphaZero, Danihelka et al. 2022) is the simple-regret-optimal way to
  spend a fixed budget on picking the best arm. With **paired worlds**, the
  comparison drops the deal's variance (189 points per round) and keeps
  only the variance of the action difference. That is far smaller, which is
  why tichuengine reports Δ ± σ rather than means.
- **Truncated rollouts with a value net** trade the rollout's variance and
  cost for the net's bias. On the true state the net has no hidden
  information to infer, only the play still to come, so it learns faster
  than the imperfect-information play net.
- **Match utility** keeps the decision rule linear in probability: the
  value of a round is ΔP(win) divided by the slope at the entering score.
  Early in a match this equals the points; late it saturates and steepens.
- **Belief networks.** The posterior over deals given the public history
  is what ReBeL / Student of Games make explicit as public belief states.
  The practical version, as in tichuengine, is a net trained on self-play
  to predict hidden quantities (marginals, structure). Its worlds are then
  sampled, or importance-weighted, to match.
- **Expert iteration.** Search plus net is a policy-improvement operator.
  Our rollout labels are a one-step version of it. Training the play net on
  the halving search's values (search as teacher) is the natural next loop
  once the search is clearly stronger than the net.

## 4. Groundwork in this branch

Nothing changes the shipped bot. Every piece is opt-in in the headless
runner.

| Piece | Where | What |
|---|---|---|
| Value net (true state) | `lib/agents/nn/value_model.dart`, `rl/value_data.py`, `rl/value_train.py` | 373 state + 168 true-holder inputs, 9 outputs: our and their round points, first out (4), double victory (3). Data comes free from bc-jsonl self-play (play rows now carry `seat`). |
| Truncated playouts | `playOutRoundPoints` in `lib/game/simulation.dart` | Plays on `simulationEngine` and returns the round points of both teams. With `leaf`, it stops at the first turn after `leafAfter` actions and asks the value net. |
| Sequential halving | `lib/agents/halving_search.dart` | Paired worlds, a fixed budget, the incumbent always kept, a prior (the net's Q in points) weighted by `priorWeight`. Deviation needs `margin` and `minZ`·σ of the paired Δ. |
| Match utility | `lib/agents/match_utility.dart` | Random-walk model fitted on v10 self-play (σ = 189 per round, leader +76 per round). `pointsEquivalent` turns a round result into points at the current slope. |
| Wiring | `EndgameSearch.halvingBudget / priorWeight / minZ / leafAfter / matchUtility`, `EndgameSearcher.value` | The halving path re-deals with the belief net, scores in points or match utility, and runs locally (not on the app's worker isolates yet). |
| Value data from records | `lib/headless/value_rows_from_records.dart`, `value_data.py --records=` | Replays the stored `*.games.jsonl.xz` games (no net runs; matches with moves rejected since #45 are cut). 448 v10-loop files → 2.5 M positions in minutes. `value_v1` (Supabase `value/value_v1.safetensors`): held-out RMSE 124.6 of 182 points, 77 % first-out accuracy. |
| Partner convention | `lib/agents/partner_convention.dart`, `NnSchupfStrategy.convention`, `EndgameSearch.partnerConvention`, `conventionAccept` | 2+HC Odd as tichuengine's overlay: the schupf net passes its best *conforming* candidate (off when the team called Grand). The partner's search re-deals by rejection until the partner's high cards after the schupf (in hand + played − the one we gave) keep the promise. `--partner-convention=2hc-odd`, `--opponent-partner-convention=`. |
| Headless flags | `--endgame-halving=N`, `--endgame-prior-weight`, `--endgame-min-z`, `--value-net=`, `--endgame-leaf-after=N`, `--endgame-match-utility`, opponent twins `--opponent-endgame-{halving,leaf-after,match-utility,max-actions}` (off by default, so side B stays the shipped bot) and `--opponent-endgame-margin` (defaults to the shared margin) | |

Example duel (A = halving with value-net leaves at every hand size, B =
shipped):

```bash
rl/.venv/bin/python rl/duel.py --deals=600 \
  --a="--nn-policy=assets/bots/tichu_q_v10.safetensors --schupf-net=assets/bots/tichu_schupf_v5.safetensors --schupf-extended \
       --endgame-search --endgame-solve --belief-net=assets/bots/tichu_belief_v1.safetensors --endgame-belief \
       --endgame-max-cards=14 --endgame-max-actions=12 --endgame-halving=96 --endgame-margin=5 --endgame-min-z=1 \
       --value-net=rl/outputs/value/value.safetensors --endgame-leaf-after=8" \
  --b="--opponent-policy=assets/bots/tichu_q_v10.safetensors --opponent-schupf-net=assets/bots/tichu_schupf_v5.safetensors \
       --opponent-schupf-extended --opponent-endgame-search --opponent-endgame-solve --opponent-endgame-belief \
       --opponent-endgame-max-cards=12 --opponent-endgame-margin=10"
```

## 4b. Results so far (duplicate duels against the shipped bot)

| Duel | A | Result |
|---|---|---|
| H | halving, ≤ 12 cards, 56 rollouts (today's budget), `minZ` 1, full rollouts | **54.4 % ± 1.2**, +80 ± 12 per match (600 deals × 2) |
| C | shipped + `--partner-convention=2hc-odd` | 43.5 %, −91 after 476 matches of the first seating; stopped |
| L | halving at every decision (≤ 14 cards, 12 candidates, 96 rollouts), `value_v1` leaves after 8 actions, match utility | 41.7 %, −109 after 115 matches of the first seating; stopped |

| H2 | halving, ≤ 12 cards, 112 rollouts | 54.8 %, +59 after 186 first-seating matches; stopped (same as H) |
| H3 | halving, ≤ 14 cards, 10 candidates, 96 full rollouts | 53.5 %, +51 after 127 first-seating matches; stopped (same as H) |
| S1 | `ctrl1` (net retrained on it11–13) + H's search | 53.9 % ± 1.2, +63 ± 13 (600 × 2): the net-only +2 pp does not add on top of search |
| it14 | one fresh rollout-loop iteration from `ctrl1` (0.9 M new decisions) vs `ctrl1`, net only | 49.2 % ± 1.1, not promoted: the net is at its fixed point |
| calls | Tichu threshold −0.6 / −0.4 / −0.25 / +0.1 / +0.3, vs-call 0 / 1, Grand 4 / 4.5 / 6 (net only, 1000 × 2 each) | 49.1–50.6 %, none better: the calibrated thresholds stay |
| **H + prior** | H with `--endgame-prior-weight=1` (the net's Q in the halving score, tichuengine's "ln prior + σ·mean") | **56.3 % ± 1.6, +106 ± 17** (300 × 2), the best so far |
| H + parity | H with `--partner-convention=parity` (odd = 2+ high cards, even = ≤ 1, no forced high-card pass) | 54.3 % ± 1.7, +61 ± 20 (300 × 2): no gain over H |
| net only: belief inputs | v10 + 168 belief inputs (zero-weight warm start), 3 epochs on it11–13 (5.6 M decisions) vs v10, no search | 51.3 % ± 1.1, +41 ± 12 |
| net only: control | the same training without belief inputs | 52.0 % ± 1.2, +27 ± 12 |

What they show:

- **More budget or larger hands add nothing over H.** At ~54–55 % the
  search side of this design is saturated.
- **Belief inputs add nothing measurable.** The belief net is a function
  of the same state features, and the play net can learn what it needs
  from them (a wider net never helped either). The +1–2 pp of both nets
  is the extra training. The control net (`ctrl1`, 431 inputs) is kept:
  it needs no belief at inference.

- **Halving works.** At the same budget, spending it on the moves still
  in contention and comparing them in paired worlds is worth +4.4 pp.
- **The convention costs more than it gives.** Forcing the conforming
  pass hands over a lone Ace or Dragon. The promise is only read by the
  ≤ 12-card search, because neither net was trained to read it. It needs
  step 6's retraining before another duel.
- **The value-net leaf is not accurate enough.** Its error (RMSE 125)
  is independent for each candidate, so pairing does not cancel it.
  Swings of that size swamp the few-point differences between moves.
  Before searching with leaves again, measure leaf vs full-rollout
  agreement on the same decisions (step 1's gate). Then train on more
  data played by the rollout bots themselves: the record data mixes v10
  with older nets.

## 5. Plan, with the gate for each step

Each step is a duplicate duel against the shipped bot (600 deals × 2
unless noted). Keep the step only if it gains.

1. **Value net v1 at scale.** Generate 5–10 M positions on the data
   workers (`value_data.py`, v10 self-play). Add suit-permutation
   augmentation, as `rollout_train.py` has. Gate: the held-out RMSE of the
   difference clearly below the spread of a single rollout. Then check
   leaf against rollout on the same positions: the decision with
   `--endgame-leaf-after=8` should agree with the full-rollout decision in
   most searched positions.
2. **Halving at the shipped scope** (≤ 12 cards, full rollouts, budget 56
   = today's 8 × 7). This isolates the allocation and the paired Δ ± σ
   rule. Expect a small gain (+1–3 pp). Tune `margin`, `minZ` and
   `priorWeight`.
3. **Search every decision** with value-net leaves (`--endgame-max-cards=14`,
   leaf after 6–10 actions, budget 64–128). This is the main bet: leads and
   early tempo are where v10 has not improved. Gate: ≥ 60 %. Check the time
   per decision too (the app budget is about 100 ms natively).
4. **Match utility** on top. It matters only late in a match, so judge it
   on the match-win share, not the margin.
5. **Belief v2.** Retrain on v10 play (REVIEW plan item 2). Add structure
   heads: bomb per seat, longest straight, and singles, as tichuengine
   has. Fix the sampler: weight each dealt world by Π p / q (the belief
   over the proposal), or deal by rejection against the structure heads.
   Gate: the duel at step 3's settings.
6. **Partner convention.** Measured alone first (duel C: shipped +
   `--partner-convention=2hc-odd` vs shipped). The inference now acts only
   through the search worlds. Next:
   - give the play and belief nets the promise as inputs (a `received`
     group bit "partner promised 0 / 2+") and retrain with the convention
     in the data, so the nets read it as tichuengine's do;
   - add the opponent convention (Odd/Even Left), which avoids
     double-passing the same rank;
   - the Tichu-after-trade reversal.

   A convention needs both partners to be our bots (in the app, a human
   partner would have to agree to it).
7. **Calls by search.** Gate the decision with the heuristic, probe the
   call's EV with the value net, and run a halving search only when the
   probe is ambiguous (tichuengine's ladder). REVIEW: call success rose at
   an unchanged call rate, so the thresholds are likely too tight.
8. **Belief as a play-net input** (DouZero+, tichuengine). Add a
   `belief` state group:
   - per opponent and partner: P(holds each high card), expected high
     cards, P(bomb);
   - computed by `tichu_belief_v1` from the state features in Dart and,
     for the caches, in `data_upgrade.py`.

   Retrain the play net on all rebuilt data with the rollout loop. Gate:
   the loop's panel gate, then the duel.
9. **Expert iteration.** Once the search wins clearly, label positions with
   the halving values (search as teacher) and train the play net on them.
   The search then starts from a stronger prior. Repeat with the
   `rollout_loop.py` gate.

Out of scope for now: a tree per world (depth > 1) and public-belief-state
methods (ReBeL). Steps 1–3 show whether the leaf is accurate enough to
search deeper.
