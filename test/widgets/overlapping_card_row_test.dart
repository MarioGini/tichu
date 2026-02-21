import 'package:flutter/material.dart' hide Card;
import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/game/turn/tichu_data.dart';
import 'package:tichu/widgets/card_widget.dart';
import 'package:tichu/widgets/overlapping_card_row.dart';

void main() {
  testWidgets('single card scales down in narrow width without overflow', (
    final tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 44,
            height: 80,
            child: OverlappingCardRow(
              itemCount: 1,
              cardWidth: CardWidget.compactWidth,
              cardHeight: CardWidget.compactHeight,
              height: 70,
              itemBuilder: (final context, final index) => CardWidget(
                card: Card(CardFace.ace, CardColor.blue),
                isSelected: false,
                compact: true,
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
