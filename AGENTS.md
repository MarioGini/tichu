# Project Guidelines

## Code Style
- Language: Dart/Flutter, snake_case filenames.
- Lint baseline: `analysis_options.yaml` includes `flutter_lints`; `public_member_api_docs` is disabled.
- Keep edits minimal and local to the owning layer. Follow existing naming and file layout before introducing new folders.
- Prefer `dart format .` (CI uses this), then `flutter analyze --fatal-infos --fatal-warnings`.

## Architecture
- App entry and theme wiring: `lib/main.dart`.
- UI composition/state: `lib/screens/` and reusable widgets in `lib/widgets/`.
  - Main game orchestration lives in `lib/screens/game/game_screen.dart` (split with `part` files).
- Game domain rules: `lib/game/` (`turn/`, `scoring/`, `schupfen/`).
  - Engine contract: `lib/game/engine.dart`.
- Driver → UI projection seam: `lib/game/driver_ui_projector.dart`.
  - `DriverUiProjector` maps backend/player-driver state (`PlayerSnapshot`) into UI-ready state.
  - This is the single place where manual-vs-AI driver differences are normalized for rendering.
- Player behavior: `lib/agents/` (`ai/`, `opponents/`).
- Integration boundaries: `lib/services/`.
  - Backend API contract: `lib/game/game_backend.dart`.
  - Local runtime backend implementation: `lib/services/local/local_backend.dart`.

## Driver/UI Explainer
- Principle: UI is a projection of driver state, not a second source of truth.
- Manual mode flow: UI emits user intents (tap/select/schupf/play) → backend/driver applies action → UI re-renders from snapshot.
- AI mode flow: AI emits intents through the same backend/driver action path → UI re-renders from snapshot.
- Phase boundaries are strict:
  - Play-phase pending previews are rendered only in `GamePhase.play`.
  - Schupf-phase previews/slots are rendered only in `GamePhase.schupf`.
- Avoid reusing one pending channel for multiple phase semantics without explicit phase gating.

## Build and Test
- Install deps: `flutter pub get`
- Run app (Linux): `flutter run -d linux`
- Run app (Web): `flutter run -d chrome`
- Analyze: `flutter analyze --fatal-infos --fatal-warnings`
- Tests: `flutter test`
- Coverage: `flutter test --coverage`
- Global coverage workflow (preferred): run all tests once in coverage mode,
  then inspect `coverage/lcov.info` for whole-repo and per-file metrics.
  Avoid repeatedly re-running coverage for single files unless diagnosing a
  specific gap.
- Format check/fix: `dart format .`
- Headless AI simulation: `dart run lib/headless/headless.dart --seed=42 --target-score=1000`

## Project Conventions
- Treat `GameBackend` as the seam between UI and runtime state updates (`watchGame`, `submitAction`, etc.).
- Keep rules and turn-resolution logic in `lib/game/turn/**`, not in screen widgets.
- Keep mode-specific UI behavior out of screen conditionals where possible; encode it in `DriverUiProjector` and consume the projected state in the screen.
- If adding new pending/preview visuals, define phase ownership explicitly to prevent cross-phase leakage.
- `test/` mirrors `lib/`; add tests in the corresponding mirrored folder.
  - Examples: `test/game/turn/tichu_rules_test.dart`, `test/screens/game/*`, `test/headless/headless_test.dart`.
- For screen tests, use fakes from `test/utils/` (e.g., `test/utils/test_game_backend.dart`) instead of real backends.

## Integration Points
- Audio uses `audioplayers` via `lib/services/sound_effects.dart`.
- Firebase packages are declared in `pubspec.yaml`, but current gameplay flow is local-first and uses `LocalGameBackend`.
- Headless mode (`lib/headless/headless.dart`) drives AI-vs-AI via backend streams and writes CSV output.

## Security
- No auth boundary is currently enforced in local mode; backend checks are validity/state checks.
- Headless mode writes to caller-provided output paths; avoid untrusted paths when scripting.
- Local game IDs are timestamp-derived and suitable for local simulation, not as secure identifiers.

## Learnings
- When the user says `LEARN!`, update this section with the new persistent project guidance from that request.
- User preference: act proactively and continue with likely/adjacent fixes without waiting for explicit confirmation at each step; only pause when requirements are ambiguous or risky.
- Current debug UI purpose: evaluate (a) clean implementation separation between player interface and its driver, and (b) whether AI behavior is smart in practice.
- Architectural goal: keep a strict separation between the player-facing interface and who drives it, so the same interface can be driven by:
  - a) manual user input (self)
  - b) AI agent
  - c) remote multiplayer player
- Keep opponent integration generic via an opponent implementation interface that can be driven by:
  - a) AI opponents
  - b) real multiplayer opponents
- Current delivery focus is case a) AI-driven opponents, while preserving compatibility for future case b).
- User preference: every implementation file should have an equivalent mirrored unit test file in `test/`.
- User preference: target 100% test coverage, especially for AI strategy/policy behavior against `lib/agents/ai_strategy.md`.
- User preference: use `uv` to run Python commands/scripts.
- User command: `CI!` means run the full local CI gate: `dart format --output=none --set-exit-if-changed .`, `flutter analyze --fatal-infos --fatal-warnings`, `dart fix --dry-run`, `flutter test`
