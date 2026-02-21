# Project Guidelines

## Command Keywords (Priority)
- `LEARN!`
  - Review recent request + edits + tool output + failures.
  - Identify what happened, what failed, and root cause.
  - Add one concise, actionable, durable rule to `## Learnings`.
  - If needed, improve `doc/**` (relevant mirrored folder docs + summaries) so agents retain high-quality context and avoid context loss in future tasks.
- `CI!`
  - Run in order: `dart format --output=none --set-exit-if-changed .` -> `flutter analyze --fatal-infos --fatal-warnings` -> `dart fix --apply` -> `flutter test`.
  - If any step fails, fix it and rerun from step 1.
  - Keep `doc/**` in sync for affected areas before reporting green CI.

## Mission and Scope
- Stack: Flutter/Dart only; snake_case filenames.
- Keep edits minimal, local, and layer-correct.
- Do not move rules into UI; do not duplicate state across layers.

## Documentation Map
- Start at `doc/README.md`.
- For implementation lookup, traverse `doc/lib/**/README.md` to mirror `lib/**`.
- Each folder doc lists implemented files and links to child-folder docs.
- Do not read all docs recursively; open only the branch relevant to the current task.
- Expand to additional branches only when the first branch does not answer the question.

## Architecture (High-Signal Map)
- Entry/theme wiring: `lib/main.dart`.
- UI orchestration: `lib/screens/game/game_screen.dart` (+ part files).
- Reusable UI: `lib/widgets/`.
- Domain/rules engine: `lib/game/turn/**`, `lib/game/scoring/**`, `lib/game/schupfen/**`.
- Engine contract: `lib/game/engine.dart`.
- UI projection seam: `lib/game/driver_ui_projector.dart`.
- Runtime boundary: `lib/game/game_backend.dart`.
- Local backend impl: `lib/services/local/local_backend.dart`.
- AI behavior/policy: `lib/agents/**`.

## Core Invariants
- UI is a projection of driver/backend state, never a second source of truth.
- Human and AI must flow through the same action path (`submitAction` → engine → snapshot).
- `DriverUiProjector` is the normalization seam for manual-vs-AI presentation differences.
- Phase ownership is strict:
  - Play pending visuals only in `GamePhase.play`.
  - Schupf previews/slots only in `GamePhase.schupf`.
- Do not reuse one pending channel for different phase semantics without explicit gating.

## Implementation Rules
- Keep mode-specific behavior out of screen conditionals when it can live in projector/policy.
- Keep turn/scoring legality in `lib/game/turn/**`, not widgets.
- Respect existing naming/layout before introducing new folders or abstractions.
- For screen tests, prefer `test/utils/test_game_backend.dart` fakes over real backends.

## Testing and Quality
- Mirror `lib/` structure under `test/` for new coverage.

## Operations Quick Reference
- Install deps: `flutter pub get`
- Run app (Linux): `flutter run -d linux`
- Run app (Web): `flutter run -d chrome`
- Headless simulation: `dart run lib/headless/headless.dart --seed=42 --target-score=1000`

## Learnings
- Never pipe `flutter test` or build commands through `Select-Object`, `Out-String`, or other filters. Run them bare so the user sees streaming output in real time.
- Tests run in parallel via `dart_test.yaml` (`concurrency: 8`). Always use `flutter test` (no extra flags needed) — the config file handles parallelism.
- When splitting a class, never duplicate object creation in an initializer list (e.g. `engine ?? Impl()` repeated for two fields). Assign once, then pass the reference to avoid hidden duplicate instances.

## Integration and Security Notes
- Audio path: `lib/services/sound_effects.dart` (`audioplayers`).
- Firebase deps exist; gameplay is currently local-first via `LocalGameBackend`.
- Local IDs are timestamp-derived (not secure identifiers).
- Headless output paths are caller-provided; avoid untrusted paths.
