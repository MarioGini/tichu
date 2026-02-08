# Tichu AI Strategy North Star

This document is the concise, shared strategy reference for the AI. It captures the intended play style, architecture, and the policy values to tune over time. It distills guidance from the following sources:
- BoardGameGeek: Basic Tichu strategy tips (thread)
- SCV/B.U. Tichu strategy notes
- Board Game Arena tips page
- Stanford CS229 project report (as accessible)
- SpotlightOnGames Tichu analysis

---

## 1) Overall AI Philosophy
- **Lead low, win high**: Preserve control cards (Dragon, Phoenix, Aces) for when control matters.
- **Tempo & control**: Maintain the ability to reclaim the lead; do not burn winners early.
- **Endgame awareness**: Avoid stranded low singles; prioritize “unbeatable” lines when opponents are low.
- **Partner support**: Play to help partner go out; avoid overtaking partner’s winning tricks.
- **Risk-adjusted aggression**: Call Tichu/Grand when expected success is above a threshold that shifts with score.

---

## 2) Architecture Overview (Implemented)
**Core modules** (all under [lib/view_model/ai/](lib/view_model/ai/)):
- `TichuCallStrategy`: decides Tichu/Grand Tichu based on hand strength and score state.
- `SchupfStrategy`: chooses pass cards (to partner/opponents) with conventions.
- `PlaySelectionStrategy`: picks the best turn from all legal turns using a scoring policy.
- `WishStrategy`: chooses Mahjong wishes.
- `BombTimingStrategy`: decides when bombs are justified.
- `DragonGiveStrategy`: selects who gets the Dragon.

**Support modules**:
- `HandEvaluator`: scores hand strength (combos, control cards, bombs, connectivity).
- `TurnScorer`: assigns a numeric score to each legal turn.
- `GameStateTracker`: tracks specials, Aces/Kings, hand sizes, and pass inferences.

**Flow**:
1. Generate legal turns.
2. Filter by mandatory constraints (wish rules, legality).
3. Score turns using policy weights + situational rules.
4. Select highest score, with tie-breaking toward safer/lower-risk plays.

**Implementation files**:
- Strategies and agent wiring: [lib/view_model/ai/smart_ai_agent.dart](lib/view_model/ai/smart_ai_agent.dart)
- Tichu calling: [lib/view_model/ai/tichu_call_strategy.dart](lib/view_model/ai/tichu_call_strategy.dart)
- Schupf: [lib/view_model/ai/schupf_strategy.dart](lib/view_model/ai/schupf_strategy.dart)
- Play selection policy: [lib/view_model/ai/play_selection_strategy.dart](lib/view_model/ai/play_selection_strategy.dart)
- Wish: [lib/view_model/ai/wish_strategy.dart](lib/view_model/ai/wish_strategy.dart)
- Dragon give: [lib/view_model/ai/dragon_give_strategy.dart](lib/view_model/ai/dragon_give_strategy.dart)
- Policy scoring: [lib/view_model/ai/turn_scorer.dart](lib/view_model/ai/turn_scorer.dart)
- Card counting: [lib/view_model/ai/game_state_tracker.dart](lib/view_model/ai/game_state_tracker.dart)

---

## 3) Policy Values (Initial Weights)
These are seed values to iterate on. Values are **relative**, not absolute.

### 3.1 Turn Scoring Weights
- **Low-Lead Preference (early)**: +2
- **Control Preservation (Dragon/Phoenix/Ace held)**: +3
- **Avoid High Burn (early)**: +4
- **Shedding Risky Low Single**: +2
- **Combo Efficiency (pairs/straights/trips)**: +2
- **Bomb Usage (early)**: -6
- **Bomb Usage (late, stop Tichu or 1–2)**: +6
- **Unbeatable Line (opponent <5 cards)**: +5
- **Give Partner Lead (Dog or low handoff)**: +3
- **Prefer Multi-Card (opponent at 1)**: +4
- **Avoid Singles (opponent at 1)**: -4
- **Support Partner Tichu (don’t overtake)**: -4
- **Trick Point Capture**: +1 per point in current trick

### 3.2 Tichu/Grand Thresholds
- Implemented via `HandEvaluator`:
	- **Grand Tichu**: hand score ≥ 70
	- **Tichu**: hand score ≥ 55
- No difficulty scaling (single max-skill AI).

### 3.3 Endgame Priorities
- Opponent at 1 card: **lead multi-card groups** before singles.
- Opponent at 2–4 cards: **prefer large, hard-to-beat lines** (e.g., strong straight).
- Avoid leaving **low single** as last card unless partner is already out.

---

## 4) Condensed Strategy Guidance (North Star)

### 4.1 Lead/Follow
- Lead **low**; keep high winners for reclaiming lead later.
- **Do not top a partner’s likely-winning trick** unless preventing 1–2 or saving Tichu.
- If partner called Tichu: **mostly pass**, only shed low singles/pairs that help them.

### 4.2 Passing (Schupf)
- Pass **worst-fit** cards to opponents (not just lowest), avoid enabling bombs.
- To partner: if strong, pass **third-worst** (keep strength concentrated); if weak, pass a **best** card.
- **Never pass Mahjong to opponents**; avoid passing specials to opponents.
- Dog often to partner to set tempo, especially when supporting Tichu.

