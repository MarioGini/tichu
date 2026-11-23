# Tichu AI Agent Strategy Contract

This file is the implementation-locked strategy contract for the heuristic
bot (`SmartAiAgent`). Every rule listed here is present in code today.

The rule set was cut down on 2026-11-17: every rule and `TurnScorer` weight
was scored on exact rollout values (`headless --shadow-heuristics`, see
[rl/README.md](../../rl/README.md)) and in duplicate duels, and rules
without measurable value were deleted (section 3b). The heuristic before
that is commit 92aed27.

---

## 1) Runtime Goal
- Play a tempo-aware, partner-supporting game that preserves control cards
  early and does not waste strength.
- Keep decision flow deterministic and testable.

---

## 2) Decision Pipeline (authoritative)
1. Build legal turns (wish enforcement included).
2. Hard rules: go out when possible; never go out ahead of a partner who
   called Tichu (R2).
3. Tactical shortcuts, in order: partner support pass, Mahjong opening lead,
   partner finish lead, early Dog lead, Dog lead for a Grand Tichu partner,
   singleton response.
4. Score the remaining candidates with `TurnScorer` (R10), pick the maximum
   (tie-break: lower turn value).
5. Swap a chosen multi-card combination for the cheapest equivalent one
   (R12).

Primary wiring: [smart_ai_agent.dart](smart_ai_agent.dart),
[smart_ai_heuristic_turn.dart](smart_ai_heuristic_turn.dart)

---

## 3) Rule Set (must hold)

### R1 — Empty/No-Legal Safety
- If the hand is empty or nothing beats the trick, pass.
- Code: [smart_ai_agent.dart](smart_ai_agent.dart)

### R2 — Partner Protection
- Partner is winning the trick: pass, unless it is a low single (below 10)
  and nobody called; with a calling partner pass on anything they can hold
  (`partner_pass`).
- Partner called Tichu and is still in: never go out ahead of them
  (`guard`).
- Code: [play_tactics_policy.dart](play_tactics_policy.dart),
  [smart_ai_agent.dart](smart_ai_agent.dart)

### R3 — Partner Finish Enablement
- Leading, partner called Tichu and has exactly 1 card: lead the lowest
  single (prefer non-Dragon) (`partner_finish_lead`).
- Code: [play_tactics_policy.dart](play_tactics_policy.dart)

### R4 — Mahjong Lead Preference
- Opening lead of the game with the Mahjong and no active wish: prefer
  Mahjong straights, otherwise the best Mahjong play (`mahjong_lead`).
- Code: [play_tactics_policy.dart](play_tactics_policy.dart)

### R5 — Wish Compliance
- Turns that violate an active wish are never played (wish logic).
- Code: [play_tactics_policy.dart](play_tactics_policy.dart),
  [../game/turn/wish_logic.dart](../game/turn/wish_logic.dart)

### R6 — Mahjong Wish Selection
- Preferred wish source is the last card schupfed to the next player when
  valid and still useful.
- Fallback order: first missing among A, K, Q, J, 10; else no wish.
- Code: [smart_ai_agent.dart](smart_ai_agent.dart),
  [wish_strategy.dart](wish_strategy.dart)

### R7 — Tichu Calls
- Never Grand Tichu, never before the schupf.
- Tichu at the first opportunity when
  `strength = Dragon + 0.8 Phoenix + 0.7/Ace + 1.2/bomb + 0.2/King
  - 0.35 * plays-to-go-out - 0.7 if holding the Dog` reaches -0.1
  (0.5 when an opponent already called), calibrated on exact
  counterfactual call values.
- Never call when the partner already called.
- Code: [tichu_call_strategy.dart](tichu_call_strategy.dart),
  [smart_ai_agent.dart](smart_ai_agent.dart)

### R8 — Schupf Conventions
- Reject schupf when hand has <3 cards.
- If opponent called Grand Tichu and Dog exists, give Dog to that opponent.
- Prefer splitting low pairs to opponents.
- Fill opponent slots with low cards (odd-left / even-right preference).
- Give strongest partner card when partner called Grand Tichu.
- Code: [schupf_strategy.dart](schupf_strategy.dart)

### R9 — Dragon Give
- Prefer giving Dragon to opponent without Tichu call.
- If symmetric, give to opponent with more cards.
- Code: [dragon_give_strategy.dart](dragon_give_strategy.dart)

