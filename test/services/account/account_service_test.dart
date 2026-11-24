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

  test('an offline rename is marked pending for the next sync', () async {
    final service = SupabaseAccountService(
      local: LocalAccountService(),
      client: () => Future.error(StateError('offline')),
    );
    await service.updateDisplayName('Mario');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(SupabaseAccountService.pendingNameKey), isTrue);
    // The device keeps the new name, offline loads return it.
    expect((await service.load()).displayName, 'Mario');
  });

  test('load and rename run one at a time, in call order', () async {
    final service = SupabaseAccountService(
      local: LocalAccountService(),
      client: () => Future.error(StateError('offline')),
    );
    final loading = service.load();
    final renaming = service.updateDisplayName('Anna');
    await Future.wait([loading, renaming]);
    expect((await LocalAccountService().load()).displayName, 'Anna');
  });

  test('names are cut by code point, never inside an emoji', () {
    final name = '${'a' * 23}\u{1F600}b';
    expect(normalizeDisplayName(name), '${'a' * 23}\u{1F600}');
  });

  test('a stored account with a too short id is replaced', () async {
    SharedPreferences.setMockInitialValues({
      LocalAccountService.storageKey:
          '{"id":"ab","displayName":"x","createdAt":"2026-01-01T00:00:00Z"}',
    });
    final account = await LocalAccountService().load();
    expect(account.id, hasLength(36));
    expect(account.shortId, hasLength(5));
  });
}
