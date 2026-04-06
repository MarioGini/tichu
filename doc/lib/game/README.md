# lib/game/

Domain and runtime seam for game progression: engine contracts, backend APIs, player/opponent interfaces, and UI projection.

## Implemented Here
- `card_identifiers.dart`: shared card-identifier map for building full 56-card Tichu decks.
- `engine.dart`: main engine contract used by controller/backend.
- `engine_state.dart`: engine state shapes/snapshots.
- `game_actions.dart`: `GameAction` abstract class + all concrete action subclasses (PlayTurnAction, PassAction, etc.).
- `game_match.dart`: multiplayer-ready live match contract with revision/idempotency metadata around player snapshots.
- `game_session.dart`: lobby/session contract for create/join/seat/ready/start flows before a live match begins.
- `game_play_controller.dart`: orchestrates play flow between UI and backend.
- `game_snapshot.dart`: `GameSnapshot` and `PlayerSnapshot` — immutable state snapshots for UI and backend communication.
- `game_types.dart`: core domain enums and simple types (`PlayerType`, `GamePhase`, `SchupfDirection`, `SchupfReceipt`, `GamePlayer`).
- `driver_ui_projector.dart`: normalizes backend/driver state for UI consumption.
- `player_control.dart`: user action/control abstractions.
- `player_agent.dart`: player decision-driver contract (AI or manual).
- `turn_rules_adapter.dart`: adapter from runtime actions to turn-rule system.

## Child Folders
- [schupfen](schupfen/README.md): schupf pass modeling.
- [scoring](scoring/README.md): score data/tracking.
- [turn](turn/README.md): legality, move generation, and turn engine internals.
