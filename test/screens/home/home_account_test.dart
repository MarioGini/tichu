import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tichu/screens/home/home_screen.dart';
import 'package:tichu/services/account/account_service.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('home screen restores and saves the device name', (tester) async {
    tester.view
      ..physicalSize = const Size(412, 839) * 2
      ..devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    final service = LocalAccountService();
    final account = await tester.runAsync(
      () => service.updateDisplayName('Mario'),
    );

    await tester.pumpWidget(
      MaterialApp(home: HomeScreen(accountService: LocalAccountService())),
    );
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(find.text('Mario'), findsOneWidget);
    expect(find.textContaining(account!.shortId), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Mario G');
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));

    final reloaded = await tester.runAsync(() => LocalAccountService().load());
    expect(reloaded!.displayName, 'Mario G');
    expect(reloaded.id, account.id);

    // Dispose to stop the screen's refresh timer.
    await tester.pumpWidget(const SizedBox());
  });
}
