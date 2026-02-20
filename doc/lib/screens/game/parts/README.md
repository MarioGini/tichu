# lib/screens/game/parts/

Partitioned logic for `game_screen` to keep widget file focused and maintainable.

## Implemented Here
- `game_screen_actions.dart`: action handlers and user-triggered command wiring.
- `game_screen_dialogs.dart`: dialog presentation flows (dragon give, round complete, wish selection).
- `game_screen_logic.dart`: game-screen-specific orchestration/state logic.
- `game_screen_state_bindings.dart`: bindings from backend/projected state into UI fields.
