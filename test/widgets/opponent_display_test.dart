import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' hide Card;
import 'package:tichu/widgets/opponent_display.dart';

void main() {
  testWidgets('grand tichu uses badge without coloring whole player box', (
    tester,
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

  testWidgets('player box is always square', (tester) async {
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
}
