# Agent Guide — Tichu

## Project Overview

A single-player **Tichu** card game built with **Flutter** (Dart), featuring
3 AI opponents and a fully functional local game engine. Tichu is a 4-player
trick-taking card game played in teams of 2. The game logic, AI, scoring, and
UI are all implemented and working. Firebase/Firestore integration exists as
stubs for future online multiplayer.

## Tech Stack

- **Client**: Flutter (Dart SDK ^3.10.0), Material Design
- **Local engine**: `LocalGameBackend` — in-memory game state with stream-based
  updates
- **AI**: `SmartAiAgent` — rule-based strategic AI with hand evaluation
- **Audio**: `audioplayers` package for sound effects (bomb, dog)
- **Firebase** (stubbed): Firebase Hosting, Cloud Firestore, Cloud Functions
  (TypeScript)
- **Linting**: `flutter_lints` + `analysis_options.yaml` (Dart), TSLint
  (TypeScript)

## Project Structure

```
lib/
  main.dart                          # App entry point → HomeScreen
  game/
    game_notifier.dart               # Abstract ChangeNotifier bridge to GameBackend
  screens/
    home/
      home_screen.dart               # Home screen — target score selector, "New Local Game" button
    game/
      game_screen.dart               # Main game UI (StatefulWidget, uses part files below)
      game_board.dart                # Board layout — opponents, trick area, hand, action bar
      game_screen_actions.dart       # Mixin: card selection, play, pass, bomb, schupf, tichu
      game_screen_bindings.dart      # Mixin: abstract getters/setters for shared state across mixins
      game_screen_bomb_overlay.dart  # Bomb slam animation overlay widget
      game_screen_dialogs.dart       # Mixin: all dialogs (round-complete, phoenix, wish, grand tichu, dragon-give, schupfen)
      game_screen_helpers.dart       # Mixin: sound effects, auto-confirm AI, snapshot updates
  widgets/
    action_bar.dart                  # Play / Pass / Bomb / Tichu buttons
    card_widget.dart                 # Single card visual representation (face + color, selectable)
    hand_display.dart                # Horizontal scrollable hand of CardWidgets (multi-select)
    opponent_display.dart            # AI opponent: card count, name, tichu badge, out badge
    trick_display.dart               # Current trick cards + winner label
  services/
    firestore_api.dart               # Firestore stubs, 56-card cardIdentifiers map
    game_backend.dart                # Core data classes + abstract GameBackend interface
    get_cards.dart                   # Stream widget prototype (mostly commented out)
    local_backend.dart               # Full local game engine (983 lines) — deal, grand tichu, schupf, play, scoring, multi-round
    sound_effects.dart               # Static playDog() and playBomb() via audioplayers
  theme/
    app_theme.dart                   # Light + dark ThemeData (green/gold color scheme)
  view_model/
    player.dart                      # Legacy Player class (pre-game flow with StoreAPI refs)
    ai/
      hand_evaluator.dart            # Hand strength scorer (0-100) for tichu/grand tichu decisions
      player_agent.dart              # Abstract PlayerAgent interface
      smart_ai_agent.dart            # SmartAiAgent — strategic rule-based AI (320 lines)
    schupfen/
      schupfer.dart                  # SchupfSelection / SchupfSend data classes
    scoring/
      score_data.dart                # Card point values, Team, ScoreCounter
      score_tracker.dart             # Full scoring engine — tichu/GT bonuses, 1-2 finish, multi-round, game-over
    turn/
      find_turn.dart                 # Turn classification engine (cards → TichuTurn)
      move_generator.dart            # Legal move generator — all valid TichuTurns for hand + DeckState
      tichu_data.dart                # Core data model: Card, TichuTurn, DeckState, enums
      tichu_rules.dart               # requiredPassesForTrick() helper
      turn_handler.dart              # Turn validation against current deck state
      wish_logic.dart                # Mah Jong wish enforcement & propagation
      utils/
        bomb_utils.dart              # Bomb detection (quartets + straight bombs)
        card_utils.dart              # Card occurrence counting, connected-card finding
        full_house_utils.dart        # Full house detection & generation
        pair_straight_utils.dart     # Pair straight detection & generation
        straight_utils.dart          # Straight detection, Phoenix gap-filling
test/
  utils/
    test_game_backend.dart           # FakeGameBackend for widget tests
    test_game_fixtures.dart          # Test fixture builder
  screens/
    game/
      game_screen_ai_confirmation_test.dart  # Widget test: pending AI cards, confirm button
      game_screen_bomb_button_test.dart      # Widget test: bomb button enabled state
  view_model/
    ai/
      hand_evaluator_test.dart       # Hand scoring, GT/tichu thresholds
      smart_ai_agent_test.dart       # All AI phases (464 lines)
    scoring/
      score_tracker_test.dart        # Card points, tichu/GT, 1-2 finish, multi-round, game-over
    turn/
      find_turn_test.dart            # Turn classification: singles through bombs, phoenix combos
      move_generator_test.dart       # Legal move generation for various hand/deck combos
      tichu_data_test.dart           # Card sorting (compareCards)
      turn_handler_test.dart         # validTurn() checks
      wish_logic_test.dart           # Wish enforcement across all combination types
      utils/
        bomb_utils_test.dart         # Quartet + straight bomb detection
        card_utils_test.dart         # occurrences, occurrence count, connected cards
        full_house_utils_test.dart   # Full house detection with phoenix
        pair_straight_utils_test.dart # Pair-straight detection with phoenix
        straight_utils_test.dart     # Straight detection, phoenix gap-filling
functions/
  src/index.ts                       # Firebase Cloud Functions (Firestore triggers, stubs)
```

