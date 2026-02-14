# lib/agents/

AI policy layer: evaluates hand/game state and chooses legal, tactical actions.

## AI Strategy (Agent Summary)

Read this section first when the task is about AI decisions. It is intentionally compact for quick retrieval.

### Runtime Goal
- Play tempo-aware, partner-supporting Tichu.
- Preserve control cards early; increase disruption pressure near opponent exits.
- Keep decision flow deterministic and testable.

### Decision Pipeline (authoritative)
1. Update tracker/memory state.
2. Build legal turns.
3. Apply tactical overrides (partner support, Mahjong/wish constraints).
4. Score candidates.
5. Select highest score; tie-break by lower turn value.

### Non-Negotiable Rules
- **Safety**: no legal turn or empty hand -> pass.
- **Partner support**: prefer pass when partner tichu/grand tichu is active and legal, unless wish or disruption constraints override.
- **Wish compliance**: prefer/require wish-valid plays when wish is active.
- **Mahjong handling**: prefer Mahjong-strong leads when leading without active wish; choose useful wish faces.
- **Tichu calls**: use threshold policy; never call when partner already called (`tichu` or `grandTichu`).
- **Schupf policy**: prioritize tactical low-card distribution and partner/opponent context.
- **Dragon give**: prefer opponent target choices that reduce risk of immediate punishment.

### File-to-Question Map (open only what you need)
- Call timing/thresholds -> `tichu_call_strategy.dart`
- Turn choice/tactical pass/wish lead overrides -> `play_tactics_policy.dart`
- Candidate scoring weights/heuristics -> `turn_scorer.dart`
- Schupf decisions -> `schupf_strategy.dart`
- Dragon handoff decisions -> `dragon_give_strategy.dart`
- End-to-end AI orchestration -> `smart_ai_agent.dart`
- Team/seat semantics -> `table_relationships.dart`

### Source Contract
- Full strategy contract: `lib/agents/ai_strategy.md`

## Implemented Here
- `smart_ai_agent.dart`: orchestrates end-to-end AI action selection.
- `../../../lib/agents/ai_strategy.md`: full source strategy contract used by implementation/tests.
- `game_state_tracker.dart`: extracts/normalizes state signals used by policy.
- `hand_evaluator.dart`: strength/value assessment of current hand.
- `play_selection_strategy.dart`: candidate play choice strategy.
- `play_tactics_policy.dart`: tactical bias/heuristics during play decisions.
- `turn_scorer.dart`: scores candidate turn outcomes.
- `bomb_timing_strategy.dart`: bomb usage timing policy.
- `wish_strategy.dart`: wish declaration and wish-response handling.
- `tichu_call_strategy.dart`: small/grand tichu call timing policy.
- `schupf_strategy.dart`: card passing (schupf) strategy.
- `dragon_give_strategy.dart`: dragon trick handoff choice policy.
- `table_relationships.dart`: partner/opponent relational context helpers.
