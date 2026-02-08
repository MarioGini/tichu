# Agent Guide — Tichu

## Overview

Single-player **Tichu** built in **Flutter (Dart)** with 3 AI opponents and a
fully local game engine. Online multiplayer hooks exist as stubs only.

## Folder Structure Philosophy

We keep a highly structured, logical folder layout so each layer of the app has
an obvious home:

- **Separation by responsibility**: UI, domain logic, and services are split
  cleanly so changes are easy to scope.
- **Mirrored test structure**: `test/` mirrors `lib/` for fast navigation.
- **Stable paths**: core domain folders rarely move, keeping imports stable and
  change diffs focused.

When adding new code, place it in the most specific existing subfolder. Create
a new folder only if there is no clear home and the new category is durable.

## Key Paths

- `lib/main.dart` — app entry point
- `lib/screens/` — UI screens and parts
- `lib/widgets/` — reusable UI components
- `lib/services/` — backend interfaces, local backend, sound
- `lib/view_model/` — game logic, AI, scoring, turn rules, utils
- `test/` — tests mirroring `lib/`

## Conventions

- Dart filenames use snake_case.
- Core game logic lives in `lib/view_model/` (pure logic; no side effects).
- I/O lives in `lib/services/`.
- UI state is in `lib/screens/` and `lib/widgets/`.

## Tooling Expectations

- Formatting: use `dart format .` for batch formatting (avoid `dart_format` tool
  in batch mode).
- Larger tasks: always run `dart format .`, a lint pass (analyze), and unit
  tests via terminal when finishing bigger changes, without waiting to be asked.

## Common Commands

```bash
flutter pub get
flutter run -d linux
flutter test
```
