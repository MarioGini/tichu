/// The value of [values] named [name]; [FormatException] for an unknown
/// name (the JSON came from a client).
T enumByName<T extends Enum>(List<T> values, String name) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  throw FormatException('Unknown $T: $name');
}

List<Map<String, dynamic>> decodeMapList(Object? json) =>
    (json as List? ?? const <Object>[])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();

List<String> decodeStringList(Object? json) =>
    (json as List? ?? const <Object>[]).map((item) => item as String).toList();

Map<String, int> decodeIntMap(Object? json) => Map<String, int>.fromEntries(
  (json as Map? ?? const <Object, Object>{}).entries.map(
    (entry) => MapEntry(entry.key as String, (entry.value as num).toInt()),
  ),
);

Map<String, bool> decodeBoolMap(Object? json) => Map<String, bool>.fromEntries(
  (json as Map? ?? const <Object, Object>{}).entries.map(
    (entry) => MapEntry(entry.key as String, entry.value as bool),
  ),
);

Map<String, String> decodeStringMap(Object? json) =>
    Map<String, String>.fromEntries(
      (json as Map? ?? const <Object, Object>{}).entries.map(
        (entry) => MapEntry(entry.key as String, entry.value as String),
      ),
    );

T? decodeNullableMap<T>(
  Object? json,
  T Function(Map<String, dynamic> json) decode,
) {
  if (json == null) {
    return null;
  }
  return decode(Map<String, dynamic>.from(json as Map));
}
