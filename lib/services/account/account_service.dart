import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tichu/services/account/player_account.dart';
import 'package:tichu/services/supabase/supabase_app_client.dart';

/// Gives the app its [PlayerAccount]: the same one on every launch on this
/// device, created on first use without any sign-in.
abstract interface class AccountService {
  /// The account of this device, created on first call.
  Future<PlayerAccount> load();

  /// Renames the account; returns it with the normalised name.
  Future<PlayerAccount> updateDisplayName(String name);
}

/// The app's account service: Supabase (anonymous auth user + profile row)
/// when the build has a Supabase project, else this device only.
AccountService createAccountService() => supabaseConfigured
    ? SupabaseAccountService(local: LocalAccountService())
    : LocalAccountService();

/// Keeps the account in local storage (shared_preferences; localStorage on
/// web), so the device is recognised again as long as its app data is kept.
class LocalAccountService implements AccountService {
  LocalAccountService({DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  static const storageKey = 'account.local';

  final DateTime Function() _clock;
  PlayerAccount? _cached;

  @override
  Future<PlayerAccount> load() async {
    if (_cached case final account?) return account;
    final prefs = await SharedPreferences.getInstance();
    final stored = _decode(prefs.getString(storageKey));
    if (stored != null) return _cached = stored;
    return save(
      PlayerAccount(
        id: newAccountId(),
        displayName: PlayerAccount.defaultDisplayName,
        createdAt: _clock().toUtc(),
      ),
    );
  }

  @override
  Future<PlayerAccount> updateDisplayName(String name) async =>
      save((await load()).copyWith(displayName: normalizeDisplayName(name)));

  /// Stores [account] as this device's account.
  Future<PlayerAccount> save(PlayerAccount account) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(storageKey, jsonEncode(account.toJson()));
    return _cached = account;
  }

  static PlayerAccount? _decode(String? raw) {
    if (raw == null) return null;
    try {
      return PlayerAccount.fromJson(
        Map<String, Object?>.from(jsonDecode(raw) as Map),
      );
    } on Object catch (_) {
      // A corrupt entry is replaced by a new account rather than crashing.
      return null;
    }
  }
}

/// Uses the Supabase anonymous auth user as the account: supabase_flutter
/// keeps its session on the device, so the same user comes back on every
/// launch. The display name lives in `public.tichu_profiles` (see
/// `supabase/migrations/*_tichu_profiles.sql`) and is mirrored locally, so
/// the app still starts with the right name when offline.
class SupabaseAccountService implements AccountService {
  SupabaseAccountService({
    required this.local,
    Future<SupabaseClient> Function()? client,
  }) : _client = client ?? appSupabaseClient;

  static const table = 'tichu_profiles';

  final LocalAccountService local;
  final Future<SupabaseClient> Function() _client;

  /// Error of the last server call, null after a successful one.
  Object? lastError;

  /// Set while a rename has not reached the server (e.g. made offline);
  /// the next [load] then pushes the device's name instead of taking the
  /// server's.
  static const pendingNameKey = 'account.namePending';

  /// Runs [load] and [updateDisplayName] one at a time, so a rename made
  /// while the account is still loading is not overwritten by the load.
  Future<void> _queue = Future<void>.value();

  Future<T> _serial<T>(Future<T> Function() op) {
    final result = _queue.then((_) => op());
    _queue = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  @override
  Future<PlayerAccount> load() => _serial(_load);

  @override
  Future<PlayerAccount> updateDisplayName(String name) =>
      _serial(() => _updateDisplayName(name));

  Future<PlayerAccount> _load() async {
    final device = await local.load();
    try {
      final client = await _client();
      final user = client.auth.currentUser;
      if (user == null) return device;
      final prefs = await SharedPreferences.getInstance();
      final pending = prefs.getBool(pendingNameKey) ?? false;
      final row = await client
          .from(table)
          .select('display_name, created_at')
          .eq('id', user.id)
          .maybeSingle();
      final serverName = row?['display_name'] as String?;
      final account = PlayerAccount(
        id: user.id,
        displayName: pending || serverName == null
            ? device.displayName
            : serverName,
        createdAt: switch (row?['created_at']) {
          final String at => DateTime.parse(at),
          _ => DateTime.parse(user.createdAt),
        },
        isAnonymous: user.isAnonymous,
      );
      if (row == null || pending) {
        // Upsert: two first launches racing must not fail on the key.
        await client.from(table).upsert({
          'id': user.id,
          'display_name': account.displayName,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        });
        await prefs.remove(pendingNameKey);
      }
      lastError = null;
      return await local.save(account);
    } on Object catch (error) {
      // Offline or misconfigured: keep playing with the device account.
      lastError = error;
      return device;
    }
  }

  Future<PlayerAccount> _updateDisplayName(String name) async {
    final account = await local.updateDisplayName(name);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(pendingNameKey, true);
    try {
      final client = await _client();
      final user = client.auth.currentUser;
      if (user != null) {
        await client.from(table).upsert({
          'id': user.id,
          'display_name': account.displayName,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        });
        await prefs.remove(pendingNameKey);
      }
      lastError = null;
    } on Object catch (error) {
      lastError = error;
    }
    return account;
  }
}
