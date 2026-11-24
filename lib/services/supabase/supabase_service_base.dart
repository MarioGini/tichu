part of 'supabase_multiplayer_backend.dart';

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
    } on Object catch (_) {
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
      void Function(T value) emit,
      RealtimeSubscribeStatus status,
      Object? error,
    )?
    onStatus,
    final Future<void> Function(void Function(T value) emit)?
    onProjectionMiss,
  }) {
    final controller = StreamController<T>();
    RealtimeChannel? channel;
    String? previousSignature;

    /// Adds [value] unless the subscriber has cancelled (callbacks can
    /// still run after that, e.g. once an await returns).
    void emit(final T value) {
      if (!controller.isClosed) controller.add(value);
    }

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
          .subscribe((final status, final error) {
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

  /// Mirrors [source] and sends a heartbeat every 15 s while listened to.
  Stream<T> withHeartbeat<T>({
    required final Stream<T> Function() source,
    required final Map<String, dynamic> heartbeatBody,
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
