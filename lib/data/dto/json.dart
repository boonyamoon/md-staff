/// Small readers used by every DTO's `fromJson`.
///
/// The app hand-writes its JSON instead of generating it: `json_serializable` cannot resolve
/// against this Flutter SDK's pinned `test` package, and these models are simple enough that a
/// factory per class is clearer than a build step anyway. Each reader is tolerant in the one way
/// that matters against a live API — a field that is absent, null or the wrong shape produces the
/// documented default rather than a crash in front of a waiter mid-service.
library;

String asString(Object? value, {String fallback = ''}) =>
    value is String ? value : (value == null ? fallback : value.toString());

String? asStringOrNull(Object? value) {
  if (value is String) return value.isEmpty ? null : value;
  return null;
}

int asInt(Object? value, {int fallback = 0}) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}

int? asIntOrNull(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

num asNum(Object? value, {num fallback = 0}) {
  if (value is num) return value;
  if (value is String) return num.tryParse(value) ?? fallback;
  return fallback;
}

bool asBool(Object? value, {bool fallback = false}) {
  if (value is bool) return value;
  if (value is String) {
    if (value == 'true') return true;
    if (value == 'false') return false;
  }
  return fallback;
}

Map<String, dynamic>? asMapOrNull(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : null;

/// Maps a JSON array of objects, skipping anything that is not an object.
List<T> asList<T>(Object? value, T Function(Map<String, dynamic>) parse) {
  if (value is! List) return <T>[];
  return value
      .whereType<Map<Object?, Object?>>()
      .map((e) => parse(Map<String, dynamic>.from(e)))
      .toList();
}
