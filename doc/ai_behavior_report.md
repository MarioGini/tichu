# How our Tichu AI plays, and where it goes wrong

*Analysis of 2026-11-15. Bots: the heuristic `SmartAiAgent` with no nets, and
the NN play policy `rl/outputs/best_policy.safetensors`. `rl/outputs/bot_best/`
holds the same play net (identical md5) plus a value net, and no call or
schupf nets. The `tichu_net` / `grand_net` / `schupf_net` files in
`rl/outputs/` were built for an older input size and do not load in the
current binary, so all call and schupf decisions below are heuristic, for
both bots.*

Card notation: `Dr` Dragon, `Ph` Phoenix, `MJ` Mah Jong, `Dog`, `T` = 10.
Hands are listed from strongest to weakest.

---

## TL;DR

1. **The heuristic never chooses to pass.** If it holds a legal card that
   beats the trick, it plays one. This includes tricks its **partner** is
   winning: it overtakes the partner in **99 %** of beatable single or pair
   tricks, and in **66 %** of them when the partner has called Tichu. That is
   about 1.2 overtakes per team per round, with 0.08 Dragons, 0.22 Aces and
   0.04 Phoenixes spent on a trick the partner already held. This is the
   biggest weakness of the play.
2. **The NN cannot see who is winning the trick.** The features
   `trick_winner_*` and `overtakes_partner` read `deck.currentWinner`, which
   the engine never sets. Across 16,684 logged decisions they were 0 every
   time. So the net cannot learn "don't beat my partner". It copies the
   heuristic (it differs in only 4 % of moves) and overtakes the partner just
   as often (100 % / 70 %). The result is parity with the heuristic: −0.8 vs
   +0.8 points per round over 722 rounds.
3. **The Tichu calls are too loose.** Both teams call in about 60 % of
   rounds, about 0.3 calls per player per round, and only 49–54 % succeed.
   Measured exactly by forking each round (call vs. no call), calls with
   **Phoenix + 1 Ace** (called 81 % of the time) lose 20–26 points each on
   average. **Dragon + 2 Aces** loses 22 points (heuristic play). Hands with
   **3 or more of {Dragon, Phoenix, Aces}** gain +10 to +83. A rule like
   "3+ controls and no opponent has called" is worth about **+5 to +7 points
   per round** more than the current rule. No class of hand is
   systematically under-called.
4. **The rule also over-rates the Phoenix.** It scores the Phoenix like the
   Dragon (+6), and the Phoenix also completes straights, so "Phoenix +
   1 Ace" passes the call threshold 81 % of the time. "Dragon + 1 Ace" passes
   only 33 % of the time. The rule also calls into an opponent's Tichu
   (84 calls, −11 points each).
5. **The schupf breaks its own bombs.** The rule "lowest odd card to the
   left, lowest even card to the right, lowest card to partner when my hand
   is a Tichu hand" never checks for bombs. It splits **29 % of
   four-of-a-kind bombs** (40 of 139) and about half of the straight-flush
   bombs. For example, with `K K J J T T 9 8 5 3 2 2 2 2` it passes a 2 to
   the right opponent. It also gives away its **only Ace** to the partner in
   29 % of all schupfs.
6. **Bombs are thrown away early.** About 60 % of the heuristic's bombs are
   played with 14 cards in hand, mostly on the opening straight. Because the
   heuristic never passes, a bomb that is its only card able to beat a
   straight gets played.
7. **Smaller leaks:** the Mah Jong wish is a 3 in about 75 % of rounds. That
   is the card it just passed to the left opponent, so the wish hurts no one.
   It leads the Dog after its partner is out (the lead then goes to an
   opponent, 21–32 times per 506 rounds). It feeds a partner with one card
   left only if that partner called Tichu. It never calls Grand Tichu.
   Whether a simple Grand Tichu rule would gain anything is unclear: with
   heuristic play, Grand Tichu on 3+ controls scores +52 per call, and with
   NN play it scores −19 per call (n ≈ 57 each).
8. **What to fix first:** (a) set `deck.currentWinner` in the engine, or
   compute the winner from `lastPlayedBy` in the encoder, then retrain the
   NN. (b) Give the heuristic a real "pass when my partner is winning" rule.
   (c) Tighten the Tichu rule. (d) Make the schupf avoid bomb cards.

