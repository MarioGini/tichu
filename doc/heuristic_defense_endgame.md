# Heuristic bot: Tichu defense and endgame

*Analysis of 2026-11-15. Bot: `SmartAiAgent` with `HeuristicOptions.latest`
(guard, strict, planPass, planBombs, planScore; planLead and planSingles
off), all four seats, no nets. Runner: `build/bin/headless_dev`.
Main data: 200 matches to 1000 points, seed 9101: **2,454 rounds**, replayed
play by play with full hands (see the appendix). Two extra runs, with round
results only: 300 matches of `latest` (seed 9302, 3,621 rounds) and 300
matches with the partner guard switched off (seed 9301, 3,734 rounds).*

This report covers two areas the earlier analyses
(`doc/heuristic_weaknesses.md`, `doc/ai_behavior_report.md`) only touched:
**(A)** how the bot fights an opponent's Tichu call, and **(B)** how it plays
the endgame, from the first player out to the last cards.

Card notation: `Dr` Dragon, `Ph` Phoenix, `MJ` Mah Jong, `Dog`, `T` = 10.
"F" is the player who went out first, "P" is F's partner. "Caller" is the
player who called Tichu, and "defenders" are the caller's two opponents.

---

## How to read the costs

Costs are given in **points of round difference per team per round**, the
same unit as the earlier reports. An event that costs one team D points of
difference adds D / (2 × rounds) to this number. These reference values
come from the data:

* **1-2 finish:** worth about **210** points of difference to the team that
  makes it. A 1-2 scores 200–0, and in the other rounds F's team ends with
  −10 card points on average.
* **Tichu made vs. stopped:** about **250**. The bonus alone swings 200, and
  the first-out advantage adds to it.
* **3rd place vs. last place** in the 2-player race at the end: about
  **55**. The last player hands over 24 trick points and 3.5 hand points
  on average.

All costs are **rough, observational estimates**, not A/B tests. Where a
"could have" is judged with hindsight (the opponents' hands are known in the
log), I say so and discount it. The items overlap, so do not add the costs
up. Each fix below names a `HeuristicOptions` flag, so it can be checked
with the usual duplicate A/B run (150–400 deals to 1000, both seatings).

---

## Ranked summary

| # | Weakness | How often | Est. cost (per team per round) |
|---|---|---|---|
| 1 | **Wrong lead order against a 1-card opponent after the first out.** It leads its low single first and hands F's partner the 1-2 | 141 beatable single leads into P. In 39 of them, playing the same cards high-first would have gone out first. 32 became opponent 1-2s | **0.8–1.4** |
| 2 | **Defenders' bombs do nothing against a Tichu.** Callers succeed 65 % of the time whether or not a defender holds a bomb. A defender's Dragon cuts that to 54 % | 158 rounds with a call (11 % of calls). 56 of 162 defender bombs are used while the caller still has ≥ 6 cards, and 40 are broken up | **0.4–1.0** |
| 3 | **A partner with 1 card is not fed** unless that partner called. This includes defenders, who never feed each other | 430 leads (0.09 per team-round). 97 of them were by defenders, and 24 of those Tichus were made | **0.4–0.9** |
| 4 | **Leads the Dog after the partner is out.** The lead goes to an opponent | 179 harmful leads (0.04 per team-round). As P in the 1-2 race: 1-2 only 16 % | **0.4–0.9** |
| 5 | **`planPass` lets the caller keep tricks.** It passes on the caller's beatable trick to protect its own hand shape | 398 passes (0.08 per team-round) in 20 % of called rounds. 59 passed a sure winner | **0.4–0.9** |
| 6 | **Endgame order:** with one loser and some winners, it leads the loser first | In the 1-2 race (as P): 33. In the head-to-head for 3rd: 128 | **0.2–0.5** |
| 7 | **Bombs an opponent's Dragon for 0 points.** That trick would be given to us anyway | 96 bombs (23 % of all bombs), 27 of them against a caller | **0.2–0.4** (overlaps #2) |
| 8 | **Ignores the last-place transfer.** Point cards are kept to the end, and tricks are won that will be handed over | Every round that is not a 1-2. The last player holds 5.8 hand points when the head-to-head starts and 3.5 at the end | **0.2–0.4** (very rough) |
| 9 | **`planPass` stays on after someone is out** | 343 passes with ≥ 8 cards in the race and the head-to-head | 0.1–0.3 |
| 10 | **Mah Jong wish ignores the caller.** It always wishes the low card it passed left | 758 defender Mah Jong plays | 0.1–0.3 (speculative) |

