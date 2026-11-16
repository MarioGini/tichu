// Renders the observe ("Watch AI") screen mid-round and writes PNGs:
//
//   flutter test tool/ui_preview/observe_screen_preview_test.dart --update-goldens
//
// Output: tool/ui_preview/out/observe_<device>.png (git-ignored).
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tichu/game/record/game_record_store.dart';
import 'package:tichu/screens/observe/observe_controller.dart';
import 'package:tichu/screens/observe/observe_screen.dart';
import 'package:tichu/theme/app_theme.dart';

import 'phone_screens_test.dart' show loadFonts;

const devices = <String, (Size, double)>{
  'desktop_1280x800': (Size(1280, 800), 1.0),
  'pixel7_412x915': (Size(412, 915), 2.625),
};

void main() {
  setUpAll(loadFonts);

  for (final device in devices.entries) {
    testWidgets('observe ${device.key}', (final tester) async {
      final (size, dpr) = device.value;
      tester.view
        ..physicalSize = size * dpr
        ..devicePixelRatio = dpr;
      addTearDown(tester.view.reset);

      final controller = ObserveController(
        store: InMemoryGameRecordStore(),
        phaseDelay: Duration.zero,
      );
      addTearDown(controller.dispose);
      await tester.runAsync(() async {
        await controller.start();
        for (var i = 0; i < 14 && controller.step == ObserveStep.move; i++) {
          await controller.continueGame();
        }
      });

      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: ThemeMode.dark,
          home: ObserveScreen(controller: controller),
        ),
      );
      await tester.pump();
      await tester.runAsync(() async {
        for (final element in find.byType(Image).evaluate()) {
          final widget = element.widget as Image;
          await precacheImage(widget.image, element);
        }
      });
      await tester.pump(const Duration(milliseconds: 300));
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('out/observe_${device.key}.png'),
      );
    });
  }
}
