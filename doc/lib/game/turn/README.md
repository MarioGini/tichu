# lib/game/turn/

Core turn rules surface: legality, move generation, selection matching, wish/tichu state, and turn handling.

## Implemented Here
- `find_turn.dart`: current/next turn lookup helpers.
- `move_generator.dart`: legal move generation from state/hand.
- `selection_matcher.dart`: maps UI card selections to legal combinations.
- `tichu_data.dart`: tichu-related turn metadata.
- `turn_handler.dart`: applies and advances turn actions.
- `wish_logic.dart`: wish declaration/fulfillment logic.

## Child Folders
- [engine](engine/README.md): concrete turn engine implementation.
- [utils](utils/README.md): card/combo helpers and engine utility modules.