Weaknesses #1, #3, #4 and #6 are old items #2, #5, #8 and #6 of
`heuristic_weaknesses.md`. They are still there because their fixes sit in
`PlanPlay.lead`, behind `planLead`, and `planLead` is off: it measured
−200 margin as a bundle. The new data shows where these items cost the most,
which is in the endgame. It also points to a likely cause of the bundle's bad
result (see #6). **Split `planLead` into separate flags.**

**Note: the scoring code does not follow the stated rule** (this is not a bot
weakness, but it changes the endgame values). See the section
[Scoring discrepancy](#scoring-discrepancy-last-player-is-the-partner-of-the-first-out).

---

## A. Tichu calls and defense: the numbers

### Success by situation

There were 1,554 Tichu calls (63.8 % made; 61.4 % in the second sample) and
**no Grand Tichu calls at all**. 1,426 rounds had one call. 64 rounds had a
call from both teams, and those calls succeeded 49 % of the time.
Single-call rounds:

| Situation (single-call rounds) | Calls | Made |
|---|---|---|
| all | 1,426 | **65 %** |
| caller strength < 0.2 / 0.2–0.9 / ≥ 0.9 | 304 / 590 / 532 | 52 % / 65 % / 73 % |
| caller holds Dragon / not | 584 / 842 | 73 % / 60 % |
| caller holds Mah Jong / not | 270 / 1,156 | 74 % / 63 % |
| caller holds Dog / not | 70 / 1,356 | 43 % / 66 % |
| caller holds a bomb / not | 288 / 1,138 | **59 %** / 67 % |
| a defender holds the Dragon / not | 548 / 878 | **54 %** / 72 % |
| **a defender holds a bomb / not** | 158 / 1,268 | **65 % / 65 %** |
| defenders' controls (A, Ph, Dr) 0 / 1 / 2 / 3 / 4+ | 55 / 278 / 552 / 429 / 112 | 75 / 74 / 69 / 57 / 50 % |

Who goes out first after a call: the caller 65 %, the caller's partner 2.7 %
(the guard works), a defender 32 %. The calling team makes a 1-2 in 14 % of
calls, and the defenders make one in 7 %.

### Calls compared with the same hands when nobody called

Hands just below the call threshold (strength −0.3…−0.1, no call in the
round) can be compared with callers just above it (−0.1…+0.3). Both samples
of `latest` are pooled:

| | Hands | Goes out first | Opponents go out first |
|---|---|---|---|
| no call, strength −0.5…−0.3 | 590 | 40 % | 44 % |
| no call, strength −0.3…−0.1 | 532 | 48 % | **35 %** |
| caller, strength −0.1…+0.3 | 919 | 54 % | **42 %** |
| caller, same, partner guard off | 534 | 54 % | 37 % |

The trend of the uncalled hands would put the opponents at about 30 % for
this strength. After a call they go out first at 42 %. About 5 points of
this gap come from the calling side's guard: the partner no longer goes out
first. That cost is accepted, because the guard raises the call success
rate: 61–64 % with it, 59.5 % without. The other 5–7 points are the effect of
the defense. **So the defense works, but only a little.** The bot changes
very little when an opponent calls:

* **Bombs.** `PlanPlay.keepBombs` stops protecting them, and the
  `bombUsageLate` bonus (+6 instead of −6) applies at any card count.
* **Near the finish.** The `opponentTichuNearFinish*` rules apply only once
  the caller is down to ≤ 2 cards.
* **Dragon.** `DefaultDragonGiveStrategy` gives the Dragon trick to the
  opponent who did not call.

Nothing else changes. Defenders lead singles as often against a caller as
against a strong player who did not call (38 % vs 41 % of leads when that
player has 6+ cards). The caller wins 40 % of those leads, against 26 %
for the uncalled player.

### How the caller gets out (929 made calls)

| Final play | Count | Could a defender have stopped it there? |
|---|---|---|
| Leads its last cards after winning a trick nobody could beat | 488 (53 %) | Only 4 times did a defender pass with a legal beat |
| Plays its last cards on a defender's lead | 214 (23 %) | 173 single leads and 39 pairs. A different lead would have stopped it only 3 times (caller at 1 card) and 8 times (caller at 2) |
| Plays its last cards on its partner's lead | 114 (12 %) | – |
| Its own lead was beaten, and it comes back over the top | 77 (8 %) | – |
| Leads after its partner's Dog | 32 (3 %) | – |

**At the moment the caller went out**, the defenders still held: at least
one Ace in 39 % of rounds, the Dragon in 3 %, the Phoenix in 1.5 %, and **a
bomb in 0 %**. In 35 % of made calls a defender was down to 1–2 cards
(1 card: 181, 2 cards: 144). The race was close, and support from the other
defender (#3) would have mattered.

**The last moment is defended correctly.** The losses come earlier. Bombs
are spent or broken while the caller still has many cards (#2). The
defenders pass on the caller's tricks to keep their own shape (#5). And
nobody feeds the defender who is about to go out (#3). Defender controls
(A, Ph, Dr, bombs) played on a caller with 6+ cards won the trick only 57 %
of the time in made calls, against 75 % in stopped calls: they climbed into
the caller's Dragon or Phoenix.

### Schupf and Grand Tichu

Every call happens after the schupf (`announceBeforeSchupf` is off), and the
bot never calls Grand Tichu. So "pass the Dog to the caller"
(`DefaultSchupfStrategy`, `leftGrand`/`rightGrand`) and
`selectPartnerGrandTichuDogLead` **never run**. Nothing can be done at the
schupf against a Tichu that is called after it. This is not a cost, but those
code paths are untested in practice.

---

## B. Endgame: the numbers

* **1-2 finishes: 580 of 2,454 rounds (23.6 %).** The chance that P also
  goes out depends mostly on how many cards P holds when F goes out:

  | P's cards when F goes out | 1 | 2 | 3 | 4 | 5+ |
  |---|---|---|---|---|---|
  | rounds | 247 | 250 | 223 | 198 | 1,536 |
  | 1-2 made | 46 % | 34 % | 33 % | 23 % | 17 % |

  With 1 card it is 31 % when an opponent also has 1 card, and 77 % when both
  opponents have 5 or more.
* **Who leads after F goes out:** the opponent on F's left 1,402 times, P 627
  times, the other opponent 356 times.
* **Last player (rounds that are not a 1-2):** the last player won 24 trick
  points on average, and those are handed over. Their hand still held
  3.5 points at the end, and 5.8 points (0.8 cards of 5, T or K) when the
  head-to-head started. In the 2-player race for 3rd place, the player with
  fewer cards wins 57 % of the time. The 3rd-place team beats the
  last-place team by **+55** on average.
* **Dragon gift:** the opponent who gets it ends last 36 % of the time, and
  the other opponent 16 %. So "give it to the opponent with more cards" works.

---

## 1. Wrong lead order against a 1-card opponent after the first out (0.8–1.4)

**What happens.** F is out, P (F's partner) has one card left, and I (an
opponent of F) have the lead. If P goes out now, F's team gets a 1-2. The bot
led a single that P's card could beat **141 times**.

* In **39** of them, the same hand played in a different order would have
  taken me out first: combos and high singles first, the lowest single as
  my last card. Only my last play needs to be beatable, because by then
  I am out and the 1-2 is gone.
* **32 of those 39 became 1-2s.** In the other 102 cases no order worked.

Counting more broadly (a pair, or a higher single that P's card cannot
beat, was available), there were 76 such leads, followed by 58 opponent
1-2s.

**Examples**

* Round 2378. I hold `A 3`, and P's last card is a **T**. The bot leads
  **3**. P goes out, and the round is 0–200. Leading A and then 3 takes me
  out second.
* Round 885. I hold `Q J 3`, and the caller has just gone out. Their partner
  holds a **5**. The bot leads **3**, the partner plays the 5, and the round
  is 0–300 (Tichu plus 1-2). Leading Q, then J, then 3 takes me out
  second.
* Round 1391. I hold `T 5 5 4`, and P holds a **5**. The bot leads **4**.
  Leading `5 5`, then T, then 4 goes out.

**Why the code does it.** With an opponent at 1 card, `TurnScorer` gives
−4 to *every* single (`avoidSingleWhenOpponentLow`) and +4 to multi-card
plays. That does not change which single wins, so `lowLeadPreference` and
`sheddingRiskyLowSingle` still pick the lowest one. The rule that would fix
it (`PlanPlay.lead`, `minOpp == 1`: combos, then the highest single) sits
behind `planLead`, which is off.

**Fix (flag `escapeLeadVsOne`).** If an opponent has exactly 1 card, my
partner does not have exactly 1 card, and no wish is pending:

* lead my combos first (longest first);
* then lead singles from the highest down, keeping the lowest single for my
  last card.

Against an unknown single card this order is never worse than leading
low first: any card that beats a high single also beats every lower one.
Apply it at least when the 1-card opponent's partner is already out, which
is the 1-2 threat. Before the first out the same leak is small: there were
only 10 avoidable outs in this data. Keep the Dog out of this rule (see #4).

---

## 2. Defenders' bombs do nothing against a Tichu (0.4–1.0)

**What happens.** A defender with a bomb does not lower the caller's chance
at all: **65 % with a bomb, 65 % without** (158 vs 1,268 calls). A defender's
Dragon lowers it to 54 %, although part of that is because the caller then
lacks the Dragon. Here is what happened to the 162 defender bombs:

| Fate | Bombs | Tichu made |
|---|---|---|
| used on a caller with ≥ 6 cards | 56 | 68 % |
| used on a caller with ≤ 5 cards | 22 | 64 % |
| used on the caller's partner's trick | 33 | 58 % |
| used as a lead | 8 | 63 % |
| broken up by another play (almost always with the caller at ≥ 6 cards) | 40 | 70 % |
| still held when the caller went out | **3** | – |

**Examples**

* Round 0. A defender holds `A J 9 9 9 9 7 6 5 4 2 2 2`. The caller (12
  cards) wins the opening single climb with the **Dragon**, and the defender
  bombs it with `9 9 9 9`. The 45 points would have been given to the
  defenders anyway (see #7). The caller goes out first; Tichu made.
* Round 426. Caller `Ph A A K J J J 7 7 6 5 3 2 MJ` leads
  `Ph 6 5 3 2 MJ` (8 cards left). A defender plays the straight-flush bomb
  `7 6 5 4 3` on a trick worth −20 points. The caller later wins with
  `J J J 7 7` and `A`, and makes the Tichu.
* Round 960. `A 9 5 5 5 5 4 4 4 4 3 2 Dog` bombs `4 4 4 4` on the caller's
  Dragon when the caller has 12 cards left. Tichu made.

**Why the code does it.**

* `PlanPlay.keepBombs` returns all plays unchanged as soon as any opponent
  has called (`opponentCalled`).
* `TurnScorer` then adds `bombUsageLate +6` instead of `bombUsageEarly −6`
  (`_opponentCalledTichu`), at any card count. That is a 12-point swing
  towards bombing the first beatable trick.
* `_bombForValuableTrick` bombs any Dragon (see #7).
* Nothing protects bomb cards from being broken up by a straight or single.

**Fix (flag `holdBombVsCaller`).** When an opponent has called:

* keep bombs unless the caller is winning the trick and has ≤ 5 cards, or
  the trick is worth ≥ 25 points and is not a Dragon;
* apply `bombUsageLate` only below that card count;
* in `TurnScorer`, give −4 per bomb card to non-bomb plays that break a
  bomb, as old fix #4.

The best moment to bomb is the caller's second-to-last winning trick: take
the lead, then lead a type the caller cannot follow.

---

## 3. A partner with 1 card is not fed (0.4–0.9)

**What happens.** My partner has 1 card, no opponent has 1 card, and I lead.
I led a combo or a higher single **430 times**, although a Dog or a low
single that the partner's card beats was available. 204 of these were
before anyone was out and 226 after. In 154 of them the partner would have
gone out for sure (hindsight: no opponent held a single able to stop it).
When the bot *does* lead the lowest single, the partner goes out about a
quarter of the time (86 of 352 before the first out), and the Dog always
works.

This matters most against a Tichu. The defenders never feed each other:
when one defender had 1 card, the other led a combo 95 times, a higher
single 24 times, the lowest single 66 times (15 fed), and the Dog 22 times.
There were **97 missed feeds, and the caller made the Tichu in 24 of those
rounds.**

**Examples**

* Round 1373 (nobody out). `8 8 5` leads `8 8`, and the partner holds a
  **K**. A 5 lead lets the partner out first.
* Round 541 (after the first out). `K K 6 4 4 3 2` leads `K K`, and the
  partner holds an **8**. A 2 lead lets the partner out second.
* Round 1644 (defense). `6 4 3 3` leads `3 3`, the defending partner holds a
  **T**, and the caller holds `6 6`. A 4 lead forces the caller to break its
  pair or let the partner out. The Tichu was made.

**Why the code does it.** `PlayTacticsPolicy.selectPartnerFinishLead`
returns null unless `partnerCall != TichuCall.none` (unchanged). The planLead
version (`PlanPlay.lead`, `partnerCards == 1`) also removes the Dog from the
options, but the Dog is the best feed.

**Fix (flag `feedPartnerAlways`).** Drop the call requirement. If my partner
has 1 card and no opponent has 1 card:

* lead the Dog if I have it;
* otherwise lead the lowest single (never the Dragon or Phoenix).

As a defender, apply the same rule while the caller still has more than one
card, since getting my partner out first stops the Tichu.

---

## 4. Leads the Dog after the partner is out (0.4–0.9)

**What happens.** The Dog passes the lead to my partner. If the partner is
out, the lead goes to the next player who still has cards. This happened
243 times:

* **64 times** it came back to me. In the head-to-head this happens when
  the last opponent sits to my left; it is harmless and even sheds the Dog.
* **179 times** it went to an opponent. 134 of these were in the 1-2 race:
  I was P, F had just gone out, and I went out second only 22 times (16 %).
  The opponent who got the lead finished ahead of me 105 times.
* The other 45 times it was the head-to-head for 3rd. The opponent finished
  first 32 times, and 26 of those opponents held ≤ 2 cards.

**Examples**

* Round 2242. F (my partner) is out. I hold `9 9 8 8 7 5 4 4 2 Dog` and lead
  the Dog. The opponent holding `J 7 3 2` gets the lead and goes out second.
  No 1-2.
* Round 1632. I hold `T T 9 9 6 4 4 3 2 Dog` and lead the Dog. The opponent
  holding `K Q 3` gets the lead and goes out next.
* Round 1455. `A Q J T 5 5 3 2 Dog` leads the Dog into opponents holding
  `Q J` and `A 9 9 8 8 4 2`. The `A 9 9 8 8 4 2` opponent gets the lead and
  goes out second, and I end up last.

**Why the code does it.** `selectEarlyDogLead` leads the Dog at the first
chance. The "no Dog once the partner is out" filter in `selectTurn` sits
inside `if (options.planLead)`.

**Fix (flag `noDogAfterPartnerOut`).** If my partner has no cards, remove
the Dog from the lead options. There are two exceptions: the Dog is my last
card (going out with it), or the lead provably comes back to me (the only
player left in front of me is out). Keep the Dog to go out with it last.

---

## 5. `planPass` lets the caller keep tricks (0.4–0.9)

**What happens.** `PlanPlay.passInsteadOfDamaging` makes a player pass on an
opponent's trick when every beat would break the hand plan or burn an
A/Ph/Dr. The opponent's Tichu call is not checked. Defenders passed on a
beatable trick that the caller was winning **398 times**, in 292 of the
1,426 called rounds:

* 59 of these passes gave up a beat that was a sure winner;
* the caller then won the trick 308 times.

Calls in rounds with such a pass succeeded more often, in every strength
bucket: 58 % vs 51 %, 73 % vs 62 %, 80 % vs 71 %. Part of that is
selection (the passing defender had a structured, slow hand), so the cost
estimate counts only a third to two thirds of the gap.

**Examples**

* Round 426. Defender `A K Q Q J T 9 9 9 8 8 6 4 3`, caller at 8 cards,
  leading `Ph 6 5 3 2 MJ`. The defender passes, although `A K Q J T 9` wins
  for sure: it would break the `9 9 9 8 8` full house. Tichu made.
* Round 1946. Defender `A A 9 9 8 8 7 6 5 4 4 3 2 Dog` passes on the caller's
  `6 5 4 3 2` (9 cards left). It could have played `9 8 7 6 5` or
  `8 7 6 5 4`. The caller keeps the lead; Tichu made.
* Round 141. Defender `Ph K Q J J 9 7 6 6 5 4 3 2 2` passes on the caller's
  `Q Q 8 8 8`. The only beats use the Phoenix. Tichu made.

**Fix (flag `noPassVsCaller`).** In `selectTurn`, skip the `planPass` branch
when the trick winner has called Tichu. A softer version: still pass when
the caller has ≥ 11 cards and the only beat burns a control that is not a
sure winner.

---

## 6. Endgame order: the loser before the winners (0.2–0.5)

**What happens.** With ≤ 6 cards, one loser and at least one sure winner,
the right order is winners first and the loser last.

* **In the 1-2 race (as P):** loser-first 33 times, and the 1-2 came 76 % of
  the time. Winner-first 166 times, and it came 98 % of the time.
* **In the head-to-head for 3rd:** loser-first 128 times, and I came 3rd
  84 % of the time. Winner-first 601 times, 98 %.

Before the first out it is the same pattern (old item #6: 245 times).

**Examples**

* Round 2324 (head-to-head). `A 2` leads **2**. The opponent holds `3`,
  goes out, and I am last. A, then 2, goes out.
* Round 1330 (head-to-head). `K 4 4` leads `4 4`. The opponent holds
  `T T 9 9 3 3 2`, takes the trick with `T T`, and I end last.
* Round 1674 (as P in the race). `A T T` leads `T T`. The opponents beat
  it, and there is no 1-2.

**Why, and why `planLead` measured badly.** `PlanPlay.lead` leads a sure
winner whenever one exists (`hand.length <= 6`). It does not check that at
most one loser is left. With 2+ losers, cashing the winner first throws away
the card needed to win the lead back. That is the opposite of correct play,
and a likely reason for the "sure winners first: −200" result in the last
commit.

**Fix (flag `endgameOrder`).** Only for ≤ 6 cards:

* find the fewest-plays partition (about 20 to check) and mark each play as
  a sure winner (`CardKnowledge.isUnbeatable`) or not;
* with ≤ 1 loser, lead a winner;
* with ≥ 2 losers, lead the lowest loser and keep the winners;
* #1 has priority when an opponent is at 1 card.

---

## 7. Bombing an opponent's Dragon gains 0 points (0.2–0.4)

**What happens.** `_bombForValuableTrick` (and `keepBombs`) bomb whenever an
opponent's Dragon is on top. But a trick won by the Dragon *must be given to
one of the Dragon player's opponents*, which is us. Bombing it gains the lead
and nothing else, and costs the bomb. This happened **96 times** (23 % of the
419 bombs played on a trick), 94 of them with ≥ 7 cards in hand. 27 bombed a
caller's Dragon, and 19 of those Tichus were still made.

Examples: round 0 (above). Round 986: `A K K Q T 8 8 8 8 3 2 MJ` bombs the
caller's Dragon when the caller has 12 cards; Tichu made. Round 1031:
`A K T T T T 8 8 8 3 3 2 Dog` does the same.

**Fix (part of flag `holdBombVsCaller`, or its own flag
`noDragonBomb`).** Drop `dragonOnTop` from `_bombForValuableTrick` and
`keepBombs`. Bomb a Dragon only when taking the lead matters: the Dragon
player is a caller with ≤ 5 cards, or an opponent has ≤ 3 cards. Keep the
"25+ points" rule only for tricks not won by the Dragon.

---

## 8. Ignores the last-place transfer (0.2–0.4, very rough)

**What happens.** Nothing in the play heuristic knows that the last player
gives away their hand and their tricks. `TurnScorer` only has `pointGift`
(points played into a trick that is not a sure win), and the scorer rewards
winning point tricks (`trickPointCapture`) at any stage. When the
head-to-head starts, the eventual last player still holds 5.8 points
(0.8 cards of 5, T or K), and still 3.5 at the end. They also won 24 trick
points on average, all handed over.

Most of this cannot be avoided, since you cannot discard in Tichu. The
avoidable part is:

* shedding a 5, T or K single while it costs nothing (as the lead into a
  trick my partner will win, or as my cheapest beat);
* in the head-to-head, not spending a winner just to capture a point trick
  when I am likely to be last anyway.

The rough upper bound is 1.3 per team-round. The realistic gain is maybe a
quarter of that.

**Fix (flag `lastPlaceAware`).** After the first out, if I have the most
cards among the players left (≥ 2 more than the next):

* add +1 per point card a play sheds;
* switch off `trickPointCapture` for tricks I would win.

The scoring discrepancy below changes what "handed over" means. Fix that
first.

---

## 9. `planPass` stays on after someone is out (0.1–0.3)

The pass rule needs ≥ 8 cards and every opponent at > 3 cards. It still
fires after the first out: 287 passes in the 1-2 race and 56 in the
head-to-head. As P (F's partner), the bot passed a beatable opponent trick
107 times (of 3,226 chances), and the 1-2 came only 15 times. Example: round
2444, P holds `K K Q Q T T 5 5 4 3 MJ` and passes on an opponent's J and on
a 7. The opponents hold `A A A K 9 7` and `A J T 3 3`. No 1-2.
On the other side, opponents let P's tricks stand 124 times (with P at
4+ cards).

**Fix (flag `planPassEarlyOnly`).** Require `finishOrder.isEmpty` for
`planPass`.

---

## 10. Mah Jong wish ignores the caller (0.1–0.3, speculative)

`DefaultWishStrategy` wishes the card the bot passed to its left opponent.
Against a caller, defenders' 758 Mah Jong plays wished a 3 (495), 5 (168),
7 (55) or 9 (18). The caller held the wished rank 56 % of the time, but
being made to play a low card only helps a caller shed. The defender's own
partner held it 53 % of the time. A wish can make a caller play an Ace
early, or break a straight.

**Fix (flag `wishVsCaller`).** If an opponent called and I hold no Ace, wish
the Ace. If I hold an Ace, wish the highest rank I do not hold and did not
pass to my partner. This needs an A/B run, since the evidence here is
indirect.

---

## Checked and fine

* **The last lead against a caller with 1–2 cards.** Of 1,008 defender leads
  into a caller at 1 card, only 3 could have been a lead that stops the
  caller (a combo or a higher single). At 2 cards: 8 of 1,010. The
  `disruptOpponentTichuNearFinish` and `avoidSoftLeadAgainstOpponentTichu`
  weights do their job.
* **Passing on the caller's tricks late.** With the caller at 1–2 cards,
  defenders passed a beatable trick 1 time in 1,193.
* **Dragon gift:** it goes to the non-caller, otherwise to the opponent with
  more cards. That opponent ends last 36 % of the time, against 16 % for the
  other one.
* **The first-out player's partner leading in the race:** winners first in
  166 of 199 cases with one loser.
* **Before the first out, leading into a 1-card opponent who did not
  call:** only 10 avoidable outs in 2,454 rounds. The problem is after the
  first out (#1).
* **The partner guard** costs the calling team about 5 points of first-out
  rate (the partner's own first-outs), but raises the call success rate by
  2–4 points. This is consistent with the earlier A/B result.
* **A caller holding a bomb succeeds less often** (59 % vs 67 %). That
  points at `tichuStrength` over-rating bombs, or at callers breaking them.
  This is a call question, outside this report.

---

## Scoring discrepancy: last player is the partner of the first out

The task's rule (and the official rule): *the last player gives the cards
in their hand to the opposing team, and their tricks to the player who went
out first.* `ScoreTracker._computeNormalCardPoints` does this instead:

```dart
if (key == last) { _isTeamOne(key) ? t2 += pts : t1 += pts; } // tricks -> opponents of last
...
_isTeamOne(first) ? t1 += handPts : t2 += handPts;           // hand -> first's team
```

When the last player is on the *other* team from the first out, both
versions agree. When the last player is the **first-out player's partner**
(for example A1, B1, B2, A2), the two transfers are swapped:

| | Official rule | Code |
|---|---|---|
| Last player's tricks go to | their own team (the first-out player) | the opponents |
| Last player's hand goes to | the opponents | their own team |

The replay confirms this. All 2,454 round results match the code version.
1,008 rounds (41 %) are of this kind, and in 874 of them the result differs
from the official rule by **27 card points** on average (54 points of
difference). The code punishes "partner of the first out ends last" far more
than the official rule does (24 trick points against 3.5 hand points), so
the endgame values in this report (#8 especially) depend on it. Fix the
scorer first (and the NN value targets, which were trained on it). Then
re-run the endgame measurements.

---

## Suggested order

1. **Split `planLead`** into flags: `escapeLeadVsOne` (#1),
   `feedPartnerAlways` (#3, Dog allowed), `noDogAfterPartnerOut` (#4),
   `endgameOrder` (#6, only with ≤ 1 loser), plus the "do not overtake a
   calling partner" rule. Then A/B each one on its own.
2. **Defense:** `holdBombVsCaller` together with `noDragonBomb` (#2, #7), and
   `noPassVsCaller` (#5). These are small local changes in `PlanPlay` and
   `smart_ai_agent.dart`.
3. `planPassEarlyOnly` (#9), `wishVsCaller` (#10).
4. Settle the scoring rule, then `lastPlaceAware` (#8).

Measure each step with the duplicate evaluation (150–400 deals to 1000, both
seatings). For the defense flags, also report the call success rate split
by "a defender holds a bomb" and "a defender passed on a caller's trick".
These two splits should move.

---

## Appendix: method

```bash
cd /home/user/tichu
S=/tmp/claude-0/-home-user-tichu/ae159fbf-ce92-51ac-bcb4-394a13b21561/scratchpad
build/bin/headless_dev --seed=9101 --deal-seed=9101 --episodes=200 --target-score=1000 \
    --format=csv --no-timestamps --output=$S/e/g.csv
build/bin/headless_dev --seed=9101 --deal-seed=9101 --episodes=200 --target-score=1000 \
    --format=bc-jsonl --skip-play-rows --output=$S/e/g.jsonl
# round results only: second latest sample, and latest without the partner guard
build/bin/headless_dev --seed=9302 --deal-seed=9302 --episodes=300 --target-score=1000 \
    --format=bc-jsonl --skip-play-rows --output=$S/e/lat2.jsonl
build/bin/headless_dev --seed=9301 --deal-seed=9301 --episodes=300 --target-score=1000 \
    --format=bc-jsonl --skip-play-rows \
    --heuristic=strict,plan_pass,plan_bombs,plan_score \
    --opponent-heuristic=strict,plan_pass,plan_bombs,plan_score --output=$S/e/noguard.jsonl
python3 $S/tlib.py $S/e/g.csv $S/e/g.jsonl $S/e/g.pkl
```

* The replay and its helpers come from the previous analysis:
  * `$S/tlib.py` replays every play;
  * `$S/gen.py` generates legal moves (it ignores the wish; decisions under
    an active wish were skipped);
  * `$S/part.py` finds the fewest-plays partitions and sure winners.
* Call strength (`tichuStrength`) comes from the bc-jsonl `call: "tichu"`
  rows (`$S/b_str.py` → `$S/e/strs.pkl`).
* Scripts for this report are in `$S/b_*.py` (run from `$S`):

  | Script | Measures |
  |---|---|
  | `b_calls.py`, `b_def.py` | Call outcomes, how the caller gets out, defender holdings at the out, defender leads and passes |
  | `b_def2.py`, `b_def3.py`, `b_def3b.py` | Bomb fates, avoidable leads into the caller, `planPass` against the caller |
  | `b_ctl.py`, `b_near.py`, `b_dfeed.py` | Control plays, near misses, defenders feeding each other |
  | `b_rd.py`, `b_rdj.py` | Comparison of calls with uncalled hands of the same strength |
  | `b_end.py`, `b_end2.py`, `b_b1.py`, `b_p1.py` | 1-2 race, 1-card opponent and 1-card partner leads |
  | `b_dog.py`, `b_dog2.py` | Dog leads after the partner is out |
  | `b_h2h.py`, `b_last.py`, `b_dragon.py` | Head-to-head order, last-player points, Dragon gift |
  | `b_score.py` | Checks the scoring rule against every round result |
  | `b_wish.py` | Mah Jong wishes against a caller |

  `$S/show2.py <round>` prints a round trick by trick.
* "Escapable" in #1: the leader's hand can be split into plays of which at
  most one (played last) is a single that P's card beats, and there is no
  Dog. This uses P's real card, but the proposed high-first order needs no
  hidden information.
* The opponents' cards are used only to *measure*. None of the proposed fixes
  needs hidden information.
* Limitations: one bot playing itself, and observational data. With about
  2,500 rounds, rates are good to about ±1–2 points and subgroups of 100–300
  to about ±4–5 points. The threshold comparison in section A is about ±4
  points.
