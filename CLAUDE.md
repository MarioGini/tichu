# Tichu – notes for Claude

## Working with Mario

- Send a push notification whenever you need input (a decision, approval,
  or you are blocked) and when a longer task finishes. Mario is often away
  from the session.

## Git

- Always commit as the repo owner: `git config user.name "Mario Gini"` and
  `git config user.email "mgini@hispeed.ch"`. Never commit as Claude and do not
  add `Co-Authored-By: Claude` or other Claude attribution trailers.
- Commits will show as "Unverified" on GitHub; that is expected and fine. Do not
  re-author commits to satisfy a hook asking for `noreply@anthropic.com`.
- Main development branch is `develop`.
- PR-based development: never push to `develop` directly. Work on a feature
  branch and open a PR into `develop` only once the work is a clear step up,
  roughly a 10-20 % improvement (for bots: the new bot wins 60-70 % of
  duplicate matches against the shipped one). Smaller steps stay on the
  branch until they add up.

## Toolchain

- Flutter 3.50.x (Dart 3.14). `pubspec.lock` is resolved with this version.
- Check before committing: `flutter analyze` (0 errors/warnings) and `flutter test`.
- Never silence lints: no `// ignore:` / `// ignore_for_file:` in Dart, no
  `# noqa` / `# type: ignore` / `# pylint: disable` in Python, no rules set to
  `ignore` in `analysis_options.yaml`. A lint that fires points at code to
  change: fix the design (e.g. throw a typed `Exception` instead of catching
  `StateError`, inject a dependency instead of a write-only setter). If a
  rule is wrong for the whole project, propose turning it off in
  `analysis_options.yaml` and say why. `test/no_lint_suppressions_test.dart`
  enforces this.

## Architecture rules

- Simulations (endgame search, solver, rollouts, training labels) play out
  forks on `simulationEngine` (`lib/game/simulation.dart`), never on the
  engine of the game being played, which may record or publish moves.
- Expected failures are typed exceptions: `IllegalActionException` (engine:
  move not allowed), `NoLegalActionException` (agent has no move),
  `RequestRejectedException` (lobby/match request refused). `Error`s are
  bugs and are never caught.

## RL

- The neural RL pipeline lives in `rl/` (Python) and `lib/headless/` +
  `lib/agents/nn/` (Dart). See `rl/README.md`.
- Compile the headless runner before RL runs:
  `dart compile exe lib/headless/headless.dart -o build/bin/headless`
  (`rl/headless_runner.py` looks for exactly `build/bin/headless`).
