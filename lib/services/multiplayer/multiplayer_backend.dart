import 'package:tichu/agents/app_bots.dart';
import 'package:tichu/game/game_match.dart';
import 'package:tichu/game/game_session.dart';
import 'package:tichu/game/record/game_record_store.dart';
import 'package:tichu/game/record/recording_game_engine.dart';
import 'package:tichu/game/turn/engine/engine_impl.dart';
import 'package:tichu/services/local/local_match_runtime.dart';
import 'package:tichu/services/local/local_table_service.dart';
import 'package:tichu/services/records/default_game_record_store.dart';

/// App-facing bundle for lobby and live-match services.
///
/// A concrete backend can keep separate session and match transports internally,
/// while the UI only depends on this stable pair of contracts.
abstract interface class MultiplayerBackend {
  String get id;

  String get displayName;

  bool get supportsAutomatedSeats;

  GameSessionService get sessionService;

  GameMatchService get matchService;
}

class LocalMultiplayerBackend implements MultiplayerBackend {
  LocalMultiplayerBackend({
    final LocalGameTableService? tableService,
    final GameRecordStore? recordStore,
  }) : _tableService =
           tableService ??
           LocalGameTableService(
             runtimeFactory: () => LocalMatchRuntime(
               engine: RecordingGameEngine(
                 GameEngineImpl(),
                 store: recordStore ?? createDefaultGameRecordStore(),
                 botDescription: AppBots.describe(),
               ),
             ),
           );

  final LocalGameTableService _tableService;

  @override
  String get id => 'local';

  @override
  String get displayName => 'Local Table';

  @override
  bool get supportsAutomatedSeats => true;

  @override
  GameSessionService get sessionService => _tableService;

  @override
  GameMatchService get matchService => _tableService;
}
