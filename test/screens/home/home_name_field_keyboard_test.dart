import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tichu/screens/home/home_screen.dart';

void main() {
  // Regression: opening the on-screen keyboard shrinks the body below the
  // short-screen breakpoint, which switched layouts and rebuilt the name
  // field, dropping focus and closing the keyboard again.
  testWidgets('name field keeps focus when the keyboard opens', (tester) async {
    tester.view
      ..physicalSize = const Size(412, 839) * 2
      ..devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pump();

    await tester.tap(find.byType(TextField));
    await tester.pump();
    final editable = find.byType(EditableText);
    expect(tester.widget<EditableText>(editable).focusNode.hasFocus, isTrue);

    // Keyboard takes ~330 logical px.
    tester.view.viewInsets = const FakeViewPadding(bottom: 330 * 2);
    await tester.pump();

    expect(tester.widget<EditableText>(editable).focusNode.hasFocus, isTrue);
    await tester.enterText(find.byType(TextField), 'Mario');
    expect(find.text('Mario'), findsOneWidget);

    // Dispose to stop the screen's refresh timer.
    await tester.pumpWidget(const SizedBox());
  });
}
