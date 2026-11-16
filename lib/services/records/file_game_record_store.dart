import 'dart:convert';
import 'dart:io';

import 'package:tichu/game/record/game_record.dart';
import 'package:tichu/game/record/game_record_store.dart';

/// Stores each record as `<directory>/<id>.json` (pretty-printed).
class FileGameRecordStore implements GameRecordStore {
  FileGameRecordStore(this.directory);

  /// `$TICHU_GAME_RECORDS_DIR`, else `$XDG_DATA_HOME/tichu/game_records`,
  /// else `~/.local/share/tichu/game_records` (`%APPDATA%` on Windows).
  factory FileGameRecordStore.defaultLocation() {
    final env = Platform.environment;
    final explicit = env['TICHU_GAME_RECORDS_DIR'];
    if (explicit != null && explicit.isNotEmpty) {
      return FileGameRecordStore(Directory(explicit));
    }
    final xdg = env['XDG_DATA_HOME'];
    final home = env['HOME'] ?? env['USERPROFILE'] ?? '.';
    final base = (xdg != null && xdg.isNotEmpty)
        ? xdg
        : Platform.isWindows
        ? (env['APPDATA'] ?? home)
        : '$home/.local/share';
    return FileGameRecordStore(Directory('$base/tichu/game_records'));
  }

  final Directory directory;

  File _file(final String id) => File('${directory.path}/$id.json');

  @override
  Future<void> save(final GameRecord record) async {
    await directory.create(recursive: true);
    final file = _file(record.id);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(
      const JsonEncoder.withIndent('  ').convert(record.toJson()),
      flush: true,
    );
    await tmp.rename(file.path);
  }

  @override
  Future<Map<String, Object?>?> load(final String id) async {
    final file = _file(id);
    if (!file.existsSync()) return null;
    return Map<String, Object?>.from(
      jsonDecode(await file.readAsString()) as Map,
    );
  }

  @override
  String describeLocation(final String id) => _file(id).path;
}