---

## 1. Tichu calls

### How the heuristic decides

`DefaultTichuCallStrategy` (`lib/agents/tichu_call_strategy.dart`) adds up an
index:

```
2·Aces − 2·Dog + 6·Dragon + 6·Phoenix + 5·bombs + #straights − #single low cards (2–7)
```

It calls Tichu when the index is ≥ 7. It decides at its first turn, after the
schupf. It never calls Grand Tichu, never calls before the schupf, and never
calls when its partner has already called. The NN bot uses the same rule.

What that means in practice:

* Dragon + 1 Ace = 8 points: a call, unless the hand has 2 low single cards.
* Phoenix + 1 Ace = 8 points, plus the Phoenix extends almost any 4-card run
  into a straight (+1). So it nearly always calls.
* 3 Aces with no Dragon or Phoenix = 6 points: never a call.

### Measured results (both seatings, 506 rounds, NN vs heuristic)

| | NN team | Heuristic team |
|---|---|---|
| Rounds with a Tichu call by the team | 58 % | 60 % |
| Calls that succeed | 51 % | 52 % |
| Grand Tichu calls | 0 | 0 |
| Going out first | 50.4 % | 49.6 % |
| Double win | 11.5 % | 11.6 % |

Call rate and success by hand type, after the schupf (506 rounds; "eligible"
means the partner had not called):

| Hand has | Eligible | Called | Success |
|---|---|---|---|
| Phoenix + 1 Ace | 144 | 90 % | **41 %** |
| Dragon + 1 Ace | 133 | 25 % | **27 %** |
| Dragon + 2 Aces | 74 | 88 % | 43 % |
| Phoenix + 2 Aces | 106 | 97 % | 52 % |
| Dragon + Phoenix + 1 Ace | 49 | 100 % | 57 % |
| Phoenix + 3 Aces | 38 | 100 % | 66 % |
| Dragon + Phoenix + 3 Aces | 10 | 100 % | 100 % |

A Tichu that succeeds only 41 % of the time loses 18 points on the bonus
alone. That is before counting the cards and tricks the team loses while
trying to make it.

### Exact value of each call (counterfactual)

