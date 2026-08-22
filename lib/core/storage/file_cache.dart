import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One JSON file per key under the app-support directory.
///
/// SharedPreferences rewrites its ENTIRE backing file on every write, so
/// storing multi-MB blobs (skin metadata, unified store items, bundles) there
/// forced a full-file rewrite on each refresh and loaded all of it at startup.
/// [FileCache] writes each key to its own JSON file with an atomic
/// tmp+rename (same pattern as `MatchDetailLocalCache`), so a small metadata
/// update never touches unrelated keys.
///
/// Migration: if the file for [key] does not exist yet, reads fall back to the
/// legacy SharedPreferences blob (read-only). The next successful write goes
/// to the file and best-effort removes the legacy prefs entry, so prefs pays
/// the multi-MB rewrite at most once more before shrinking back.
class FileCache {
  FileCache._();
  static final FileCache instance = FileCache._();

  static const _rootDirName = 'file_cache';
  static final RegExp _segmentPattern = RegExp(r'^[A-Za-z0-9_\-]{1,128}$');

  /// Platform support directory; null when unavailable (e.g. unit-test env
  /// without path_provider mocks) — callers then transparently fall back to
  /// the legacy SharedPreferences blob.
  Future<Directory?>? _resolvedBaseDir;

  static Future<Directory?> _defaultBaseDir() async {
    try {
      return await getApplicationSupportDirectory();
    } catch (_) {
      return null;
    }
  }

  Future<Directory?> _dir() async {
    final base = await (_resolvedBaseDir ??= _defaultBaseDir());
    return base;
  }

  File _fileFor(Directory base, String key) {
    // Keys here are simple ASCII constants ('skin_metadata_v5', ...), but be
    // defensive: anything outside the safe segment charset maps to '_'.
    final safe = _segmentPattern.hasMatch(key) ? key : key.replaceAll(RegExp(r'[^A-Za-z0-9_\-]'), '_');
    return File('${base.path}${Platform.pathSeparator}$_rootDirName${Platform.pathSeparator}$safe.json');
  }

  /// Reads the JSON map stored under [key], preferring the per-key file and
  /// falling back to the legacy SharedPreferences blob while it still exists.
  Future<Map<String, dynamic>?> getJson(String key) async {
    final base = await _dir();
    if (base != null) {
      try {
        final file = _fileFor(base, key);
        if (await file.exists()) {
          final decoded = jsonDecode(await file.readAsString());
          if (decoded is Map<String, dynamic>) return decoded;
          if (decoded is Map) return Map<String, dynamic>.from(decoded);
          return null;
        }
      } catch (e) {
        debugPrint('[FileCache] File read failed for $key: $e');
      }
    }

    // Legacy / pre-migration path: single SharedPreferences entry.
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      if (raw == null) return null;
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Atomically persists [value] as the JSON file for [key]. When the file
  /// write is unavailable, falls back to the legacy SharedPreferences blob.
  Future<void> setJson(String key, Object value) async {
    final encoded = jsonEncode(value);
    final base = await _dir();
    if (base != null) {
      try {
        await base.create(recursive: true);
        final file = _fileFor(base, key);
        final tmp = File('${file.path}.tmp');
        await tmp.writeAsString(encoded, flush: true);
        try {
          await tmp.rename(file.path);
        } catch (_) {
          // rename can fail across some FS setups — write directly.
          await file.writeAsString(encoded, flush: true);
          try {
            await tmp.delete();
          } catch (_) {}
        }
        // Migration complete — drop the legacy prefs blob so SharedPreferences
        // no longer pays the multi-MB full-file rewrite cost for this key.
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.remove(key);
        } catch (_) {}
        return;
      } catch (e) {
        debugPrint('[FileCache] File write failed for $key, using prefs: $e');
      }
    }

    // Fallback: legacy SharedPreferences write.
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, encoded);
    } catch (_) {}
  }
}
