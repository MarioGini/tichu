import 'dart:async';
import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tichu/game/game_match.dart';
import 'package:tichu/game/game_session.dart';
import 'package:tichu/game/game_types.dart';
import 'package:tichu/services/multiplayer/multiplayer_backend.dart';
import 'package:tichu/services/transport/dto/match_dto.dart' as match_dto;
import 'package:tichu/services/transport/dto/session_dto.dart' as session_dto;

class SupabaseMultiplayerConfig {
  const SupabaseMultiplayerConfig({
    required this.url,
    required this.anonKey,
    this.functionName = 'tichu',
    this.watchInterval = const Duration(milliseconds: 1000),
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
      defaultValue: '',
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
      watchInterval: Duration(milliseconds: watchIntervalMs),
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
  bool get supportsAutomatedSeats => false;

  @override
  GameSessionService get sessionService => _sessionService;

  @override
  GameMatchService get matchService => _matchService;
}

abstract base class _SupabaseServiceBase {
  static const String _lobbyViewTable = 'tichu_lobby_views';
  static const String _matchViewTable = 'tichu_match_player_views';
  static const String _connectionViewTable = 'tichu_match_connection_views';

  _SupabaseServiceBase({
    required final SupabaseClient client,
    required final SupabaseMultiplayerConfig config,
  }) : _client = client,
       _config = config;

  final SupabaseClient _client;
  final SupabaseMultiplayerConfig _config;

  Future<Map<String, dynamic>> invokeJson(
    final String action, {
    final Map<String, dynamic>? body,
  }) async {
    final response = await _client.functions.invoke(
      _config.functionName,
      body: _buildFunctionBody(action, body),
    );
    return _normalizeMap(response.data);
  }

  Future<void> invokeVoid(
    final String action, {
    final Map<String, dynamic>? body,
  }) async {
    await _client.functions.invoke(
      _config.functionName,
      body: _buildFunctionBody(action, body),
    );
  }

  Map<String, dynamic> _buildFunctionBody(
    final String action,
    final Map<String, dynamic>? body,
  ) => <String, dynamic>{'action': action, ...?body};

  Future<Map<String, dynamic>?> loadProjectedPayload({
    required final String table,
    required final String scopeColumn,
    required final String scopeValue,
    required final String accessToken,
  }) async {
    try {
      final response = await _client
          .from(table)
          .select('payload')
          .eq(scopeColumn, scopeValue)
          .eq('access_token', accessToken)
          .order('updated_at', ascending: false)
          .limit(1);
      if (response.isEmpty) {
        return null;
      }

      final row = response.first;
      if (!row.containsKey('payload')) {
        return null;
      }

      return _normalizeMap(row['payload']);
    } catch (_) {
      return null;
    }
  }

  Stream<T> watchProjectedValue<T>({
    required final String channelTopic,
    required final String table,
    required final String scopeColumn,
    required final String scopeValue,
    required final Future<T?> Function() loadProjectedValue,
    required final Future<T> Function() loadFallbackValue,
    required final String Function(T value) signatureOf,
    final T? seedValue,
    final void Function(
      StreamController<T> controller,
      RealtimeSubscribeStatus status,
      Object? error,
    )?
    onStatus,
    final Future<void> Function(StreamController<T> controller)?
    onProjectionMiss,
  }) {
    final controller = StreamController<T>();
    RealtimeChannel? channel;
    String? previousSignature;

    Future<void> emitIfChanged(final T value) async {
      if (controller.isClosed) {
        return;
      }
      final signature = signatureOf(value);
      if (signature == previousSignature) {
        return;
      }
      previousSignature = signature;
      controller.add(value);
    }

    Future<void> emitCurrent({required final bool allowFallback}) async {
      try {
        final projectedValue = await loadProjectedValue();
        if (projectedValue != null) {
          await emitIfChanged(projectedValue);
          return;
        }
        if (!allowFallback) {
          if (onProjectionMiss != null) {
            await onProjectionMiss(controller);
          }
          return;
        }
        await emitIfChanged(await loadFallbackValue());
      } catch (error, stackTrace) {
        if (!controller.isClosed) {
          controller.addError(error, stackTrace);
        }
      }
    }

    controller.onListen = () {
      if (seedValue != null) {
        previousSignature = signatureOf(seedValue as T);
        controller.add(seedValue as T);
      }

      channel = _client
          .channel(channelTopic)
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: table,
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: scopeColumn,
              value: scopeValue,
            ),
            callback: (_) {
              unawaited(emitCurrent(allowFallback: false));
            },
          )
          .subscribe((final status, final error) {
            if (status == RealtimeSubscribeStatus.subscribed) {
              unawaited(emitCurrent(allowFallback: true));
            }
            if (onStatus != null) {
              onStatus(controller, status, error);
            }
          });
    };

    controller.onCancel = () async {
      final activeChannel = channel;
      if (activeChannel != null) {
        await _client.removeChannel(activeChannel);
      }
    };

    return controller.stream;
  }

