import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' hide Card;
import 'package:tichu/game/record/game_record_store.dart';
import 'package:tichu/screens/game/widgets/player_hand_area.dart';
import 'package:tichu/screens/observe/observe_controller.dart';
import 'package:tichu/screens/observe/observe_screen.dart';
import 'package:tichu/widgets/card_widget.dart';
import 'package:tichu/widgets/opponent_display.dart';

Future<ObserveController> _pumpObserve(
  final WidgetTester tester,
  final Size size, {
  final double dpr = 2,
}) async {
  tester.view
    ..physicalSize = size * dpr
    ..devicePixelRatio = dpr;
  addTearDown(tester.view.reset);

  final controller = ObserveController(
    store: InMemoryGameRecordStore(),
    phaseDelay: Duration.zero,
  );
  addTearDown(controller.dispose);
  await tester.runAsync(controller.start);

  await tester.pumpWidget(
    MaterialApp(home: ObserveScreen(controller: controller)),
  );
  await tester.pump();
  return controller;
}

String _seatName(final WidgetTester tester, final String position) => tester
    .widget<OpponentDisplay>(
      find.descendant(
        of: find.byKey(Key('observe-seat-$position')),
        matching: find.byType(OpponentDisplay),
      ),
    )
    .name;

String _handName(final WidgetTester tester) => tester
    .widget<PlayerHandArea>(find.byKey(const Key('observe-hand')))
    .playerName;

/// Cards drawn inside the bottom hand area.
Finder _handCards() => find.descendant(
  of: find.byKey(const Key('observe-hand')),
  matching: find.byType(CardWidget),
);

void main() {
  testWidgets('followed bot is at the bottom; tapping a seat rotates the '
      'table', (final tester) async {
    const size = Size(412, 839);
    final controller = await _pumpObserve(tester, size);
    expect(tester.takeException(), isNull);
    expect(controller.step, ObserveStep.move);

    // Default: Bot 1 (seat 0) at the bottom, partner Bot 3 on top, the
    // left opponent is the seat before, the right one the seat after.
    expect(controller.followedSeat, 0);
    expect(_handName(tester), 'Bot 1');
    expect(_seatName(tester, 'partner'), 'Bot 3');
    expect(_seatName(tester, 'left'), 'Bot 4');
    expect(_seatName(tester, 'right'), 'Bot 2');

    // Bot 1's cards are face up at the bottom of the screen.
    final hand = controller.snapshot!.hands['bot_1']!;
    expect(_handCards(), findsNWidgets(hand.length));
    for (final element in _handCards().evaluate()) {
      final rect = tester.getRect(find.byWidget(element.widget));
      expect(rect.top, greaterThan(size.height * 0.55));
      expect(rect.bottom, lessThanOrEqualTo(size.height));
    }

    // Follow the left opponent: Bot 4 moves to the bottom.
    await tester.tap(find.byKey(const Key('observe-seat-left')));
    await tester.pump();
    expect(controller.followedSeat, 3);
    expect(_handName(tester), 'Bot 4');
    expect(_seatName(tester, 'partner'), 'Bot 2');
    expect(_seatName(tester, 'left'), 'Bot 3');
    expect(_seatName(tester, 'right'), 'Bot 1');
    expect(
      _handCards(),
      findsNWidgets(controller.snapshot!.hands['bot_4']!.length),
    );

    // And the partner of Bot 4: Bot 2.
    await tester.tap(find.byKey(const Key('observe-seat-partner')));
    await tester.pump();
    expect(controller.followedSeat, 1);
    expect(_handName(tester), 'Bot 2');
    expect(_seatName(tester, 'partner'), 'Bot 4');
    expect(_seatName(tester, 'left'), 'Bot 1');
    expect(_seatName(tester, 'right'), 'Bot 3');
  });

  testWidgets('Step applies the staged move; speed and play controls', (
    final tester,
  ) async {
    final controller = await _pumpObserve(tester, const Size(1280, 800));
    expect(
      find.textContaining('#${controller.record!.events.length + 1}'),
      findsOneWidget,
    );

    final before = controller.record!.events.length;
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('observe-step')));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    expect(controller.record!.events.length, greaterThan(before));

    expect(controller.speedLabel, '1×');
    await tester.tap(find.byKey(const Key('observe-speed')));
    await tester.pump();
    expect(controller.speedLabel, '2×');

    expect(controller.autoPlay, isFalse);
    await tester.tap(find.byKey(const Key('observe-autoplay')));
    await tester.pump();
    expect(controller.autoPlay, isTrue);
    await tester.tap(find.byKey(const Key('observe-autoplay')));
    await tester.pump();
    expect(controller.autoPlay, isFalse);
  });

  testWidgets('All hands sheet shows every hand and follows on tap', (
    final tester,
  ) async {
    final controller = await _pumpObserve(tester, const Size(412, 839));
    await tester.tap(find.byKey(const Key('observe-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All hands'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final cards = controller.snapshot!.hands.values.fold<int>(
      0,
      (final sum, final hand) => sum + hand.length,
    );
    expect(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byType(CardWidget),
      ),
      findsNWidgets(cards),
    );

    await tester.tap(find.text('Bot 3').last);
    await tester.pump();
    expect(controller.followedSeat, 2);
  });

  for (final (size, dpr) in const [
    (Size(412, 839), 2.0),
    (Size(360, 780), 3.0),
    (Size(863, 360), 2.0),
    (Size(915, 412), 2.0),
    (Size(600, 360), 2.0),
    (Size(1280, 800), 1.0),
    (Size(1080, 2400), 1.0),
  ]) {
    testWidgets('observe table fits at ${size.width.toInt()}x'
        '${size.height.toInt()}', (final tester) async {
      final controller = await _pumpObserve(tester, size, dpr: dpr);
      expect(tester.takeException(), isNull);

      final step = tester.getRect(find.byKey(const Key('observe-step')));
      expect(step.bottom, lessThanOrEqualTo(size.height));
      expect(step.right, lessThanOrEqualTo(size.width));
      for (final position in ['partner', 'left', 'right']) {
        final seat = tester.getRect(find.byKey(Key('observe-seat-$position')));
        expect(seat.left, greaterThanOrEqualTo(0));
        expect(seat.right, lessThanOrEqualTo(size.width));
        expect(seat.bottom, lessThanOrEqualTo(step.top + 1));
      }
      final handCards = _handCards().evaluate().toList();
      expect(handCards, hasLength(controller.snapshot!.hands['bot_1']!.length));
      for (final element in handCards) {
        final rect = tester.getRect(find.byWidget(element.widget));
        expect(rect.right, lessThanOrEqualTo(size.width));
        expect(rect.bottom, lessThanOrEqualTo(size.height));
      }

      // Rotating the table keeps the layout intact.
      await tester.tap(find.byKey(const Key('observe-seat-right')));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(controller.followedSeat, 1);
    });
  }
}
