import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../../../core/storage/cache_storage.dart';
import '../../../core/utils/async_lock.dart';
import '../domain/models/match_history.dart';

class MatchHistoryLocalCache {
  final CacheStorage _cache;
  const MatchHistoryLocalCache(this._cache);

  String _cacheKey(String? queue) =>
      queue == null || queue.isEmpty ? 'all' : queue;

  Future<void> saveHistory(MatchHistoryResult result,
      {String? queue,
      required String puuid,
      required CacheTransaction transaction}) async {
    // The history blob is stored per-user; a stale write from a request that
    // was in-flight during an account switch must never land here.
    final baseKey =
        CacheStorage.userKeyFor(CacheStorage.keyMatchHistoryCache, puuid);
    await _cache.runUserTransaction(transaction, () async {
      await AsyncLock.run('match_history_cache/$puuid', () async {
        final all = await _cache.getJson(baseKey) ?? {};
        all[_cacheKey(queue)] = {
          'Subject': result.puuid,
          'Total': result.total,
          'BeginIndex': result.start,
          'EndIndex': result.end,
          'History': result.matches
              .map((e) => {
                    'MatchID': e.matchId,
                    'GameStartTime': e.gameStartMillis,
                    'QueueID': e.queueId,
                    'TeamID': e.teamId,
                    'IsRanked': e.isRanked,
                    'MapID': e.mapId,
                  })
              .toList(),
        };
        await _cache.setJson(baseKey, all);
        await _cache.setTimestamp(CacheStorage.userKeyFor(
            CacheStorage.keyMatchHistoryCacheFetchedAt, puuid));
      });
    });
  }

  Future<MatchHistoryResult?> loadHistory(
      {String? queue, required String puuid}) async {
    final all = await _cache.getJson(
        CacheStorage.userKeyFor(CacheStorage.keyMatchHistoryCache, puuid));
    if (all == null) return null;
    final value = all[_cacheKey(queue)];
    if (value is! Map) return null;
    try {
      return MatchHistoryResult.fromJson(Map<String, dynamic>.from(value));
    } catch (e) {
      debugPrint(
          '[MatchHistoryLocalCache] Error parsing cached MatchHistoryResult: $e');
      all.remove(_cacheKey(queue));
      if (all.isEmpty) {
        await _cache.remove(
            CacheStorage.userKeyFor(CacheStorage.keyMatchHistoryCache, puuid));
      } else {
        await _cache.setJson(
            CacheStorage.userKeyFor(CacheStorage.keyMatchHistoryCache, puuid),
            all);
      }
      return null;
    }
  }
}

class MatchDetailLocalCache {
  MatchDetailLocalCache(
    this._cache, {
    Future<Directory?> Function()? baseDirResolver,
  }) : _baseDirResolver = baseDirResolver ?? _defaultBaseDir;

  final CacheStorage _cache;
  final Future<Directory?> Function() _baseDirResolver;
  Future<Directory?>? _resolvedBaseDir;

  static const _rootDirName = 'match_details';
  static const _maxEntries = 30;
  static final RegExp _segmentPattern = RegExp(r'^[A-Za-z0-9\-]{1,128}$');

  /// Platform support directory; null when unavailable (e.g. unit-test env
  /// without path_provider mocks) — callers then transparently fall back to
  /// the legacy namespaced SharedPreferences blob.
  static Future<Directory?> _defaultBaseDir() async {
    try {
      return await getApplicationSupportDirectory();
    } catch (_) {
      return null;
    }
  }

  Future<Directory?> _dirFor(String puuid) async {
    final base = await (_resolvedBaseDir ??= _baseDirResolver());
    if (base == null || !_segmentPattern.hasMatch(puuid)) return null;
    final dir = Directory(
        '${base.path}${Platform.pathSeparator}$_rootDirName${Platform.pathSeparator}$puuid');
    try {
      await dir.create(recursive: true);
      return dir;
    } catch (_) {
      return null;
    }
  }

