import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' hide Card;
import 'package:tichu/game/turn/tichu_data.dart';
import 'package:tichu/screens/game/game_screen.dart';
import 'package:tichu/widgets/card_widget.dart';

import '../../utils/test_game_fixtures.dart';
import '../../utils/test_game_match_service.dart';

/// Real portrait phones are ~360–430 logical px wide (the 1080x2400 tests
/// use physical pixels as logical ones). A full 14-card hand must fit with
/// every card's rank corner visible.
void main() {
  final fullHand = [
    for (final face in [
      CardFace.two,
      CardFace.three,
      CardFace.four,
      CardFace.five,
      CardFace.six,
      CardFace.seven,
      CardFace.eight,
      CardFace.nine,
      CardFace.ten,
      CardFace.jack,
      CardFace.queen,
      CardFace.king,
      CardFace.ace,
    ])
      Card(face, CardColor.red),
    Card(CardFace.dragon, CardColor.special),
  ];

  for (final (size, dpr) in [
    (const Size(360, 780), 3.0),
    (const Size(412, 915), 2.625),
  ]) {
    testWidgets('14-card hand is readable at ${size.width.toInt()}x'
        '${size.height.toInt()} dp', (tester) async {
      tester.view
        ..physicalSize = size * dpr
        ..devicePixelRatio = dpr;
      addTearDown(tester.view.reset);

      final backend = FakeGameMatchService();
      await tester.pumpWidget(
        MaterialApp(
          home: GameScreen(
            matchService: backend,
            sessionHandle: backend.sessionHandle,
          ),
        ),
      );
      backend.emit(
        buildPlayerSnapshot(currentPlayerId: testHumanId, hand: fullHand),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      final lefts =
          find
              .byType(CardWidget)
              .evaluate()
              .map((e) => tester.getRect(find.byWidget(e.widget)))
              .where((r) => r.bottom > size.height * 0.6)
              .map((r) => r.left)
              .toList()
            ..sort();
      expect(lefts.length, 14);
      for (var i = 1; i < lefts.length; i++) {
        expect(lefts[i] - lefts[i - 1], greaterThanOrEqualTo(20));
      }
      for (final left in lefts) {
        expect(left, greaterThanOrEqualTo(0));
        expect(left, lessThan(size.width));
      }
    });
  }
}
