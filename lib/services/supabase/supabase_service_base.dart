part of 'supabase_multiplayer_backend.dart';

abstract base class _SupabaseServiceBase {
  static const String _lobbyViewTable = 'tichu_lobby_views';
  static const String _matchViewTable = 'tichu_match_player_views';
  static const String _connectionViewTable = 'tichu_match_connection_views';

  _SupabaseServiceBase({required this._client, required this._config});

  final SupabaseClient _client;
  final SupabaseMultiplayerConfig _config;

  Future<Map<String, dynamic>> invokeJson(
    String action, {
    Map<String, dynamic>? body,
  }) async {
    final response = await _client.functions.invoke(
      _config.functionName,
      body: _buildFunctionBody(action, body),
    );
    return _normalizeMap(response.data);
  }

  Future<void> invokeVoid(String action, {Map<String, dynamic>? body}) async {
    await _client.functions.invoke(
      _config.functionName,
      body: _buildFunctionBody(action, body),
    );
  }

  Map<String, dynamic> _buildFunctionBody(
    String action,
    Map<String, dynamic>? body,
  ) => <String, dynamic>{'action': action, ...?body};

  Future<Map<String, dynamic>?> loadProjectedPayload({
    required String table,
    required String scopeColumn,
    required String scopeValue,
    required String accessToken,
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
    } on Object catch (_) {
      return null;
    }
  }

  Stream<T> watchProjectedValue<T>({
    required String channelTopic,
    required String table,
    required String scopeColumn,
    required String scopeValue,
    required Future<T?> Function() loadProjectedValue,
    required Future<T> Function() loadFallbackValue,
    required String Function(T value) signatureOf,
    T? seedValue,
    void Function(
      void Function(T value) emit,
      RealtimeSubscribeStatus status,
      Object? error,
    )?
    onStatus,
    Future<void> Function(void Function(T value) emit)? onProjectionMiss,
  }) {
    final controller = StreamController<T>();
    RealtimeChannel? channel;
    String? previousSignature;

    /// Adds [value] unless the subscriber has cancelled (callbacks can
    /// still run after that, e.g. once an await returns).
    void emit(T value) {
      if (!controller.isClosed) controller.add(value);
    }

    Future<void> emitIfChanged(T value) async {
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

    Future<void> emitCurrent({required bool allowFallback}) async {
      try {
        final projectedValue = await loadProjectedValue();
        if (projectedValue != null) {
          await emitIfChanged(projectedValue);
          return;
        }
        if (!allowFallback) {
          if (onProjectionMiss != null) {
            await onProjectionMiss(emit);
          }
          return;
        }
        await emitIfChanged(await loadFallbackValue());
      } on Object catch (error, stackTrace) {
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
          .subscribe((status, error) {
            if (status == RealtimeSubscribeStatus.subscribed) {
              unawaited(emitCurrent(allowFallback: true));
            }
            if (onStatus != null) {
              onStatus(emit, status, error);
            }
          });
    };

    controller.onCancel = () async {
      final activeChannel = channel;
      if (activeChannel != null) {
        await _client.removeChannel(activeChannel);
      }
      await controller.close();
    };

    return controller.stream;
  }

  Map<String, dynamic> _normalizeMap(Object? raw) {
    final normalized = switch (raw) {
      final String text => jsonDecode(text),
      _ => jsonDecode(jsonEncode(raw)),
    };
    if (normalized is! Map) {
      throw StateError('Expected a JSON object response from Supabase.');
    }
    return Map<String, dynamic>.from(normalized);
  }

  /// Mirrors [source] and sends a heartbeat every 15 s while listened to.
  Stream<T> withHeartbeat<T>({
    required Stream<T> Function() source,
    required Map<String, dynamic> heartbeatBody,
  }) {
    final controller = StreamController<T>();
    Timer? heartbeatTimer;
    StreamSubscription<T>? subscription;

    controller.onListen = () {
      heartbeatTimer = Timer.periodic(
        const Duration(seconds: 15),
        (_) => invokeVoid('heartbeat', body: heartbeatBody).catchError((_) {}),
      );
      unawaited(
        invokeVoid('heartbeat', body: heartbeatBody).catchError((_) {}),
      );
      subscription = source().listen(
        controller.add,
        onError: controller.addError,
        onDone: controller.close,
      );
    };

    controller.onCancel = () async {
      heartbeatTimer?.cancel();
      await subscription?.cancel();
    };

    return controller.stream;
  }
}
