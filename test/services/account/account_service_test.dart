import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tichu/services/account/account_service.dart';
import 'package:tichu/services/account/player_account.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('LocalAccountService', () {
    test(
      'creates an account once and finds it again on the next launch',
      () async {
        final first = await LocalAccountService().load();
        expect(first.displayName, PlayerAccount.defaultDisplayName);
        expect(first.isAnonymous, isTrue);
        expect(
          first.id,
          matches(
            RegExp(
              '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-'
              r'[0-9a-f]{12}$',
            ),
          ),
        );

        // A new service instance stands for the next app launch.
        final again = await LocalAccountService().load();
        expect(again, first);
      },
    );

    test('renames and keeps the id', () async {
      final service = LocalAccountService();
      final before = await service.load();
      final renamed = await service.updateDisplayName('  Mario   G  ');
      expect(renamed.displayName, 'Mario G');
      expect(renamed.id, before.id);
      expect((await LocalAccountService().load()).displayName, 'Mario G');
    });

    test('empty names fall back to the default, long ones are cut', () {
      expect(normalizeDisplayName('   '), PlayerAccount.defaultDisplayName);
      expect(normalizeDisplayName('x' * 40), 'x' * 24);
    });

    test('a corrupt entry is replaced by a new account', () async {
      SharedPreferences.setMockInitialValues({
        LocalAccountService.storageKey: '{not json',
      });
      final account = await LocalAccountService().load();
      final prefs = await SharedPreferences.getInstance();
      final stored =
          jsonDecode(prefs.getString(LocalAccountService.storageKey)!) as Map;
      expect(stored['id'], account.id);
    });
  });

  test('shortId is the first four hex digits', () {
    final account = PlayerAccount(
      id: '3f9a1c2e-0000-4000-8000-000000000000',
      displayName: 'A',
      createdAt: DateTime(2026),
    );
    expect(account.shortId, '#3F9A');
  });

  test(
    'SupabaseAccountService falls back to the device account offline',
    () async {
      final local = LocalAccountService();
      final service = SupabaseAccountService(
        local: local,
        client: () => Future.error(StateError('offline')),
      );
      final account = await service.load();
      expect(account, await local.load());
      expect(service.lastError, isA<StateError>());

      final renamed = await service.updateDisplayName('Anna');
      expect(renamed.displayName, 'Anna');
      expect((await local.load()).displayName, 'Anna');
    },
  );
}
