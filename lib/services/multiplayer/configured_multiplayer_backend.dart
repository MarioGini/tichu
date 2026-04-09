import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tichu/services/multiplayer/multiplayer_backend.dart';
import 'package:tichu/services/supabase/supabase_multiplayer_backend.dart';

Future<MultiplayerBackend> createConfiguredMultiplayerBackend() async {
  const backendId = String.fromEnvironment(
    'TICHU_BACKEND',
    defaultValue: 'local',
  );

  switch (backendId) {
    case 'local':
      return LocalMultiplayerBackend();
    case 'supabase':
      final config = SupabaseMultiplayerConfig.fromEnvironment();
      await Supabase.initialize(url: config.url, anonKey: config.anonKey);
      final client = Supabase.instance.client;
      if (client.auth.currentSession == null) {
        await client.auth.signInAnonymously();
      }
      return SupabaseMultiplayerBackend(config: config, client: client);
    default:
      throw StateError(
        'Unknown TICHU_BACKEND value: $backendId. Use local or supabase.',
      );
  }
}
