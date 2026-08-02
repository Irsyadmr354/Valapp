import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/async_lock.dart';

/// Lightweight cache using [SharedPreferences] for non-sensitive data
/// (skin metadata, client version, last-fetch timestamps, etc.).
class CacheStorage {
  CacheStorage._();
  static final CacheStorage instance = CacheStorage._();

  // Cached SharedPreferences instance — initialised once and reused.
  // SharedPreferences.getInstance() is internally synchronous after the first
  // call, but caching it here removes the async overhead on every single
  // read/write and makes call-sites cleaner.
  SharedPreferences? _prefs;

  Future<SharedPreferences> _getPrefs() async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  // ── Key Constants ──────────────────────────────────────────────────────────
  static const keyClientVersion = 'client_version';
  static const keyClientVersionFetchedAt = 'client_version_fetched_at';
  static const keyDailyShop = 'daily_shop';
  static const keyDailyShopFetchedAt = 'daily_shop_fetched_at';
  static const keySkinMetadata = 'skin_metadata_v2';
  static const keySkinMetadataFetchedAt = 'skin_metadata_v2_fetched_at';
  static const keyCompetitiveTiers = 'competitive_tiers';
  static const keyCompetitiveTiersFetchedAt = 'competitive_tiers_fetched_at';
  static const keyWishlist = 'wishlist_skin_ids';
  static const keyLastShopReset = 'last_shop_reset';

  // Feature response caches (non-sensitive)
  static const keyMmrCache = 'mmr_cache';
  static const keyMmrCacheFetchedAt = 'mmr_cache_fetched_at';
  static const keyCompetitiveUpdatesCache = 'competitive_updates_cache';
  static const keyCompetitiveUpdatesCacheFetchedAt =
      'competitive_updates_cache_fetched_at';
  static const keyMatchHistoryCache = 'match_history_cache';
  static const keyMatchHistoryCacheFetchedAt = 'match_history_cache_fetched_at';
  static const keyMatchDetailCache = 'match_detail_cache';
  static const keyAccountXpCache = 'account_xp_cache';
  static const keyAccountXpCacheFetchedAt = 'account_xp_cache_fetched_at';
  static const keyDisplayNameCache = 'display_name_cache';
  static const keyDisplayNameCacheFetchedAt = 'display_name_cache_fetched_at';
  static const keyContractsCache = 'contracts_cache';
  static const keyContractsCacheFetchedAt = 'contracts_cache_fetched_at';

  // ── String ─────────────────────────────────────────────────────────────────

  Future<void> setString(String key, String value) async {
    final prefs = await _getPrefs();
    await prefs.setString(key, value);
  }

  Future<String?> getString(String key) async {
    final prefs = await _getPrefs();
    return prefs.getString(key);
  }

  // ── JSON ───────────────────────────────────────────────────────────────────

  Future<void> setJson(String key, Object value) async {
    final prefs = await _getPrefs();
    await prefs.setString(key, jsonEncode(value));
  }

  Future<Map<String, dynamic>?> getJson(String key) async {
    final prefs = await _getPrefs();
    final raw = prefs.getString(key);
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<List<dynamic>?> getJsonList(String key) async {
    final prefs = await _getPrefs();
    final raw = prefs.getString(key);
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as List<dynamic>;
    } catch (_) {
      return null;
    }
  }

  // ── Timestamp helpers ──────────────────────────────────────────────────────

  Future<void> setTimestamp(String key) async {
    final prefs = await _getPrefs();
    await prefs.setString(key, DateTime.now().toIso8601String());
  }

  Future<bool> isStale(String timestampKey, Duration maxAge) async {
    final prefs = await _getPrefs();
    final raw = prefs.getString(timestampKey);
    if (raw == null) return true;
    try {
      final ts = DateTime.parse(raw);
      return DateTime.now().isAfter(ts.add(maxAge));
    } catch (_) {
      return true;
    }
  }

  // ── Wishlist ───────────────────────────────────────────────────────────────

  Future<List<String>> getWishlist() async {
    final prefs = await _getPrefs();
    return prefs.getStringList(keyWishlist) ?? [];
  }

  Future<void> setWishlist(List<String> skinIds) async {
    final prefs = await _getPrefs();
    await prefs.setStringList(keyWishlist, skinIds);
  }

  Future<void> addToWishlist(String skinId) async {
    final list = await getWishlist();
    if (!list.contains(skinId)) {
      list.add(skinId);
      await setWishlist(list);
    }
  }

  Future<void> removeFromWishlist(String skinId) async {
    final list = await getWishlist();
    list.remove(skinId);
    await setWishlist(list);
  }

  // ── Match Map Cache ────────────────────────────────────────────────────────

  static const keyMatchMapCache = 'match_map_cache';

  Future<Map<String, String>> getMatchMaps() async {
    final cached = await getJson(keyMatchMapCache);
    if (cached == null) return {};
    return cached.map((k, v) => MapEntry(k, v.toString()));
  }

  Future<void> saveMatchMap(String matchId, String mapId) async {
    if (matchId.isEmpty || mapId.isEmpty) return;
    await AsyncLock.run('cache_match_map', () async {
      final current = await getMatchMaps();
      current[matchId] = mapId;
      await setJson(keyMatchMapCache, current);
    });
  }

  // ── Remove ─────────────────────────────────────────────────────────────────

  Future<void> remove(String key) async {
    final prefs = await _getPrefs();
    await prefs.remove(key);
  }

  /// Wipes user-specific cached responses upon account switch
  /// so old account data is not served to the new account.
  Future<void> clearUserCache() async {
    final keys = [
      keyDailyShop,
      keyDailyShopFetchedAt,
      keyMmrCache,
      keyMmrCacheFetchedAt,
      keyCompetitiveUpdatesCache,
      keyCompetitiveUpdatesCacheFetchedAt,
      keyMatchHistoryCache,
      keyMatchHistoryCacheFetchedAt,
      keyMatchDetailCache,
      keyAccountXpCache,
      keyAccountXpCacheFetchedAt,
      keyDisplayNameCache,
      keyDisplayNameCacheFetchedAt,
      keyContractsCache,
      keyContractsCacheFetchedAt,
      'player_loadout',
      // Background shop checker state — must be cleared on account switch so
      // the new account's first shop check always fires a reset notification.
      'background_last_shop_ids',
    ];
    for (final k in keys) {
      await remove(k);
    }
  }

  Future<void> clearAll() async {
    final prefs = await _getPrefs();
    await prefs.clear();
    // Reset cached instance so next access re-reads from disk.
    _prefs = null;
  }
}