  File _fileFor(Directory dir, String matchId) =>
      File('${dir.path}${Platform.pathSeparator}$matchId.json');

  Future<void> saveMatchDetail(String matchId, Map<String, dynamic> raw,
      {required String puuid, required CacheTransaction transaction}) async {
    final key =
        CacheStorage.userKeyFor(CacheStorage.keyMatchDetailCache, puuid);
    await _cache.runUserTransaction(transaction, () async {
      await AsyncLock.run('match_detail_cache/$puuid', () async {
        final encoded = jsonEncode(raw);

        // Preferred storage: one JSON file per match under the account's own
        // directory. A single SharedPreferences blob holding ~30 full match
        // details forced a complete rewrite of a multi-hundred-KB string on
        // EVERY save and loaded all of it at app startup.
        final dir = await _dirFor(puuid);
        if (dir != null && _segmentPattern.hasMatch(matchId)) {
          try {
            final file = _fileFor(dir, matchId);
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
            await _evictOldest(dir);
            return;
          } catch (e) {
            debugPrint(
                '[MatchDetailLocalCache] File write failed, using prefs blob: $e');
          }
        }

        // Fallback / legacy path: single namespaced prefs blob.
        final all = await _cache.getJson(key) ?? {};
        final isNew = !all.containsKey(matchId);
        all[matchId] = raw;
        if (isNew && all.length > _maxEntries) {
          final toRemove = all.length - _maxEntries;
          for (final k in all.keys.take(toRemove).toList()) {
            all.remove(k);
          }
        }
        await _cache.setJson(key, all);
      });
    });
  }

  /// Keeps only the newest [_maxEntries] files in [dir] by modified time.
  Future<void> _evictOldest(Directory dir) async {
    try {
      final files = <File>[];
      await for (final entity in dir.list()) {
        if (entity is File && entity.path.endsWith('.json')) {
          files.add(entity);
        }
      }
      if (files.length <= _maxEntries) return;
      int lastModified(File f) {
        try {
          return f.lastModifiedSync().millisecondsSinceEpoch;
        } catch (_) {
          return 0;
        }
      }

      files.sort((a, b) => lastModified(a).compareTo(lastModified(b)));
      for (final f in files.take(files.length - _maxEntries)) {
        try {
          await f.delete();
        } catch (_) {}
      }
    } catch (_) {}
  }

  Future<Map<String, dynamic>?> loadMatchDetailRaw(String matchId,
      {required String puuid}) async {
    // Preferred: per-match file.
    final dir = await _dirFor(puuid);
    if (dir != null && _segmentPattern.hasMatch(matchId)) {
      try {
        final file = _fileFor(dir, matchId);
        if (await file.exists()) {
          final decoded = jsonDecode(await file.readAsString());
          if (decoded is Map<String, dynamic>) return decoded;
          if (decoded is Map) return Map<String, dynamic>.from(decoded);
        }
      } catch (e) {
        debugPrint('[MatchDetailLocalCache] File read failed: $e');
      }
    }

    // Fallback / legacy pre-migration prefs blob (read-only).
    final all = await _cache.getJson(
        CacheStorage.userKeyFor(CacheStorage.keyMatchDetailCache, puuid));
    if (all == null) return null;
    final raw = all[matchId];
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return null;
  }

  /// Removes EVERY stored detail for [puuid] — file tree AND legacy blob.
  /// Called when an account is removed from Multi-Account Manager so deleted
  /// accounts leave no orphaned data on disk.
  Future<void> purgeAccount(String puuid) async {
    try {
      final base = await (_resolvedBaseDir ??= _baseDirResolver());
      if (base != null && _segmentPattern.hasMatch(puuid)) {
        final dir = Directory(
            '${base.path}${Platform.pathSeparator}$_rootDirName${Platform.pathSeparator}$puuid');
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      }
    } catch (_) {}
    await _cache.remove(
        CacheStorage.userKeyFor(CacheStorage.keyMatchDetailCache, puuid));
  }
}
