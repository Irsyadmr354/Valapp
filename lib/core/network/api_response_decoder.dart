import 'dart:convert';
import '../exceptions/api_exception.dart';

/// Strict decoder for 2xx response bodies coming from Riot's `pvp.net` APIs.
///
/// The old per-source `_toMap` helpers silently returned `{}` for any body they
/// could not parse (HTML error pages, truncated JSON, a JSON list, an empty
/// string, ...). That empty map was then stored in the local cache as if it
/// were fresh, valid data, so malformed responses poisoned the cache.
///
/// This decoder never returns a placeholder. It either returns the decoded
/// object or throws [ApiException], which lets callers fall back to their cache
/// (or show an error) instead of persisting garbage.
class ApiResponseDecoder {
  const ApiResponseDecoder._();

  /// Decodes [data] into a non-empty [Map].
  ///
  /// Throws [ApiException] when:
  /// - the body is `null`, empty, or not a Map (e.g. a List or primitive);
  /// - a String body is not valid JSON;
  /// - the decoded JSON is an empty map (invalid for every Valorant endpoint
  ///   this decoder is used with).
  static Map<String, dynamic> decodeMap(dynamic data, {String? source}) {
    final label = source == null ? 'response' : 'response from $source';

    if (data is Map<String, dynamic>) {
      if (data.isEmpty) throw ApiException('Empty $label');
      return data;
    }
    if (data is Map) {
      final map = Map<String, dynamic>.from(data);
      if (map.isEmpty) throw ApiException('Empty $label');
      return map;
    }
    if (data is String) {
      final trimmed = data.trim();
      if (trimmed.isEmpty) throw ApiException('Empty $label');
      dynamic decoded;
      try {
        decoded = jsonDecode(trimmed);
      } catch (_) {
        throw ApiException('Malformed JSON $label');
      }
      if (decoded is Map<String, dynamic>) {
        if (decoded.isEmpty) throw ApiException('Empty $label');
        return decoded;
      }
      if (decoded is Map) {
        final map = Map<String, dynamic>.from(decoded);
        if (map.isEmpty) throw ApiException('Empty $label');
        return map;
      }
      throw ApiException('Unexpected JSON shape (not an object) in $label');
    }
    if (data == null) throw ApiException('Empty $label');
    throw ApiException('Unexpected $label body type: ${data.runtimeType}');
  }

  /// Decodes [data] into a [List]. Empty lists are accepted because several
  /// Riot endpoints legitimately return no results.
  static List<dynamic> decodeList(dynamic data, {String? source}) {
    final label = source == null ? 'response' : 'response from $source';
    dynamic decoded = data;
    if (data is String) {
      final trimmed = data.trim();
      if (trimmed.isEmpty) throw ApiException('Empty $label');
      try {
        decoded = jsonDecode(trimmed);
      } catch (_) {
        throw ApiException('Malformed JSON $label');
      }
    }
    if (decoded is List) return List<dynamic>.from(decoded);
    if (decoded == null) throw ApiException('Empty $label');
    throw ApiException('Unexpected JSON shape (not an array) in $label');
  }

  /// Ensures required response fields have the expected container types.
  /// This is intentionally endpoint-specific: a non-empty JSON object alone
  /// is not enough evidence that it is safe to cache.
  static Map<String, dynamic> requireShape(
    Map<String, dynamic> data, {
    required String source,
    List<String> maps = const [],
    List<String> lists = const [],
    List<String> strings = const [],
  }) {
    for (final key in maps) {
      if (data[key] is! Map) _invalidField(source, key, 'object');
    }
    for (final key in lists) {
      if (data[key] is! List) _invalidField(source, key, 'array');
    }
    for (final key in strings) {
      if (data[key] is! String || (data[key] as String).isEmpty) {
        _invalidField(source, key, 'non-empty string');
      }
    }
    return data;
  }

  static Never _invalidField(String source, String key, String expected) {
    throw ApiException(
      'Invalid response from $source: "$key" must be a $expected',
    );
  }
}
