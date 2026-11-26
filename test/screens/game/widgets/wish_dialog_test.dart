import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' hide Card;
import 'package:tichu/game/turn/tichu_data.dart';
import 'package:tichu/screens/game/widgets/wish_dialog.dart';

void main() {
  testWidgets('preselects schupf default wish instead of No wish', (
    tester,
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
        .where((chip) => chip.selected)
        .map((chip) => (chip.label as Text).data)
        .toList();

    expect(selectedLabels, equals(<String>['9']));
  });

  testWidgets('falls back to No wish for non-wishable defaults', (
    tester,
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
        .where((chip) => chip.selected)
        .map((chip) => (chip.label as Text).data)
        .toList();

    expect(selectedLabels, equals(<String>['No wish']));
  });
}
