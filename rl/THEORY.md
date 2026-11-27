# Beyond v10: what tichuengine.com does, and the plan to beat v10

Status 2026-11-27. This note reviews the bot behind tichuengine.com,
compares it with ours (v10 + schupf v5 + belief search ≤ 12 + solver, see
`rl/REVIEW.md`), and sets out the groundwork added for the next step. The
ship rule is unchanged: a new bot must win 60–70 % of duplicate matches
against the shipped one.

## 1. What tichuengine.com runs

The site publishes no write-up. Its web client does contain the
"Advisor Bot" and the bot-assessment panel, though, and those name every
quantity the server returns. The picture below comes from those field names
and labels (client bundle of 2026-11-27, changelog "11/10: Small bot
strength improvements"). It shows what they compute, not how well.

| Component | Evidence in the client | Reading |
|---|---|---|
| **Determinized tree search** | `possible_states`, `search_trees` (one tree per state, with `nodes`, `child_state_values`), "Top Tree Search Visits", "Top Tree Search Value Estimates", `tree_search_value_stdevs` | Sampled deals ("universes"), each with its own search tree. It is PIMC with a tree per world, not our depth-1 rollouts. |
| **Policy prior + completed Q** | "Pick = best CQ (ln prior + σ·mean)", `p_best_prior`, `completed_q`, a "Policy" column | The Gumbel AlphaZero / MuZero selection rule: a policy net's log-prior plus a monotone transform of the mean value. |
| **Value-of-information budget** | "VOI Search", `iterations_used / effective_budget`, `trimmed_candidates`, "KG = expected decision gain (pts) of one more sample" | Samples go to the candidates where one more sample is most likely to change the decision (knowledge gradient), and hopeless candidates are trimmed. |
| **Paired comparison** | "Δ = paired per-universe diff vs incumbent (pts, world luck cancelled) ± σ" | Every candidate is played in the same universes, and the decision uses the per-universe difference to the incumbent (common random numbers). |
| **Value net on the true state** | "Outcome Prediction (value net, true state)": `point_probs` (point-split bins), `call_probs` (joint Tichu outcomes per seat), `exit_order_probs` (finishing orders), "Exit 1st" | A perfect-information value net with *distributional* heads, used as a leaf evaluator. The bins also allow non-linear utilities. |
| **Rich belief net** | `belief_prediction`: `high_card_probs`, `combo_probs`, `rank_expected_counts`, `straight_length`, `stair_length`, `rough_singles_count`, `race_level` ("P beats # opponents"), `joint_lho_lacks_partner_has` | Besides card locations, it predicts hand **structure**: bombs, straight and stair lengths, singles, how many opponents a player can beat, and joint events across seats. |
| **Match utility** | `use_match_utility`, `match_win_prob`, `match_point_slope` ("pp/pt, EV-equiv 0.5"), match scores as inputs | Values are the acting team's match-win probability, converted back to points at the current slope. |
| **Staged call decisions** | "Interrupt Windows", gate priors (`prior_source`, ε, δ points), `probe_evs`, `probe_verdict`, `last_chance`, stages 1–3 ("declined at gate", "ambiguous → stage-3 search") | Tichu calls and bombs out of turn ("interrupts") go through a ladder: a policy gate first, then a cheap probe EV, and a full search only when the probe is ambiguous. |
| **Slate-level schupf** | "Assess Trade", `top_slates_by_position` with a rating per 3-card slate | A policy over complete slates, not over each card on its own. |
| **Wish politeness** | "Base = z-scored completed-Q; Polite = Base − λ·Proxy" | A wish is scored by its search value minus a penalty for self-harm. |
| **Conventions and duplicate** | partner/opponent trade conventions ("with 0 high cards, pass high"), par games A–D | Passing conventions are a table setting, and humans are scored against four bot par games of the same deal. |

The advisor also labels a move "conservative" or "greedy" (best when the
cards lie badly or well for us) and shows "~X % chance an opponent can beat
this" (the share of worlds with an answer).

## 2. Where we stand against that

| | tichuengine | ours (v10) |
|---|---|---|
| Policy | net (prior) | play net Q, strong and coherent over several moves (REVIEW) |
| Search scope | every decision | ≤ 12 cards in hand, plus the 1-on-1 solver |
| Search shape | tree per world, prior + completed Q | depth 1: 8 worlds × ≤ 7 actions, full rollouts with the net |
| Budget | VOI / knowledge gradient, paired Δ ± σ | fixed grid, unanimity + margin 10 |
| Leaf | value net on the true state | full rollout to the end of the round |
| Belief | marginals **and** hand structure | per-card marginals (`tichu_belief_v1`), sampled card by card |
| Objective | match-win probability | round points |
| Calls | gate → probe → search | heuristic (`DefaultTichuCallStrategy`) |
| Schupf | slate policy | schupf net v5 over candidates (similar) |

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
6. **Calls by search.** Gate the decision with the heuristic, probe the
   call's EV with the value net, and run a halving search only when the
   probe is ambiguous (tichuengine's ladder). REVIEW: call success rose at
   an unchanged call rate, so the thresholds are likely too tight.
7. **Expert iteration.** Once the search wins clearly, label positions with
   the halving values (search as teacher) and train the play net on them.
   The search then starts from a stronger prior. Repeat with the
   `rollout_loop.py` gate.

Out of scope for now: a tree per world (depth > 1) and public-belief-state
methods (ReBeL). Steps 1–3 show whether the leaf is accurate enough to
search deeper.