  Map<String, dynamic> _normalizeMap(final Object? raw) {
    final normalized = switch (raw) {
      final String text => jsonDecode(text),
      _ => jsonDecode(jsonEncode(raw)),
    };
    if (normalized is! Map) {
      throw StateError('Expected a JSON object response from Supabase.');
    }
    return Map<String, dynamic>.from(normalized);
  }
}

final class SupabaseGameSessionService extends _SupabaseServiceBase
    implements GameSessionService {
  SupabaseGameSessionService({
    required final SupabaseClient client,
    required final SupabaseMultiplayerConfig config,
  }) : super(client: client, config: config);

  @override
  Future<GameSessionHandle> createLobby(
    final CreateGameLobbyRequest request,
  ) async {
    final payload = await invokeJson(
      'create-lobby',
      body: <String, dynamic>{
        'request': session_dto.CreateGameLobbyRequestDto.fromDomain(
          request,
        ).toJson(),
      },
    );
    return session_dto.GameSessionHandleDto.fromJson(payload).toDomain();
  }

  @override
  Future<GameSessionHandle> joinLobby(
    final JoinGameLobbyRequest request,
  ) async {
    final payload = await invokeJson(
      'join-lobby',
      body: <String, dynamic>{
        'request': session_dto.JoinGameLobbyRequestDto.fromDomain(
          request,
        ).toJson(),
      },
    );
    return session_dto.GameSessionHandleDto.fromJson(payload).toDomain();
  }

  @override
  Stream<GameLobbySnapshot> watchLobby(
    final String lobbyId, {
    required final String accessToken,
  }) => watchProjectedValue(
    channelTopic: 'tichu:lobby:$lobbyId:$accessToken',
    table: _SupabaseServiceBase._lobbyViewTable,
    scopeColumn: 'lobby_id',
    scopeValue: lobbyId,
    loadProjectedValue: () async {
      final payload = await loadProjectedPayload(
        table: _SupabaseServiceBase._lobbyViewTable,
        scopeColumn: 'lobby_id',
        scopeValue: lobbyId,
        accessToken: accessToken,
      );
      if (payload == null) {
        return null;
      }
      return session_dto.GameLobbySnapshotDto.fromJson(payload).toDomain();
    },
    loadFallbackValue: () async {
      final payload = await invokeJson(
        'get-lobby',
        body: <String, dynamic>{'lobbyId': lobbyId, 'accessToken': accessToken},
      );
      return session_dto.GameLobbySnapshotDto.fromJson(payload).toDomain();
    },
    signatureOf: (final value) =>
        jsonEncode(session_dto.GameLobbySnapshotDto.fromDomain(value).toJson()),
  );

  @override
  Future<void> claimSeat(
    final String lobbyId, {
    required final String accessToken,
    required final int seat,
    final PlayerType type = PlayerType.human,
    final String? automatedDisplayName,
  }) => invokeVoid(
    'claim-seat',
    body: <String, dynamic>{
      'lobbyId': lobbyId,
      'accessToken': accessToken,
      'seat': seat,
      'type': type.name,
      'automatedDisplayName': automatedDisplayName,
    },
  );

  @override
  Future<void> setReadyState(
    final String lobbyId, {
    required final String accessToken,
    required final bool isReady,
  }) => invokeVoid(
    'set-ready-state',
    body: <String, dynamic>{
      'lobbyId': lobbyId,
      'accessToken': accessToken,
      'isReady': isReady,
    },
  );

  @override
  Future<void> startMatch(
    final String lobbyId, {
    required final String accessToken,
  }) => invokeVoid(
    'start-match',
    body: <String, dynamic>{'lobbyId': lobbyId, 'accessToken': accessToken},
  );

  @override
  Future<void> leaveLobby(
    final String lobbyId, {
    required final String accessToken,
  }) => invokeVoid(
    'leave-lobby',
    body: <String, dynamic>{'lobbyId': lobbyId, 'accessToken': accessToken},
  );
}