## Architecture

| Layer | Path | Description |
|---|---|---|
| Entry point | `lib/main.dart` | Bootstrap, routes to `HomeScreen` |
| Game engine | `lib/services/local_backend.dart` | `LocalGameBackend` — full round lifecycle (deal → grand tichu → schupf → play → score → next round) |
| Backend interface | `lib/services/game_backend.dart` | `GameBackend` abstract class + data classes (`GameSnapshot`, `PlayerSnapshot`, `GameAction`, `GamePhase`) |
| State bridge | `lib/game/game_notifier.dart` | Abstract `GameNotifier extends ChangeNotifier` — wraps `GameBackend` for UI |
| UI / Home | `lib/screens/home/` | Target score selector, start game |
| UI / Game | `lib/screens/game/` | Full game board + dialogs (6 part files, 1200+ lines total) |
| UI / Widgets | `lib/widgets/` | Card, hand, trick, action bar, opponent display |
| AI | `lib/view_model/ai/` | `PlayerAgent` interface, `SmartAiAgent` (rule-based), `HandEvaluator` |
| Turn detection | `lib/view_model/turn/find_turn.dart` | Classifies card selections into turn types |
| Turn handling | `lib/view_model/turn/turn_handler.dart` | Validates turns against current `DeckState` |
| Move generation | `lib/view_model/turn/move_generator.dart` | `generateLegalTurns()` — all legal plays for a hand + deck state |
| Wish logic | `lib/view_model/turn/wish_logic.dart` | Mah Jong wish enforcement & propagation |
| Data model | `lib/view_model/turn/tichu_data.dart` | `Card`, `TichuTurn`, `DeckState`, enums |
| Turn rules | `lib/view_model/turn/tichu_rules.dart` | `requiredPassesForTrick()` helper |
| Turn utils | `lib/view_model/turn/utils/` | Bomb, straight, pair-straight, full-house, card helpers |
| Scoring | `lib/view_model/scoring/` | `score_data.dart` (point values), `score_tracker.dart` (full scoring engine) |
| Schupfen | `lib/view_model/schupfen/schupfer.dart` | Card-trading phase data classes |
| Firestore (stub) | `lib/services/firestore_api.dart` | `StoreAPI` — 56-card mapping, stubbed Firestore ops |
| Sound effects | `lib/services/sound_effects.dart` | `playDog()`, `playBomb()` via `audioplayers` |
| Theme | `lib/theme/app_theme.dart` | Light + dark themes (green/gold) |
| Legacy | `lib/view_model/player.dart` | Legacy `Player` class (pre-game flow with StoreAPI refs) |
| Cloud Functions | `functions/src/index.ts` | Firebase Cloud Functions (card distribution stubs) |

## Key Domain Concepts

- **56-card Tichu deck**: 4 suits × 13 ranks + 4 special cards (Mah Jong,
  Phoenix, Dog, Dragon).
- **Turn types**: single, pair, triplet, full house, straight (≥5), pair
  straight (≥4), bomb (quartet or same-color straight), dog.
- **Phoenix**: Wild card with variable value; can fill gaps in straights,
  promote singles to pairs, pairs to triplets for full houses.
- **Mah Jong wish**: When playing the Mah Jong, you may wish for a card face.
  Subsequent players must play that face if legally possible.
- **Schupfen**: Pre-game card-trading phase — each player passes one card to
  each other player.
- **Scoring**: 5s = 5pts, 10s/Kings = 10pts, Dragon = 25pts, Phoenix = −25pts.

## Data Model (tichu_data.dart)

