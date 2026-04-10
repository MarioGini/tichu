# Tichu

Multiplayer Tichu card game built with Flutter.

See [doc/multiplayer.md](doc/multiplayer.md) for the current multiplayer review,
backend alternatives, and local emulation plan.

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

Use the Supabase backend instead of the local in-process table service:
```
flutter run -d chrome \
	--dart-define=TICHU_BACKEND=supabase \
	--dart-define=SUPABASE_URL=https://your-project.supabase.co \
	--dart-define=SUPABASE_ANON_KEY=your-anon-key
```

Current Supabase server shape:
- Supabase Edge Functions act as the public API entrypoints the Flutter app calls.
- A Dart authority process runs the actual Tichu engine and lobby state.
- The Edge Functions proxy each action to that authority process.

Run the local authority process:
```
dart run tool/supabase_authority.dart --host 127.0.0.1 --port 8081
```

Required Supabase Function environment:
- `TICHU_AUTHORITY_URL`, for example `http://127.0.0.1:8081`
- optional `TICHU_AUTHORITY_PROXY_SECRET`

Optional authority projection environment:
- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`
- `SUPABASE_DB_URL`

When those three variables are set for the authority process, it first
bootstraps the projection tables, grants, and RLS in Postgres from Dart code,
then mirrors
sanitized per-player lobby, match, and connection views into Supabase Postgres.
The Flutter Supabase client now signs in anonymously, reads only its own
projection rows through RLS, and watches those rows through Supabase Realtime.

If you configure a proxy secret for the Edge Functions, pass the same value to
the authority process:
```
TICHU_AUTHORITY_PROXY_SECRET=dev-secret \
dart run tool/supabase_authority.dart
```

Use a direct Postgres URL for the bootstrap step:
- local Supabase example: `postgresql://postgres:postgres@127.0.0.1:54322/postgres?sslmode=disable`
- hosted Supabase: use the project's direct Postgres connection string, ideally with `sslmode=verify-full`

Optional Supabase transport tuning:
- `TICHU_SUPABASE_FUNCTION_NAME` defaults to `tichu`
- `TICHU_SUPABASE_FUNCTION_PREFIX` is still accepted as a legacy alias

Supabase auth requirement:
- Enable Anonymous sign-ins in your Supabase Auth settings.
- Projection table reads now require an authenticated Supabase user, even in local development.

The home screen now opens into a create/join lobby flow. Create a lobby to get a
join code, or open another client and join the same lobby code from there.

For local Supabase development, serve the Edge Functions and the authority in
parallel, then point Flutter at your local Supabase project:
```
supabase functions serve --env-file supabase/.env.local
SUPABASE_URL=http://127.0.0.1:54321 \
SUPABASE_SERVICE_ROLE_KEY=your-local-service-role-key \
SUPABASE_DB_URL=postgresql://postgres:postgres@127.0.0.1:54322/postgres?sslmode=disable \
dart run tool/supabase_authority.dart
flutter run -d chrome \
	--dart-define=TICHU_BACKEND=supabase \
	--dart-define=SUPABASE_URL=http://127.0.0.1:54321 \
	--dart-define=SUPABASE_ANON_KEY=your-local-anon-key
```

Current limitation:
- The current security model is row-scoped to the signed-in Supabase user via RLS.
- That is enough for local multiplayer development, but it is still anonymous-auth based and not the final production identity model.

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

Run bounded rounds (useful for repeatable stress tests and fast samples):
```
dart run lib/headless/headless.dart --seed=42 --target-score=100000 --rounds=50
```

For RL training, evaluation, and RL-specific headless usage, see `rl/README.md`.

Useful headless options:
- `--episodes=N`: run multiple self-play episodes in one invocation.
- `--rounds=N`: cap each episode to N completed rounds.
- `--max-steps=N`: safety cap to prevent accidental infinite episodes.
- `--format=csv|none`: choose event CSV or no file output.
- `--no-timestamps`: disable wall-clock timestamps in CSV rows.

## Rules explainer (scoring)
- Card points across both teams sum to 100 each round.
- Tichu/grand-tichu bonuses are applied in steps of ±100/±200.
- Double-win rounds are scored as 200:0 before bonuses.
- Therefore, the combined round score (`team_one_round + team_two_round`) is always divisible by 100.