`--counterfactual-calls` plays every round twice from the call decision,
once with the call and once without, and reports `cf` = points with the call
minus points without (for the caller's team). These are 30 games to 1000
points, all four players heuristic (372 rounds); the second figure in each
cell comes from the same deals played by the NN (382 rounds).

| Controls (Dragon + Phoenix + Aces) | Decisions | Called | Mean cf (heuristic play / NN play) | Share of decisions where the call gains |
|---|---|---|---|---|
| 0 | 234 | 1 % | −58 | 22 % |
| 1 | 435 | 6 % | −57 | 24 % |
| **2** | 285 | **46 %** | **−29** | 36 % |
| 3 | 191 | 87 % | +10 | 50 % |
| 4 | 101 | 100 % | +42 | 66 % |
| 5 | 15 | 100 % | +83 | 87 % |

The 2-control row is the mistake. The heuristic calls almost half of these
hands, and on average they lose about 30 points per call.

By hand type, mean cf of the calls the heuristic makes (heuristic play / NN
play):

* Phoenix + 1 Ace: −20 / −26 (called 81 %)
* Dragon + 2 Aces: −22 / +2
* Phoenix + 2 Aces: +19 / −8
* Dragon + Phoenix + 1 Ace: +49 / +43
* Phoenix + 3 Aces: +62 / +37

Alternative rules, scored on the same deals with exact cf. Values are points
per round, summed over both teams, compared with never calling.

| Rule | Calls (% of eligible) | Heuristic play | NN play |
|---|---|---|---|
| Current rule (as played) | 35 % | +15.5 | +9.5 |
| Current rule, but not after an opponent called | 28 % | +18.0 | +11.8 |
| Current rule, minus "single Dragon or Phoenix, ≤ 1 Ace, no bomb" | 25 % | +19.9 | **+17.0** |
| Dragon + Phoenix, or (Dragon or Phoenix) + ≥ 2 Aces, or (Dragon or Phoenix) + bomb | 24 % | **+21.6** | +16.8 |
| ≥ 3 controls and no opponent called | 20 % | **+22.2** | +14.7 |

Every tighter rule beats the current one by about 5–7 points per round. No
looser rule helps: among uncalled hands, no hand type has a positive mean cf.

**Caution about single-deal cf values.** A call changes how the partner and
the opponents play: the partner makes support passes and the opponents bomb
earlier. The whole round then plays out differently. Single cf values are
therefore very noisy. Junk hands sometimes show +500 (for example
`K Q J T T 8 7 5 5 5 4 4 3 2`, cf +530). A "perfect caller" bound summed from
these single values (+160 points per round) is not a realistic target. Use
the averages by hand type above.

### Example calls

1. **Mis-call: Phoenix + 1 Ace, low cards.**
   `Ph A K Q J T T 9 9 8 8 3 2 Dog` (index 8). The hand has one sure winner
   (the Ace), a Dog it must get rid of, and 3 and 2 as loose single cards.
   The left opponent has `A A K K Q …` and is stronger. Value: −490 (NN play).
2. **Mis-call: Dragon + 1 Ace with many small cards.**
   `Dr A J T 9 8 6 6 5 4 4 3 2 2` (cf −380). The low pairs cost about
   4 tricks, and both opponents hold 2–3 Aces between them.
3. **Calling into an opponent's Tichu.** `Dr A 9 9 8 8 7 6 5 5 4 4 3 2`
   after an opponent had called (cf −380). Across all deals, calls made
   after an opponent had called average −11.
4. **Even a good-looking Phoenix call loses.**
   `Ph A K Q J T T 9 6 6 6 3 2 MJ` lost 480 with both bots. The right
   opponent had Dragon + Dog plus a bomb's worth of low cards, so the long
   straight did not get the lead back.
5. **Good call that the rule makes correctly.** `Dr Ph A …` and
   `Ph A A A …` hands average +40 to +60 per call.

### Grand Tichu and Tichu before the schupf

Neither bot ever calls these. Measured cf on the first 8 cards (Grand Tichu):

* 0–2 controls: −56 to −75 per call.
* ≥ 3 controls: +52 per call with heuristic play (56 calls), but −19 per
  call with NN play (58 calls).

Inconclusive. It needs a few hundred rounds to decide.

A Tichu call before the schupf has negative cf for every hand type (−3 to
−27 per call). That is expected: today's partner gives a strong card anyway,
and the late call is still available.

---

## 2. Schupf (passing cards)

The rules in `DefaultSchupfStrategy` (`lib/agents/schupf_strategy.dart`):

* To the left opponent: the lowest **odd** card ≤ 10.
* To the right opponent: the lowest **even** card ≤ 10.
  (Both partners follow this, so one opponent never gets two cards of the
  same rank from us.)
* To the partner: the best normal card (never Dragon, Phoenix, Dog or
  Mah Jong). If my own hand counts as a Tichu hand, the lowest card instead.
* The Dog goes to an opponent only if that opponent has called.

What it passed in 2,024 schupfs:

* **To the partner:** Ace 45 %, King 17 %, a 2–5 card 27% (these are the
  "my hand is a Tichu hand" cases). In 586 cases, 29 % of all schupfs, the
  Ace was the passer's **only** Ace.
* **To opponents:** 2 or 3 in 70 % of cards, 4 or 5 in 22 %.
* The Dog was passed to an opponent in 4 of 506 rounds. Opponents almost
  never call before the schupf, so the Dog is nearly always kept.
* **Supporting a partner who called:** this code path never runs, because
  no bot calls Grand Tichu or Tichu before the schupf. It is dead code
  today.

### Bomb breaking (a bug)

`_pickLowestByParity` and `_pickLowest` do not look for bombs. **40 of 139
hands with four of a kind gave away a card from the bomb**, and so did 36 of
66 hands with a straight-flush bomb. Examples:

* `K K J J T T 9 8 5 3 2 2 2 2`: passes the **2** to the right (the lowest
  even card). The bomb is gone.
* `Ph K Q Q 8 8 7 6 4 3 3 3 3 2`: this is a "Tichu hand", so the partner
  also gets the lowest card. Left gets a **3**, partner gets a **3**, right
  gets the 2. Two cards of the bomb leave.
* `Ph A K Q T 9 8 7 4 2 2 2 2 Dog`: partner gets a 2 and right gets a 2.
* `A K Q Q J T T 9 8 7 6 6 6 6`: partner gets a 6 and right gets a 6.

Gifts the other way are rare and mostly unavoidable. An opponent's bomb was
completed by one of our cards in 37 of 2,024 schupfs (1.8 %). The parity
convention does its job.

---

## 3. Play

### 3.1 The basic style: "always beat it if you can"

`SmartAiAgent.selectTurn` (`lib/agents/smart_ai_agent.dart`) returns a pass
in only these cases: it has no legal play; the "partner support pass" applies
(`PlayTacticsPolicy.selectPartnerSupportPass`, only when the partner called
Tichu); or the only beating card is the Phoenix on a trick below a King.
Every other time, the `TurnScorer` chooses **which** card to play, and
"pass" is never one of the options.

Measured on single and pair tricks, where it was checked whether the bot
could beat the trick (2 × 40 games):

| Situation (bot can beat the trick) | Heuristic plays | NN plays |
|---|---|---|
| Opponent is winning | 100 % | 100 % |
| **Partner is winning, no Tichu call** | **99 %** (440/446) | **100 %** (450/451) |
| **Partner is winning and called Tichu** | **66 %** (109/164) | **70 %** (127/182) |
| Pass rate on any trick it could beat | 1.6 % | 1.8 % |

Overtaking the partner, all trick types: 620 times (heuristic) and 633 times
(NN) in 506 rounds. The cards used: Ace 113 / 125, Dragon 40 / 47,
Phoenix 19 / 19, bomb 7 / 7, and in 54 / 57 cases a play that went out.

Examples from the logs:

1. **Dragon on the partner's King.** Hand `Dr J J T 9 8`; the partner leads
   or wins with a King. The bot plays the Dragon, wins the trick, and must
   then **give it to an opponent**: those points plus the Dragon's 25 change
   sides. Same with `Dr A A K J T 7 7 7 6 6 3 2` on the partner's King, and
   `Dr A A A K K J J T T 9 9 2` on the partner's Jack.
2. **Phoenix on the partner's Ace.** `Ph A J J 8 7 3`: the partner's Ace is
   winning, and the bot spends its Phoenix to take the trick.
3. **Bomb on the partner's straight.** `Ph A K T T 8 7 7 7 7 6 6 3 2`: the
   partner leads an Ace-high straight (A-K-Q-J-T) and the bot bombs it with
   7-7-7-7.
4. **Breaking the partner's Tichu (game 2, round 1).** The caller
   (`Dr A A A K Q T T T 7 7 6 3 2`) plays a Queen. The partner overtakes it
   with a King. The caller has to burn an Ace to get the lead back. The
   opponents win the round 190 to −90.
5. **Both partners fight each other (game 3, round 1).** The caller
   (`A 9 9 9 9 8 7 7 5 5 5 5 3 2`, called on two bombs) plays an Ace. The
   partner (`Dr Ph A K K Q …`, the real Tichu hand) overtakes with the
   Phoenix. The caller then **bombs its own partner's Phoenix** with
   9-9-9-9.

Why this happens: there is no rule like "let the partner's winning trick
stand". `TurnScorer` even adds `+1 × trick points` for capturing points
(`trickPointCapture`) without checking who is winning, so a point-heavy
trick held by the partner looks attractive to take.

### 3.2 Bombs

The heuristic played 53 bombs in 506 rounds and the NN 50. **About 33 of the
heuristic's 53 were played with all 14 cards still in hand**, mostly on the
opening straight. The heuristic does not pass, and the bomb is its only
card that beats a straight.

* `A K T T 9 9 9 9 7 5 4 3 3 2`: bombs a low opening straight (worth 0
  points or less) with 9-9-9-9.
* `Ph A K T 9 9 8 7 7 7 7 6 5 2`: bombs a straight worth 10 points with
  7-7-7-7.

Later in the round these bombs would stop an opponent's Tichu or win a
Dragon trick. The scorer applies `bombUsageEarly = −6`, but that only ranks
plays against each other; it never makes the bot pass instead. The
`DefaultBombTimingStrategy` exists but always returns false and is not
wired in.

### 3.3 Dragon, Phoenix, Dog, Mah Jong

* **Dragon:** about 40 % of Dragon plays (100 of 244) capture a trick worth
  ≤ 5 points, 62 of those with 8 or more cards in hand. Example:
  `Dr A A K K Q T 9 6 6 5 3` on a single Ace, 0 points. The bot gives 25
  points to an opponent and gets only the lead back. The Dragon is given to
  the opponent who has not called Tichu, or else to the one with more cards;
  that part is fine.
* **Phoenix:** the scorer saves the Phoenix if a natural Ace can do the same
  job, which is good. With the "never pass" rule, though, it still lands on
  the partner's Ace (see 3.1).
* **Dog:** it is led at the first chance (`selectEarlyDogLead`). This goes
  wrong when the **partner is already out**: the lead then passes to the
  next active player, who is an opponent. That happened 21 times
  (heuristic) and 32 times (NN) in 506 rounds. The Tichu caller also leads
  the Dog itself (57 times).
* **Mah Jong:** it is led as part of a straight only in round 1
  (`isGameOpeningLead` requires `roundNumber == 1`). The **wish** is the
  card it just passed to the left opponent: a 3 in 383 of 541 wishes. That
  opponent can play the 3 whenever it likes, so the wish costs them nothing.

### 3.4 Partner who called Tichu, opponent who called

* **Partner called:** the bot passes only on pairs and longer combos, and on
  singles of King or higher (or ones that cannot be beaten). On anything
  lower it overtakes (66 % of beatable tricks). It feeds a partner with
  1 card left only if that partner called Tichu (`selectPartnerFinishLead`).
  When the partner had 1 card and the bot held no Dog, it did **not** lead
  its lowest single in 56 of 164 cases, for example leading T-T while the
  partner had 1 card.
* **Opponent called:** the bot always beats an opponent's trick (100 %) and
  bombs more readily (`bombUsageLate = +6`). The cost: after an opponent's
  Tichu call it bombs early, even with 14 cards.

### 3.5 Endgame

* **An opponent has 1 card, I lead.** The bot leads a beatable single in
  170 of 472 cases. Only 18 of those had a pair or longer lead available;
  the rest had nothing else. This is mostly forced, so it is not a real leak.
* **Going out:** the bot always plays out when it can (hard rule). That is
  correct.

### 3.6 NN vs heuristic

| | NN | Heuristic |
|---|---|---|
| Points per round (722 rounds, duplicate) | 63.1 | 63.9 |
| Point difference per round | −0.8 | +0.8 |
| Moves that differ from the heuristic | 4.2 % (11 % of leads, 2.6 % of follows) | — |

Where the NN differs:

* Which single to play: it plays a cheaper card where the heuristic burns an
  Ace (A-J-8 on an 8: the heuristic plays the Ace, the NN the Jack).
* Leading a single instead of a pair, or the other way round.
* Leading the Mah Jong alone instead of in a straight.
* A few passes (17 cases).

The round results attached to these differences are noisy, roughly −30 to
+80 depending on the type with 15–50 cases each. Overall it is a wash.

The NN is a faithful copy of the heuristic, and it cannot do better on the
key decision: two of its inputs are always 0. `encodeStateFeatures` reads
`deck.currentWinner` for `trick_winner_self/left/partner/right`
(`lib/agents/nn/feature_encoder.dart:201`), and the action feature
`overtakes_partner` reads it too (`:398`). The engine never assigns
`DeckState.currentWinner` (`lib/game/turn/tichu_data.dart:202`, only copied
in `engine_state.dart:54` and `engine_impl.dart:234`). The heuristic does not
notice, because it falls back to `snapshot.lastPlayedBy`
(`turn_scorer.dart:121`). The NN has no such fallback: it does not know
whether it is about to beat its partner or an opponent. Every bc-jsonl
dataset recorded so far carries the same zeros.

The same kind of problem hits the call nets. Their "received schupf cards"
input (`receivedSchupfFeatures`, `nn_tichu_call_strategy.dart:24`) reads
`snapshot.schupfSelections`, and that map is cleared as soon as the exchange
finishes (`lib/game/turn/utils/engine/schupf.dart:126`). In all 88 Tichu
decisions of a test log, all three received-card slots were empty. So the
"react to the partner's pass" input does nothing. `snapshot.schupfReceipts`
still holds the cards and is the right source.

---

## 4. Failure modes, ranked

"How often" is per team per round, from 506 to 722 rounds. Costs are
estimates in points per team per round. Only the Tichu numbers are exact
(counterfactual); the play numbers are rough, based on the points that
change hands.

| # | Mistake | How often | Estimated cost | Why it happens | Fix |
|---|---|---|---|---|---|
| 1 | **Overtaking the partner's winning trick** with Ace, Dragon, Phoenix or a bomb (Dragon gives 25+ points to the opponents) | ~1.2 overtakes, of which ~0.35 use a control card | **~8–15** (Dragon ~4, Ace or Phoenix waste ~3–5, broken partner Tichus ~2–5) | The heuristic has no voluntary pass (`selectTurn`). The scorer rewards capturing points regardless of who wins the trick. The NN cannot see the winner (#2). | Add a pass option: if the partner is winning and no opponent who called Tichu is close to going out, pass unless the play is cheap (a low card that also sheds a loose single) or goes out. Make pass a scored option in `TurnScorer`. |
| 2 | **NN input bug: trick winner and overtakes-partner always 0** | every decision | Blocks the fix for #1 in the NN; the policy can only copy the heuristic | `DeckState.currentWinner` is never set by the engine | Set `currentWinner` when a play resolves (and clear it at trick end), or use `lastPlayedBy` in `FeatureEncoder`. Then regenerate the data, retrain BC/AWR, and add a test that the feature is non-zero mid-trick. |
| 3 | **Loose Tichu calls** (2 controls, Phoenix + 1 Ace, calling after an opponent) | 0.3 calls per player per round, 46 % fail | **~3–4** per team (exact: tighter rules +5–7 per round, summed over both teams) | Index threshold 7 is too low. Phoenix +6 is the same as Dragon, plus straight credit. Opponents' calls are ignored. | Require ≥ 3 of {Dragon, Phoenix, Aces}, or (Dragon or Phoenix) with ≥ 2 Aces or a bomb. Count low single cards more heavily. Do not call after an opponent has called unless very strong. |
| 4 | **Early bombs** (14 cards, on the opening straight) | ~0.06 | ~1–2 | No pass option, so the only card that beats the straight gets played | Wire `BombTimingStrategy` into `selectTurn`: bomb with 10 or more cards only if an opponent called, the trick has ≥ 20 points, or an opponent is about to go out. |
| 5 | **Schupf breaks own bombs**; gives away an only Ace | bomb: ~0.08 (4-of-a-kind and straight flush); only Ace: 0.6 | ~1–2 (bomb); ~1 (Ace) | `_pickLowestByParity` and `_pickLowest` ignore bomb cards. The partner gets the best card even when it is my only Ace. | Leave bomb cards out of all candidate pools (fall back to the next card of the same parity, or to the other parity with a swap). Give the partner a King when it would otherwise be my only Ace. |
| 6 | **Dragon spent on a trick worth ≤ 5 points early** | ~0.1 | ~1–2 | `controlPreservation −3` is too weak; the Dragon wins the trick for sure, so `sureTrickCapture +4` cancels it | Penalise the Dragon by `(25 − trick points)` unless it is needed (an opponent about to go out, or the bot about to finish). |
| 7 | **Dog led after the partner is out** (lead goes to an opponent) | 0.02–0.03 | ~0.5 | `selectEarlyDogLead` does not check whether the partner is out | Lead the Dog only while the partner still holds cards. |
| 8 | **Not feeding a 1-card partner who did not call** | ~0.1 | ~1 | `selectPartnerFinishLead` requires a Tichu call by the partner | Drop that requirement. Lead the lowest single, or the Dog. |
| 9 | **Useless wish** (a 3 in ~75 % of rounds) | every Mah Jong | ~0.5 | It wishes the card it passed left, which is always a low card | Wish a high rank I don't hold (A/K), or a rank that would split an opponent's bomb. |
| 10 | **Grand Tichu never called** | — | 0 to +4 (unclear) | `shouldCallGrandTichu` returns false | First collect more counterfactual data (≥ 300 rounds). "≥ 3 controls in 8 cards" is the candidate rule. |
| 11 | **Call-net "received cards" input always empty** | every call net | Weaker call nets | `schupfSelections` is cleared after the exchange | Read `snapshot.schupfReceipts` instead, then retrain the call nets. |

Rough total: about 15–25 points per team per round are left on the table.
For comparison, a typical round is worth 100 points plus Tichu bonuses.

Suggested order: #2 and #1 together (the NN can only learn #1 once #2 is
fixed), then #3, #5 and #4, which are small heuristic changes. Re-measure
with the duplicate eval after each step.

