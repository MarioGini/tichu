part of 'headless.dart';

/// An external bot running as a child process, spoken to in JSON lines
/// over its stdin / stdout (`doc/bot_bridge.md`). Its stderr is passed
/// through. One process serves every seat of the external team; requests
/// are answered one at a time.
class _ExternalBotProcess implements BotChannel {
  _ExternalBotProcess._(this._process, this._lines);

  final Process _process;
  final StreamIterator<String> _lines;
  var _nextId = 0;

  /// Starts [command] in a shell.
  static Future<_ExternalBotProcess> start(String command) async {
    final process = await Process.start('/bin/sh', ['-c', command]);
    process.stderr.listen(stderr.add);
    final lines = StreamIterator(
      process.stdout.transform(utf8.decoder).transform(const LineSplitter()),
    );
    return _ExternalBotProcess._(process, lines);
  }

  @override
  Future<Map<String, Object?>> request(Map<String, Object?> message) async {
    final id = _nextId++;
    _process.stdin.writeln(jsonEncode({'id': id, ...message}));
    await _process.stdin.flush();
    if (!await _lines.moveNext()) {
      throw StateError(
        'External bot exited (code ${await _process.exitCode}) '
        'without answering request $id (${message['type']}).',
      );
    }
    final reply = Map<String, Object?>.from(jsonDecode(_lines.current) as Map);
    if (reply['id'] != id) {
      throw StateError('External bot answered ${reply['id']}, expected $id.');
    }
    if (reply['error'] case final error?) {
      throw StateError('External bot failed on ${message['type']}: $error');
    }
    return reply;
  }

  Future<void> close() async {
    await _process.stdin.close();
    await _process.exitCode;
    await _lines.cancel();
  }
}
