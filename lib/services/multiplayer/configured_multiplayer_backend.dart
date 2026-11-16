import 'package:tichu/services/multiplayer/multiplayer_backend.dart';
import 'package:tichu/services/supabase/supabase_app_client.dart';
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
      final client = await appSupabaseClient();
      return SupabaseMultiplayerBackend(config: config, client: client);
    default:
      throw StateError(
        'Unknown TICHU_BACKEND value: $backendId. Use local or supabase.',
      );
  }
}