- `CardFace` enum — `none`, `mahJong`, `two`–`ace`, `dragon`, `phoenix`, `dog`
- `CardColor` enum — `black`, `green`, `red`, `blue`, `special`
- `Card` — Immutable; has `face`, `color`, `value` (double). Special `Card.phoenix(double)` constructor.
- `TurnType` enum — `none`, `empty`, `single`, `pair`, `pairStraight`, `triplet`, `fullHouse`, `straight`, `dog`, `bomb`
- `TichuTurn` — Immutable; has `type`, `cards`, `value`. Bombs get a +20 value offset for straight bombs.
- `DeckState` — Current play state: `turn`, `wish`, `currentWinner`, `cardStack`

## Game Backend Data Model (game_backend.dart)

- `GamePhase` enum — `grandTichu`, `schupfen`, `playing`, `roundComplete`, `gameOver`
- `PlayerType` enum — `human`, `ai`
- `GamePlayer` — `name`, `type`, `hand`, `madeCards`, `calledGrandTichu`, `calledTichu`, `isOut`, `finishPosition`
- `GameSnapshot` — Full game state: `phase`, `players`, `deckState`, `activePlayer`, `leadPlayer`, `passCount`, `finishOrder`, `scores`
- `PlayerSnapshot` — Per-player view: own hand, opponent card counts, current trick, active player, wish, scores
- `GameAction` — Union type for all player actions (play, pass, grandTichu, tichu, schupf, dragonGive)
- `GameBackend` — Abstract interface: `createGame()`, `watchGame()`, `submitAction()`

## Testing

Tests live under `test/` and mirror the `lib/` structure. 15 test files with
~2,575 lines of test code.

**Well-tested areas:**
- Turn classification (`find_turn_test.dart`)
- Turn validation (`turn_handler_test.dart`)
- Wish enforcement (`wish_logic_test.dart`, 408 lines)
- All turn utils (bomb, card, full house, pair straight, straight)
- Legal move generation (`move_generator_test.dart`)
- AI agent — all phases (`smart_ai_agent_test.dart`, 464 lines)
- Hand evaluation (`hand_evaluator_test.dart`)
- Scoring engine (`score_tracker_test.dart`)
- UI widget tests (AI confirmation, bomb button)

**Not yet tested:**
- `LocalGameBackend` (983 lines — no direct tests, indirectly exercised via
  AI/scoring tests)
- `GameNotifier`
- Most widget files (card, hand, trick, action bar, opponent display)
- Game screen integration

```bash
# Run all tests
flutter test

# Run a specific test file
flutter test test/view_model/turn/find_turn_test.dart
```

## Build & Run

```bash
# Get dependencies
flutter pub get

# Run the app (Linux desktop)
flutter run -d linux

# Run the app (web)
flutter run -d chrome

# Build for web (deployed via Firebase Hosting)
flutter build web

# Deploy to Firebase
firebase deploy
```

### Cloud Functions

```bash
cd functions
npm install
npm run build
npm run serve    # Local emulator
npm run deploy   # Deploy to Firebase
```

## Coding Conventions

- Dart files use lowercase snake_case filenames.
- Immutable data classes (`Card`, `TichuTurn`, `DeckState`) — prefer creating
  new instances over mutation.
- Game logic is pure (no side effects) and lives in `view_model/`; Firestore I/O
  is isolated in `services/`.
- `GameScreen` uses `part` files to split a large StatefulWidget across mixins
  (actions, dialogs, helpers, bindings, bomb overlay).
- Tests follow the same directory structure as `lib/`.
- Linter: `flutter_lints` package; `public_member_api_docs` rule is disabled.

---

## Tichu — Detailed Game Rules

### Overview

Tichu is a partnership climbing/shedding card game for exactly **4 players** in
**2 teams of 2**. Teammates sit across from each other so that play alternates
between teams. The objective is to be the first to get rid of all your cards
while accumulating points. The first team to reach **1,000 points** wins.

### The Deck (56 cards)

| Cards | Count | Details |
|---|---|---|
| Suited cards | 52 | 4 suits (Jade, Sword, Pagoda, Star) × 13 ranks (2–Ace) |
| Mah Jong | 1 | Value 1. Leads the first trick. Allows making a wish. |
| Dog | 1 | No numeric value. Passes the lead to your partner. |
| Phoenix | 1 | Wild card. Worth −25 points. |
| Dragon | 1 | Strongest single card (value 25). Worth +25 points. |

### Dealing & Pre-Game

1. **First deal**: Each player receives **8 cards**.

2. **Grand Tichu**: A player may call **Grand Tichu** up until they pick up
  their **9th card** — a **±200 point** bet that they will be the first player
  to go out.

3. **Second deal**: The remaining **6 cards** are dealt (all players now hold
  **14 cards**). After a player has picked up their 9th card, Grand Tichu can
  no longer be declared.

4. **Tichu**: At any time before playing their first card of the round, a player
  may call **Tichu** — a **±100 point** bet that they will go out first.

