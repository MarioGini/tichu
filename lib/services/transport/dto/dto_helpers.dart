T enumByName<T extends Enum>(final List<T> values, final String name) =>
    values.firstWhere((final value) => value.name == name);

List<Map<String, dynamic>> decodeMapList(final Object? json) =>
    (json as List? ?? const <Object>[])
        .map((final item) => Map<String, dynamic>.from(item as Map))
        .toList();

List<String> decodeStringList(final Object? json) =>
    (json as List? ?? const <Object>[])
        .map((final item) => item as String)
        .toList();

Map<String, int> decodeIntMap(final Object? json) =>
    Map<String, int>.fromEntries(
      (json as Map? ?? const <Object, Object>{}).entries.map(
        (final entry) =>
            MapEntry(entry.key as String, (entry.value as num).toInt()),
      ),
    );

Map<String, bool> decodeBoolMap(final Object? json) =>
    Map<String, bool>.fromEntries(
      (json as Map? ?? const <Object, Object>{}).entries.map(
        (final entry) => MapEntry(entry.key as String, entry.value as bool),
      ),
    );

Map<String, String> decodeStringMap(final Object? json) =>
    Map<String, String>.fromEntries(
      (json as Map? ?? const <Object, Object>{}).entries.map(
        (final entry) => MapEntry(entry.key as String, entry.value as String),
      ),
    );

T? decodeNullableMap<T>(
  final Object? json,
  final T Function(Map<String, dynamic> json) decode,
) {
  if (json == null) {
    return null;
  }
  return decode(Map<String, dynamic>.from(json as Map));
}
