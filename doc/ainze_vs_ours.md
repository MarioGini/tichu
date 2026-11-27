# ainze/tichu's findings next to ours

ainze/tichu (`arena/.bots/ainze__tichu/docs/notes`, 30 notes, and 45 ADRs)
is the most careful public Tichu AI research. Their bot is behaviour cloning
on ~100 k BSW human games, refined by AWR, PPO and co-training. Sean
McCarthy's bot beats it by 44 a round. Ours is `rl/REVIEW.md`: rollout
policy iteration plus endgame search.

What follows sets their measured findings next to ours: where we agree,
where we disagree, and what we should do about it. Both projects report
their numbers from duplicate (seat-swapped) matches.

## Where we agree

| Finding | ainze | ours |
|---|---|---|
| A bigger net does not help | 2.25× trunk: +0.08 pp play accuracy; "label-bound, not capacity-bound" | 512-256-128: no gain; "capacity is not the limit" |
| One-outcome returns are a weak signal | AWR game target flat; PPO plateaued at +8 because a +60 effect in < 1 % of states sits below the outcome noise | Deep Monte Carlo labels (4 M) worse than rollout labels at every evaluation |
| Calls are not a lever | lowering the call threshold is −EV; "call heads do not matter at all" | the heuristic call rule is worth +1.8 (Grand) / +3.8 (Tichu); marginal Tichu calls lose 13.5 each |
| Inference-time tweaks are exhausted | 15 forced-play and threshold probes, all neutral or −EV | the rule tweaks in `ai_strategy.md` §3b are measured one by one; most are neutral |
| Gate statistics decide progress | a gate that treated paired deltas as unpaired held 129 windows while the learner won every one | a single-opponent gate was too noisy, and a panel gate let iterations exploit old nets; now panel plus ≥ 50 % against the best |
| Out-of-turn bombs are small | ~2 % of human rounds; the uncovered bomb moments change ~4 % of deals | out-of-turn bombs for bots: no gain |
| Warm starts, not resets | from-random and shrink-and-perturb: RL never wins back a 5-point dent | every net warm-starts from the previous one |
| Belief has little headroom | belief net only 2–4 pp top-1 above a hand-size baseline | belief-weighted worlds: +2.5 pp in the search |

## Where we differ, and why it matters

1. **The training signal.** This is the big one.
   - **ainze**: their central lesson is that within-world paired
     comparison of alternatives is the signal outcome-based RL lacks. Their
     blunder miner finds ~1 true blunder per 50–60 rounds, worth ~+60 each,
     that PPO cannot see. They call this "the one mechanism this codebase
     has never tried".
   - **Ours**: our rollout labels are exactly that mechanism. Each legal
     action is played out from the same position and the advantages are
     regressed. It took us from parity with the heuristic to clearly ahead,
     and it is why our bot beats theirs-class bots.
   - **The catch**: they also found that 96–99 % of single-world hindsight
     gains vanish across worlds consistent with what the player knows. Our
     loop labels in the *real* deal only (`--rollout-worlds=1`), with
     rollouts that see every hand, so our labels carry that hindsight noise.
     Averaging out noise of that size takes data, and we found that data
     volume was a lever (v10 iterations 9–10).
   - **To do**: re-test `--rollout-worlds=K` with **belief-weighted**
     worlds, and the rollout bots playing from their own view. We tested
     "more rollout worlds: no gain" before belief worlds existed.
2. **Search at decision time.**
   - **ainze**: one-step search on top of a finished policy gains almost
     nothing. A value net overriding the policy costs −70 to −116 a round;
     even a cheating play-out in the real deal gains only +7.
   - **Ours**: endgame search wins 57 % against the same bot without it,
     the one-on-one solver adds +11.5 a match, and belief worlds add more.
   - **Why both can be true**:
     - Our search runs only late (≤ 12 cards).
     - It plays every candidate to the end with the policy in 8 sampled
       worlds, with no value net.
     - It overrides only when the move is no worse in *every* world and
       better by a margin.
     - Late positions are where world sampling is accurate and play-outs
       are short.
   - **To keep in mind**: extending this search to early positions will
     likely hit their wall, because a near-top policy's alternatives are
     close in value.
3. **Where the remaining gain is.**
   - **ainze**: polishing a finished policy is capped. Sean's gain comes
     from search *inside* the training loop: policy targets from ~20-world
     shallow search with a value net, over millions of games.
   - **Ours**: we generate training data **without** search (4–10× slower
     with it).
   - **To do**: expert iteration. Run the rollout loop with the endgame
     search on for the learner's own decisions, and train the policy on the
     searched move, first late in the round where our search is proven.

## Their findings we have not checked

- **Caller passivity and combo-breaking.** Their BC undervalued bombs: a
  committed Tichu caller ceded winnable tricks, and the bot shed cards that
  broke its own bomb. Our v8 notes say the opposite drift: more patience,
  bombs kept. We have never measured these two rates directly. To do: add
  both rates to `style_report.py`, comparing ours with tichubot and h2 in
  arena games.
- **Partner coordination.** Their literature sweep names joint policy
  improvement for the 2v2 partnership (bridge-style, JPS family) as the
  structurally untested failure mode of 2v2 self-play. We have not tested
  it either. A cheap probe: duel "our bot + a copy" against "our bot + h2
  as partner" to see how much partner modelling is worth.
- **Distilling mined blunders.** Fine-tuning on 483 verified corrections
  fixed 21 % of held-out ones, but cost −18 in play. A strongly anchored
  version was neutral. Our loop already regresses all-action advantages
  with a warm start, the safer form of the same idea; do not add naive
  cross-entropy fine-tunes.
- **Human data.** They train on BSW logs. We store human game records in
  Supabase, but nothing reads them. Their deciles show the top human
  players are a meaningful target.

## Next steps, in order

1. **Expert iteration, late-round first.** Label the learner's decisions
   at ≤ 12 cards with the searched move instead of the net's.
2. **Belief-weighted multi-world rollout labels**, re-testing
   `--rollout-worlds` with the belief net.
3. **Caller-passivity and combo-breaking rates** in `style_report.py`,
   measured in arena games.
4. **Partner-coordination probe**, with h2 as partner.