5. **Schupfen (card exchange)**: After everyone has **14 cards**, each player
  simultaneously passes **one card face-down** to each of the other three
  players (one to the left opponent, one to the partner, one to the right
  opponent). The recipient knows exactly who sent which card and should see
  the received cards in fixed left/partner/right slots. Tichu/Grand Tichu
  timing is independent of this exchange.

### Card Combinations (Playable Turns)

| Combination | Description | Example |
|---|---|---|
| **Single** | Any single card | 7 |
| **Pair** | Two cards of the same rank | 7-7 |
| **Triplet** | Three cards of the same rank | 7-7-7 |
| **Pair Straight (Stairs)** | Two or more consecutive pairs | 5-5-6-6-7-7 |
| **Straight** | Five or more consecutive cards (any suits) | 5-6-7-8-9 |
| **Full House** | Triplet + Pair | 7-7-7-Q-Q |
| **Bomb (4-of-a-kind)** | Four cards of the same rank | 8-8-8-8 |
| **Bomb (straight flush)** | Five or more consecutive cards of the **same suit** | ♦9-♦10-♦J-♦Q-♦K |

### Trick Play

- The player with the **Mah Jong** leads the first trick of the round.
- On your turn you must either **beat the current top combination** with a
  higher combination of the **same type and length**, or **pass**.
- Passing does not prevent you from playing later in the same trick (you can
  "check" back in).
- A trick ends when **three consecutive players pass** — the last player who
  played wins the trick, collects the cards, and leads the next trick.
- **Bombs** are the only exception: a bomb can be played on **any** combination
  type (not just the same type), and can be played **out of turn**. A bomb can
  only be beaten by a higher bomb. After a bomb, every player gets a chance to
  play a bigger bomb before the trick is taken.
- Bomb ranking: 4-of-a-kind < higher 4-of-a-kind < 5-card straight flush <
  longer straight flush.

### Special Cards — Detailed Rules

#### Mah Jong (value 1)
- The holder leads the opening trick but is **not required** to play the Mah
  Jong in that trick.
- Can be played as a single **1** or as part of a straight starting from 1
  (e.g., MJ-2-3-4-5).
- When played, the player **may make a Wish** — requesting any card rank from 2
  through Ace.
- The wish **remains active** until it is fulfilled. Every subsequent player who
  holds the wished card **must play it** if they can legally do so (even if it
  means playing a bomb).
- If a straight is led and the wish can only be satisfied by constructing a
  straight using the Phoenix as a wild card, the player must do so.

#### Dog (no value)
- Cannot be played within a trick — it must be played as a **lead card**
  (starting a new trick).
- Immediately **passes the lead to your partner**.
- If your partner has already gone out, play passes to the next active player
  after your partner's seat.
- The Dog **cannot be bombed**.

#### Phoenix (value −25 points)
- **As a single**: Played as **0.5 higher** than the previous single card (e.g.,
  after an Ace, Phoenix = Ace + 0.5). When led, its value is **1.5**.
- **In a combination**: Acts as a **wild card** with any rank from 2 through
  Ace. Can substitute for any missing card in a straight, pair straight, or full
  house.
- **Cannot** be used as a wild card in a bomb.
- The Phoenix's declared value in a straight does **not** satisfy the Mah Jong
  wish.
- Cannot beat the Dragon as a single (Dragon is the highest single card).

#### Dragon (value 25 points)
- The **strongest single card** in the game. Can only be played in a single-card
  trick.
- If the Dragon wins the trick, the **entire trick must be given to an
  opponent** (you choose which one).
- The Dragon **can be bombed**. If bombed, the player who played the largest
  bomb takes the trick (including the Dragon).

### End of Round

- The round continues until three players have emptied their hands. The last
  player still holding cards:
  - Gives their **remaining hand cards** to the **opposing team**.
  - Gives all **tricks they won** this round to the **player who went out
    first**.

### Scoring

#### Card Points (per round, 100 points total in the deck)
| Card    | Points |
|---------|--------|
| 5s      | 5      |
| 10s     | 10     |
| Kings   | 10     |
| Dragon  | 25     |
| Phoenix | −25    |
| Others  | 0      |

#### Bonus Scoring

| Event | Points |
|---|---|
| **Tichu** called and succeeded | +100 to the calling team |
| **Tichu** called and failed | −100 to the calling team |
| **Grand Tichu** called and succeeded | +200 to the calling team |
| **Grand Tichu** called and failed | −200 to the calling team |
| **1-2 finish** (both teammates out before either opponent) | +200 to the winning team (no card scoring this round) |

Tichu/Grand Tichu bonuses and penalties are always applied, even during a 1-2 finish.

### Winning the Game

Rounds continue until one team reaches **1,000 points or more**. That team wins.
