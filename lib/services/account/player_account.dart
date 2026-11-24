import 'dart:math';

import 'package:meta/meta.dart';

/// The player using this device. Anonymous for now: created on first launch
/// and recognised on later launches without any sign-in. Linking a Google or
/// e-mail login later keeps the same [id].
@immutable
class PlayerAccount {
  const PlayerAccount({
    required this.id,
    required this.displayName,
    required this.createdAt,
    this.isAnonymous = true,
  });

  factory PlayerAccount.fromJson(final Map<String, Object?> json) {
    final id = json['id']! as String;
    if (id.replaceAll('-', '').length < 4) {
      throw FormatException('account id too short: $id');
    }
    return PlayerAccount(
      id: id,
      displayName: json['displayName']! as String,
      createdAt: DateTime.parse(json['createdAt']! as String),
      isAnonymous: json['isAnonymous'] as bool? ?? true,
    );
  }

  static const String defaultDisplayName = 'Player';

  final String id;
  final String displayName;
  final DateTime createdAt;
  final bool isAnonymous;

  /// Short form of [id] to tell accounts apart in the UI, e.g. `#3F9A`.
  String get shortId {
    final hex = id.replaceAll('-', '');
    return '#${hex.substring(0, hex.length < 4 ? hex.length : 4).toUpperCase()}';
  }

  PlayerAccount copyWith({final String? displayName}) => PlayerAccount(
    id: id,
    displayName: displayName ?? this.displayName,
    createdAt: createdAt,
    isAnonymous: isAnonymous,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'displayName': displayName,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'isAnonymous': isAnonymous,
  };

  @override
  bool operator ==(final Object other) =>
      other is PlayerAccount &&
      other.id == id &&
      other.displayName == displayName &&
      other.createdAt == createdAt &&
      other.isAnonymous == isAnonymous;

  @override
  int get hashCode => Object.hash(id, displayName, createdAt, isAnonymous);
}

/// Random (version 4) UUID.
String newAccountId([final Random? random]) {
  final r = random ?? Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final hex = b.map((final x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// Trims a display name and limits it to [maxLength] characters; empty
/// names fall back to [PlayerAccount.defaultDisplayName].
String normalizeDisplayName(final String name, {final int maxLength = 24}) {
  final trimmed = name.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (trimmed.isEmpty) return PlayerAccount.defaultDisplayName;
  // Count code points, like Postgres char_length, so an emoji is never
  // cut in half.
  final runes = trimmed.runes;
  return runes.length > maxLength
      ? String.fromCharCodes(runes.take(maxLength)).trimRight()
      : trimmed;
}
