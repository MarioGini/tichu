import 'package:tichu/game/game_match.dart';
import 'package:tichu/game/game_session.dart';
import 'package:tichu/services/local/local_table_service.dart';

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
  LocalMultiplayerBackend({final LocalGameTableService? tableService})
    : _tableService = tableService ?? LocalGameTableService();

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