---

## Appendix: how this was measured

All runs from `/home/user/tichu`. `build/bin/headless_dev` was used
throughout (no recompiling), each script in a single process.
`$S` = scratchpad directory
`/tmp/claude-0/-home-user-tichu/ae159fbf-ce92-51ac-bcb4-394a13b21561/scratchpad`.
The play net was copied to `$S/bot/` first.

```bash
# 1. Round outcomes and NN-vs-heuristic deviations (60 deal sequences x 2 seatings, target 500)
TICHU_HEADLESS=/home/user/tichu/build/bin/headless_dev rl/.venv/bin/python rl/analyze_games.py \
    --nn-policy=$S/bot/best_policy.safetensors --episodes=60 --shards=1 --examples=20

# 2. Mixed games with shadow heuristic (per-decision data), both seatings, plus the same games as csv logs
build/bin/headless_dev --seed=777 --deal-seed=777 --episodes=40 --target-score=500 --mixed \
    --nn-policy=$S/bot/best_policy.safetensors --format=bc-jsonl --shadow-heuristic --output=$S/runs/mix0.jsonl
build/bin/headless_dev --seed=778 --deal-seed=777 --episodes=40 --target-score=500 --mixed --swap-teams \
    --nn-policy=$S/bot/best_policy.safetensors --format=bc-jsonl --shadow-heuristic --output=$S/runs/mix1.jsonl
#   (same two commands with --format=csv --no-timestamps -> mix0.csv / mix1.csv; the games come out
#    identical, checked round by round)

# 3. Exact call values: 30 games to 1000, all-heuristic and all-NN-play
build/bin/headless_dev --seed=101 --deal-seed=101 --episodes=30 --target-score=1000 \
    --format=bc-jsonl --counterfactual-calls --skip-play-rows --output=$S/runs/cf_heur.jsonl
build/bin/headless_dev --seed=101 --deal-seed=101 --episodes=30 --target-score=1000 \
    --format=bc-jsonl --counterfactual-calls --skip-play-rows \
    --nn-policy=$S/bot/best_policy.safetensors --output=$S/runs/cf_nn.jsonl
```

Throwaway parsers in `$S`:

* `calls.py`: cf by hand type, worst and missed calls.
* `rules.py`: alternative call rules scored with cf.
* `callstats.py`: call rate and success by hand type.
* `schupf.py`: what is passed, broken bombs, bomb gifts.
* `play.py` and `play2.py`: pass rates, bombs, Dragon/Dog/Phoenix, leads,
  endgame, deviations.
* `csvplay.py`: rebuilds each trick from the csv logs to find who was
  winning, partner overtakes, and Tichu callers (matched by hand from the
  call rows).

Trick winners come from the csv logs, because the bc-jsonl winner features
are always 0 (bug #2).

Limitations:

* The cf values are exact only for these deterministic bots on these deals.
  A call also changes everyone else's play, so single values are noisy.
* Play costs in section 4 are estimates, not A/B measurements. Confirm a fix
  with `rl/evaluate_policy.py`-style duplicate evaluation.
* The sample sizes (372–722 rounds) give standard errors of about ±5–10
  points per round on round differences.