### R10 — Turn Scoring
- Going out scores 1000.
- Leading: prefer low plays. Every card played: small bonus.
- Spending Ace / Phoenix / Dragon on a trick not sure to be taken from an
  opponent: penalty. Early (9+ cards): penalty for K / A / Phoenix / Dragon,
  smaller on tricks with points.
- Own point cards into a trick not sure to be won: penalty.
- Breaking the hand plan (more plays needed to go out): penalty.
- Getting rid of unpaired low cards (<= 7): bonus.
- An opponent with 4 cards or fewer: bonus for unbeatable plays; with 1
  card: prefer multi-card plays, avoid singles.
- Code: [turn_scorer.dart](turn_scorer.dart)

### R11 — Seat/Team Semantics
- Partner/opponent semantics are parity-based seat relationships.
- Code: [table_relationships.dart](table_relationships.dart)

### R12 — Cheapest Equivalent Combination
- After the scorer picked a multi-card, non-bomb combination, play the
  cheapest legal one of the same type and length (lowest rank sum; Phoenix
  and Dragon count as the most expensive cards): 6-6-Q-Q-Q instead of
  J-J-Q-Q-Q, Q-Q-Q-x-x instead of A-A-A-x-x, 4-4-4-9-9 instead of 4-4-4-J-J
  (`cheap_combos`).
- Code: [smart_ai_helpers.dart](smart_ai_helpers.dart)

---

## 3b) Measured value of the rules

- R12 is the main gain over the old heuristic (58.9 % in duplicate duels on
  its own; with the retuned weights and without "pass instead of damaging
  the plan" 61.6 % ± 0.5).
- Kept because removing them loses points: control preservation, shedding
  low singletons, avoid-high-burn, point gift, the opponent-low weights, the
  plan penalty, the early Dog lead, the singleton response, the partner
  finish lead.
- Deleted on 2026-11-17 (the remaining heuristic beats the old one
  50.9 % ± 0.3 and plays bit-identically to the duel-tested variant): the
  trick-point and partner-Tichu terms (same for every candidate, so they
  never changed a choice), the Dog-lead, sure-capture and both bomb-timing
  weights, the opponent-Tichu disruption terms, all five Phoenix/trump
  weights and the low-single Phoenix filter, the valuable-bomb, keep-bombs
  and wish-preference shortcuts, the A/B options that measured worse
  (plan-lead, plan-pass, plan-singles, lead-sure, feed-partner, opponent-1
  lead, no-Dog, conserve-controls, support, announce) and the legacy Tichu
  index.
- The rules are unconditional (the A/B rule switches were removed on
  2026-11-22); `TurnScorer` weights can be overridden for experiments:
  `--heuristic=latest,lowLeadPreference:4`
  ([heuristic_options.dart](heuristic_options.dart)).

---

## 4) Policy Weights (defaults)
- `lowLeadPreference`: 2
- `controlPreservation`: 6
- `avoidHighBurn`: 4
- `sheddingRiskyLowSingle`: 2
- `comboEfficiency`: 2
- `unbeatableLine`: 2.5
- `preferMultiCardWhenOpponentLow`: 4
- `avoidSingleWhenOpponentLow`: 4
- `pointGift`: 0.15 (per point)
- `planEfficiency`: 2.5 (per extra play)

Code: [turn_scorer.dart](turn_scorer.dart)

---

## 5) Verification Map (tests)
- Agent orchestration and tactical behavior:
  [smart_ai_agent_test.dart](../../test/agents/smart_ai_agent_test.dart)
- Tactical policy rules:
  [play_tactics_policy_test.dart](../../test/agents/play_tactics_policy_test.dart)
- Rule switches and R12:
  [heuristic_options_test.dart](../../test/agents/heuristic_options_test.dart)
- Schupf rules:
  [schupf_strategy_test.dart](../../test/agents/schupf_strategy_test.dart)
- Dragon give rules:
  [dragon_give_strategy_test.dart](../../test/agents/dragon_give_strategy_test.dart)
- Wish rules:
  [wish_strategy_test.dart](../../test/agents/wish_strategy_test.dart)
- Tichu-call thresholds:
  [tichu_call_strategy_test.dart](../../test/agents/tichu_call_strategy_test.dart)
- Turn scoring policy:
  [turn_scorer_test.dart](../../test/agents/turn_scorer_test.dart)

---

## 6) Scope Guard
- Do not add strategy statements here unless they are implemented in code and
  covered by tests.
- If a new rule is added, update both implementation and mirrored tests in the
  same change.
