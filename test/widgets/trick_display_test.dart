import 'package:flutter/material.dart' hide Card;
import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/game/turn/tichu_data.dart';
import 'package:tichu/widgets/card_widget.dart';
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

    expect(find.text('Wish:'), findsNothing);
    expect(find.byType(CardValueChip), findsNothing);
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

    expect(find.byType(CardValueChip), findsOneWidget);
    expect(find.text('A'), findsOneWidget);
  });

  testWidgets('does not duplicate wish card when trick already has Mahjong', (
    final tester,
  ) async {
    await tester.pumpWidget(
      buildWidget(
        TrickDisplay(
          cards: [Card(CardFace.mahJong, CardColor.special)],
          currentWinnerLabel: '',
          activeWish: CardFace.nine,
        ),
      ),
    );

    expect(find.byType(CardWidget), findsOneWidget);
    expect(find.byType(CardValueChip), findsOneWidget);
    expect(find.text('9'), findsOneWidget);
  });
}
