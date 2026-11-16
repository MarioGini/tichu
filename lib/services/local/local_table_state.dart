part of 'local_table_service.dart';

/// Shared state of [LocalGameTableService]; the part files add the match API
/// (mixin) and private helpers (extensions) on top of it.
abstract class _LocalTableBase {
  _LocalTableBase({
    final LocalMatchRuntime Function()? runtimeFactory,
    final GameEngine? projectionEngine,
    final GameTableProjectionStore? projectionStore,
    final AuthorityStateStore? stateStore,
    final HeartbeatConfig heartbeatConfig = HeartbeatConfig.disabled,
  }) : _runtimeFactory = runtimeFactory ?? LocalMatchRuntime.new,
       _projectionEngine = projectionEngine ?? GameEngineImpl(),
       _projectionStore =
           projectionStore ?? const NoopGameTableProjectionStore(),
       _stateStore = stateStore ?? const NoopAuthorityStateStore(),
       _heartbeatConfig = heartbeatConfig {
    if (_heartbeatConfig.enabled) {
      _heartbeatSweepTimer = Timer.periodic(
        _heartbeatConfig.sweepInterval,
        (_) => sweepHeartbeats(),
      );
    }
  }

  final LocalMatchRuntime Function() _runtimeFactory;
  final GameEngine _projectionEngine;
  final GameTableProjectionStore _projectionStore;
  final AuthorityStateStore _stateStore;
  final HeartbeatConfig _heartbeatConfig;
  Timer? _heartbeatSweepTimer;
  final Random _random = Random();
  final Map<String, _LocalLobbyState> _lobbies = {};
  final Map<String, String> _lobbyIdByJoinCode = {};
  int _nextLobbyId = 1;
  int _nextPlayerId = 0;
  int _nextAccessTokenId = 1;

  void sweepHeartbeats();
}
