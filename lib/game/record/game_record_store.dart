import 'package:tichu/game/record/game_record.dart';

/// Where finished and running games are kept, keyed by [GameRecord.id].
abstract interface class GameRecordStore {
  /// Creates or replaces the stored copy of [record].
  Future<void> save(GameRecord record);

  /// The stored JSON of record [id], or null when there is none.
  Future<Map<String, Object?>?> load(String id);

  /// Human-readable location of record [id] (file path, table row, ...).
  String describeLocation(String id);
}

/// Keeps records in memory only (web builds and tests).
class InMemoryGameRecordStore implements GameRecordStore {
  final Map<String, Map<String, Object?>> records = {};

  @override
  Future<void> save(GameRecord record) async {
    records[record.id] = record.toJson();
  }

  @override
  Future<Map<String, Object?>?> load(String id) async => records[id];

  @override
  String describeLocation(String id) =>
      'kept in memory only (use "Copy record")';
}
