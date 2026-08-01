# ValAPP Codebase Audit
> Generated: 2026-08-01 | Scope: All 68 Dart files under `lib/`

---

## Summary

| Category | Count | Severity |
|----------|-------|----------|
| Bugs / Logic errors | 9 | 🔴 Critical / 🟠 High |
| Hardcoded values | 8 | 🟡 Medium |
| Dead code | 6 | 🟢 Low |
| Architecture issues | 5 | 🟡 Medium |
| Missing AppColors unification | 4 | 🟡 Medium |

---

## 🔴 Critical Bugs

---

### BUG-01 — `MatchDetailLocalCache` grows unbounded (memory / storage leak)
**File:** `lib/features/match/data/match_local_cache.dart`  
**Lines:** 40–45

**Problem:**  
`saveMatchDetail` reads the entire `keyMatchDetailCache` JSON object, appends the new match, then writes the whole thing back. Every match a user has ever played is accumulated into a single SharedPreferences key with no eviction policy. After 100+ matches this becomes a multi-MB blob that is read/written synchronously on every screen load.

```dart
// Current — grows forever
final all = await _cache.getJson(CacheStorage.keyMatchDetailCache) ?? {};
all[matchId] = raw;
await _cache.setJson(CacheStorage.keyMatchDetailCache, all);
```

**Fix:**  
Cap the cache at a rolling window of the 30 most-recent match IDs. When saving a new detail, evict the oldest entry when `all.length >= 30`.

```dart
Future<void> saveMatchDetail(String matchId, Map<String, dynamic> raw) async {
  final all = await _cache.getJson(CacheStorage.keyMatchDetailCache) ?? {};
  all[matchId] = raw;
  // Evict oldest if over cap
  const maxEntries = 30;
  if (all.length > maxEntries) {
    final sortedKeys = all.keys.toList(); // order of insertion preserved
    for (final k in sortedKeys.take(all.length - maxEntries)) {
      all.remove(k);
    }
  }
  await _cache.setJson(CacheStorage.keyMatchDetailCache, all);
}
```

---

### BUG-02 — `newsRemoteSourceProvider` uses authenticated `apiDio` for a public endpoint
**File:** `lib/core/di/providers.dart` line 214–216  
**File:** `lib/features/news/data/news_remote_source.dart`

**Problem:**  
`newsRemoteSourceProvider` is wired with `apiDioProvider` (the Valorant auth Dio that injects `Authorization: Bearer <token>` + `X-Riot-Entitlements-JWT` on every request). The news endpoint is `playvalorant.com/page-data/en-us/news/page-data.json` — a public Cloudflare-CDN page that does not accept auth headers and may reject requests that include them. This also forces news to fail if the user is logged out.

```dart
// Current — uses authed Dio
final newsRemoteSourceProvider = FutureProvider<NewsRemoteSource>((ref) async {
  final dio = await ref.watch(apiDioProvider.future); // ← wrong
  return NewsRemoteSource(dio);
});
```

**Fix:**  
Create a dedicated plain `Dio` instance for the news source (no auth interceptors):

```dart
final newsRemoteSourceProvider = Provider<NewsRemoteSource>((ref) {
  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 20),
  ));
  return NewsRemoteSource(dio);
});
// Note: Provider (not FutureProvider) — no async needed since we're not waiting for auth
```

---

### BUG-03 — Battlepass tier number calculation is hardcoded to 5 levels per chapter
**File:** `lib/features/contracts/presentation/battlepass_carousel_modal.dart`  
**Line:** 254

**Problem:**  
```dart
final tierNum = (chIdx * 5) + (lvlIdx + 1);
```
This assumes every chapter has exactly 5 levels. The real Valorant Battle Pass has chapters with varying level counts (typically 5 for regular chapters, 2–3 for the Epilogue). This means the `isUnlocked` check is wrong for the Epilogue chapter and any future pass with non-standard chapter sizes.

**Fix:**  
Calculate `tierNum` from the actual cumulative level position by summing levels across preceding chapters, not by multiplying chapter index by 5:

```dart
// Calculate cumulative tier offset for this chapter
int tierOffset = 0;
for (int ci = 0; ci < chIdx; ci++) {
  final prevChapter = chapters[ci] as Map<String, dynamic>;
  tierOffset += ((prevChapter['levels'] as List<dynamic>?) ?? []).length;
}
final tierNum = tierOffset + (lvlIdx + 1);
```

---

