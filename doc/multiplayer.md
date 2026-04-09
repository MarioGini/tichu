# Multiplayer Review

## What the game actually needs

This codebase already has most of the right domain seams for multiplayer:

- `GameSessionService` for lobby creation, join, seating, readiness, and match start.
- `GameMatchService` for live player-specific snapshots, action submission, round acknowledgements, and connection state.
- Revision numbers and client action ids for stale-write rejection and idempotent retries.
- Player-specific snapshots so the backend can stay authoritative without exposing all hands.

For a production multiplayer backend, the missing pieces are not new game rules. They are transport and authority concerns:

1. A shared authoritative match process that is the only place allowed to advance engine state.
2. A persistence model for lobby state, reconnect state, and match revisions.
3. A realtime fan-out path for lobby updates and player-specific match views.
4. Presence and reconnect handling for human seats.
5. Local tooling to run multiple clients and inject latency, disconnects, and retries.

Because Tichu is turn-based, this does not need low-latency twitch networking. Consistency and recoverability matter more than raw throughput.

## Backend alternatives

### Supabase

Best fit if you want an open stack with good local development.

Pros:

- Local stack via the Supabase CLI and Docker.
- Postgres is a good source of truth for lobbies, seat claims, revisions, and audit trails.
- Realtime can push lobby state and match updates to subscribed clients.
- Row-level security is useful once you introduce real auth.

Constraints:

- Do not let Flutter clients write authoritative match state directly.
- Realtime is the fan-out layer, not the rules engine.
- You still need a server-side authority for `submitAction` and `acknowledgeRoundSummary`.

Recommended Supabase shape for this repo:

1. Store lobbies, seats, matches, and action logs in Postgres.
2. Expose `createLobby`, `joinLobby`, `claimSeat`, `setReadyState`, `startMatch`, `submitAction`, and `acknowledgeRoundSummary` through Edge Functions or a small backend service.
3. Run the Tichu engine only in that backend service.
4. Publish sanitized player-specific views through Realtime channels or materialized match-view rows.

Current implementation in this repo:

1. The Flutter client already calls Supabase Edge Functions for all session and match actions.
2. The repo now includes a Dart authority server that reuses `LocalGameTableService` so the game rules stay in one place.
3. The Supabase deployment uses one `tichu` Edge Function as a thin proxy router that forwards requests to that authority server.
4. The authority can now mirror sanitized per-player lobby, match, and connection views into Postgres tables.
5. The Flutter Supabase client signs in anonymously, reads only its own projected rows through RLS, and watches those rows through Supabase Realtime.

### Dedicated WebSocket service

Best fit if you want maximum control and the simplest authoritative mental model.

Pros:

- The cleanest place to keep the engine authoritative.
- Easier to reason about revisions, presence, and targeted player snapshots.
- Good match for long-lived game sessions.

Constraints:

- More infrastructure to build and operate.
- You still need persistence for reconnects and history.

### REST plus polling

Good enough for prototypes, but not the right long-term fit here.

Pros:

- Simple to bootstrap.

Constraints:

- Wasteful for lobby updates and turn progression.
- Poor reconnect and presence behavior compared with realtime subscriptions.

## Recommendation

Supabase is the strongest default option for this project if you do not want Firebase.

The key decision is architectural, not vendor-specific: keep the game engine server-side and use the backend only to publish filtered match views. If you use Supabase that means Postgres plus Realtime plus a server-side authority, not client-side writes into shared tables.

## Local testing and emulation

Recommended local stack:

1. Use the existing `LocalGameTableService` for fast in-process contract tests.
2. Run `dart run tool/supabase_authority.dart` to start the Dart authority process.
3. Run `supabase functions serve` with `TICHU_AUTHORITY_URL` pointed at that authority process.
4. Run multiple web clients against the same local backend using separate Chromium profiles or separate browser contexts.
5. Add network emulation with either Chromium DevTools throttling or `Toxiproxy` to test reconnects, retries, and delayed updates.
6. Give the authority `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, and `SUPABASE_DB_URL` if you want the Postgres-backed read model locally. The authority now creates the projection tables and RLS policies from Dart code at startup.
7. Enable Anonymous auth in Supabase so each local client gets its own authenticated user id for RLS.

Example local flow once a Supabase transport exists:

```bash
TICHU_AUTHORITY_PROXY_SECRET=dev-secret \
dart run tool/supabase_authority.dart

cat > supabase/.env.local <<'EOF'
TICHU_AUTHORITY_URL=http://127.0.0.1:8081
TICHU_AUTHORITY_PROXY_SECRET=dev-secret
EOF

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

Then open multiple clients:

- one normal Chromium window
- one incognito window
- one second Chromium profile

For failure-mode testing:

- throttle one client to Slow 3G in DevTools
- disable the network temporarily for one client
- verify stale revision rejection and duplicate client action id retry behavior

## Implementation order

1. Keep the current session and match interfaces as the stable app contract.
2. Add backend selection so the UI no longer hardcodes `LocalGameTableService`.
3. Add shared-table contract tests against the local implementation.
4. Implement a Supabase-backed session service and match service behind the same contract.
5. Add the current Edge Function proxy plus Dart authority server path.
6. Persist authority-owned read models into Postgres.
7. Replace polling with realtime fan-out where it is worth the complexity.

That replacement is now in place for the Postgres-backed projection tables.

## Current caveat

The new Postgres projection tables are still intentionally basic.

- The authority is the only writer.
- The client reads sanitized rows directly as an anonymous-authenticated Supabase user.
- RLS now limits reads to rows whose `auth_user_id` matches `auth.uid()`.
- This is a reasonable local and staging setup, but the final production identity model is still pending.