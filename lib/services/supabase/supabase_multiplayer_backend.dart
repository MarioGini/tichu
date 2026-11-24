import 'dart:async';
import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tichu/game/game_match.dart';
import 'package:tichu/game/game_session.dart';
import 'package:tichu/game/game_types.dart';
import 'package:tichu/services/multiplayer/multiplayer_backend.dart';
import 'package:tichu/services/transport/dto/match_dto.dart' as match_dto;
import 'package:tichu/services/transport/dto/session_dto.dart' as session_dto;

part 'supabase_match_service.dart';
part 'supabase_service_base.dart';
part 'supabase_session_service.dart';

class SupabaseMultiplayerConfig {
  const SupabaseMultiplayerConfig({
    required this.url,
    required this.anonKey,
    this.functionName = 'tichu',
    required this.watchInterval,
  });

  final String url;
  final String anonKey;
  final String functionName;
  final Duration watchInterval;

  factory SupabaseMultiplayerConfig.fromEnvironment() {
    const url = String.fromEnvironment('SUPABASE_URL');
    const anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
    const configuredFunctionName = String.fromEnvironment(
      'TICHU_SUPABASE_FUNCTION_NAME',
      defaultValue: 'tichu',
    );
    const legacyFunctionPrefix = String.fromEnvironment(
      'TICHU_SUPABASE_FUNCTION_PREFIX',
    );
    const watchIntervalMs = int.fromEnvironment(
      'TICHU_SUPABASE_POLL_MS',
      defaultValue: 1000,
    );

    if (url.isEmpty || anonKey.isEmpty) {
      throw StateError(
        'Supabase backend requires SUPABASE_URL and SUPABASE_ANON_KEY.',
      );
    }

    return SupabaseMultiplayerConfig(
      url: url,
      anonKey: anonKey,
      functionName: legacyFunctionPrefix.isNotEmpty
          ? legacyFunctionPrefix
          : configuredFunctionName,
      watchInterval: const Duration(milliseconds: watchIntervalMs),
    );
  }
}

class SupabaseMultiplayerBackend implements MultiplayerBackend {
  SupabaseMultiplayerBackend({
    required final SupabaseMultiplayerConfig config,
    final SupabaseClient? client,
  }) : _sessionService = SupabaseGameSessionService(
         client: client ?? Supabase.instance.client,
         config: config,
       ),
       _matchService = SupabaseGameMatchService(
         client: client ?? Supabase.instance.client,
         config: config,
       );
  final SupabaseGameSessionService _sessionService;
  final SupabaseGameMatchService _matchService;

  @override
  String get id => 'supabase';

  @override
  String get displayName => 'Supabase';

  @override
  bool get supportsAutomatedSeats => true;

  @override
  GameSessionService get sessionService => _sessionService;

  @override
  GameMatchService get matchService => _matchService;
}
