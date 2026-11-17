# Tichu AI Agent Strategy Contract

This file is the implementation-locked strategy contract for the current AI.
Every rule listed here is expected to be present in code today (not
aspirational).

---

## 1) Runtime Goal
- Play a strong, tempo-aware, partner-supporting game that preserves control
  cards early and increases disruption pressure near opponent exits.
- Keep decision flow deterministic and testable.

---

## 2) Decision Pipeline (authoritative)
1. Update memory/tracker state.
2. Build legal turns.
3. Apply tactical overrides (partner support, mahjong lead, wish constraints).
4. Score candidate turns.
5. Select max score, tie-break by lower turn value.

Primary wiring: [smart_ai_agent.dart](smart_ai_agent.dart)

---

## 3) Rule Set (must hold)

### R1 — Empty/No-Legal Safety
- If hand is empty or no legal turns exist, return pass.
- Code: [smart_ai_agent.dart](smart_ai_agent.dart)

### R2 — Partner Protection Pass
- If partner is currently winning a high trick, prefer pass (unless urgent
  opponent-Tichu disruption condition).
- If partner called Tichu or Grand Tichu and partner has not yet finished,
  pass whenever pass is legal only when self has not called Tichu/Grand Tichu
  (avoid conflicting dual-support behavior).
- Code: [play_tactics_policy.dart](play_tactics_policy.dart)

### R3 — Partner Finish Enablement
- If leading and partner called Tichu with exactly 1 card, lead lowest single
  (prefer non-Dragon).
- Code: [play_tactics_policy.dart](play_tactics_policy.dart)

### R4 — Mahjong Lead Preference
- When leading with Mahjong and no active wish, prefer Mahjong straights;
  otherwise best Mahjong lead.
- Code: [play_tactics_policy.dart](play_tactics_policy.dart)

### R5 — Wish Compliance
- If active wish exists, prefer turns containing wished face.
- Filter out wish-violating turns via wish logic.
- Code: [play_tactics_policy.dart](play_tactics_policy.dart),
  [../game/turn/wish_logic.dart](../game/turn/wish_logic.dart)

### R6 — Mahjong Wish Selection
- Preferred wish source is the last card schupfed to next player (right in this
  UI / seat+1 in engine order) when valid and still useful.
- Fallback order: first missing among A, K, Q, J, 10; else no wish.
- Code: [smart_ai_agent.dart](smart_ai_agent.dart),
  [wish_strategy.dart](wish_strategy.dart)

### R7 — Tichu Calling Thresholds
- Implemented from the CS229 paper using rounded logistic-feature indices.
- **Grand Tichu (8 cards):** the heuristic never calls Grand Tichu. Grand
  Tichu (and optionally Tichu) calls can instead come from learned call-value
  nets (`NnTichuCallStrategy`, see [rl/README.md](../../rl/README.md)).
- **Tichu (14 cards):** compute
  `It = 2*NAce - 2*NDog + 6*NDragon + 6*NPhoenix + 5*NBomb + NStraight - NSmallSingleton(2..7)`
  and call when `It >= 7`.
- Tichu is evaluated on full hand state.
- Delayed Tichu timing for automated opponents is decided in the AI layer at
  first legal call opportunity (`selectAction`), not in backend orchestration.
- Team constraint in AI: never call Tichu when partner already has any call
  (`tichu` or `grandTichu`) in the current round.
- Code: [tichu_call_strategy.dart](tichu_call_strategy.dart),
  [player_agent.dart](../game/player_agent.dart)

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

### R10 — Turn Scoring Core
- Immediate win bonus dominates (`1000`).
- Lead-low preference, combo efficiency, control preservation.
- Early high-card burn penalty with tracker-aware Ace/King exceptions.
- Trick-point capture bonus while following.
- Low-singleton shedding reward.
- Bomb timing: early penalty vs late reward.
- Opponent-low unbeatable-line bonus.
- Opponent-at-one: prefer multi-card, penalize singles.
- Opponent-Tichu-near-finish disruption/anti-soft-lead.
- Dog lead bonus.
- Partner-Tichu-overcall penalty.
- Code: [turn_scorer.dart](turn_scorer.dart)

### R11 — Seat/Team Semantics
- Partner/opponent semantics are parity-based seat relationships.
- Code: [table_relationships.dart](table_relationships.dart)

---

### R12 — Cheapest Equivalent Combination (`latest`)
- After the scorer picked a multi-card, non-bomb combination, play the
  cheapest legal one of the same type and length (lowest rank sum; Phoenix
  and Dragon count as the most expensive cards): 6-6-Q-Q-Q instead of
  J-J-Q-Q-Q, Q-Q-Q-x-x instead of A-A-A-x-x, 4-4-4-9-9 instead of 4-4-4-J-J.
- Code: [smart_ai_helpers.dart](smart_ai_helpers.dart) (`_cheapestEquivalent`)

---

## 3b) Presets and measured value of the rules

`HeuristicOptions.latest` (the app's heuristic) = `classic` + R12, without the
"pass instead of damaging the plan" rule, with `unbeatableLine` 2.5 and
`controlPreservation` 6. It beats `classic` 61.6 % ± 0.5 in duplicate duels
(R12 alone: 58.9 %).

Every rule and weight was scored on exact rollout values
(`headless --shadow-heuristics`, see [rl/README.md](../../rl/README.md)):

- Rules that earn their keep (removing them costs 0.15-0.6 points per
  decision): R12, control preservation, shedding low singletons,
  avoid-high-burn, the early Dog lead, the singleton response.
- Rules and weights that change fewer than 1 in 2000 decisions and have no
  measurable value: `trickPointCapture`, `supportPartnerTichu` (both are the
  same for every candidate play, so they cannot change the choice),
  `givePartnerLead`, the three `phoenixTrump*` weights,
  `preferNaturalTrumpResponse`, `preserveFlexibleTrump`,
  `preferMultiCardWhenOpponentLow`, `avoidSingleWhenOpponentLow`,
  `avoidSoftLeadAgainstOpponentTichu`, `sureTrickCapture`, both `bombUsage*`
  weights, and the shortcuts valuable-bomb, keep-bombs, wish preference and
  the low-single Phoenix filter. They are candidates for deletion.
- Rules that lose points and stay off: plan-lead, lead-sure, feed-partner,
  support (always pass for a calling partner), plan-singles.

---

## 4) Policy Weights (current defaults)
- `lowLeadPreference`: 2
- `controlPreservation`: 3 (`latest`: 6)
- `avoidHighBurn`: 4
- `sheddingRiskyLowSingle`: 2
- `comboEfficiency`: 2
- `bombUsageEarly`: -6
- `bombUsageLate`: 6
- `unbeatableLine`: 5 (`latest`: 2.5)
- `givePartnerLead`: 3
- `preferMultiCardWhenOpponentLow`: 4
- `avoidSingleWhenOpponentLow`: 4
- `supportPartnerTichu`: 4
- `disruptOpponentTichuNearFinish`: 8
- `avoidSoftLeadAgainstOpponentTichu`: 4
- `trickPointCapture`: 1

Code: [turn_scorer.dart](turn_scorer.dart)

---

## 5) Verification Map (tests)
- Agent orchestration and tactical behavior:
  [smart_ai_agent_test.dart](../../test/agents/smart_ai_agent_test.dart)
- Tactical policy rules:
  [play_tactics_policy_test.dart](../../test/agents/play_tactics_policy_test.dart)
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
