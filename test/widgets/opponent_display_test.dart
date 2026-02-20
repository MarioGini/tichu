import 'package:flutter/material.dart' hide Card;
import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/game/turn/tichu_data.dart';
import 'package:tichu/widgets/opponent_display.dart';
import 'package:tichu/widgets/overlapping_card_row.dart';

void main() {
  testWidgets('grand tichu uses badge without coloring whole player box', (
    final tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 260,
              height: 260,
              child: OpponentDisplay(
                name: 'Opponent',
                cardCount: 8,
                isActive: false,
                isFinished: false,
                tichuDeclared: true,
                grandTichuDeclared: true,
                finishPosition: null,
                alignment: Axis.vertical,
                icon: Icons.smart_toy_outlined,
                teamScore: 0,
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('GRAND'), findsOneWidget);

    final container = tester.widget<AnimatedContainer>(
      find.byType(AnimatedContainer).first,
    );
    final decoration = container.decoration! as BoxDecoration;

    expect(decoration.border, isNotNull);
    expect((decoration.border! as Border).top.color, Colors.white24);
    expect((decoration.border! as Border).top.width, 1);
    expect(decoration.boxShadow, isNull);
  });

  testWidgets('horizontal and vertical boxes share same inner chrome', (
    final tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 260,
                height: 260,
                child: OpponentDisplay(
                  name: 'Opponent Top',
                  cardCount: 8,
                  isActive: false,
                  isFinished: false,
                  tichuDeclared: false,
                  grandTichuDeclared: false,
                  finishPosition: null,
                  alignment: Axis.horizontal,
                  icon: Icons.psychology_alt,
                  teamScore: 0,
                ),
              ),
              SizedBox(
                width: 260,
                height: 260,
                child: OpponentDisplay(
                  name: 'Opponent Side',
                  cardCount: 8,
                  isActive: false,
                  isFinished: false,
                  tichuDeclared: false,
                  grandTichuDeclared: false,
                  finishPosition: null,
                  alignment: Axis.vertical,
                  icon: Icons.memory,
                  teamScore: 0,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final topContainer = tester.widget<AnimatedContainer>(
      find.byType(AnimatedContainer).at(0),
    );
    final sideContainer = tester.widget<AnimatedContainer>(
      find.byType(AnimatedContainer).at(1),
    );

    expect(topContainer.margin, const EdgeInsets.all(6));
    expect(sideContainer.margin, const EdgeInsets.all(6));
    expect(topContainer.padding, const EdgeInsets.all(8));
    expect(sideContainer.padding, const EdgeInsets.all(8));
  });

  testWidgets('horizontal player box is always square', (final tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              height: 180,
              child: OpponentDisplay(
                name: 'Opponent Top',
                cardCount: 8,
                isActive: false,
                isFinished: false,
                tichuDeclared: false,
                grandTichuDeclared: false,
                finishPosition: null,
                alignment: Axis.horizontal,
                icon: Icons.psychology_alt,
                teamScore: 0,
              ),
            ),
          ),
        ),
      ),
    );

    final boxSize = tester.getSize(
      find
          .descendant(
            of: find.byType(OpponentDisplay),
            matching: find.byType(AnimatedContainer),
          )
          .first,
    );

    expect(boxSize.width, closeTo(boxSize.height, 0.001));
  });

  testWidgets('horizontal pending cards fit available pending area', (
    final tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 280,
              height: 140,
              child: OpponentDisplay(
                name: 'Opponent Top',
                cardCount: 7,
                isActive: true,
                isFinished: false,
                tichuDeclared: false,
                grandTichuDeclared: false,
                finishPosition: null,
                alignment: Axis.horizontal,
                icon: Icons.psychology_alt,
                teamScore: 10,
                pendingCards: [
                  Card(CardFace.ace, CardColor.blue),
                  Card(CardFace.king, CardColor.red),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    final pendingRow = tester.widget<OverlappingCardRow>(
      find.byType(OverlappingCardRow),
    );
    final pendingCard = tester.getSize(
      find
          .descendant(
            of: find.byType(OverlappingCardRow),
            matching: find.byType(AnimatedContainer),
          )
          .first,
    );

    expect(pendingRow.height, isNotNull);
    expect(pendingRow.height, greaterThanOrEqualTo(pendingCard.height));
    expect(find.byType(OverflowBar), findsNothing);
  });

  testWidgets('horizontal pending cards stay visible in tight mobile layout', (
    final tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 220,
              height: 110,
              child: OpponentDisplay(
                name: 'Opponent Top',
                cardCount: 5,
                isActive: true,
                isFinished: false,
                tichuDeclared: false,
                grandTichuDeclared: false,
                finishPosition: null,
                alignment: Axis.horizontal,
                icon: Icons.psychology_alt,
                teamScore: 12,
                pendingCards: [
                  Card(CardFace.ace, CardColor.blue),
                  Card(CardFace.king, CardColor.red),
                  Card(CardFace.queen, CardColor.green),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    final pendingRow = tester.widget<OverlappingCardRow>(
      find.byType(OverlappingCardRow),
    );
    final pendingCard = tester.getSize(
      find
          .descendant(
            of: find.byType(OverlappingCardRow),
            matching: find.byType(AnimatedContainer),
          )
          .first,
    );

    expect(pendingRow.height, isNotNull);
    expect(pendingRow.height, greaterThanOrEqualTo(pendingCard.height));
    expect(tester.takeException(), isNull);
  });

  testWidgets('pending pass does not render pass text', (final tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 260,
              height: 260,
              child: OpponentDisplay(
                name: 'Opponent',
                cardCount: 8,
                isActive: false,
                isFinished: false,
                tichuDeclared: false,
                grandTichuDeclared: false,
                finishPosition: null,
                alignment: Axis.vertical,
                icon: Icons.smart_toy_outlined,
                teamScore: 0,
                pendingPass: true,
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Pass'), findsNothing);
    expect(find.text('PASS'), findsNothing);
    expect(find.text('Their turn'), findsNothing);
  });
}
