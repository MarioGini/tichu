# Tichu

Multiplayer Tichu card game built with Flutter.

## Supported targets
- Linux desktop
- Web

## Prerequisites
- Flutter SDK (stable channel)
- A working C++ toolchain
- Linux build deps: GTK 3 and Ninja
- A Chromium-based browser for web runs

Linux deps (Ubuntu/Debian):
```
sudo apt-get update -y
sudo apt-get install -y ninja-build libgtk-3-dev \
	libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev \
	lld
```

## Run (end user)
First time only, enable the required platforms:
```
flutter config --enable-linux-desktop --enable-web
```

Get dependencies:
```
flutter pub get
```

Run on Linux:
```
flutter run -d linux
```

Run on Web (Chrome):
```
flutter run -d chrome
```

Run on Web (local web server):
```
flutter run -d web-server --web-port 8080
```

## Build
Linux desktop bundle:
```
flutter build linux
```

Web release bundle:
```
flutter build web
```

## Common tasks
Format code:
```
flutter format --output=none --set-exit-if-changed .
```

Analyze:
```
flutter analyze --fatal-infos --fatal-warnings
```

Run tests:
```
flutter test
```

Global coverage report (single run for all files):
```
flutter test --coverage
```

Coverage output is written to `coverage/lcov.info`.

Quick inspect examples:
```
# overall line coverage
lcov --summary coverage/lcov.info

# inspect one file (example)
lcov --list coverage/lcov.info | grep "lib/agents/wish_strategy.dart"

# python summary helper (overall + top files)
uv run python coverage/parse_lcov.py --top 30

# focus only on game/scoring files and show uncovered line numbers
uv run python coverage/parse_lcov.py --include lib/game --include scoring --show-uncovered
```

Clean build outputs:
```
flutter clean
```

## Headless AI mode
Run an AI-vs-AI match without UI and emit CSV for analysis:
```
dart run lib/headless/headless.dart --seed=42 --target-score=1000
```

By default, the CSV is written to game.csv with a header and one row per event.
Use --output=path.csv to change the output file.

## Rules explainer (scoring)
- Card points across both teams sum to 100 each round.
- Tichu/grand-tichu bonuses are applied in steps of ±100/±200.
- Double-win rounds are scored as 200:0 before bonuses.
- Therefore, the combined round score (`team_one_round + team_two_round`) is always divisible by 100.
