# lib/game/

Domain and runtime seam for game progression: engine contracts, backend APIs, player/opponent interfaces, and UI projection.

## Implemented Here
- `engine.dart`: main engine contract used by controller/backend.
- `engine_state.dart`: engine state shapes/snapshots.
- `game_backend.dart`: runtime backend boundary exposed to UI/controller.
- `game_play_controller.dart`: orchestrates play flow between UI and backend.
- `driver_ui_projector.dart`: normalizes backend/driver state for UI consumption.
- `player_control.dart`: user action/control abstractions.
- `player_agent.dart`: player decision-driver contract (AI or manual).
- `turn_rules_adapter.dart`: adapter from runtime actions to turn-rule system.

## Child Folders
- [schupfen](schupfen/README.md): schupf pass modeling.
- [scoring](scoring/README.md): score data/tracking.
- [turn](turn/README.md): legality, move generation, and turn engine internals.
