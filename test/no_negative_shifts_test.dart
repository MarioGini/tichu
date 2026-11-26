import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// dart2js (the web app) makes shift results unsigned 32-bit: `-1 << 30`
/// is +3221225472 there. The one-on-one solver started its maximiser at
/// that value and found no move on the web. Write such bounds as literals.
void main() {
  test('no shifts of negative literals in lib/', () {
    final pattern = RegExp(r'-\s*\(?\s*1\s*\)?\s*<<');
    final offenders = <String>[];
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i].trimLeft();
        if (line.startsWith('//')) continue;
        if (pattern.hasMatch(line)) offenders.add('${file.path}:${i + 1}');
      }
    }
    expect(offenders, isEmpty);
  });
}
