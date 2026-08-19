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

  // ── Active Session Scope ──────────────────────────────────────────────────
  //
  // Tracks the currently-active user so that writes from requests that were
  // in-flight during an account switch can be detected and dropped. Cache keys
  // themselves are namespaced deterministically per puuid (see [userKeyFor]),
  // so account A's data is never served to account B even without clearing.
  //
  // NOTE: writes must be keyed by the puuid the *request was made for*, not by
  // the current active puuid — otherwise a stale response landing after a
  // switch would still be written into the new account's namespace.

  String _activePuuid = '';
  int _sessionGeneration = 0;
  String get activePuuid => _activePuuid;

  /// Call this whenever the active account changes (login, switch, logout).
  Future<void> setActiveSession(
    String puuid, {
    bool clearPrevious = false,
  }) {
    return AsyncLock.run('cache_session', () async {
      if (puuid == _activePuuid) return;

      final previousPuuid = _activePuuid;
      _activePuuid = puuid;
      _sessionGeneration++;

      if (clearPrevious && previousPuuid.isNotEmpty) {
        await _clearUserCacheInternal(previousPuuid);
      }
    });
  }

  /// Initializes cache scope after startup without allowing a late credential
  /// read to overwrite a session transition that has already happened.
  Future<void> initializeActiveSession(String puuid) {
    return AsyncLock.run('cache_session', () async {
      if (_sessionGeneration != 0) return;
      _activePuuid = puuid;
      _sessionGeneration = 1;
    });
  }

  /// Returns true when [puuid] still matches the currently-active session.
  /// Call right before persisting a fetch result; if the user switched (or
  /// logged out) while the request was in flight, this returns false and the
  /// write must be skipped.
  bool isActiveSession(String puuid) =>
      puuid.isNotEmpty && puuid == _activePuuid;

  /// Captures the account and activation generation before a request starts.
  /// A token from an earlier activation is invalid even after switching back
  /// to the same account.
  CacheTransaction? beginUserTransaction(String puuid) {
    if (!isActiveSession(puuid)) return null;
    return CacheTransaction._(puuid, _sessionGeneration);
  }

  /// Runs all writes in [action] as one session-guarded cache commit.
  Future<bool> runUserTransaction(
    CacheTransaction? transaction,
    Future<void> Function() action,
  ) {
    return AsyncLock.run('cache_session', () async {
      if (transaction == null ||
          transaction.puuid != _activePuuid ||
          transaction._generation != _sessionGeneration) {
        return false;
      }
      await action();
      return true;
    });
  }

  /// Deterministic per-user namespace for a cache key. Non-user caches (skin
  /// metadata, competitive tiers, client version, ...) must NOT use this —
  /// they are intentionally shared across accounts.
  static String userKeyFor(String key, String puuid) {
    if (puuid.isEmpty) {
      throw ArgumentError.value(puuid, 'puuid', 'must not be empty');
    }
    return '$puuid/$key';
  }

  /// Same as [userKeyFor] but keyed by the current active session. Only use
  /// this when you *intend* to write into the active user's namespace.
  String userKey(String key) => userKeyFor(key, _activePuuid);

  // ── Key Constants ──────────────────────────────────────────────────────────
  static const keyClientVersion = 'client_version';
  static const keyClientVersionFetchedAt = 'client_version_fetched_at';
  static const keyDailyShop = 'daily_shop';
  static const keyDailyShopFetchedAt = 'daily_shop_fetched_at';
  static const keySkinMetadata = 'skin_metadata_v4';
  static const keySkinMetadataFetchedAt = 'skin_metadata_v4_fetched_at';
  static const keyBundles = 'bundles_metadata_v4';
  static const keyBundlesFetchedAt = 'bundles_metadata_v4_fetched_at';
  static const keyCompetitiveTiers = 'competitive_tiers';
  static const keyCompetitiveTiersFetchedAt = 'competitive_tiers_fetched_at';
  static const keyWishlist = 'wishlist_skin_ids';
  static const keyWishlistNotificationDedupe =
      'wishlist_notification_dedupe_v1';

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
  static const keyWalletCache = 'cached_wallet';

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
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      await prefs.remove(key);
      return null;
    } catch (_) {
      await prefs.remove(key);
      return null;
    }
  }

  Future<List<dynamic>?> getJsonList(String key) async {
    final prefs = await _getPrefs();
    final raw = prefs.getString(key);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) return List<dynamic>.from(decoded);
      await prefs.remove(key);
      return null;
    } catch (_) {
      await prefs.remove(key);
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

  static String wishlistKeyFor(String puuid) => userKeyFor(keyWishlist, puuid);

  String _resolveWishlistKey([String? puuid]) {
    final effectivePuuid =
        (puuid != null && puuid.isNotEmpty) ? puuid : _activePuuid;
    if (effectivePuuid.isNotEmpty) {
      return wishlistKeyFor(effectivePuuid);
    }
    return keyWishlist;
  }

  Future<List<String>> getWishlist([String? puuid]) async {
    final prefs = await _getPrefs();
    final key = _resolveWishlistKey(puuid);
    var list = prefs.getStringList(key);

    // One-time auto migration from legacy global wishlist
    if (list == null && key != keyWishlist) {
      final legacy = prefs.getStringList(keyWishlist);
      if (legacy != null && legacy.isNotEmpty) {
        list = List<String>.from(legacy);
        await prefs.setStringList(key, list);
      }
    }

    return list ?? [];
  }

  Future<void> setWishlist(List<String> skinIds, [String? puuid]) async {
    final prefs = await _getPrefs();
    final key = _resolveWishlistKey(puuid);
    await prefs.setStringList(key, skinIds);
  }

  Future<void> addToWishlist(String skinId, [String? puuid]) {
    return AsyncLock.run('wishlist', () async {
      final list = await getWishlist(puuid);
      if (!list.contains(skinId)) {
        list.add(skinId);
        await setWishlist(list, puuid);
      }
    });
  }

  Future<void> removeFromWishlist(String skinId, [String? puuid]) {
    return AsyncLock.run('wishlist', () async {
      final list = await getWishlist(puuid);
      list.remove(skinId);
      await setWishlist(list, puuid);
    });
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
  ///
  /// Since user caches are namespaced per puuid, this removes the *current*
  /// active session's namespace (the account being switched away from) as well
  /// as any legacy un-namespaced keys from pre-namespace installs.
  Future<void> clearUserCache({String? puuid}) {
    return AsyncLock.run(
      'cache_session',
      () => _clearUserCacheInternal(puuid ?? _activePuuid),
    );
  }

  /// Atomically claims a wishlist alert for a specific shop rotation.
  /// Foreground and background callers share this persisted ledger, so only
  /// the first caller is allowed to display the notification.
  Future<bool> claimWishlistNotification({
    required String puuid,
    required String shopIdentity,
    required String skinId,
  }) {
    if (puuid.isEmpty || shopIdentity.isEmpty || skinId.isEmpty) {
      return Future.value(false);
    }
    return AsyncLock.run('wishlist_notification_dedupe', () async {
      final key = userKeyFor(keyWishlistNotificationDedupe, puuid);
      final ledger = await getJson(key) ?? <String, dynamic>{};
      final previousShop = ledger['shopIdentity'] as String?;
      final notified = previousShop == shopIdentity
          ? (ledger['skinIds'] as List<dynamic>?)
                  ?.whereType<String>()
                  .toSet() ??
              <String>{}
          : <String>{};
      if (notified.contains(skinId)) return false;
      notified.add(skinId);
      await setJson(key, {
        'shopIdentity': shopIdentity,
        'skinIds': notified.toList()..sort(),
      });
      return true;
    });
  }

  Future<void> _clearUserCacheInternal(String puuid) async {
    final baseKeys = [
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
      keyWalletCache,
      'player_loadout',
      keyWishlistNotificationDedupe,
    ];

    final keys = <String>[...baseKeys];
    if (puuid.isNotEmpty) {
      // Namespaced keys for the session being switched away from.
      keys.addAll(baseKeys.map((k) => userKeyFor(k, puuid)));
    }

    // Background shop checker state — must be cleared on account switch so
    // the new account's first shop check always fires a reset notification.
    keys.add('background_last_shop_ids');

    for (final k in keys) {
      await remove(k);
    }
  }

  Future<void> clearAll() async {
    await AsyncLock.run('cache_session', () async {
      _activePuuid = '';
      _sessionGeneration++;
      final prefs = await _getPrefs();
      await prefs.clear();
      // Reset cached instance so next access re-reads from disk.
      _prefs = null;
    });
  }
}

class CacheTransaction {
  const CacheTransaction._(this.puuid, this._generation);

  final String puuid;
  final int _generation;
}