final class SupabaseGameMatchService extends _SupabaseServiceBase
    implements GameMatchService {
  SupabaseGameMatchService({
    required final SupabaseClient client,
    required final SupabaseMultiplayerConfig config,
  }) : super(client: client, config: config);

  @override
  Stream<GameMatchView> watchMatch(
    final String matchId, {
    required final String accessToken,
  }) => watchProjectedValue(
    channelTopic: 'tichu:match:$matchId:$accessToken',
    table: _SupabaseServiceBase._matchViewTable,
    scopeColumn: 'match_id',
    scopeValue: matchId,
    loadProjectedValue: () async {
      final payload = await loadProjectedPayload(
        table: _SupabaseServiceBase._matchViewTable,
        scopeColumn: 'match_id',
        scopeValue: matchId,
        accessToken: accessToken,
      );
      if (payload == null) {
        return null;
      }
      return match_dto.GameMatchViewDto.fromJson(payload).toDomain();
    },
    loadFallbackValue: () async {
      final payload = await invokeJson(
        'get-match-view',
        body: <String, dynamic>{'matchId': matchId, 'accessToken': accessToken},
      );
      return match_dto.GameMatchViewDto.fromJson(payload).toDomain();
    },
    signatureOf: (final value) =>
        jsonEncode(match_dto.GameMatchViewDto.fromDomain(value).toJson()),
  );

  @override
  Stream<GameMatchConnectionSnapshot> watchConnection(
    final String matchId, {
    required final String accessToken,
  }) => watchProjectedValue(
    channelTopic: 'tichu:connection:$matchId:$accessToken',
    table: _SupabaseServiceBase._connectionViewTable,
    scopeColumn: 'match_id',
    scopeValue: matchId,
    seedValue: const GameMatchConnectionSnapshot(
      state: GameMatchConnectionState.connecting,
    ),
    loadProjectedValue: () async {
      final payload = await loadProjectedPayload(
        table: _SupabaseServiceBase._connectionViewTable,
        scopeColumn: 'match_id',
        scopeValue: matchId,
        accessToken: accessToken,
      );
      if (payload == null) {
        return null;
      }
      return match_dto.GameMatchConnectionSnapshotDto.fromJson(
        payload,
      ).toDomain();
    },
    loadFallbackValue: () async {
      final payload = await invokeJson(
        'get-match-connection',
        body: <String, dynamic>{'matchId': matchId, 'accessToken': accessToken},
      );
      return match_dto.GameMatchConnectionSnapshotDto.fromJson(
        payload,
      ).toDomain();
    },
    signatureOf: (final value) => jsonEncode(
      match_dto.GameMatchConnectionSnapshotDto.fromDomain(value).toJson(),
    ),
    onStatus: (final controller, final status, final error) {
      if (status == RealtimeSubscribeStatus.channelError ||
          status == RealtimeSubscribeStatus.timedOut) {
        controller.add(
          GameMatchConnectionSnapshot(
            state: GameMatchConnectionState.reconnecting,
            detail: error?.toString(),
            updatedAt: DateTime.now(),
          ),
        );
      }
    },
    onProjectionMiss: (final controller) async {
      controller.add(
        GameMatchConnectionSnapshot(
          state: GameMatchConnectionState.closed,
          updatedAt: DateTime.now(),
        ),
      );
    },
  );

  @override
  Future<void> submitAction(
    final String matchId,
    final GameActionSubmission submission, {
    required final String accessToken,
  }) => invokeVoid(
    'submit-action',
    body: <String, dynamic>{
      'matchId': matchId,
      'accessToken': accessToken,
      'submission': match_dto.GameActionSubmissionDto.fromDomain(
        submission,
      ).toJson(),
    },
  );

  @override
  Future<void> acknowledgeRoundSummary(
    final String matchId,
    final RoundSummaryAcknowledgement acknowledgement, {
    required final String accessToken,
  }) => invokeVoid(
    'acknowledge-round-summary',
    body: <String, dynamic>{
      'matchId': matchId,
      'accessToken': accessToken,
      'acknowledgement': match_dto.RoundSummaryAcknowledgementDto.fromDomain(
        acknowledgement,
      ).toJson(),
    },
  );

  @override
  Future<void> leaveMatch(
    final String matchId, {
    required final String accessToken,
  }) => invokeVoid(
    'leave-match',
    body: <String, dynamic>{'matchId': matchId, 'accessToken': accessToken},
  );
}
