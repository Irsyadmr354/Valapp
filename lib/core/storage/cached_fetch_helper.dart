import 'cache_storage.dart';
import 'cached_fetch_result.dart';

/// Shared fetch-cache pipeline for the account-data providers
/// (CQ-04 / ARCH-03): fetches fresh raw JSON, parses it, persists it under
/// the user-scoped [CacheTransaction], guards against an account switch
/// while the request is in flight, and falls back to [loadCached] when the
/// network path throws.
///
/// Returns `null` only when the active session changed mid-fetch; callers
/// map that to their own empty/absent state. Rethrows when both the fetch
/// and the cached fallback fail.
Future<CachedFetchResult<T>?> cachedFetch<T>({
  required String puuid,
  required CacheStorage cache,
  required Future<Map<String, dynamic>> Function() fetchRaw,
  required T Function(Map<String, dynamic>) fromJson,
  required Future<void> Function(Map<String, dynamic>, CacheTransaction)
      saveRaw,
  required Future<T?> Function() loadCached,
}) async {
  final transaction = cache.beginUserTransaction(puuid);
  try {
    final raw = await fetchRaw();
    final value = fromJson(raw);
    if (transaction != null) {
      await saveRaw(raw, transaction);
    }
    if (!cache.isActiveSession(puuid)) {
      return null;
    }
    return CachedFetchResult(value);
  } catch (_) {
    final value = await loadCached();
    if (value != null) return CachedFetchResult(value, fromCache: true);
    rethrow;
  }
}
