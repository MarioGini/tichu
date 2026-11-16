import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tichu/game/record/game_record_store.dart';
import 'package:tichu/screens/observe/observe_controller.dart';
import 'package:tichu/screens/observe/observe_screen.dart';

void main() {
  testWidgets('shows all hands and steps on Continue', (final tester) async {
    tester.view
      ..physicalSize = const Size(1280, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final controller = ObserveController(
      store: InMemoryGameRecordStore(),
      phaseDelay: Duration.zero,
    );
    addTearDown(controller.dispose);
    await tester.runAsync(controller.start);

    await tester.pumpWidget(
      MaterialApp(home: ObserveScreen(controller: controller)),
    );
    await tester.pump();

    expect(controller.step, ObserveStep.move);
    for (final name in ['Bot 1', 'Bot 2', 'Bot 3', 'Bot 4']) {
      expect(find.text(name), findsOneWidget);
    }
    expect(
      find.textContaining('#${controller.record!.events.length + 1}'),
      findsOneWidget,
    );

    final before = controller.record!.events.length;
    await tester.runAsync(() async {
      await tester.tap(find.text('Continue'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    expect(controller.record!.events.length, greaterThan(before));
  });
}
