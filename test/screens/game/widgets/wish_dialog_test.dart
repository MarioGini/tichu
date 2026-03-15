import 'package:flutter/material.dart' hide Card;
import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/game/turn/tichu_data.dart';
import 'package:tichu/screens/game/widgets/wish_dialog.dart';

void main() {
  testWidgets('preselects schupf default wish instead of No wish', (
    final tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: WishDialog(defaultWish: CardFace.nine)),
      ),
    );

    final selectedChips = tester.widgetList<ChoiceChip>(
      find.byType(ChoiceChip),
    );

    final selectedLabels = selectedChips
        .where((final chip) => chip.selected)
        .map((final chip) => (chip.label as Text).data)
        .toList();

    expect(selectedLabels, equals(<String>['9']));
  });

  testWidgets('falls back to No wish for non-wishable defaults', (
    final tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: WishDialog(defaultWish: CardFace.dragon)),
      ),
    );

    final selectedChips = tester.widgetList<ChoiceChip>(
      find.byType(ChoiceChip),
    );

    final selectedLabels = selectedChips
        .where((final chip) => chip.selected)
        .map((final chip) => (chip.label as Text).data)
        .toList();

    expect(selectedLabels, equals(<String>['No wish']));
  });
}
