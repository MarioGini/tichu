# Heuristic bot: remaining weaknesses in the play phase

*Analysis of 2026-11-15. Bot: `SmartAiAgent` with `HeuristicOptions.latest`
(guard + strict), all four seats, no nets. Runner: `build/bin/headless_dev`.
Data: 150 matches to 1000 points, seed 9001: **1,866 rounds, 57,600 plays**.
Every play was replayed from the CSV log, with full hands and exact card
tracking (see the appendix).*

Card notation: `Dr` Dragon, `Ph` Phoenix, `MJ` Mah Jong, `Dog`, `T` = 10.
Hands are listed from strongest to weakest. "Est" means
`HandShape.estPlays`, the estimated number of plays needed to go out. A clean
play lowers it by 1. A play that leaves it the same or raises it has damaged
the hand.

---

## How to read the costs

Going out first is worth a lot. In this data the team that goes out first
gains **+100 points of round difference on average** (+49 in rounds without
a Tichu call). Most of that comes from Tichu bonuses and 1-2 finishes. Card
points alone are about even (−4). So the costs below are mostly "first-outs
lost × about 100". They are given as **points of round difference per team
per round**, the same unit as `doc/ai_behavior_report.md`.

All costs are **rough estimates** from observed data, not A/B tests. The
logs show what the bot did and what else it could have done. They do not
show how the round would have gone. Where I could control for hand strength,
I did, and the estimate came out 2–3× smaller than the raw correlation. I
used the smaller numbers. The weaknesses overlap (1 and 3 especially), so do
not add the costs up. Each fix should be confirmed with a duplicate A/B run
behind a new `HeuristicOptions` flag.

---

## Ranked summary

| # | Weakness | How often | Est. cost (per team per round) |
|---|---|---|---|
| 1 | **Never passes on an opponent's trick.** Breaks combos, burns Aces and the Phoenix in early "climbing wars" | Plays on 99.9 % of beatable opponent tricks. 0.7 shape-damaging follows per team-round with ≥ 10 cards | **2–5** |
| 2 | **Leads a low single into an opponent with 1 card** | 0.09 per team-round with nobody out yet (0.17 overall). The opponent went out on it 73 % of the time, and 87 of those finishes made a Tichu | **1.5–3.5** |
| 3 | **"Lowest singleton" reply breaks straights** (`selectSingletonResponse` counts only same ranks) | 0.48 per team-round. 40 % of players who hold a straight break it this way | **1.5–3** |
| 4 | **Bombs are never kept.** 45 % are blown cheaply on the first tricks, 34 % are broken up by other plays, 0 % are still in hand at the end | 0.13 lost bombs per team-round | **1–2.5** |
| 5 | **Does not feed a partner with 1 card left** unless that partner called Tichu | 0.05 per team-round with nobody out (more later) | **0.5–1.5** |
| 6 | **Endgame order:** with one loser plus winners, it leads the loser first | 0.07 per team-round with nobody out. First-out rate drops from 96 % to 86 % | **0.5–1** |
| 7 | **Overtakes a partner who called Tichu** with K, A or a low card on that partner's winning single | 0.05 per team-round | **0.5–1** |
| 8 | **Leads the Dog after the partner is out** (the lead goes to an opponent) | 0.05 per team-round. The opponent went out at once 23 % of the time | **0.3–0.7** |
| 9 | **Spends a sure winner when a cheaper sure winner exists** (mostly the Phoenix as a full-house kicker) | 0.05 per team-round | **0.2–0.5** |
| 10 | **Useless Mah Jong wish** (a 3 in 66 % of wishes; unchanged) | every Mah Jong | ~0.3 |

Root cause behind 1, 3, 4 and 9: **the play heuristic never looks at the
shape of the hand that is left.** `HandShape` is used only by the Tichu call
rule and the NN encoder. `TurnScorer` knows only "low singletons ≤ 7"
(`_countLowSingletons`) and "more cards is better" (`comboEfficiency`). It
does not know straights, full houses or bombs as things worth keeping. And
`selectTurn` has no option to pass on an opponent's trick.