### 4.3 Specials
- **Dragon**: hold for control; avoid using early unless it wins a key trick.
- **Phoenix**: flexible; use for combo completion or key single; don’t over-fear -25.
- **Dog**: tempo tool to give partner the lead; timing is critical.
- **Mahjong**: wish for passed card or Ace vs left-hand Tichu; avoid wish if it harms long-term plan.

### 4.4 Bombs
- Save bombs for **late game** or **to stop a Tichu** just before exit.
- Early bomb is only justified if it leads to an immediate exit or critical control.

### 4.5 Endgame
- With opponents low, prioritize **unbeatable lines** (e.g., straight when opponent <5 cards).
- If opponents keep leading singles, **break sets** when needed to regain lead.
- If partner already out and holding Phoenix, consider **not going out immediately** to avoid -25 swing.

### 4.6 Tempo & Control
- Maintain at least one reclaim card (Dragon, Ace, Phoenix in some contexts).
- Use Dog/low lead to give partner control when beneficial.

### 4.7 Card Counting & Inference (Lightweight)
- Track specials and **all Aces and Kings** to identify safe winners and control lines.
- Remember passed cards to infer partner holdings.
- Estimate bomb risk and safety of winners based on unseen ranks.

---

## 5) Implementation Details (Current Behavior)

### 5.1 Play Selection Scoring (TurnScorer)
Scoring uses these concrete rules in [lib/view_model/ai/turn_scorer.dart](lib/view_model/ai/turn_scorer.dart):
- **Immediate win**: if a play empties the hand, score = 1000.
- **Lead state**: a play is “leading” if the deck is empty/none/dog.
- **Early game**: `hand.length >= 9`.
- **Low-lead preference**: add $2\cdot(\frac{25 - value}{25})$ when leading.
- **Combo efficiency**: add $2\cdot(\text{cards in play})$.
- **Control preservation**: subtract $3$ per control card in the play (Dragon/Phoenix/Ace).
- **Avoid high burn (early)**: subtract $4$ per high card in the play (Dragon/Phoenix/Ace/King),
  except when the `GameStateTracker` shows that **all Aces** or **all Kings** are known and you hold the last one.
- **Trick points**: add $1\cdot\text{pointsForCards(deck.turn.cards)}$ when following, and reduce high-burn penalty by $\frac{\text{trickPoints}}{25}$.
- **Shedding low singles**: compare low-singleton count (<= 7) before and after the play and add $2$ per single shed.
- **Bomb timing**: add -6 for bombs early; add +6 for bombs late when an opponent is low or has called Tichu.
- **Unbeatable lines vs low opponents**: add +5 for straight/pair-straight/full house/bomb when opponent <5 cards.
- **Opponent at 1**: add +4 if multi-card, subtract -4 if single.
- **Partner Tichu support**: subtract 4 if partner called Tichu and is currently winning the trick.
- **Dog**: add +3 to prefer giving partner the lead.
- **Tie-breaker**: if scores are equal, pick lower `value` (conserve strength).

### 5.2 Wish Handling
- Uses the wish enforcement in [lib/view_model/turn/wish_logic.dart](lib/view_model/turn/wish_logic.dart).
- When playing Mahjong, `WishStrategy` selects the highest missing card from A, K, Q, J, 10.

### 5.3 Schupf Behavior
- Avoids specials if possible; gives two lowest to opponents and a higher remaining to partner.
- If partner called **Grand Tichu**, give the **best** card to partner.
- If an opponent called **Grand Tichu**, give them the **Dog** if available, otherwise the worst.
- Prefer **even-valued** cards to the right opponent to reduce overlap.
- Optionally split **low pairs** to opponents to reduce bomb potential.
- Implementation: [lib/view_model/ai/schupf_strategy.dart](lib/view_model/ai/schupf_strategy.dart).

### 5.4 Dragon Give
- Avoid opponent with Tichu if possible; otherwise give to opponent with more cards.
- Implementation: [lib/view_model/ai/dragon_give_strategy.dart](lib/view_model/ai/dragon_give_strategy.dart).

### 5.5 GameStateTracker (Ace/King awareness)
- Tracks seen cards from: current hand, schupf receipts, and last played turn.
- Enables “last Ace/King” recognition to reduce early high-burn penalties.
- Implementation: [lib/view_model/ai/game_state_tracker.dart](lib/view_model/ai/game_state_tracker.dart).

### 5.6 Partner Support (Tichu)
- If partner called Tichu and is winning the trick with <= 5 cards, the AI prefers to pass.
- If partner called Tichu and has **1 card**, and the AI is leading, it leads a **low single** to enable partner to finish.
- Implementation: [lib/view_model/ai/smart_ai_agent.dart](lib/view_model/ai/smart_ai_agent.dart).

---

## 6) Open Questions (to revisit)
- Should we extend counting beyond Aces/Kings for endgame precision?
- If we add any lookahead, keep it hand-size only (no hidden cards).

---

## 7) Next Actions
- Review live play and tune policy weights if needed.
- Expand tests to cover bomb timing and partner Tichu support.
