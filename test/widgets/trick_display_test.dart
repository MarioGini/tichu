import 'package:flutter/material.dart' hide Card;
import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/game/turn/tichu_data.dart';
import 'package:tichu/widgets/trick_display.dart';

void main() {
  Widget buildWidget(final TrickDisplay child) => MaterialApp(
      home: Scaffold(body: Center(child: child)),
    );

  testWidgets('does not render wish row when no active wish exists', (
    final tester,
  ) async {
    await tester.pumpWidget(
      buildWidget(
        const TrickDisplay(
          cards: [],
          currentWinnerLabel: '',
          activeWish: CardFace.none,
        ),
      ),
    );

    expect(find.textContaining('Wish:'), findsNothing);
  });

  testWidgets('renders wish row when active wish exists', (final tester) async {
    await tester.pumpWidget(
      buildWidget(
        const TrickDisplay(
          cards: [],
          currentWinnerLabel: '',
          activeWish: CardFace.ace,
        ),
      ),
    );

    expect(find.text('Wish: A'), findsOneWidget);
  });
}
