# Multiplayer Setup

## Architecture

```
Flutter Client (anonymous auth)
  │
  ├─ Mutations → Supabase Edge Function (tichu)
  │                 │
  │                 └─ proxy.ts → Dart Authority Server
  │                                  │
  │                                  ├─ LocalGameTableService (game engine)
  │                                  ├─ Heartbeat sweep (30s timeout)
  │                                  └─ SupabaseTableProjectionStore → Postgres
  │
  └─ Reads → Supabase Realtime subscriptions
               (RLS: auth.uid() = auth_user_id)
```

All game logic runs in the authority server. Clients never write game state directly. The Edge Function is an action-agnostic proxy that extracts the authenticated user ID from the JWT and forwards requests.

## What's implemented

- **Lobby lifecycle**: create, join (random 5-digit codes), team-based seat preference, manual seat claim, readiness, bot fill, match start.
- **Live match**: player-specific snapshots, idempotent action submission, stale-revision rejection, round acknowledgement gating.
- **Heartbeat presence**: clients send heartbeats every 15 seconds. The authority sweeps every 10 seconds with a 30-second timeout. Disconnected players are marked offline; heartbeat reconnects them.
- **Authority durability**: lobby metadata and action logs are persisted to Postgres (`tichu_authority_lobbies`, `tichu_authority_actions`) so pre-match lobbies survive restarts.
- **Realtime fan-out**: per-player projected views in Postgres (`tichu_lobby_views`, `tichu_match_player_views`, `tichu_match_connection_views`) with RLS. Flutter subscribes via Supabase Realtime.
- **Backend selection**: compile-time `TICHU_BACKEND` flag switches between `local` (in-process, default) and `supabase`.
- **Solo play**: "Play Solo" button on the home screen creates a lobby, fills bots, starts the match, and navigates directly to the game — no lobby screen.

## Prerequisites

- [Dart SDK](https://dart.dev/get-dart) (3.x)
- [Flutter SDK](https://docs.flutter.dev/get-started/install)
- [Supabase CLI](https://supabase.com/docs/guides/cli) (`npm i -g supabase`)
- [Docker](https://docs.docker.com/get-docker/) (for `supabase start`)

## Local multiplayer setup

### 1. Start the local Supabase stack

```bash
supabase start
```

Note the `API URL`, `anon key`, `service_role key`, and `DB URL` from the output.

### 2. Enable anonymous auth

In `supabase/config.toml`, ensure:

```toml
[auth]
enable_anonymous_sign_ins = true
```

Then restart: `supabase stop && supabase start`.

### 3. Create the environment file for the Edge Function

```bash
cat > supabase/.env.local <<'EOF'
TICHU_AUTHORITY_URL=http://host.docker.internal:8081
TICHU_AUTHORITY_PROXY_SECRET=dev-secret
EOF
```

On Linux, use `http://172.17.0.1:8081` instead of `host.docker.internal`.

### 4. Start the authority server

Without Postgres projection (simpler, lobby state is in-memory only):

```bash
TICHU_AUTHORITY_PROXY_SECRET=dev-secret \
  dart run tool/supabase_authority.dart
```

With Postgres projection and durable lobby state (recommended):

```bash
TICHU_AUTHORITY_PROXY_SECRET=dev-secret \
SUPABASE_URL=http://127.0.0.1:54321 \
SUPABASE_SERVICE_ROLE_KEY=<service-role-key> \
SUPABASE_DB_URL=postgresql://postgres:postgres@127.0.0.1:54322/postgres?sslmode=disable \
  dart run tool/supabase_authority.dart
```

The authority bootstraps projection tables and RLS policies on startup.

### 5. Serve the Edge Function

```bash
supabase functions serve --env-file supabase/.env.local
```

### 6. Run the Flutter client

```bash
flutter run -d chrome \
  --dart-define=TICHU_BACKEND=supabase \
  --dart-define=SUPABASE_URL=http://127.0.0.1:54321 \
  --dart-define=SUPABASE_ANON_KEY=<anon-key>
```

### 7. Open a second client

Use an incognito window or a separate Chromium profile so each tab gets its own anonymous Supabase session. One player creates a lobby, shares the 5-digit code, and the other joins.

## Production deployment

The authority server needs a persistent host reachable by the Edge Function.

### Authority server

`tool/supabase_authority.dart` is a standalone Dart HTTP server. Deploy it wherever you can run a long-lived Dart process:

- **Cloud Run / Fly.io / Railway**: build with `dart compile exe tool/supabase_authority.dart -o authority` and deploy the binary.
- **Docker**: use the official `dart:stable` image.
- **VPS**: run directly with `dart run`.

Environment variables for the authority:

| Variable | Required | Description |
|----------|----------|-------------|
| `TICHU_AUTHORITY_PROXY_SECRET` | Yes | Shared secret the Edge Function sends in `x-tichu-proxy-secret` |
| `SUPABASE_URL` | For projections | Supabase project URL |
| `SUPABASE_SERVICE_ROLE_KEY` | For projections | Service role key (authority is the only writer) |
| `SUPABASE_DB_URL` | For projections + durability | Direct Postgres connection string |

### Supabase project

1. Create a project at [supabase.com](https://supabase.com) or self-host.
2. Enable anonymous auth in Authentication → Settings.
3. Deploy the Edge Function:

```bash
supabase functions deploy tichu
```

4. Set Edge Function secrets:

```bash
supabase secrets set \
  TICHU_AUTHORITY_URL=https://your-authority-host:8081 \
  TICHU_AUTHORITY_PROXY_SECRET=your-production-secret
```

### Flutter client

Build for web with the Supabase backend:

```bash
flutter build web \
  --dart-define=TICHU_BACKEND=supabase \
  --dart-define=SUPABASE_URL=https://your-project.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<anon-key>
```

Host the `build/web/` output on any static host (Supabase Storage, Vercel, Netlify, etc.).

## Testing

### In-process (no network)

```bash
flutter test test/services/
```

All contract tests run against `LocalGameTableService` with a static engine. This validates lobby lifecycle, seat assignment, heartbeat presence, stale revision rejection, action idempotency, round acknowledgement gating, and Postgres projection fan-out.

### Authority server over HTTP

```bash
flutter test test/services/supabase/supabase_authority_server_test.dart
```

Starts a real `HttpServer` on a random port and exercises the full create → seat → start → play → heartbeat path.

### Manual multi-client

Open two browser windows against the same Supabase stack (see steps 6–7 above). For failure-mode testing:

- Throttle one client to Slow 3G in DevTools.
- Disable the network for one client and observe the heartbeat timeout marking them offline.
- Verify stale-revision rejection by having both clients race to submit.

## Known limitations

- **No crash recovery for active matches.** Lobby metadata is persisted, but `GameEngineState` is not serializable. If the authority restarts mid-match, that match is lost. An action-replay recovery path (replay the action log from `tichu_authority_actions`) would require engine state serialization.
- **No lobby expiry.** Abandoned lobbies stay in memory and Postgres until the authority restarts. A TTL sweep would fix this.
- **Anonymous auth only.** There are no real user accounts. Each browser session is a separate anonymous identity. The projection RLS is sound but tied to ephemeral UUIDs.
- **Single-process authority.** No horizontal scaling or failover. Fine for small-scale play.