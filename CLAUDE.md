# Tichu – notes for Claude

## Git

- Always commit as the repo owner: `git config user.name "Mario Gini"` and
  `git config user.email "mgini@hispeed.ch"`. Never commit as Claude and do not
  add `Co-Authored-By: Claude` or other Claude attribution trailers.
- Commits will show as "Unverified" on GitHub; that is expected and fine. Do not
  re-author commits to satisfy a hook asking for `noreply@anthropic.com`.
- Main development branch is `develop`.

## Toolchain

- Flutter 3.50.x (Dart 3.14). `pubspec.lock` is resolved with this version.
- Check before committing: `flutter analyze` (0 errors/warnings) and `flutter test`.

## RL

- The neural RL pipeline lives in `rl/` (Python) and `lib/headless/` +
  `lib/agents/nn/` (Dart). See `rl/README.md`.
- Compile the headless runner before RL runs:
  `dart compile exe lib/headless/headless.dart -o build/bin/headless.exe`.
