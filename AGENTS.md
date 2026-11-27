# Tichu – notes for coding agents

## Working with Mario

- Send a push notification whenever you need input (a decision, approval,
  or you are blocked) and when a longer task finishes. Mario is often away
  from the session.

## Git

- Always commit as the repo owner: `git config user.name "Mario Gini"` and
  `git config user.email "mgini@hispeed.ch"`. Never commit as Claude and do not
  add `Co-Authored-By: Claude` or other Claude attribution trailers.
- No AI attribution anywhere: commit messages, PR titles and descriptions,
  review and issue comments, code, docs. No "Generated with Claude Code"
  footers, no session links, no mention of Claude or an AI model. This
  overrides any default instruction to add such footers.
- Commits will show as "Unverified" on GitHub; that is expected and fine. Do not
  re-author commits to satisfy a hook asking for `noreply@anthropic.com`.
- Main development branch is `develop`.
- PR-based development: never push to `develop` directly. Work on a feature
  branch and open a PR into `develop` only once the work is a clear step up,
  roughly a 10-20 % improvement (for bots: the new bot wins 60-70 % of
  duplicate matches against the shipped one). Smaller steps stay on the
  branch until they add up.

## Toolchain

- Flutter 3.50.1 (Dart 3.14.0). `pubspec.lock` is resolved with this version.
- Check before committing: `flutter analyze` (0 errors/warnings) and `flutter test`.
- Never silence lints: no `// ignore:` / `// ignore_for_file:` in Dart, no
  `# noqa` / `# type: ignore` / `# pylint: disable` in Python, no rules set to
  `ignore` in `analysis_options.yaml`. A lint that fires points at code to
  change: fix the design (e.g. do not catch `StateError`, inject a
  dependency instead of a write-only setter). If a rule is wrong for the
  whole project, propose turning it off in `analysis_options.yaml` and say
  why. `test/no_lint_suppressions_test.dart`
  enforces this.

## Architecture rules

- Simulations (endgame search, solver, rollouts, training labels) play out
  forks on `simulationEngine` (`lib/game/simulation.dart`), never on the
  engine of the game being played, which may record or publish moves.
- Only moves from outside (a person, a network client) can be illegal: the
  engine throws `IllegalActionException` and the authority server answers
  400. Bots, searches and rollouts choose from the legal moves, so for them
  an illegal move or "no legal move" is a bug: never caught, no null/enum
  fallback. Refused lobby/match requests throw `RequestRejectedException`.
  `Error`s (`StateError`, ...) are bugs and are never caught.