---

## 1. Never passes on an opponent's trick (cost 2–5)

**What happens.** If the bot can beat an opponent's trick, it plays. The only
exceptions are the partner-support rules. Measured on every follow decision
where it had a legal non-bomb beat:

| Opponent is winning | Decisions | Plays | Play does not lower est (damages the hand) |
|---|---|---|---|
| single, ≥ 10 cards in hand | 11,290 | 99.9 % | 31 % |
| pair, ≥ 10 cards | 1,136 | 100 % | 31 % |
| full house, straight, pair straight, ≥ 10 cards | 1,395 | 100 % | **50 %** |
| single, 6–9 cards | 8,736 | 99.8 % | 15 % |

In **2,592 early follows** (≥ 10 cards; 0.7 per team-round), *every*
possible beat damaged the hand. Passing was the only move that kept the hand
intact. The damage is costly:

* **Climbing wars on singles.** An opponent leads a 2, and the trick climbs
  3–5–9–J–A–Ph–Dr. The bot puts in a card every time it can. Aces played on
  an opponent's single with ≥ 10 cards: 1,579, and **48 % of them still lost
  the trick**. Phoenix played on an opponent's Ace while the Dragon was
  unseen: 235 times, **lost to the Dragon 80 % of the time**.
* **Breaking combos to beat a combo.** It plays `Ph T T 6 6` (est 5 → 8) or
  `Ph A Q J T` out of its own straight to beat a low straight on the first
  trick. With the one card that beats a straight being a bomb, it bombs (see
  #4).
* Observationally, players who did 3 or more "excess damage" plays with
  ≥ 10 cards went out first about half as often as players with the same
  starting hand shape who did none (for example est 6: 35 % vs 18 %).
  Part of that is reverse causality, so the cost range above uses about a
  third of it.

**Examples**

1. *Tichu caller loses Phoenix and straight* (round 87). Caller `Ph A A K Q Q
   J T 9 8 7 6 5 2`. Trick 2: an opponent leads 2. The caller plays **5**
   (from its straight). The trick climbs, and the caller then plays **J**
   (from its straight). An opponent plays A, the caller plays **Ph** on it,
   and the other opponent plays **Dr**. In trick 4 the caller again plays
   **T** from the straight on a 9 and later the A. The K-Q-J-…-5 straight
   that should have been one play turned into five single plays. The Tichu
   failed.
2. *Round 6, seat 1.* `Ph K K Q J T 9 8 8 5 4 4 2 Dog` holds the straight
   K-Q-J-T-9-8. Over the round it plays 5 on a 4, **Ph on an opponent's K**
   (the Ace then beats it), T on a 9 (the Dragon beats it), 9, J and Q one
   at a time. It finishes last.
3. *Opening straight.* `Ph A K Q J T T 9 6 6 6 3 2` with an opponent's
   `9 8 7 6 5` straight on the table. It plays `Ph A K Q J` (est 5 → 7):
   Phoenix and Ace are spent, and two singles (T, 9) are left behind.

**Why the code does it.** `SmartAiAgent.selectTurn` returns `PassAction`
only when `validPlays` is empty, for a calling partner
(`_holdBackForPartnerTichu`), or for a partner's trick
(`selectPartnerSupportPass`). Otherwise
`playSelectionStrategy.selectPlay(...)` picks the best *play*. Pass is never
a scored option. The `−6` early-bomb and `−3` control-card penalties in
`TurnScorer` only rank plays against each other.

**Fix.**

* Make pass a scored option when following. In `DefaultPlaySelectionStrategy`
  (or a new `FullTurnPolicy`), compute `passScore`, and play only if the best
  play beats it.
* A simple first rule: **pass on an opponent's trick** when all of these
  hold:
  * I hold ≥ 9 cards;
  * the trick is worth < 15 points and is not the Dragon;
  * no opponent has ≤ 4 cards, and no opponent who called Tichu is winning;
  * every beat either
    * leaves `HandShape(remaining).estPlays ≥ HandShape(hand).estPlays`, or
    * spends a control (A, Ph, Dr, bomb) that the unseen cards can still
      beat. Examples: Ph on an Ace while the Dragon is unseen. An Ace while
      the Dragon or Phoenix is unseen and the partner has not played yet.
* Add a shape term to `TurnScorer`:
  `+w · (estBefore − estAfter − 1)` with `w ≈ 3`. Then, among the plays it
  does make, it keeps combos together.

---

## 2. Leads a low single into an opponent with 1 card (cost 1.5–3.5)

**What happens.** An opponent has one card left, and the bot leads. It leads
a combo when it has one (1,332 times, correct). With only singles left, it
leads its **lowest** single. Counting only the cases where that opponent's
card beats the lead:

* Nobody out yet: **348 times**. The opponent went out on it 255 times.
  111 of these opponents had called Tichu, and **87 Tichus were made this
  way**.
* After someone is out: 272 more times, with 242 outs.
* In **44 %** of the nobody-out cases, leading my *highest* single would
  have held against the opponent's last card.

**Examples**

1. Round 1611. `Q 9 3`, the opponent (a Tichu caller) holds one **7**. The
   bot leads **3**, and the caller goes out with the 7. Leading Q stops
   them.
2. `K Q 8 7 6 3`, the opponent (a Tichu caller) holds a **K**. The bot leads
   **3**, and the Tichu is made. A K lead cannot be beaten by a K.
3. `A K Q J 8 7 6`, the opponent's last card is an **A**. The bot leads 6.
   A, K, Q or J would all have held.

**Why the code does it.** When an opponent has 1 card, `TurnScorer` gives
`−4` to *every* single (`avoidSingleWhenOpponentLow`). That does not change
which single wins, so `lowLeadPreference` and `sheddingRiskyLowSingle` still
pick the lowest one. `unbeatableLine +5` helps only when a single is provably
unbeatable.

**Fix.** In `selectTurn`, when leading with an opponent at 1 card and no
pair or combo to lead:

* lead the Dog if the partner still has cards;
* otherwise lead the lowest single that is unbeatable
  (`CardKnowledge.isUnbeatable`), or else the single that beats the most
  unseen cards (count from `unseenCount`), which is usually the highest;
* keep the low singles for the partner's leads.

Exception: if the partner also has 1 card, use the feed rule (#5).

---

## 3. "Lowest singleton" reply breaks straights (cost 1.5–3)

**What happens.** On a single, `selectSingletonResponse` plays the lowest
beating card whose *rank* appears once in the hand. A card in the middle of
a straight also appears once, so it gets played. This happened **1,807
times** (0.48 per team-round; 1,692 with ≥ 10 cards). **40 % of all players
who start the play with a 5+ straight break it this way at least once**
(1,955 of 4,910).

Controlled for starting est, among players who faced a beatable single with
the straight still intact, those who broke it went out first about 5 points
less often (17 % vs 22 %). The raw gap is 37 % vs 21 %, but that is mostly
selection.

**Examples**

1. Round 1657. `Dr A K K Q T 6 6 5 4 3 2 MJ Dog` holds MJ-2-3-4-5-6. An
   opponent leads **2**, and the bot plays the **3**: est goes 7 → 10.
   A Q would cost nothing. It finished last.
2. Round 1032. `A Q J T T 7 6 6 5 4 3 2 MJ Dog` holds the straight MJ…7.
   It plays 4 over its partner's 2, 7 on a 6 and 3 on a 2. The straight is
   spread over five tricks, and it finishes last.
3. Same round, other seat. `A K K J T T 9 7 6 5 5 4 3 2` on a **4** plays
   the **6** (est 7 → 10) instead of the J.

**Why the code does it.** `PlayTacticsPolicy.selectSingletonResponse` uses
`getOccurrenceCount` only. It also accepts the Dragon as a "singleton"
(`face == dragon → true`), so on some tricks the Dragon is chosen ahead of a
K from a pair.

**Fix.** Define "singleton" by hand shape. A card is a free single if
`HandShape.fromCards(hand − card).estPlays == estPlays − 1`. Pick the lowest
such card. If none exists, fall through to the scorer, and to the pass rule
from #1. Drop the Dragon from the singleton set, and let the scorer decide.

---

## 4. Bombs are never kept (cost 1–2.5)

**What happens.** 588 player-rounds start the play with a bomb:

* **387** bombs are played. **267 of them (69 %) with ≥ 10 cards on a trick
  worth < 20 points that is not the Dragon**. 155 of those tricks were worth
  0 points or less. In 239 of them the bomb was the only legal beat, so this
  is the no-pass rule (#1) at work. 28 bombed the *partner's* trick.
* **201** bombs (34 %) are broken up by other plays, 187 of them with ≥ 10
  cards. Mostly a straight or full house is led through a four-of-a-kind,
  or a straight-flush card is played as a single.
* **0** bombs are still in a hand at the end of a round. Nothing is held
  back to stop a Tichu or a 1-2.

`DefaultBombTimingStrategy` exists but is still not wired in (no reference
outside its own file), and it always returns `false`.

**Examples**

* `A A A Q Q Q Q T 9 9 8 6 3 2` with 14 cards: bombs `QQQQ` on an opponent's
  10-card straight worth −10 points.
* `A Q Q J J T T T 9 5 5 5 5 2`: bombs `5555` on `Ph 6 4 3 2 MJ`, a trick
  worth **−25**.
* Broken: `K K J 9 9 5 4 4 4 4 3 3 2 MJ` leads `5 4 3 2 MJ`, and the 4-bomb
  is gone. `Dr Ph A A A A K K 9 8 7 6 4 3` plays `Ph A A A 7` as a full house
  on `8 8 8 7 7`: the Ace bomb *and* the Phoenix are spent on a 0-point
  trick. `Dr K Q J T 7 7 7 7` leads `7 7`.

**Why the code does it.** There is no pass option (#1), and the
`bombUsageEarly −6` only ranks plays. Bomb cards get no protection in
`TurnScorer`. `comboEfficiency` (+2 per card) even rewards a long straight
that eats a bomb card.

**Fix.**

* Wire `BombTimingStrategy` into `selectTurn`. With ≥ 9 cards, bomb only if
  one of these holds:
  * the trick is the Dragon or worth ≥ 20 points;
  * an opponent who called Tichu is winning it;
  * an opponent has ≤ 4 cards;
  * the bomb is part of my way out (est ≤ 3).

  Otherwise pass.
* In the scorer, penalise any non-bomb play that removes a card of a bomb:
  `−8`, or `−4` per bomb card lost.

---

## 5. Does not feed a partner with 1 card left (cost 0.5–1.5)

**What happens.** The partner has 1 card, no opponent has 1 card, nobody is
out yet, and the bot leads:

| Lead | Cases | Partner went out on it |
|---|---|---|
| Dog | 44 | 44 (always works) |
| lowest single | 270 | 161 (60 %) |
| higher single | 47 | 7 |
| **pair or combo** | **135** | **0** |

In 109 of the 135 combo leads, the lowest single would have been beatable by
the partner's card. Over the whole round (not only before the first
finisher), this happened 258 times for combos and 107 for higher singles.

**Examples**

* `9 9 7 7 6 6 6 5 2` leads `7 7 6 6`. The partner holds a 9, and a 2 lead
  lets them out.
* `Q Q 9 9` leads `9 9`. The partner holds an A.
* `J 8 8 8 6 6 6 2` leads `8 8 6 6 6`. The partner holds a Q.

**Why the code does it.** `PlayTacticsPolicy.selectPartnerFinishLead`
returns null unless `partnerCall != TichuCall.none` (unchanged from the old
report).

**Fix.** Drop the call requirement. With the partner at 1 card and no
opponent at 1 card, lead the Dog if I have it, else the lowest single.

---

## 6. Endgame order: winners first, last loser at the end (cost 0.5–1)

**What happens.** At ≤ 6 cards with the lead, I split the hand into its
fewest possible plays and marked each play as a sure winner
(`CardKnowledge`, bombs aside) or a loser. A strong player with **one loser
and at least one winner** leads the winners first and goes out with the
loser. The bot led the loser first **245 times with nobody out yet** (0.07
per team-round). It still went out first in 86 % of those, against 96 % when
it led a winner first.

The reverse also happens. With 2+ losers it led a sure winner 479 times,
which spends a card it needs later to win back the lead.

**Examples**

* `A 4` (Dr and Ph gone): leads **4**, loses the lead, finishes 2nd.
  `A` then `4` goes out.
* `A MJ`, an opponent at 1 card: leads **MJ**. The opponent goes out with a
  K.
* `A A 5 5` leads `5 5` instead of `A A`, then `5 5`.

**Why the code does it.** There is no plan for the last cards. When
leading, the scorer gives the Ace `−3` (`controlPreservation`; the sure-win
exemption only applies when *following* an opponent) and the low card
`+2` (`sheddingRiskyLowSingle`) plus `lowLeadPreference`.

**Fix.** Add a small endgame planner in `selectTurn` for hands of ≤ 6
cards (cheap: about 20 partitions). Find the fewest-plays partition and
mark the winners with `isUnbeatable`. If losers ≤ 1, lead a winner (the one
of the type opponents can least follow). If losers ≥ 2, lead the lowest
loser and keep the winners. The `opponentLow` rules keep priority.

---

## 7. Overtakes a partner who called Tichu (cost 0.5–1)

**What happens.** The partner called Tichu, still has cards, and is winning
the trick. The bot (not about to go out) still overtook **186 times**: with
a K 43 times, an A 13, the Dragon 2, and low cards 128 (mostly on singles
below a 10). The caller then has to spend a winner to get the lead back.

**Examples**

* Round 40. The caller holds `T A A` and leads the T. The partner plays
  **Q** over it, and the caller has to spend an Ace to get the lead back.
* `Dr K Q J J 9 8 8 7 5 5 3 2` with 13 cards plays a K on the caller's Q.

**Why the code does it.** In `selectPartnerSupportPass`, with the partner
having called, `_isPartnerSupportPassTurn` passes on a single only if it is
≥ K or unbeatable. On a caller's 7, J or Q the bot falls through to
`selectSingletonResponse` and the scorer. The scorer's
`supportPartnerTichu −4` is too small against `+2` for shedding a single.

**Fix.** When the calling partner is winning, pass on *any* trick unless an
opponent who called Tichu is about to go out, or this play takes me out.
This is narrower than the `support` option, which also passed on opponents'
tricks and measured slightly worse.

---

## 8. Dog led after the partner is out (cost 0.3–0.7)

195 times. 147 of these handed the lead to an opponent, and 44 times that
opponent went out at once.

* Round 6. `K K 8 8 4 4 2 Dog`, the partner is out, the next opponent holds
  one 9. The bot leads Dog → 9 → out.
* `A Q J 4 Dog`: the same with an opponent holding a 3.

**Why:** `selectEarlyDogLead` leads the Dog at the first chance, with no
check (unchanged from the old report). **Fix:** skip it when the partner's
hand is empty, unless the Dog is my last card.

---

## 9. Spends a sure winner when a cheaper sure winner exists (cost 0.2–0.5)

200 times, a play with an A or Ph was chosen while a play with fewer of
those cards also won for sure. 79 of these are combos, mostly the Phoenix
used as the pair of a full house (62 times in all). Examples:

* `Ph A A A K K T T 9 9 8 6 4 3` plays `Ph A A A 6` on `Q Q Q 8 8`, though
  `A A A T T` also wins for sure.
* `Ph A A A J 9 8 6 6 5 5 4 3 2` plays `Ph A A A 4` on `Q Q 4 4 4`.

**Why:** a sure capture switches off `controlPreservation` in `TurnScorer`
(`if (controlCount > 0 && !sureCapture)`), and the Phoenix kicker sheds a low
singleton (+2). The scorer never compares the play with a cheaper play that
wins just as surely. **Fix:**

* Keep the control penalty when another sure win with fewer controls
  exists.
* Never use the Phoenix as a full-house kicker when a natural pair is
  available.

---

## 10. Mah Jong wish (about 0.3)

Unchanged from the old report. Of 1,801 Mah Jong plays, 1,190 wished a 3
and 386 a 5: the card the bot itself passed to the left opponent.
`DefaultWishStrategy` takes `preferredFace` (the left schupf card) first.
**Fix:** wish a high rank I do not hold (A, K, Q). The current high-card
fallback already does that.

---

## Checked and fine (or fixed)

* **Overtaking a partner who did not call:** mostly fixed. On a partner's
  trick it now plays 12–55 % of the time with ≥ 6 cards (it was 99 %). What
  is left is overtaking low singles, plus partners who are already out
  (576 cases; taking the lead there is correct).
* **Bombing the Dragon or a trick worth 25+** (`_bombForValuableTrick`):
  works.
* **Dragon on tricks worth ≤ 5 points** (793 times): **not** a leak, despite
  the old report's item 6. A trick won with the Dragon always goes to an
  opponent, so a cheap trick is the *cheapest* place to play it. The real
  question is spending the top card early, which is part of #1.
* **Mah Jong lead:** it never breaks a straight to lead the Mah Jong alone
  (0 of 1,326).
* **Dog to a partner who still has cards:** fine (1,785 Dog leads in
  total).
* **Tichu calls** (strict): 65.5 % succeed in `rl/tichu_analysis.py` (100
  matches). 52 % of the failures are near misses (the caller had ≤ 2 cards
  left), which points back to #1, #2 and #6.
* Double wins happen in 22 % of rounds.

---

## Suggested order

1. **#3 and #9.** These are local scorer and tactics changes with no new
   concepts. Add the shape term from #1 (`estBefore − estAfter − 1`) at the
   same time.
2. **#1 with #4.** Add the pass option and wire in bomb timing. This is the
   biggest change and needs tuning (an A/B flag `passStructure`).
3. **#2, #5, #6, #8.** Small lead rules for the endgame, which can go
   together in one `EndgamePolicy`.
4. **#7, #10.**

Re-measure after each step with the duplicate evaluation (150 deals to
1000, both seatings).

---

## Appendix: method

```bash
cd /home/user/tichu
build/bin/headless_dev --seed=9001 --deal-seed=9001 --episodes=150 --target-score=1000 \
    --format=csv --no-timestamps --output=$S/w/g.csv
build/bin/headless_dev --seed=9001 --deal-seed=9001 --episodes=150 --target-score=1000 \
    --format=bc-jsonl --skip-play-rows --output=$S/w/g.jsonl
TICHU_HEADLESS=build/bin/headless_dev rl/.venv/bin/python rl/tichu_analysis.py --episodes=100 --shards=2
```

`$S` = `/tmp/claude-0/-home-user-tichu/ae159fbf-ce92-51ac-bcb4-394a13b21561/scratchpad`.

* The two runs produce the same games. All 1,866 round results match.
  Full post-schupf hands come from the bc-jsonl `call: "tichu"` rows (one per
  seat). Tichu calls come from the `round_end.calls`. Every play and pass
  comes from the CSV.
* `$S/tlib.py` replays each round. It tracks all hands, the trick winner
  (last player to play), the unseen cards, and the tricks won. It also holds
  ports of `HandShape.estPlays` and `CardKnowledge.canBeBeaten`.
* `$S/gen.py` is a simple legal-move generator. It ignores the wish;
  decisions under an active wish were skipped.
* `$S/part.py` finds the fewest-plays partition and the winners and losers
  (for #6).
* The analysis scripts are `$S/a_*.py`, and `$S/show.py <round>` prints a
  round trick by trick.
* "Excess damage" for a play = the best est reduction among legal plays
  that use no more controls (A, Ph, Dr, bomb), minus the chosen play's
  reduction.
* Opponents' cards are used only to *measure* (for example "the
  opponent's last card beats this lead"). None of the proposed fixes need
  hidden information.
* Limitations: these are observational costs from one bot playing itself.
  Single values are noisy. 1,866 rounds give about ±1 percentage point on
  rates and about ±5 points on mean round differences.
