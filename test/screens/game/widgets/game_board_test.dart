import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/screens/game/widgets/game_board.dart';

void main() {
  testWidgets('uses same size for top and side opponent areas', (
    final tester,
  ) async {
    const topKey = Key('top-area');
    const leftKey = Key('left-area');
    const rightKey = Key('right-area');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1100,
            height: 820,
            child: GameBoard(
              topOpponent: Container(key: topKey, color: Colors.amber),
              leftOpponent: Container(key: leftKey, color: Colors.red),
              rightOpponent: Container(key: rightKey, color: Colors.blue),
              trickArea: const SizedBox.shrink(),
              handArea: const SizedBox.shrink(),
              actionBar: const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );

    final topSize = tester.getSize(find.byKey(topKey));
    final leftSize = tester.getSize(find.byKey(leftKey));
    final rightSize = tester.getSize(find.byKey(rightKey));

    expect(topSize.width, closeTo(leftSize.width, 0.001));
    expect(topSize.height, closeTo(leftSize.height, 0.001));
    expect(leftSize, rightSize);
  });

  testWidgets('uses larger trick square than side player areas', (
    final tester,
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

    expect(leftSize, rightSize);
    expect(centerSize.width, greaterThan(leftSize.width));
    expect(centerSize.height, greaterThan(leftSize.height));
  });

  testWidgets('scales on compact layout and keeps opponent sizes equal', (
    final tester,
  ) async {
    const topKey = Key('top-compact');
    const leftKey = Key('left-compact');
    const rightKey = Key('right-compact');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            height: 520,
            child: GameBoard(
              topOpponent: Container(key: topKey, color: Colors.amber),
              leftOpponent: Container(key: leftKey, color: Colors.red),
              rightOpponent: Container(key: rightKey, color: Colors.blue),
              trickArea: const SizedBox.shrink(),
              handArea: const SizedBox.shrink(),
              actionBar: const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );

    final topSize = tester.getSize(find.byKey(topKey));
    final leftSize = tester.getSize(find.byKey(leftKey));
    final rightSize = tester.getSize(find.byKey(rightKey));

    expect(topSize.width, closeTo(leftSize.width, 0.001));
    expect(topSize.height, closeTo(leftSize.height, 0.001));
    expect(leftSize, rightSize);
    expect(tester.takeException(), isNull);
  });
}
