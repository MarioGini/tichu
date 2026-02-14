import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/screens/game/widgets/game_board.dart';

void main() {
  testWidgets('uses same square size for trick and side player areas', (
    tester,
  ) async {
    const leftKey = Key('left-area');
    const centerKey = Key('center-area');
    const rightKey = Key('right-area');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1200,
            height: 900,
            child: GameBoard(
              topOpponent: const SizedBox.shrink(),
              leftOpponent: Container(key: leftKey, color: Colors.red),
              rightOpponent: Container(key: rightKey, color: Colors.blue),
              trickArea: Container(key: centerKey, color: Colors.green),
              handArea: const SizedBox.shrink(),
              actionBar: const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );

    final leftSize = tester.getSize(find.byKey(leftKey));
    final centerSize = tester.getSize(find.byKey(centerKey));
    final rightSize = tester.getSize(find.byKey(rightKey));

    expect(centerSize, leftSize);
    expect(centerSize, rightSize);
  });
}
