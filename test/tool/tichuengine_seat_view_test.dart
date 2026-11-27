import 'dart:collection';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/tichuengine_client.dart';

/// A server position whose `hand_cards` must never be read.
class _Hidden extends MapBase<String, Object?> {
  _Hidden(this._inner);
  final Map<String, Object?> _inner;

  @override
  Object? operator [](Object? key) {
    if (key == 'hand_cards') fail("read another seat's hand_cards");
    return _inner[key];
  }

  @override
  void operator []=(String key, Object? value) => _inner[key] = value;
  @override
  void clear() => _inner.clear();
  @override
  Iterable<String> get keys => _inner.keys;
  @override
  Object? remove(Object? key) => _inner.remove(key);
}

Map<String, Object?> _state(int seat, List<List<int>> hands) => {
  'positions': [
    for (var s = 0; s < 4; s++)
      if (s == seat)
        <String, Object?>{
          'hand_cards': hands[s],
          'trade_slate': null,
          'grand_bet': false,
        }
      else
        _Hidden({
          'hand_cards': hands[s],
          'trade_slate': null,
          'grand_bet': false,
        }),
  ],
  'phase': 0,
  'is_trade_phase': false,
  'active_player': 0,
  'grand_phase_state': {
    'first_8s': [for (final h in hands) h.take(8).toList()],
    'grand_bet_choices': [null, false, false, false],
  },
};

void main() {
  final deck = List<int>.generate(56, (i) => i)..shuffle(Random(1));
  final hands = [for (var s = 0; s < 4; s++) deck.sublist(14 * s, 14 * s + 14)];

  for (final seat in [0, 2]) {
    test('seat $seat reads only its own cards', () {
      final state = _state(seat, hands);
      final view = SeatView(seat, {
        'play_state': state,
        'history': [
          {'move': null, 'state': state},
        ],
      });
      expect(view.myHand(), hands[seat]);
      expect(view.myFirstEight(), hands[seat].take(8).toList());
      expect(view.moves(), isEmpty);
      // The shadow game is rebuilt from that view alone.
      final shadow = Shadow(view, Random(2))..build();
      expect(
        shadow.state.hands['p$seat']!.map(idOf).toSet(),
        hands[seat].take(8).toSet(),
      );
    });
  }
}
