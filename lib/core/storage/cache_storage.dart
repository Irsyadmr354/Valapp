import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Lightweight cache using [SharedPreferences] for non-sensitive data
/// (skin metadata, client version, last-fetch timestamps, etc.).
class CacheStorage {
  CacheStorage._();
  static final CacheStorage instance = CacheStorage._();

  // ── Key Constants ──────────────────────────────────────────────────────────
  static const keyClientVersion = 'client_version';
  static const keyClientVersionFetchedAt = 'client_version_fetched_at';
  static const keyDailyShop = 'daily_shop';
  static const keyDailyShopFetchedAt = 'daily_shop_fetched_at';
  static const keySkinMetadata = 'skin_metadata_v2';
  static const keySkinMetadataFetchedAt = 'skin_metadata_v2_fetched_at';
  static const keyContentTiers = 'content_tiers';
  static const keyContentTiersFetchedAt = 'content_tiers_fetched_at';
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
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value);
  }

  Future<String?> getString(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(key);
  }

  // ── JSON ───────────────────────────────────────────────────────────────────

  Future<void> setJson(String key, Object value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, jsonEncode(value));
  }

  Future<Map<String, dynamic>?> getJson(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<List<dynamic>?> getJsonList(String key) async {
    final prefs = await SharedPreferences.getInstance();
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
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, DateTime.now().toIso8601String());
  }

  Future<bool> isStale(String timestampKey, Duration maxAge) async {
    final prefs = await SharedPreferences.getInstance();
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
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(keyWishlist) ?? [];
  }

  Future<void> setWishlist(List<String> skinIds) async {
    final prefs = await SharedPreferences.getInstance();
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
  Future<void>? _saveMatchMapLock;

  Future<Map<String, String>> getMatchMaps() async {
    final cached = await getJson(keyMatchMapCache);
    if (cached == null) return {};
    return cached.map((k, v) => MapEntry(k, v.toString()));
  }

  Future<void> saveMatchMap(String matchId, String mapId) async {
    if (matchId.isEmpty || mapId.isEmpty) return;

    // Mutex lock to prevent concurrent read-modify-write race conditions
    while (_saveMatchMapLock != null) {
      await _saveMatchMapLock;
    }

    final completer = Completer<void>();
    _saveMatchMapLock = completer.future;

    try {
      final current = await getMatchMaps();
      current[matchId] = mapId;
      await setJson(keyMatchMapCache, current);
    } finally {
      completer.complete();
      _saveMatchMapLock = null;
    }
  }

  // ── Remove ─────────────────────────────────────────────────────────────────

  Future<void> remove(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
  }

  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }
}
