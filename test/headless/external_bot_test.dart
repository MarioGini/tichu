import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/agents/external/bridge_codec.dart';
import 'package:tichu/game/card_identifiers.dart';
import 'package:tichu/headless/headless.dart' as headless;

void main() {
  test('card codes round-trip for the whole deck', () {
    final codes = {for (final c in cardIdentifiers.values) BridgeCodec.card(c)};
    expect(codes, hasLength(cardIdentifiers.length));
    for (final card in cardIdentifiers.values) {
      expect(BridgeCodec.parseCard(BridgeCodec.card(card)), card);
    }
  });

  test('an external bot plays whole games over the bridge', () async {
    final dir = await Directory.systemTemp.createTemp('tichu_bridge_');
    final out = File('${dir.path}/summary.jsonl');
    try {
      // The random adapter checks on every request that the events
      // explain its hand, and reports an error otherwise.
      await headless.main([
        '--seed=3',
        '--episodes=2',
        '--target-score=300',
        '--format=summary',
        '--output=${out.path}',
        '--opponent-external=python3 arena/adapters/random_bot.py 7',
      ]);
      final rows = [
        for (final line in await out.readAsLines())
          jsonDecode(line) as Map<String, Object?>,
      ];
      expect(rows, hasLength(2));
      for (final row in rows) {
        expect(row['done'], isTrue);
      }
    } finally {
      await dir.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
}
