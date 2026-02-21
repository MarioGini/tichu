import 'package:flutter/material.dart' hide Card;
import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/game/turn/tichu_data.dart';
import 'package:tichu/widgets/card_widget.dart';

void main() {
  Widget buildWidget(final Card card) => MaterialApp(
    home: Scaffold(
      body: Center(child: CardWidget(card: card, isSelected: false)),
    ),
  );

  testWidgets('formats phoenix 10.5 as 10+', (final tester) async {
    await tester.pumpWidget(buildWidget(const Card.phoenix(10.5)));

    expect(find.text('10+'), findsOneWidget);
  });

  testWidgets('formats phoenix 11.5 as J+', (final tester) async {
    await tester.pumpWidget(buildWidget(const Card.phoenix(11.5)));

    expect(find.text('J+'), findsOneWidget);
  });
}
