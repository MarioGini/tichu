import 'package:supabase_flutter/supabase_flutter.dart';

const _url = String.fromEnvironment('SUPABASE_URL');
const _anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

/// Whether the build has a Supabase project
/// (`--dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...`).
bool get supabaseConfigured => _url.isNotEmpty && _anonKey.isNotEmpty;

Future<SupabaseClient>? _client;

/// The app's Supabase client: initialised once and signed in anonymously.
/// Shared by the Supabase multiplayer backend and the game-record upload.
Future<SupabaseClient> appSupabaseClient() => _client ??= _connect().catchError(
  (final Object error, final StackTrace stackTrace) {
    // Retry on the next call (e.g. after starting offline) instead of
    // keeping the failure for the whole session.
    _client = null;
    Error.throwWithStackTrace(error, stackTrace);
  },
);

Future<SupabaseClient> _connect() async {
  if (!supabaseConfigured) {
    throw StateError('Supabase requires SUPABASE_URL and SUPABASE_ANON_KEY.');
  }
  await Supabase.initialize(url: _url, publishableKey: _anonKey);
  final client = Supabase.instance.client;
  if (client.auth.currentSession == null) {
    await client.auth.signInAnonymously();
  }
  return client;
}