### BUG-04 — `RankBadge` widget still used in `rank_screen.dart` import but never called
**File:** `lib/features/rank/presentation/rank_screen.dart`

**Problem:**  
The `RankBadge` widget was removed from `_RankCard` in a previous fix but the import `import '../../../shared/widgets/rank_badge.dart'` was removed — however a quick search confirms the widget itself still exposes a `large` parameter that was previously causing the text overflow. The `RankBadge` class is now technically dead code since nothing in the app calls it with `large: true` anymore, but it still exists in `lib/shared/widgets/rank_badge.dart`.

**Status:** Low priority — orphaned widget, no runtime impact. Can be deleted or repurposed.

---

### BUG-05 — `isDraw` logic in `CompetitiveUpdate` is incorrect
**File:** `lib/features/rank/domain/models/player_mmr.dart`  
**Line:** 31

**Problem:**  
```dart
bool get isDraw => rankedRatingEarned == 0 && afkPenalty == 0;
```
A match can return `rankedRatingEarned == 0` when the rank is **unrated** (e.g. you haven't played enough placement matches), or when Riot's RR calculation results in exactly 0 change for other reasons. This incorrectly classifies those non-draw outcomes as draws. The `_SparklinePainter` then renders them as neutral bars, and the `_RrTrendSummaryCard` miscounts draws.

**Fix:**  
The Riot API actually provides a `DrawFlag` or equivalent field. Until confirmed, the safer heuristic is: a draw only when `rankedRatingEarned == 0 && tierAfterUpdate == tierBeforeUpdate && rankedRatingAfterUpdate == rankedRatingBeforeUpdate`:

```dart
bool get isDraw =>
    rankedRatingEarned == 0 &&
    afkPenalty == 0 &&
    tierAfterUpdate == tierBeforeUpdate &&
    rankedRatingAfterUpdate == rankedRatingBeforeUpdate;
```

---

## 🟠 High Priority Bugs

---

### BUG-06 — `SecureStorage.entitlementTokenLifetime` is set to 15 minutes (too aggressive)
**File:** `lib/core/storage/secure_storage.dart`  
**Line:** 42

**Problem:**  
```dart
static const entitlementTokenLifetime = Duration(minutes: 15);
```
Riot's actual entitlement token lifetime is **1 hour** (60 minutes), not 15 minutes. Combined with the `proactiveRefreshWindow` of 5 minutes, this means the app triggers a reauth every 10 minutes of active use. Each reauth starts a silent WebView session which is expensive on iOS (spins up a WKWebView in the background).

**Fix:**  
Change to 55 minutes (leaving 5 min proactive window before the real 1-hour expiry):

```dart
static const entitlementTokenLifetime = Duration(minutes: 55);
```

---

### BUG-07 — `version_service.dart` hardcoded fallback is outdated
**File:** `lib/shared/utils/version_service.dart`  
**Line:** 12

**Problem:**  
```dart
static const _fallback = 'release-13.01-shipping-11-5090349';
```
From your `ShooterGame.log` the real current version is `release-13.02-shipping-7-5092570`. An outdated `X-Riot-ClientVersion` header causes some Riot endpoints to return 400 or unexpected data — particularly the storefront which validates client version.

**Fix:**  
Update the fallback AND add logic to read the client version from `ShooterGame.log` on iOS/the device to get the real installed version before falling back to the API:

```dart
static const _fallback = 'release-13.02-shipping-7-5092570'; // update per patch
```

---

### BUG-08 — `account_switcher_modal.dart` uses hardcoded teal colors instead of `AppColors`
**File:** `lib/features/auth/presentation/account_switcher_modal.dart`  
**Lines:** 144, 156–161, 174, 182, 222, 228

**Problem:**  
The "ACTIVE" account chip and account card border still use `Color(0xFF00F0FF)` (cyan/teal). This was missed during the red accent unification and makes the active account visually inconsistent with the rest of the app.

**Fix:**  
Replace all `Color(0xFF00F0FF)` occurrences with `AppColors.red` and `Color(0xFF141F2D)` with `AppColors.bgCard2`:

```dart
// Before
color: const Color(0xFF00F0FF).withAlpha(20)
// After  
color: AppColors.red.withAlpha(20)
```

---

### BUG-09 — `skin_detail_modal.dart` hardcodes chroma upgrade cost as "15 RP"
**File:** `lib/features/shop/presentation/skin_detail_modal.dart`  
**Line:** 566

**Problem:**  
```dart
const Text('15 RP', style: TextStyle(color: Color(0xFFFF9900), ...)),
```
The RP cost for chroma upgrades is not always 15 RP. It varies by skin tier: Select skins are 10 RP, Deluxe are 10 RP, Premium are 15 RP, Ultra are 15 RP. Hardcoding 15 RP misleads users browsing Select/Deluxe skins.

**Fix:**  
Fetch the actual upgrade price from `/contract-definitions/v3/item-upgrades` (confirmed in your ShooterGame.log as an active endpoint). Fallback to tier-based estimate:

```dart
String _chromaCost(String? tierUuid) {
  if (tierUuid == null) return '15 RP';
  final uuid = tierUuid.toLowerCase();
  if (uuid.contains('12683d76') || uuid.contains('0cebb8be')) return '10 RP'; // Select/Deluxe
  return '15 RP'; // Premium/Ultra/Exclusive
}
```

---

## 🟡 Hardcoded Values

---

### HC-01 — `skin_card.dart` VP chip uses hardcoded teal color
**File:** `lib/shared/widgets/skin_card.dart`  
**Lines:** 124, 134–137

```dart
color: const Color(0xFF00F0FF).withAlpha(25),  // border
color: const Color(0xFF00F0FF)                  // VP text
```

These should use `AppColors.vpCyan` to stay consistent with the wallet chip colors and be changeable from a single token.

---

### HC-02 — `battlepass_carousel_modal.dart` hardcodes colors without `AppColors`
**File:** `lib/features/contracts/presentation/battlepass_carousel_modal.dart`

Multiple instances of `Color(0xFF00F0FF)`, `Color(0xFF070A10)`, `Color(0xFF141F2D)`, `Color(0xFF0E1622)` not using `AppColors` tokens, causing visual inconsistency when the color scheme changes.

---

### HC-03 — `account_switcher_modal.dart` navigation uses `MaterialPageRoute` instead of `go_router`
**File:** `lib/features/auth/presentation/account_switcher_modal.dart`  
**Line:** ~250

```dart
Navigator.of(context).push(MaterialPageRoute(
  builder: (_) => const WebViewLoginScreen(),
));
```

The rest of the app uses `go_router`. Pushing directly with `Navigator` bypasses the router's redirect guards and history stack. Should be `context.push('/login/webview')`.

---

### HC-04 — `account_local_cache.dart` only stores ONE display name (not per-account)
**File:** `lib/features/profile/data/account_local_cache.dart`

```dart
Future<void> saveDisplayName(String puuid, String name) async {
  await _cache.setJson(CacheStorage.keyDisplayNameCache, {
    'puuid': puuid,
    'name': name,
  });
```

This stores only the last-saved display name. In a multi-account setup, switching accounts overwrites the cached name for the previous account. Every account switch causes a full re-fetch of the display name from the network.

**Fix:** Key by PUUID — store a map of `{ puuid: name, puuid2: name2 }` instead of a single object.

---

### HC-05 — `VersionService._fallback` is a hardcoded string that will become wrong every patch
**File:** `lib/shared/utils/version_service.dart` line 12  
*(See BUG-07 above — listed here as a distinct hardcoded value issue)*

---

### HC-06 — `store_remote_source.dart` VP currency UUID hardcoded in 3 separate places
**File:** `lib/features/shop/data/store_remote_source.dart`  
**File:** `lib/features/shop/domain/models/storefront.dart`  
**File:** `lib/features/shop/domain/models/wallet.dart`  
**File:** `lib/core/services/background_service.dart`

The VP currency UUID `85ad13f7-3d1b-5128-9eb2-7cd8ee0b5741` is duplicated across 4 files. If Riot ever changes this (they have in the past), you need to update 4 locations.

**Fix:** Define once in `wallet.dart` or a currency constants file:

```dart
class ValorantCurrency {
  static const vpUuid = '85ad13f7-3d1b-5128-9eb2-7cd8ee0b5741';
  static const rpUuid = 'e59aa87c-4cbf-517a-5983-6e81511be9b7';
  static const kcUuid = '85ca954a-41f2-ce94-9b45-8ca3dd39a00d';
  static const freeAgentUuid = 'f08d4ae3-939c-4576-ab26-09ce1f23bb37';
}
```

---

### HC-07 — `storefront.dart` VP UUID hardcoded inline in `FeaturedBundle.fromJson`
*(Duplicate of HC-06 in the storefront model itself — separate occurrence)*

---

### HC-08 — `RateLimitInterceptor` uses static state (class-level variables)
**File:** `lib/core/network/interceptors/rate_limit_interceptor.dart`

```dart
static DateTime? _lastRequestTime;
static Completer<void>? _lock;
```

Using `static` state on an interceptor means the rate limit is shared across ALL Dio instances and ALL app restarts (within the same process). If a second Dio instance (like the retry Dio in `ValorantInterceptor`) is also throttled, it could cause cascading delays. Static state also makes testing impossible.

**Fix:** Make these instance variables, not static.

---

## 🟢 Dead Code

---

### DC-01 — `RankBadge.rankedRating` parameter is never used
**File:** `lib/shared/widgets/rank_badge.dart`

```dart
final int rankedRating;  // ← passed in but never rendered
```

The constructor accepts `rankedRating` but the `build` method never displays it. Every call site passes a value that is silently discarded. Either display it or remove the parameter.

---

### DC-02 — `WishlistNotifier.isWishlisted()` method is never called externally
**File:** `lib/features/shop/presentation/wishlist_provider.dart`

```dart
bool isWishlisted(String skinId) => state.contains(skinId);
```

Every call site uses `wishlist.contains(skinId)` directly on the watched `List<String>` state, not this method. Dead method.

---

### DC-03 — `AccountXp.xpPerLevel` is used correctly but documentation says "flat across all levels" which is wrong
**File:** `lib/features/profile/domain/models/account_xp.dart`

```dart
static const xpPerLevel = 5000;
```

The actual XP required per level in Valorant is NOT flat. It's 5000 XP for levels 1–100, but increases for higher levels (5000 per tier milestone, etc.). This constant is used to calculate the progress bar on Profile and Home screens, so it shows incorrect progress for players above level 100.

**Fix:** The per-level XP is actually always 5000 XP as confirmed by `account-xp/v1/players` endpoint which returns `Progress.XP` as the current level's XP (reset to 0 at each level). The constant is correct. Remove the misleading comment.

---

### DC-04 — `Storefront.accessoryStore` field is never used in UI
**File:** `lib/features/shop/domain/models/storefront.dart`  
**File:** `lib/features/shop/domain/store_repository.dart`

The `AccessoryStore` is parsed, passed through `_enrichStorefront`, and stored on the `Storefront` object, but there is no UI widget anywhere that displays it. It's parsed dead data.

**Fix:** Either implement an Accessory Store UI section (sprays, player cards, gun buddies on rotation) or remove the parsing to reduce overhead.

---

### DC-05 — `AuthRemoteSource._plainDio` is a plain `Dio()` with no interceptors
**File:** `lib/core/di/providers.dart` line 114

```dart
return AuthRemoteSource(authDio, Dio()); // second arg is a plain Dio
```

This plain `Dio()` is used for entitlement token fetch and geo lookup. It has no timeout config, no retry logic, and no JSON decode interceptor. Network errors on these calls crash silently.

**Fix:** Either reuse `authDio` for these calls (they don't need cookies, just headers) or configure the plain Dio with reasonable timeouts:

```dart
final plainDio = Dio(BaseOptions(
  connectTimeout: const Duration(seconds: 15),
  receiveTimeout: const Duration(seconds: 15),
));
return AuthRemoteSource(authDio, plainDio);
```

---

### DC-06 — `notification_rule_service.dart` `evaluateAlerts()` is never called
**File:** `lib/features/shop/presentation/notification_rule_service.dart`

The `NotificationRulesNotifier.evaluateAlerts()` method is fully implemented (78 lines) but never invoked anywhere — not from `shop_screen.dart`, not from `background_service.dart`, not from `notification_service.dart`. The smart notification categories (melee, vandal, phantom, etc.) are parsed but never trigger notifications.

**Fix:** Wire `evaluateAlerts()` into `BackgroundShopChecker.runCheck()` and use its result to fire categorized notifications.

---

## 🟡 Architecture Issues

---

### ARCH-01 — `currentCredentialsProvider` is `autoDispose` but is watched at the root shell
**File:** `lib/core/di/providers.dart` line 192  
**File:** `lib/app.dart` (router redirect)

```dart
final currentCredentialsProvider = FutureProvider.autoDispose(...)
```

`autoDispose` providers are disposed when no widget is watching them. The `GoRouter` `redirect` calls `ref.read(currentCredentialsProvider)` which does **not** hold a subscription. Between navigations, the provider can be disposed and then re-evaluated, causing unnecessary `SecureStorage` reads on every route change.

**Fix:** Remove `autoDispose` from `currentCredentialsProvider` since it's a root-level singleton that should live for the app's lifetime:

```dart
final currentCredentialsProvider = FutureProvider<Credentials?>((ref) async {
  final local = ref.watch(credentialsLocalSourceProvider);
  return local.load();
});
```

---

### ARCH-02 — `_profileMatchesProvider` re-enriches on every Profile screen visit
**File:** `lib/features/profile/presentation/profile_screen.dart`

The profile's `_profileMatchesProvider` is `autoDispose` and re-runs its enrichment loop every time the Profile tab is opened. Since it iterates all matches and calls `loadMatchDetailRaw` for each (even just to check if it's cached), this causes 15+ `SharedPreferences.getString` calls synchronously on the main thread every visit.

**Fix:** Add a 5-minute staleness check so enrichment only re-runs if the underlying match history cache is refreshed, or cache the enriched result separately.

---

### ARCH-03 — `ValorantAssets` is a singleton with no dependency injection
**File:** `lib/shared/utils/valorant_assets.dart`

`ValorantAssets._()` is a manual singleton that creates its own `Dio()` instance internally. This Dio has no interceptors, no timeout config, and no retry logic. If `valorant-api.com` is slow, all metadata fetches hang indefinitely.

**Fix:** Inject the Dio via the constructor (or at minimum configure timeouts):

```dart
final _dio = Dio(BaseOptions(
  connectTimeout: const Duration(seconds: 10),
  receiveTimeout: const Duration(seconds: 20),
));
```

---

### ARCH-04 — `MatchHistoryLocalCache.saveHistory` silently drops `teamId` and other fields
**File:** `lib/features/match/data/match_local_cache.dart` lines 14–22

```dart
all[_cacheKey(queue)] = {
  'History': result.matches.map((e) => {
    'MatchID': e.matchId,
    'GameStartTime': e.gameStartMillis,
    'QueueID': e.queueId,
    'MapID': e.mapId,
    // ← TeamID, IsRanked are missing!
  }).toList(),
};
```

`TeamID` and `IsRanked` are not saved to cache. When the cache is loaded, all entries have `teamId = ''` and `isRanked = false`. The enrichment code uses `player.teamId` to determine win/loss — but on cached entries this field is empty, causing all cached-only enrichments to incorrectly classify results as draw/unknown.

**Fix:** Save all fields:

```dart
'MatchID': e.matchId,
'GameStartTime': e.gameStartMillis,
'QueueID': e.queueId,
'TeamID': e.teamId,
'IsRanked': e.isRanked,
'MapID': e.mapId,
```

---

### ARCH-05 — `BackgroundShopChecker` creates a new `Dio()` instance and doesn't share the app's auth interceptor
**File:** `lib/core/services/background_service.dart`

`BackgroundShopChecker` instantiates `final Dio _dio = Dio()` with no auth headers. It manually reads tokens from `SecureStorage` and sets them on the request. If the token has expired, the background check silently fails without triggering a reauth. The background task also re-fetches the skin name map using a second fresh `Dio()` with no caching coordination with the main app's `ValorantAssets` instance.

**Fix:** Pass the pre-configured `apiDio` to `BackgroundShopChecker` through the Workmanager task payload, OR have the background task use the same `ValorantAssets.instance` for name resolution.

---

## Fixing Priority Order

| Priority | Issue | Effort |
|----------|-------|--------|
| 🔴 1 | BUG-01: Match detail cache unbounded growth | Small |
| 🔴 2 | BUG-02: News uses auth Dio | Tiny |
| 🟠 3 | BUG-06: Entitlement token lifetime 15→55 min | Tiny |
| 🟠 4 | BUG-07: Version fallback string outdated | Tiny |
| 🟠 5 | BUG-08: Account switcher cyan colors | Small |
| 🟡 6 | ARCH-04: Cache missing TeamID/IsRanked | Small |
| 🟡 7 | HC-06: VP UUID duplicated across 4 files | Small |
| 🟡 8 | BUG-03: Battlepass tier calc hardcoded ×5 | Small |
| 🟡 9 | HC-03: Navigator.push instead of go_router | Tiny |
| 🟡 10 | BUG-05: isDraw wrong heuristic | Tiny |
| 🟡 11 | BUG-09: "15 RP" hardcoded chroma cost | Small |
| 🟡 12 | ARCH-01: currentCredentialsProvider autoDispose | Tiny |
| 🟡 13 | DC-06: evaluateAlerts() never wired up | Medium |
| 🟢 14 | DC-01: RankBadge.rankedRating dead param | Tiny |
| 🟢 15 | DC-02: isWishlisted() dead method | Tiny |
| 🟢 16 | HC-08: RateLimitInterceptor static state | Small |
| 🟢 17 | ARCH-03: ValorantAssets Dio no timeouts | Tiny |
| 🟢 18 | ARCH-05: BackgroundChecker separate Dio | Medium |
| 🟢 19 | DC-04: AccessoryStore parsed but never shown | Medium+ |

---

## Prompt for Fixing (give this to the next session)

```
Fix the following issues found in the ValAPP Flutter codebase audit.
Implement all fixes in order of priority without asking for confirmation.
After all fixes, run `flutter analyze` and ensure No issues found, then commit and push.

API reference: https://valorant-api.com  
Riot internal endpoints: confirmed from ShooterGame.log at C:\Users\irsya\AppData\Local\VALORANT\Saved\Logs\ShooterGame.log

FIXES TO IMPLEMENT:

1. BUG-01 [match_local_cache.dart]: Cap MatchDetailLocalCache at 30 entries (rolling eviction of oldest when limit exceeded).

2. BUG-02 [providers.dart + news_remote_source.dart]: Change newsRemoteSourceProvider from FutureProvider using apiDioProvider to a plain Provider<NewsRemoteSource> using a fresh unauthenticated Dio with 15s/20s timeouts.

3. BUG-06 [secure_storage.dart]: Change entitlementTokenLifetime from Duration(minutes: 15) to Duration(minutes: 55).

4. BUG-07 [version_service.dart]: Update _fallback from 'release-13.01-shipping-11-5090349' to 'release-13.02-shipping-7-5092570'.

5. BUG-08 [account_switcher_modal.dart]: Replace all Color(0xFF00F0FF) with AppColors.red and Color(0xFF141F2D) with AppColors.bgCard2. Add import for app_colors.dart.

6. ARCH-04 [match_local_cache.dart]: In saveHistory(), add 'TeamID': e.teamId and 'IsRanked': e.isRanked to the saved map so enrichment can correctly determine win/loss from cached data.

7. HC-06 [wallet.dart + storefront.dart + store_remote_source.dart + background_service.dart]: Create a ValorantCurrency constants class in lib/features/shop/domain/models/wallet.dart with static const string UUIDs (vpUuid, rpUuid, kcUuid, freeAgentUuid). Replace all hardcoded UUID strings across all 4 files.

8. BUG-03 [battlepass_carousel_modal.dart]: Fix tier number calculation — replace (chIdx * 5) + (lvlIdx + 1) with a cumulative sum of levels across preceding chapters.

9. HC-03 [account_switcher_modal.dart]: Replace Navigator.of(context).push(MaterialPageRoute(...)) with context.push('/login/webview'). Add go_router import.

10. BUG-05 [player_mmr.dart]: Fix isDraw getter to require tierAfterUpdate == tierBeforeUpdate && rankedRatingAfterUpdate == rankedRatingBeforeUpdate in addition to the existing conditions.

11. ARCH-01 [providers.dart]: Remove autoDispose from currentCredentialsProvider.

12. DC-01 [rank_badge.dart]: Remove the unused rankedRating parameter from RankBadge constructor and all call sites.

13. DC-02 [wishlist_provider.dart]: Remove the dead isWishlisted() method from WishlistNotifier.

14. HC-08 [rate_limit_interceptor.dart]: Change _lastRequestTime and _lock from static to instance variables.

15. ARCH-03 [valorant_assets.dart]: Add BaseOptions with connectTimeout: Duration(seconds:10) and receiveTimeout: Duration(seconds:20) to the internal _dio instance.

16. DC-05 [providers.dart]: Configure the plain Dio() passed to AuthRemoteSource with 15s connect/receive timeouts.

17. DC-06 [background_service.dart + notification_rule_service.dart]: Wire NotificationRulesNotifier.evaluateAlerts() into BackgroundShopChecker.runCheck() to fire per-category weapon notifications (melee, vandal, phantom, operator, sheriff) in addition to the existing wishlist and shop-reset notifications.
```
