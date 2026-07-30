# Audit Codebase `Valapp` — LENGKAP (56/56 file)

Repo: https://github.com/Irsyadmr354/Valapp
**Update:** Audit ronde pertama cuma nyentuh jalur network/auth/shop-vs-lainnya (sebagian kecil codebase). Dokumen ini adalah hasil audit MENYELURUH — **seluruh 56 file `.dart` (±8.900 baris) sudah dibaca satu per satu**, termasuk semua model, semua provider, semua screen/widget, semua util, dan file test. Bagian 1-5 (root cause 400 error) tetap dari audit awal dan masih valid. Bagian 6 ke bawah adalah temuan baru dari audit menyeluruh ini.

---

## TL;DR

Bug-nya **bukan** di server Riot, dan **bukan** cuma satu bug — ini kombinasi dari:

1. **`ValorantInterceptor` cuma nge-handle status `401`**, sedangkan status `400` (bad syntax / entitlement token invalid) langsung `rethrow` sebagai `DioException [bad response]` mentah-mentah ke UI — persis pesan yang muncul di screenshot kamu.
2. **Halaman Shop punya cache-fallback, halaman Rank/Match/Profile tidak.** Makanya Shop "selalu fresh tanpa masalah" — begitu fetch gagal (400/timeout/apapun), dia diam-diam nge-load data lama dari cache lokal dan render itu, jadi user gak pernah lihat error-nya. Rank/Match/Profile langsung nembak `DioException` mentah ke widget karena gak ada fallback.
3. Root exception yang sebenarnya (kenapa jadi 400) kemungkinan besar **`X-Riot-Entitlements-JWT` yang stale**, karena token ini gak pernah di-refresh ulang di proactive-reauth logic maupun di reauth 401-handler dengan benar — dijelaskan detail di bagian 3.

---

## 1. Kenapa muncul `DioException [bad response] ... status code 400`

File: `lib/core/network/interceptors/valorant_interceptor.dart`

```dart
@override
void onError(DioException err, ErrorInterceptorHandler handler) async {
  final status = err.response?.statusCode;
  // ONLY 401 Unauthorized indicates an expired access_token needing reauth
  if (status == 401) {
    ...
  }
  handler.next(err);  // <-- 400, 403, 5xx, dll semua lolos mentah ke sini
}
```

Komentar di kode sendiri sudah eksplisit menyatakan **cuma 401** yang dianggap token expired. Padahal di Riot's unofficial API (`pd.<shard>.a.pvp.net`), token/entitlement yang basi **seringkali balikin `400`, bukan `401`** — terutama untuk endpoint MMR (`/mmr/v1/players/...`), match-history, dan account-xp. Ini yang bikin RequestOptions.validateStatus (default Dio: cuma 2xx yang lolos) throw exception, dan exception itu gak pernah ketangkep sama logic reauth — jadi langsung nyampur ke `err` yang di-propagate ke provider, lalu di-render mentah-mentah sebagai string exception ke layar (`Text(error.toString())` kemungkinan besar di widget-nya).

**Bukti pendukung:** di `store_remote_source.dart` (endpoint shop), penulisnya SENDIRI sudah tau endpoint Riot bisa return 400 untuk alasan lain selain auth — makanya storefront punya fallback manual:

```dart
} on DioException catch (e) {
  if (e.response?.statusCode == 404 ||
      e.response?.statusCode == 405 ||
      e.response?.statusCode == 400) {
    // Fall back to v3
    final response = await _dio.post<dynamic>(
      'https://pd.$shard.a.pvp.net/store/v3/storefront/$puuid',
      data: {},
    );
    ...
```

Tapi fallback ini **cuma ada di storefront**, gak di rank (`mmr_remote_source.dart`), match (`match_remote_source.dart`), maupun profile (`account_remote_source.dart`). Endpoint-endpoint itu manggil `_dio.get(...)` polos tanpa try/catch sama sekali.

---

## 2. Kenapa Shop "selalu fresh" padahal network/token sama-sama basi

File: `lib/features/shop/presentation/shop_screen.dart`

```dart
final _storefrontProvider = FutureProvider.autoDispose<Storefront?>((ref) async {
  ...
  // Fetch fresh data first — fallback to cache on error
  try {
    return await repo.fetchStorefront(creds.shard, creds.puuid);
  } catch (_) {
    return repo.loadCachedStorefront();   // <-- SWALLOW error, render cache lama
  }
});

final _walletProvider = FutureProvider.autoDispose<Wallet?>((ref) async {
  ...
  try {
    return await repo.fetchWallet(creds.shard, creds.puuid);
  } catch (_) {
    return repo.loadCachedWallet();       // <-- sama
  }
});
```

Jadi kalau fetch storefront gagal (400 karena token basi, atau network apapun), Shop **diam-diam** balik ke cache lokal (`store_local_cache.dart`) dan render itu — user gak pernah lihat error, cuma lihat data yang (sebenarnya) stale tapi keliatan "fine". Ini bikin ilusi "Shop gak pernah error" padahal Shop **juga kena error yang sama**, cuma disembunyikan.

Bandingkan dengan Rank (`rank_screen.dart`), Match (`match_history_screen.dart`), Profile (`profile_screen.dart`) — semua providernya **tanpa try/catch**, jadi begitu request gagal, `FutureProvider` reject dengan error itu, lalu widget nge-render `AsyncError` (yang isinya `error.toString()` dari `DioException`) — persis seperti di 3 screenshot kamu.

**Kesimpulan bagian 2:** Ini bukan berarti Shop "beneran gak ada masalah". Shop juga kena 400 yang sama, cuma UX-nya nutup-nutupin lewat cache silent-fallback yang gak dimiliki 3 fitur lain.

---

## 3. Kenapa baru muncul "setelah beberapa menit" (bukan langsung)

Ini kandidat root cause di lapisan auth/token. Ada 2 kecurigaan konkret:

### 3a. Proactive refresh window cuma nge-cek `access_token`, bukan entitlement token

File: `valorant_interceptor.dart`, `onRequest`:

```dart
final expiresAtStr = await _secureStorage.read(SecureStorage.keyExpiresAt);
if (expiresAtStr != null) {
  final expiresAt = DateTime.tryParse(expiresAtStr);
  if (expiresAt != null &&
      DateTime.now().isAfter(expiresAt.subtract(const Duration(minutes: 5)))) {
    await onReauth();
  }
}
```

`expiresAt` di sini disimpan dari `expires_in` hasil RSO auth (biasanya default fallback `3600` detik / 1 jam kalau parsing gagal — lihat `auth_remote_source.dart`: `int.tryParse(params['expires_in'] ?? '3600') ?? 3600`). Tapi **`X-Riot-Entitlements-JWT` (entitlement token) TIDAK punya expiry tracking sendiri** — hanya di-refresh ulang saat `reauth()` dipanggil (yang triggernya cuma dari access-token expiry ATAU dari 401 handler). Kalau entitlement token Riot expire lebih cepat dari access token (yang sangat mungkin — entitlement token Riot punya masa berlaku pendek, biasa dalam hitungan menit sampai puluhan menit tergantung sesi), maka:

- Access token masih dianggap valid (belum masuk window 5-menit-sebelum-expiry).
- Entitlement token sudah basi.
- Request ke endpoint yang strict validasi entitlement (mmr, match-history, account-xp) → Riot balikin **400**, bukan 401.
- `onError` di interceptor cuma ngecek `status == 401` → gak ke-trigger reauth → error mentah nyampe ke UI.

Ini match sempurna sama gejala "setelah beberapa menit tiba-tiba 400 di semua tab kecuali shop".

### 3b. Retry setelah 401-reauth pakai Dio baru yang gak punya semua interceptor

File: `valorant_interceptor.dart`, di `onError` untuk kasus 401:

```dart
final retryDio = Dio();
retryDio.interceptors.add(_JsonDecodeInterceptor());
final response = await retryDio.fetch(err.requestOptions);
```

Retry pakai `Dio()` polos baru (bukan dio asli yang ada `RateLimitInterceptor`/`RetryInterceptor`). Kalau retry ini sendiri kena 429 (karena request-request lain lagi jalan cepat dan `RateLimitInterceptor` cuma ada di dio original), gak ada retry-429-handler di retryDio ini, jadi ujungnya tetep gagal — tapi ini cuma relevan untuk path 401, bukan penyebab 400 utama.

---

## 4. Daftar Cacat Logic / Bug Konkret (ringkas, actionable)

| # | Lokasi | Masalah |
|---|--------|---------|
| 1 | `valorant_interceptor.dart` `onError` | Hanya menangani status `401`. Status `400` (yang jadi gejala utama kamu) tidak pernah memicu reauth — langsung `handler.next(err)` alias diteruskan sebagai fatal error. |
| 2 | `valorant_interceptor.dart` `onRequest` | Proactive refresh hanya berdasarkan `keyExpiresAt` (access token). Tidak ada tracking expiry terpisah untuk `entitlement_token`, padahal entitlement token adalah yang divalidasi ketat oleh endpoint mmr/match/account. |
| 3 | `store_remote_source.dart` vs `mmr/match/account_remote_source.dart` | Inkonsistensi: hanya storefront yang punya fallback 400→v3 & try/catch. Endpoint lain tidak — bug simetri, bukan by design. |
| 4 | `shop_screen.dart` providers | Silent catch-all (`catch (_) { return cache }`) menyembunyikan error asli dari user & dev — termasuk error yang seharusnya memicu re-login (mis. token benar-benar expired total), bukan cuma dipoles jadi "keliatan fine". Ini juga bikin debugging susah karena log error hilang (gak ada `debugPrint` di catch block ini). |
| 5 | `rank/match/profile` presentation | Tidak ada error handling / cache fallback sama sekali — begitu exception naik, `error.toString()` dari `DioException` (termasuk pesan panjang MDN link) langsung dirender ke UI, seperti di semua 3 screenshot kamu. |
| 6 | `retry_interceptor.dart` | Hanya menangani `429`. Tidak menangani `400`/`403`/`5xx` sama sekali, padahal ini interceptor generik "retry" — namanya menyiratkan retry umum, tapi scope-nya sempit. |
| 7 | `auth_repository.dart` `reauth()` | Refresh entitlement token cuma dipanggil ulang **di dalam** `reauth()` (dipicu access-token-expiry atau 401). Tidak ada jalur independen untuk refresh entitlement token saja kalau ternyata entitlement yang basi duluan. |
| 8 | `valorant_interceptor.dart` retry-after-401 | Pakai `Dio()` baru polos untuk retry, bukan dio asli — kehilangan rate-limiting & retry-429 protection pada request retry itu sendiri (inkonsistensi minor, bukan penyebab utama). |

---

## 5. Kesimpulan

Urutan kejadian yang paling cocok dengan gejala kamu:

1. Login sukses → semua token (access, entitlement) fresh → semua tab (Shop, Rank, Match, Profile) fine.
2. Beberapa menit berjalan → **entitlement token expire duluan** (lebih cepat dari access token yang masih dianggap valid oleh `keyExpiresAt`).
3. Rank/Match/Profile manggil endpoint yang strict validasi entitlement → Riot balikin `400` → interceptor **tidak** mendeteksi ini sebagai auth-issue (cuma cek 401) → exception mentah lolos ke UI persis seperti screenshot.
4. Shop juga kena entitlement basi yang sama & fetch-nya juga gagal — tapi providernya nge-**catch** error itu dan diam-diam render `loadCachedStorefront()`/`loadCachedWallet()` dari cache lokal, jadi user gak pernah lihat kegagalannya — cuma keliatan "selalu fresh" padahal sebenarnya bisa jadi data itu udah beberapa menit basi juga.

---

## 6. Temuan Tambahan dari Audit Menyeluruh (semua 56 file)

Bagian ini adalah hasil baca ulang **setiap file** di codebase, bukan cuma jalur network. Diurutkan per area.

### 6.1 Routing / App Shell

**#Router** — `app.dart`: redirect logic gak mem-blokir transisi loading race secara eksplisit selain `credsAsync.isLoading`; cukup minor, tapi worth dicatat kalau ada masalah navigasi flicker saat login/logout.

### 6.2 Dead Code (fitur yang ditulis lengkap tapi tidak pernah dipakai)

| # | Lokasi | Keterangan |
|---|--------|------------|
| **#Dead-1** | `login_controller.dart`, `mfa_screen.dart`, `auth_remote_source.dart` (`submitCredentials`, `submitMfaCode`, `initSession`) | Seluruh flow login username/password + MFA manual **tidak pernah dipanggil** — `login_screen.dart` cuma `context.push('/login/webview')`, langsung ke WebView login. Route `/mfa` terdaftar di router tapi tidak ada tombol/navigasi manapun yang mengarah ke sana. |
| **#Dead-2** | `notification_rule_service.dart` (seluruh file: `evaluateAlerts`, `notificationRulesProvider`, kategori melee/vandal/phantom/operator/sheriff) | Tidak direferensikan dari file manapun (`grep` kosong). Sistem smart-notification per kategori senjata sudah ditulis lengkap tapi 100% tidak terpakai. |

### 6.3 Bug Logic / Kalkulasi Salah

| # | Lokasi | Bug |
|---|--------|-----|
| **#I** | `match_details.dart` → `PlayerStats.kda` | `(kills + assists) / deaths.clamp(1, 999)` — kalau deaths beneran 0 (ace tanpa mati), hasilnya dihitung seolah deaths=1 (jadi angka KDA under-reported), bukan ditandai sebagai "Perfect"/infinite. Silent math error. |
| **#M** | `profile_screen.dart` → `_XpCard` | `xp.xp % 10000` mengasumsikan tiap level butuh persis 10.000 XP flat. Riot tidak pakai threshold flat — beda level beda kebutuhan XP. Progress bar & angka XP yang ditampilkan kemungkinan besar **salah** untuk sebagian besar level. |
| **#F** | `rank_screen.dart` → `_RrTrendSummaryCard` | `losses = updates.where((u) => !u.isWin && rankedRatingEarned < 0)` — draw/match ter-nullify (RR change = 0) tidak terhitung sebagai win maupun loss, jadi `wins + losses` bisa tidak match total match dalam 10 game terakhir. |
| **#Q** | `storefront.dart` → `Storefront.fromJson` | Harga skin di-mapping ke `SingleItemOfferIds` murni berdasarkan **index array**, bukan ID matching eksplisit terhadap `SingleItemStoreOffers`. Kalau Riot pernah ubah urutan salah satu list ini, harga yang ditampilkan bisa ketuker/salah tanpa error apapun — silent data corruption. |
| **#G** | `player_mmr.dart` → `PlayerMmr.fromJson` | `seasonal.values.toList().reversed` mengasumsikan urutan Map JSON `SeasonalInfoBySeasonID` selalu urut kronologis. Tidak ada sorting eksplisit by season ID/timestamp — rapuh terhadap perubahan urutan response API. |
| **#E** | `contracts.dart` → `Contract.fromJson` | `isActive: json['ContractDefinitionID'] == activePuuid` — field ini cuma valid untuk mengecek battlepass aktif, tapi diberi nama generik `isActive` dan dipakai untuk semua jenis contract. Agent contract non-battlepass yang sedang aktif digrind akan selalu bernilai `isActive: false`. |

### 6.4 Duplikasi Kode & Inkonsistensi Data (Bug Desain)

| # | Lokasi | Masalah |
|---|--------|---------|
| **#H/#J** | `match_history.dart` (`mapDisplayName`), `match_history_screen.dart` (`_resolveMapName`), `match_detail_screen.dart` (`_mapName`) | **3 implementasi terpisah** dari fungsi yang sama persis (resolve map codename → nama tampilan), semuanya pakai `.contains()` substring matching yang rawan false-positive, dan semuanya **tidak memakai** `codenameMap` yang sudah ada rapi & tersentral di `valorant_assets.dart` (`getMapsMap`). 4 sumber kebenaran berbeda untuk 1 hal — kalau ada map baru, developer harus update di ≥3 tempat manual dan gampang lupa satu. |
| **#S/#W** | `notification_rule_service.dart` (dead code) dan `wishlist_catalog_screen.dart` | Filter kategori "Melee" (list keyword: knife, karambit, blade, dagger, axe, sword, scythe, hammer, mace, butterfly, onimaru, fan) di-copy-paste identik di 2 tempat berbeda. Kategori lain di `wishlist_catalog_screen.dart` (Ares, Judge, dll) pakai `name.contains(catLower)` polos — rawan false-positive substring match. |
| **#T** | `tier_colors.dart` (`TierColors.byUuid`) vs `skin_detail_modal.dart` (`_tierLabel`) | **UUID content tier BERBEDA** antar dua file untuk tier yang sama (Select, Deluxe, Ultra, Exclusive semuanya beda UUID; cuma Premium yang cocok). Akibatnya warna kartu skin (dari `TierColors`) dan label edisi di modal detail (`_tierLabel`) kemungkinan besar **tidak konsisten** untuk skin yang sama — badge/warna vs label bisa saling kontradiksi. Perlu diverifikasi ulang terhadap `valorant-api.com/v1/contenttiers` untuk menentukan mana yang benar. |
| **#U** | `wishlist_provider.dart` (`wishlistProvider`) vs `shop_screen.dart` (`_wishlistProvider`, `StateProvider<Set<String>>` privat) | **Dua state Riverpod terpisah** untuk data wishlist yang sama, sama-sama baca/tulis ke `CacheStorage` yang sama tapi **tidak saling sinkron** secara reaktif. Toggle wishlist dari `SkinDetailModal`/`WishlistCatalogScreen` (pakai `wishlistProvider`) tidak otomatis ter-refleksikan ke grid Shop (pakai `_wishlistProvider`) sampai `ShopScreen` di-rebuild ulang. |

### 6.5 Race Condition & Konkurensi

| # | Lokasi | Masalah |
|---|--------|---------|
| **#B** | `cache_storage.dart` → `saveMatchMap` | Read-modify-write (`getMatchMaps()` → modify → `setJson()`) **tanpa lock**. Kalau dipanggil concurrent (match history nge-load banyak match detail sekaligus), race condition bisa bikin entry yang baru ditulis ke-overwrite oleh proses lain yang baca versi cache lama. |
| **#K** | `match_history_screen.dart` → `_matchMapCacheProvider` | Manggil `fetchCompetitiveUpdates` (endpoint MMR, tujuan asli buat RR history) cuma buat efek samping isi cache mapId — padahal `fetchHistory` (endpoint match-history asli) **sudah** punya field `MapID` sendiri di `MatchHistoryEntry.mapId`. N+1 query yang boros dan berpotensi race dengan #B di atas. |

### 6.6 Auth / Token — Detail Tambahan

| # | Lokasi | Masalah |
|---|--------|---------|
| **#C** | `credentials_local_source.dart` → `load()` | Kalau `expiresAtStr == null`, fallback ke `DateTime.now()` — token langsung dianggap expired detik itu juga (bukan treat-as-valid atau null-safe). Bisa memicu reauth-loop kalau kondisi ini kejadian (misal data corrupt/migrasi). |
| **#D** | `silent_webview_reauth.dart` | Didesain sebagai "PRIMARY" reauth method dengan asumsi WKWebView shared-cookie behavior **iOS-only** (komentar kode eksplisit menyebutnya), pakai iOS user-agent hardcoded, tapi dipanggil di semua platform lewat `auth_repository.dart.reauth()`. Di Android, method ini kemungkinan besar **selalu gagal** (WebView Android tidak share cookie dengan cara yang sama), sehingga selalu fallback ke `cookieReauth()` — bukan bug fatal (ada fallback), tapi "PRIMARY" method ini secara efektif dead-path di luar iOS. |
| **#A** | `api_exception.dart` | Class exception (`NotFoundException`, `RateLimitedException`, `NetworkException`) didefinisikan lengkap tapi cuma `RateLimitedException` yang benar-benar dilempar di kode (`retry_interceptor.dart`). Sisanya dead code — termasuk gak ada exception khusus untuk status 400 (root cause utama), yang membuktikan gap ini disadari sebagian tapi tidak diselesaikan tuntas. |

### 6.7 Bug Minor / UX Kecil

| # | Lokasi | Masalah |
|---|--------|---------|
| **#N** | `profile_screen.dart` → `_ProfileHeader` | `displayName?.substring(0, 1)` akan throw `RangeError` kalau `displayName` adalah string kosong (`''`, bukan `null`). Provider saat ini sudah guard ini, tapi widget sendiri fragile terhadap input non-null-tapi-kosong. |
| **#O** | `tier_colors.dart` → `forName` | Minor: `byUuid` lookup case-sensitivity di-handle via `.toLowerCase()`, tidak masalah selama key `byUuid` sendiri konsisten lowercase (saat ini iya). |
| **#P** | `countdown_timer.dart` | Kalau `remainingSeconds` awal sudah 0/negatif, `onExpired` baru terpanggil setelah delay 1 detik pertama (`Timer.periodic` interval), bukan langsung invoke saat build. |
| **#R** | `shop_screen.dart` → `_refresh()` | Melakukan `ref.invalidate()` (yang otomatis re-fetch via provider) **dan** manual `repo.fetchStorefront()/fetchWallet()` sesudahnya — storefront & wallet ke-fetch 2x setiap pull-to-refresh. Boros network call, hasil manual call dibuang begitu saja (cuma dipakai buat efek-samping cache). |
| **#V** | `skin_video_player.dart` | `v.src = "$videoUrl"` di-inject langsung ke HTML string tanpa escaping. Risiko rendah (data dari API resmi), tapi tidak defensif terhadap karakter khusus. |
| **#Notif** | `notification_service.dart` | `_notifications.show(skinName.hashCode, ...)` pakai hash string sebagai notification ID — risiko kecil collision/overwrite notifikasi kalau ada 2 nama skin dengan hash yang sama (jarang terjadi tapi bukan nol). |
| **#L** | `match_detail_screen.dart` → `_TeamSection` | Pada kasus draw skor persis antara top-player tim dan match MVP, ada edge-case kecil kemungkinan 2 badge (MATCH MVP + TEAM MVP) muncul untuk 2 orang berbeda yang sebenarnya seri. |

### 6.8 Kualitas & Testing

| # | Lokasi | Masalah |
|---|--------|---------|
| **#X** | `test/widget_test.dart` | **Zero test coverage** — file test cuma placeholder kosong (`void main() {}`). Tidak ada unit test untuk logic non-trivial manapun (KDA, map resolution, tier UUID matching, MMR season parsing, harga skin index-matching) — semua bug kalkulasi di atas (#I, #M, #F, #Q, #G, #E) kemungkinan besar akan langsung ketahuan kalau ada unit test dasar. |

---

## 7. Ringkasan Prioritas (kalau mau diperbaiki bertahap)

**Kritis (mempengaruhi kebenaran data / UX inti):**
1. Root cause 400 error (Bagian 1-5): interceptor cuma handle 401, cache-fallback asimetris antar fitur, entitlement token tanpa expiry tracking.
2. #Q — harga skin index-matching tanpa validasi ID (bisa nampilin harga salah).
3. #T — UUID tier tidak konsisten (warna vs label edisi bisa kontradiksi).
4. #U — dua state wishlist gak sinkron (UX membingungkan).
5. #M — perhitungan XP progress salah (`% 10000` flat, padahal threshold per-level beda).

**Sedang (bug nyata tapi dampak lebih kecil/jarang kejadian):**
6. #I — KDA salah kalau deaths = 0.
7. #F — RR trend W/L count bisa gak akurat kalau ada draw.
8. #E — `isActive` pada Contract cuma valid untuk battlepass.
9. #B/#K — race condition & N+1 query di match map caching.
10. #H/#J — 4 implementasi map-name resolution yang tidak konsisten & tidak pakai source-of-truth yang sudah ada.

**Rendah (housekeeping / tech debt):**
11. #Dead-1, #Dead-2 — dead code (login manual, MFA, notification rules) — bisa dihapus atau benar-benar diaktifkan.
12. #A — exception class yang gak lengkap dipakai.
13. #R — double-fetch saat refresh.
14. #X — tidak ada test sama sekali.

Sesuai instruksi kamu, **belum ada satupun perubahan kode yang diimplementasikan** — dokumen ini murni hasil audit menyeluruh terhadap seluruh 56 file codebase. Bagian 8 di bawah berisi prompt siap-pakai untuk tiap perbaikan, kalau kamu mau eksekusi sendiri via Claude Code/session lain, atau minta gua kerjain satu-satu di sini.

---

## 8. Detailed Fix Prompts (siap pakai per bug)

Setiap prompt di bawah **berdiri sendiri** — bisa langsung ditempel ke Claude Code / sesi baru tanpa perlu context tambahan, karena masing-masing sudah menyertakan file, baris bermasalah, dan hasil yang diharapkan. Urutan mengikuti prioritas Bagian 7. Kerjakan satu prompt per sesi/commit supaya gampang di-review dan di-revert kalau ada yang meleset.

### 8.1 [KRITIS] Fix root cause 400 error — interceptor tidak handle 400 & entitlement token tanpa expiry tracking

```
Di project Flutter Valapp (D:\Valapp atau path lokal repo), perbaiki root cause bug 400 Bad Request yang muncul di halaman Rank/Match/Progress/Profile setelah beberapa menit pemakaian.

File yang terlibat:
- lib/core/network/interceptors/valorant_interceptor.dart
- lib/core/storage/secure_storage.dart
- lib/features/auth/domain/models/credentials.dart
- lib/features/auth/data/credentials_local_source.dart
- lib/features/auth/domain/auth_repository.dart

Masalah:
1. ValorantInterceptor.onError() cuma menangani status 401. Status 400 (yang sering muncul karena X-Riot-Entitlements-JWT basi) langsung diteruskan mentah ke UI tanpa memicu reauth.
2. Tidak ada tracking expiry terpisah untuk entitlement_token — SecureStorage.isTokenValid() dan Credentials.isExpired cuma cek access_token expiry (keyExpiresAt), padahal entitlement token Riot bisa expire lebih cepat dan endpoint mmr/match-history/account-xp/contracts validasi entitlement secara ketat.

Yang perlu dikerjakan:
1. Di ValorantInterceptor.onError(), tambahkan penanganan status 400 dengan logic yang sama seperti 401 (coba onReauth(), retry request sekali dengan token baru, kalau gagal baru propagate error asli). Gunakan flag terpisah di requestOptions.extra (misal 'entitlementRetried') supaya tidak infinite loop dan tidak bentrok dengan flag 'authRetried' yang sudah ada untuk 401.
2. PENTING: sebelum retry pada 400, validasi dulu bahwa response benar-benar mengindikasikan masalah auth (bukan 400 karena bad request format lain). Cek response body untuk pesan error spesifik dari Riot kalau ada (biasanya field 'errorCode' atau serupa) sebelum asumsikan ini token issue — supaya tidak salah trigger reauth untuk 400 yang sebenarnya bug lain.
3. Tambahkan field baru di SecureStorage: keyEntitlementExpiresAt. Set field ini setiap kali entitlement_token disimpan/diperbarui (di CredentialsLocalSource.save() dan di titik manapun entitlementToken diperbarui di AuthRepository).
4. Karena Riot tidak mengembalikan expires_in khusus untuk entitlement token, gunakan durasi konservatif hardcoded (misal 15 menit sebagai estimasi aman — beri komentar jelas bahwa ini adalah estimasi, bukan nilai resmi dari API) dan expose constant ini di bagian atas file supaya gampang di-tune nanti.
5. Di ValorantInterceptor.onRequest(), tambahkan proactive check kedua: kalau entitlement token mendekati/lewat estimated expiry (mirip pola cek access token yang sudah ada), trigger onReauth() SEBELUM request dikirim, sama seperti access token check yang sudah ada.
6. Jangan hapus atau ubah logic 401 yang sudah ada — cuma tambahkan penanganan paralel untuk 400.

Setelah selesai, jalankan `flutter analyze` untuk pastikan tidak ada error, dan tunjukkan diff lengkap dari semua file yang diubah sebelum saya konfirmasi.
```

### 8.2 [KRITIS] Fix asimetri cache-fallback antar fitur (Shop vs Rank/Match/Profile/Contracts)

```
Di project Flutter Valapp, samakan behavior error-handling antara halaman Shop (yang punya cache-fallback) dengan halaman Rank, Match History, Match Detail, Profile, dan Contracts (yang tidak punya cache-fallback sama sekali dan langsung menampilkan raw exception ke user).

File yang terlibat:
- lib/features/shop/presentation/shop_screen.dart (referensi pola yang benar: _storefrontProvider, _walletProvider)
- lib/features/rank/presentation/rank_screen.dart (_mmrProvider, _competitiveUpdatesProvider)
- lib/features/match/presentation/match_history_screen.dart (_matchHistoryProvider)
- lib/features/match/presentation/match_detail_screen.dart (_matchDetailFamily)
- lib/features/profile/presentation/profile_screen.dart (_accountXpProvider, _displayNameProvider)
- lib/features/contracts/presentation/contracts_screen.dart (_contractsProvider)

Masalah: provider-provider di atas (selain shop) tidak punya try/catch dengan fallback ke cache lokal. Begitu fetch gagal (400/timeout/apapun), FutureProvider reject dan widget menampilkan pesan exception mentah (contoh: "DioException [bad response]: This exception was thrown because the response has a status code of 400...") langsung ke user, tanpa retry otomatis atau fallback data lama.

PENTING — bedanya dengan Shop: Shop punya CacheStorage terpisah khusus (StoreLocalCache) yang eksplisit menyimpan raw JSON storefront/wallet. Rank/Match/Profile/Contracts BELUM punya mekanisme cache serupa sama sekali — jadi task ini butuh 2 tahap:

TAHAP 1 — Tambahkan local cache sederhana untuk tiap fitur:
1. Di lib/core/storage/cache_storage.dart, tambahkan key constants baru: keyMmrCache, keyMmrCacheFetchedAt, keyMatchHistoryCache, keyMatchHistoryCacheFetchedAt, keyAccountXpCache, keyAccountXpCacheFetchedAt, keyContractsCache, keyContractsCacheFetchedAt (ikuti pola getJson/setJson yang sudah ada di file ini, JANGAN ubah struktur kelas yang sudah ada).
2. Buat method cache save/load untuk tiap fitur, taruh di masing-masing data source atau buat file cache baru per fitur (ikuti pola StoreLocalCache di lib/features/shop/data/store_local_cache.dart sebagai referensi struktur).

TAHAP 2 — Tambahkan try/catch fallback di tiap provider:
Untuk SETIAP provider yang disebutkan di atas, ubah pola dari:
    return await source.fetchXxx(...);
menjadi:
    try {
      final result = await source.fetchXxx(...);
      await cache.saveXxx(result); // simpan ke cache setelah sukses
      return result;
    } catch (e) {
      final cached = await cache.loadXxx(); // fallback ke cache kalau ada
      if (cached != null) return cached;
      rethrow; // kalau tidak ada cache sama sekali, baru lempar error asli ke UI
    }

PENTING: jangan menelan error secara diam-diam kalau tidak ada cache sama sekali (beda dengan behavior Shop saat ini yang cuma `catch (_) { return repo.loadCachedStorefront(); }` dan bisa return null diam-diam). Gunakan `rethrow` sebagai fallback terakhir supaya user tetap tahu ada masalah kalau memang belum pernah ada data tersimpan.

Juga tambahkan indikator visual "menampilkan data cache — data mungkin tidak update" di UI screen yang bersangkutan ketika data yang ditampilkan berasal dari cache (bukan fetch baru), supaya user tidak salah kira data selalu real-time seperti masalah yang terjadi di Shop.

Tunjukkan semua file yang diubah/dibuat, lalu jalankan flutter analyze sebelum saya review.
```

### 8.3 [KRITIS] Fix harga skin salah karena index-matching tanpa validasi ID

```
Di project Flutter Valapp, perbaiki logic parsing harga skin di storefront yang saat ini rentan salah karena murni mengandalkan urutan index array dari API Riot.

File: lib/features/shop/domain/models/storefront.dart, method Storefront.fromJson()

Kode saat ini (sekitar baris 217-239):
    final dailyOffers = <SkinOffer>[];
    for (int i = 0; i < singleItemOfferIds.length; i++) {
      final id = singleItemOfferIds[i];
      int price = 0;
      if (i < singleItemStoreOffers.length) {
        final storeOffer = singleItemStoreOffers[i] as Map<String, dynamic>? ?? {};
        final cost = storeOffer['Cost'] as Map<String, dynamic>? ?? {};
        price = (cost['85ad13f7-3d1b-5128-9eb2-7cd8ee0b5741'] as num?)?.toInt() ?? 0;
      }
      dailyOffers.add(SkinOffer(offerId: id, skinLevelUuid: id, price: price));
    }

Masalah: harga di-ambil dari singleItemStoreOffers[i] berdasarkan index yang SAMA dengan singleItemOfferIds[i], dengan asumsi kedua list Riot selalu berurutan 1:1. Tidak ada validasi bahwa storeOffer benar-benar merujuk ke offer ID yang sama.

Yang perlu dikerjakan:
1. Cek dulu struktur JSON asli field 'SingleItemStoreOffers' dari response Riot storefront API (kalau kamu punya contoh response JSON tersimpan/log, gunakan itu; kalau tidak, cari referensi dari dokumentasi unofficial Riot API seperti valapi.dev atau repo open-source lain yang sudah handle endpoint ini) — pastikan apakah tiap object di 'SingleItemStoreOffers' punya field 'OfferID' yang bisa dicocokkan dengan id di 'SingleItemOffers'.
2. Kalau field ID tersedia di SingleItemStoreOffers, ubah logic jadi mencari objek yang OfferID-nya cocok dengan id (pakai .firstWhere atau bikin Map<String, dynamic> keyed by OfferID dulu untuk O(1) lookup), BUKAN pakai index i secara langsung.
3. Kalau ternyata field ID memang tidak ada di response Riot (index memang satu-satunya cara resmi), maka minimal tambahkan defensive check: kalau singleItemOfferIds.length != singleItemStoreOffers.length, log warning yang jelas (misal via debugPrint dengan prefix '[Storefront] WARNING: offer/price list length mismatch') supaya developer sadar kalau asumsi index-matching ini pernah gagal saat production, dan tambahkan komentar di kode yang menjelaskan bahwa ini adalah known limitation dari API Riot, bukan bug aplikasi.
4. Tulis unit test baru di test/ (buat file test/storefront_model_test.dart) yang memverifikasi Storefront.fromJson() dengan JSON sample yang punya jumlah SingleItemOffers dan SingleItemStoreOffers yang match, dan satu kasus lagi yang sengaja tidak match untuk memastikan defensive check berjalan.

Tunjukkan hasil investigasi struktur JSON di langkah 1 sebelum lanjut implementasi, supaya saya bisa konfirmasi pendekatan mana yang dipakai.
```

### 8.4 [KRITIS] Fix inkonsistensi UUID content tier antara warna kartu dan label edisi

```
Di project Flutter Valapp, perbaiki inkonsistensi UUID content tier Valorant yang menyebabkan warna kartu skin dan label edisi (Select/Deluxe/Premium/Ultra/Exclusive) berpotensi tidak cocok untuk skin yang sama.

File yang terlibat:
- lib/shared/utils/tier_colors.dart (class TierColors, field byUuid)
- lib/features/shop/presentation/skin_detail_modal.dart (method _tierLabel)

Masalah: dua file ini punya daftar UUID content tier yang BERBEDA untuk tier yang sama:
- tier_colors.dart byUuid: Select=12683d76-48d7-84a3-4e09-6985794f0445, Deluxe=0cebb8be-46d7-c12a-d306-e9907bfc5a25, Premium=60bca009-4182-7998-dee7-b8a2558dc369, Ultra=411e4a55-4e59-7757-41f0-86a53f101bb5, Exclusive=e046854e-406c-37f4-6607-19a9ba8426fc
- skin_detail_modal.dart _tierLabel: Select=12664872-466b-4c78-8b23-66a4c734fa5a, Deluxe=0fe42732-4e20-704e-8e3b-92865d667230, Premium=60bca009-4182-7998-dee7-b8a2558dc369, Ultra=e046854e-406c-37f4-6607-11ae36026091, Exclusive=12664872-466b-4c78-8b23-66a4c734fa5a_ex/...fa5b

Hanya Premium yang cocok antara keduanya. Ini kemungkinan besar typo/copy-paste error dari salah satu atau kedua sumber saat development.

Yang perlu dikerjakan:
1. Fetch data resmi dan terkini dari https://valorant-api.com/v1/contenttiers (endpoint publik, tidak butuh auth) untuk mendapatkan daftar UUID content tier yang benar dan terverifikasi, beserta displayName dan highlightColor masing-masing.
2. Bandingkan hasil fetch tersebut dengan kedua daftar UUID yang ada di codebase saat ini, tentukan mana yang benar (kemungkinan besar tidak satupun yang 100% benar, jadi utamakan hasil fetch API sebagai source of truth).
3. Konsolidasikan jadi SATU sumber kebenaran tunggal untuk UUID content tier — sebaiknya taruh di tier_colors.dart sebagai satu-satunya tempat yang punya daftar UUID (byUuid), lalu ubah skin_detail_modal.dart._tierLabel() supaya memakai TierColors.byUuid untuk pencocokan UUID (jangan duplikasi daftar UUID di dua tempat lagi), dan tambahkan mapping displayName yang sesuai di tier_colors.dart juga (misal Map<String, String> tierDisplayNames keyed by UUID yang sama).
4. Update kedua warna (byUuid) dan label (tierDisplayNames baru) sesuai hasil fetch API resmi di langkah 1.
5. Setelah perubahan, pastikan skin_detail_modal.dart tidak lagi punya daftar UUID sendiri — cukup panggil helper baru dari tier_colors.dart.
6. Test manual: buka skin dengan tier Deluxe, Premium, Ultra, dan Exclusive (kalau ada akses ke shop asli), pastikan warna kartu dan label edisi di modal detail konsisten satu sama lain.

Tunjukkan hasil fetch dari valorant-api.com/v1/contenttiers dan perbandingannya dengan kedua daftar lama sebelum melakukan perubahan kode, supaya saya bisa verifikasi datanya benar.
```

### 8.5 [KRITIS] Fix dua state wishlist yang tidak sinkron

```
Di project Flutter Valapp, perbaiki bug dimana ada DUA state Riverpod terpisah untuk data wishlist yang sama, yang menyebabkan toggle wishlist dari satu screen tidak langsung terlihat di screen lain.

File yang terlibat:
- lib/features/shop/presentation/wishlist_provider.dart (wishlistProvider, WishlistNotifier — dipakai oleh skin_detail_modal.dart dan wishlist_catalog_screen.dart)
- lib/features/shop/presentation/shop_screen.dart (_wishlistProvider, StateProvider<Set<String>> privat — cuma dipakai internal shop_screen.dart, di-load manual di _loadWishlist() saat initState)

Masalah: kedua provider ini sama-sama baca/tulis ke CacheStorage.instance (getWishlist/addToWishlist/removeFromWishlist) tapi merupakan Riverpod provider yang benar-benar terpisah dan tidak saling watch/listen. Kalau user toggle wishlist dari SkinDetailModal (pakai wishlistProvider), state _wishlistProvider di ShopScreen tidak otomatis ter-update sampai ShopScreen di-rebuild ulang secara independen.

Yang perlu dikerjakan:
1. Hapus _wishlistProvider (StateProvider<Set<String>> privat) dan seluruh method _loadWishlist() dari shop_screen.dart.
2. Ganti semua penggunaan _wishlistProvider di shop_screen.dart supaya menggunakan wishlistProvider yang sudah ada di wishlist_provider.dart (import file tersebut). Perhatikan: wishlistProvider mengembalikan List<String>, sedangkan _wishlistProvider lama mengembalikan Set<String> — sesuaikan semua pemakaian yang mengandalkan method Set (misal .contains() tetap ada di List, jadi seharusnya kompatibel, tapi cek ulang semua pemanggilan seperti wishlist.contains(...) di seluruh shop_screen.dart untuk memastikan tidak ada method spesifik-Set yang dipakai).
3. Untuk method _toggleWishlist(SkinOffer offer) di shop_screen.dart, ganti implementasinya supaya memanggil ref.read(wishlistProvider.notifier).toggle(offer.skinLevelUuid) (method yang sudah ada di WishlistNotifier), bukan manipulasi state manual seperti sekarang.
4. Hapus pemanggilan NotificationService.instance.requestPermissions() dari dalam _loadWishlist() lama — pindahkan ke initState() langsung supaya tetap terpanggil tanpa bergantung pada wishlist loading.
5. Setelah perubahan, pastikan tidak ada import yang tidak terpakai (cache_storage.dart mungkin masih dipakai untuk hal lain di file ini, cek dulu sebelum dihapus importnya).

Setelah selesai, jalankan flutter analyze, lalu tunjukkan diff lengkap shop_screen.dart untuk saya review sebelum saya konfirmasi perubahan ini final.
```

### 8.6 [KRITIS] Fix perhitungan account XP progress yang salah

```
Di project Flutter Valapp, perbaiki perhitungan progress XP account level yang saat ini mengasumsikan setiap level butuh persis 10.000 XP flat, padahal Riot menggunakan threshold XP yang berbeda-beda per level.

File: lib/features/profile/presentation/profile_screen.dart, class _XpCard, method build()

Kode saat ini:
    final progress = (xp.xp % 10000) / 10000.0;
    ...
    Text('${xp.xp % 10000} / 10,000', ...)

Masalah: field xp.xp dari API account-xp Riot adalah XP TOTAL/AKUMULATIF milik akun, bukan XP dalam level saat ini. Menggunakan modulo 10000 mengasumsikan setiap level butuh XP yang sama persis, yang tidak akurat untuk sistem leveling Valorant.

Yang perlu dikerjakan:
1. Cek response asli dari endpoint account-xp Riot (https://pd.<shard>.a.pvp.net/account-xp/v1/players/<puuid>) — field 'Progress' biasanya berisi {'Level': int, 'XP': int}. Cari tahu dari dokumentasi unofficial API (valapi.dev atau sumber referensi lain) apakah field 'XP' ini adalah XP-dalam-level-saat-ini (yang mereset tiap naik level) ATAU XP total akumulatif sepanjang karier akun.
2. Kalau field 'XP' memang sudah merepresentasikan XP dalam level saat ini (bukan total), maka masalahnya cuma di angka pembagi 10000 yang hardcoded — cari tahu threshold XP resmi Valorant per level (biasanya ada di dokumentasi/wiki komunitas Valorant, cek beberapa sumber untuk memvalidasi apakah threshold-nya flat 10.000 di semua level atau bertingkat).
3. Kalau threshold memang bertingkat (misal berbeda untuk level 1-20 vs 20+), buat lookup table atau formula yang sesuai, dan ubah kalkulasi progress supaya pakai threshold yang benar berdasarkan xp.level, bukan angka 10000 hardcoded.
4. Kalau ternyata field 'XP' dari Riot adalah XP TOTAL AKUMULATIF (bukan per-level), maka perlu logic tambahan untuk menghitung XP-dalam-level-saat-ini dengan mengurangi XP total dengan total-XP-yang-dibutuhkan-untuk-mencapai-level-saat-ini (butuh tabel kumulatif threshold per level).
5. Update UI di _XpCard supaya menampilkan angka yang benar berdasarkan hasil investigasi di atas, dan tambahkan komentar kode yang menjelaskan sumber/asumsi threshold yang dipakai supaya developer berikutnya paham kenapa angkanya seperti itu.

Tunjukkan hasil investigasi struktur data XP Riot di langkah 1-2 sebelum implementasi, sertakan sumber referensi yang dipakai, supaya saya bisa verifikasi sebelum kamu ubah kode.
```

### 8.7 [SEDANG] Fix KDA yang salah ketika deaths = 0

```
Di project Flutter Valapp, perbaiki perhitungan KDA yang salah untuk kasus deaths = 0 (misal player ace tanpa mati sama sekali dalam satu match).

File: lib/features/match/domain/models/match_details.dart, class PlayerStats, getter kda

Kode saat ini:
    double get kda =>
        roundsPlayed > 0 ? (kills + assists) / deaths.clamp(1, 999) : 0.0;

Masalah: kalau deaths beneran 0, deaths.clamp(1, 999) memaksa nilai jadi 1, sehingga KDA yang ditampilkan under-reported (misal 20 kills + 10 assists + 0 deaths ditampilkan sebagai 30.0, padahal seharusnya direpresentasikan sebagai "Perfect" atau nilai infinite/sangat tinggi yang ditandai khusus).

Yang perlu dikerjakan:
1. Ubah getter kda supaya mengembalikan nilai yang jelas menandakan kasus deaths=0 secara terpisah — bisa dengan menambahkan getter baru bool get isPerfectKda => deaths == 0 && roundsPlayed > 0, dan biarkan getter kda tetap menghitung dengan clamp(1, 999) untuk kasus non-perfect TAPI dokumentasikan dengan jelas di komentar bahwa nilai ini bukan KDA sesungguhnya kalau isPerfectKda true.
2. Di semua tempat UI yang menampilkan KDA (cek dengan grep 'kda' di seluruh lib/features/match/presentation/), tambahkan logic: kalau player.isPerfectKda == true, tampilkan teks khusus seperti 'PERFECT' atau simbol infinity (∞) alih-alih angka KDA biasa.
3. Cari semua pemanggilan player.kda di codebase (grep -rn '\.kda' lib/) dan pastikan semua tempat pemanggilan sudah disesuaikan dengan poin 2 di atas — jangan sampai ada satu tempat yang lupa diupdate dan masih menampilkan angka KDA biasa untuk kasus perfect.
4. Tulis unit test baru (test/player_stats_test.dart) yang memverifikasi: kasus normal (deaths > 0) menghasilkan KDA yang benar, dan kasus deaths = 0 menghasilkan isPerfectKda = true.

Tunjukkan semua lokasi UI yang menampilkan KDA sebelum diubah, supaya saya bisa lihat dulu tampilan mana saja yang akan berubah.
```

### 8.8 [SEDANG] Fix perhitungan W/L RR trend yang tidak akurat untuk draw/nullified match

```
Di project Flutter Valapp, perbaiki perhitungan win/loss count di RR trend summary yang tidak akurat kalau ada draw atau match yang di-nullify oleh Riot dalam 10 game competitive terakhir.

File: lib/features/rank/presentation/rank_screen.dart, class _RrTrendSummaryCard, method build()

Kode saat ini:
    final wins = updates.where((u) => u.isWin).length;
    final losses = updates.where((u) => !u.isWin && u.rankedRatingEarned < 0).length;

dimana CompetitiveUpdate.isWin didefinisikan di lib/features/rank/domain/models/player_mmr.dart sebagai:
    bool get isWin => rankedRatingEarned > 0;

Masalah: match dengan rankedRatingEarned == 0 (draw, atau match yang di-nullify Riot karena alasan tertentu seperti disconnect/cheating investigation) tidak terhitung sebagai win maupun loss, sehingga wins + losses bisa lebih kecil dari total match yang ditampilkan (jumlah item di updates list), membuat W/L record yang ditampilkan user terlihat tidak konsisten dengan jumlah pertandingan.

Yang perlu dikerjakan:
1. Tambahkan getter baru di CompetitiveUpdate (player_mmr.dart): bool get isDraw => rankedRatingEarned == 0 && afkPenalty == 0 (perhatikan afkPenalty karena match dengan AFK penalty tapi RR change 0 kemungkinan besar bukan draw murni, melainkan match yang di-void — sesuaikan logic ini kalau setelah investigasi ternyata asumsi ini kurang tepat).
2. Update _RrTrendSummaryCard supaya menghitung draws = updates.where((u) => u.isDraw).length juga, dan tampilkan sebagai bagian ketiga di UI (misal '{wins} W / {losses} L / {draws} D' kalau draws > 0, atau tetap '{wins} W / {losses} L' kalau draws == 0 supaya tidak mengubah tampilan untuk kasus normal).
3. Pastikan wins + losses + draws selalu sama dengan updates.length setelah perubahan ini — tambahkan assertion di dalam kode (misal via assert() saat debug mode) untuk memverifikasi invariant ini.
4. Update juga tempat lain yang mungkin menggunakan logic serupa (cek dengan grep -rn 'isWin' lib/ untuk memastikan tidak ada tempat lain yang perlu penyesuaian serupa).

Tunjukkan dulu hasil analisis apakah asumsi 'RR change 0 = draw/nullified' ini benar berdasarkan pengujian nyata (misal screenshot data mentah dari beberapa match competitive update kalau ada), sebelum saya konfirmasi perubahan logic ini.
```

### 8.9 [SEDANG] Fix field isActive pada Contract yang cuma valid untuk battlepass

```
Di project Flutter Valapp, perbaiki field isActive pada model Contract yang secara misleading diberi nama generik padahal cuma valid untuk mengecek battlepass yang sedang aktif, bukan semua jenis contract.

File: lib/features/contracts/domain/models/contracts.dart, class Contract, factory Contract.fromJson()

Kode saat ini:
    factory Contract.fromJson(Map<String, dynamic> json, String? activePuuid) {
      return Contract(
        contractId: json['ContractDefinitionID'] as String? ?? '',
        ...
        isActive: json['ContractDefinitionID'] == activePuuid,
      );
    }

dimana activePuuid sebenarnya adalah activeSpecialContractId (ID battlepass yang sedang aktif), bukan PUUID player. Nama parameter ini sendiri juga membingungkan (activePuuid padahal isinya contract ID, bukan PUUID).

Masalah: field isActive akan selalu false untuk semua agent contract non-battlepass yang sedang di-progress oleh player, walaupun sebenarnya contract itu aktif digrind. Field ini HANYA benar untuk mengecek "apakah contract ini adalah battlepass yang sedang aktif".

Yang perlu dikerjakan:
1. Rename parameter activePuuid menjadi activeSpecialContractId di factory Contract.fromJson() supaya jelas maksudnya (cek semua pemanggilan factory ini di PlayerContracts.fromJson() dan sesuaikan juga).
2. Rename field isActive menjadi isActiveBattlepass supaya jelas bahwa field ini spesifik untuk battlepass, BUKAN indikasi umum "contract ini sedang aktif/di-progress".
3. Cek semua pemakaian Contract.isActive di seluruh codebase (grep -rn '\.isActive' lib/features/contracts/) dan update ke nama baru isActiveBattlepass.
4. Kalau memang dibutuhkan indikator umum "apakah contract sedang di-progress oleh player" (terlepas dari battlepass atau bukan), pertimbangkan menambahkan logic terpisah berdasarkan data yang tersedia di response Riot (misal cek apakah progressionTowardsNextLevel > 0 atau progressionLevelReached > 0 sebagai proxy "sedang aktif digrind" — investigasi dulu field apa saja yang tersedia di response asli contracts API Riot untuk menentukan pendekatan yang paling akurat).
5. Update getter PlayerContracts.activeBattlepass supaya tetap konsisten menggunakan nama field baru.

Tunjukkan semua lokasi yang terpengaruh oleh rename ini sebelum diubah, dan jelaskan pendekatan apa yang dipakai untuk poin 4 kalau memang mau ditambahkan.
```

### 8.10 [SEDANG] Fix race condition di cache match-map dan N+1 query yang tidak perlu

```
Di project Flutter Valapp, perbaiki race condition pada read-modify-write cache match-map dan hilangkan N+1 query yang tidak perlu saat load match history.

File yang terlibat:
- lib/core/storage/cache_storage.dart, method saveMatchMap()
- lib/features/match/presentation/match_history_screen.dart, provider _matchMapCacheProvider
- lib/features/match/domain/models/match_history.dart, class MatchHistoryEntry (field mapId sudah tersedia dari endpoint match-history langsung)

Masalah 1 — Race condition: saveMatchMap() melakukan read-modify-write tanpa lock:
    Future<void> saveMatchMap(String matchId, String mapId) async {
      if (matchId.isEmpty || mapId.isEmpty) return;
      final current = await getMatchMaps();
      current[matchId] = mapId;
      await setJson(keyMatchMapCache, current);
    }
Kalau dipanggil concurrent (misal beberapa fetchMatchDetails() jalan bersamaan), race condition bisa membuat entry yang baru ditulis oleh satu proses ke-overwrite oleh proses lain yang membaca versi cache lama.

Masalah 2 — N+1 query tidak perlu: _matchMapCacheProvider di match_history_screen.dart memanggil fetchCompetitiveUpdates() (endpoint MMR, untuk RR history) hanya untuk efek samping mengisi cache mapId, padahal fetchHistory() (endpoint match-history yang memang dipakai untuk load match history) SUDAH mengembalikan field MapID langsung di setiap MatchHistoryEntry.mapId.

Yang perlu dikerjakan:
1. Untuk masalah 1: tambahkan mutex/lock sederhana di CacheStorage untuk operasi saveMatchMap(). Bisa menggunakan package 'synchronized' (tambahkan ke pubspec.yaml) atau implementasi lock manual menggunakan Completer, supaya read-modify-write pada key yang sama tidak bisa dilakukan dua proses bersamaan. Terapkan lock ini di level method saveMatchMap(), bukan di level pemanggil.
2. Untuk masalah 2: hapus provider _matchMapCacheProvider dan panggilan fetchCompetitiveUpdates() yang cuma untuk efek samping tersebut. Ganti seluruh logic resolve map di _MatchTile (match_history_screen.dart) supaya langsung memakai entry.mapId dari MatchHistoryEntry yang sudah didapat dari _matchHistoryProvider, tanpa perlu fetch tambahan sama sekali.
3. Setelah perubahan poin 2, cek apakah CacheStorage.saveMatchMap() dan getMatchMaps() masih dipakai di tempat lain (grep -rn 'saveMatchMap\|getMatchMaps' lib/) — kalau ternyata hanya dipakai di alur yang baru saja dihapus, pertimbangkan untuk menghapus method-method tersebut sepenuhnya dari CacheStorage supaya tidak jadi dead code, TAPI cek dulu apakah mmr_remote_source.dart (fetchCompetitiveUpdates) juga memanggil saveMatchMap sebagai side-effect yang dipakai fitur lain sebelum dihapus.
4. Pastikan setelah perubahan ini, tampilan map name di match history screen tetap berfungsi dengan benar menggunakan entry.mapId langsung.

Tunjukkan hasil grep dari poin 3 sebelum menghapus method apapun dari CacheStorage, supaya saya bisa konfirmasi tidak ada fitur lain yang akan rusak.
```

### 8.11 [SEDANG] Konsolidasi 4 implementasi map-name resolution jadi satu sumber kebenaran

```
Di project Flutter Valapp, konsolidasikan 4 implementasi terpisah dari fungsi resolve map codename → nama tampilan yang saat ini terduplikasi dan tidak konsisten, menjadi satu sumber kebenaran tunggal.

File yang terlibat (semua punya logic serupa yang perlu dikonsolidasi):
- lib/features/match/domain/models/match_history.dart, getter MatchHistoryEntry.mapDisplayName
- lib/features/match/presentation/match_history_screen.dart, method _MatchTile._resolveMapName()
- lib/features/match/presentation/match_detail_screen.dart, method _MatchDetailsContent._mapName()
- lib/shared/utils/valorant_assets.dart, method ValorantAssets.getMapsMap() (SUDAH punya codenameMap yang tersentral dan lebih reliable — ini yang harusnya jadi acuan)

Masalah: 3 tempat pertama masing-masing mengimplementasikan ulang string-matching manual (pakai .contains() untuk deteksi codename seperti 'plummet', 'jam', 'juliett', dst) secara independen dan identik satu sama lain, TIDAK memakai codenameMap yang sudah ada rapi di valorant_assets.dart.getMapsMap(). Ini bikin 4 sumber kebenaran berbeda untuk hal yang sama — kalau ada map baru dirilis Riot, developer harus ingat update di 3 tempat manual dan gampang lupa salah satu.

Yang perlu dikerjakan:
1. Jadikan valorant_assets.dart.getMapsMap() sebagai satu-satunya sumber resolve map name. Method ini sudah async dan network-based (fetch dari valorant-api.com), jadi pendekatannya harus disesuaikan supaya bisa dipanggil dari getter sync MatchHistoryEntry.mapDisplayName (yang saat ini sync).
2. Ubah MatchHistoryEntry.mapDisplayName dari getter sync menjadi method yang menerima parameter Map<String, dynamic> mapsData (hasil dari getMapsMap() yang sudah di-resolve di level provider/widget), lalu di dalamnya cukup lookup ke mapsData[mapId.toLowerCase()]['displayName'] alih-alih re-implementasi string matching manual.
3. Hapus seluruh method _resolveMapName() di match_history_screen.dart dan _mapName() di match_detail_screen.dart. Ganti pemanggilannya supaya memakai _mapsMapProvider yang SUDAH ADA di kedua file tersebut (sudah memanggil assets.getMapsMap()) dikombinasikan dengan method baru di poin 2.
4. Pastikan codenameMap di valorant_assets.dart.getMapsMap() sudah mencakup semua alias codename yang sebelumnya ada di 3 implementasi lama (plummet/infinity→abyss, jam→lotus, juliett→sunset, canyon→fracture, port→icebox, lowpe/pitt→pearl, foxtrot→drift, triad→haven, bonsai→split, duality→bind) — bandingkan satu per satu untuk memastikan tidak ada alias yang hilang saat konsolidasi.
5. Test manual: buka match history dan match detail untuk beberapa match dengan map berbeda, pastikan nama map yang ditampilkan tetap benar dan konsisten setelah perubahan.

Tunjukkan dulu perbandingan lengkap semua alias codename dari ke-3 implementasi lama vs yang sudah ada di codenameMap valorant_assets.dart (poin 4), supaya saya bisa pastikan tidak ada yang hilang sebelum kode lama dihapus.
```

### 8.12 [RENDAH] Bersihkan dead code — flow login manual/MFA dan notification rules

```
Di project Flutter Valapp, bersihkan dead code yang teridentifikasi saat audit — fitur yang ditulis lengkap tapi tidak pernah dipanggil dari manapun di aplikasi.

Dead code #1 — Flow login username/password manual + MFA:
File: lib/features/auth/presentation/login_controller.dart, lib/features/auth/presentation/mfa_screen.dart, method-method di lib/features/auth/data/auth_remote_source.dart (submitCredentials, submitMfaCode, initSession), route '/mfa' di lib/app.dart

Konteks: app ini sekarang cuma pakai WebView login (lib/features/auth/presentation/webview_login_screen.dart, di-push dari login_screen.dart via context.push('/login/webview')). Flow manual username/password + MFA sepenuhnya tidak terpakai — tidak ada tombol atau navigasi manapun yang mengarah ke sana.

Dead code #2 — Sistem smart notification per kategori senjata:
File: lib/features/shop/presentation/notification_rule_service.dart (seluruh file — evaluateAlerts(), notificationRulesProvider, NotificationRulesNotifier, semua kategori melee/vandal/phantom/operator/sheriff/nightMarket)

Konteks: sistem ini sudah ditulis lengkap (termasuk toggle per kategori dan evaluasi alert) tapi tidak direferensikan dari file manapun di codebase (sudah diverifikasi dengan grep). Yang aktif dipakai saat ini cuma notifikasi wishlist manual di shop_screen.dart yang terpisah dan tidak memakai service ini sama sekali.

Yang perlu dikerjakan — pilih SALAH SATU pendekatan untuk tiap dead code di atas, TANYAKAN ke saya dulu sebelum eksekusi mana yang saya mau:

Opsi A (hapus): 
- Untuk dead code #1: hapus login_controller.dart, mfa_screen.dart, method-method terkait di auth_remote_source.dart (submitCredentials, submitMfaCode, initSession, dan helper terkait yang cuma dipakai method-method ini), hapus route '/mfa' dan import MfaScreen dari app.dart.
- Untuk dead code #2: hapus notification_rule_service.dart sepenuhnya.

Opsi B (aktifkan): 
- Untuk dead code #1: kalau ternyata masih dibutuhkan sebagai alternatif WebView login (misal untuk device yang WebView-nya bermasalah), tambahkan tombol 'Login manual' di login_screen.dart yang mengarah ke halaman baru berisi form username/password yang memanggil LoginController, dan pastikan alur MFA (push ke '/mfa') benar-benar terhubung dari situ.
- Untuk dead code #2: tambahkan UI settings screen baru (atau section di ProfileScreen yang sudah ada) yang menampilkan toggle untuk tiap kategori notifikasi (wishlist, melee, vandal, phantom, operator, sheriff, night market), lalu panggil evaluateAlerts() di shop_screen.dart setelah storefront berhasil di-fetch, dan trigger NotificationService.instance untuk tiap alert yang dihasilkan.

Sebelum mengeksekusi perubahan apapun, tanyakan ke saya: untuk masing-masing dead code #1 dan #2, apakah saya pilih Opsi A (hapus) atau Opsi B (aktifkan) — bisa beda pilihan untuk masing-masing.
```

### 8.13 [RENDAH] Hilangkan double-fetch saat pull-to-refresh di Shop

```
Di project Flutter Valapp, hilangkan double-fetch yang terjadi setiap kali user melakukan pull-to-refresh di halaman Shop.

File: lib/features/shop/presentation/shop_screen.dart, method _refresh()

Kode saat ini:
    Future<void> _refresh() async {
      ref.invalidate(_storefrontProvider);
      ref.invalidate(_walletProvider);

      final creds = await ref.read(currentCredentialsProvider.future);
      if (creds == null) return;

      final repo = await ref.read(storeRepositoryProvider.future);
      await repo.fetchStorefront(creds.shard, creds.puuid);
      await repo.fetchWallet(creds.shard, creds.puuid);
    }

Masalah: ref.invalidate(_storefrontProvider) sudah otomatis membuat provider tersebut re-fetch data (karena _storefrontProvider adalah FutureProvider yang akan rebuild otomatis saat di-invalidate dan di-watch ulang oleh widget). Tapi kode ini JUGA memanggil repo.fetchStorefront() dan repo.fetchWallet() secara manual sesudahnya — sehingga setiap pull-to-refresh melakukan fetch storefront dan wallet 2 kali, boros network call ke API Riot yang punya rate limit ketat.

Yang perlu dikerjakan:
1. Hapus pemanggilan manual repo.fetchStorefront() dan repo.fetchWallet() beserta blok pengambilan creds dan repo yang menyertainya di method _refresh() — cukup sisakan pemanggilan ref.invalidate(_storefrontProvider) dan ref.invalidate(_walletProvider) saja, karena RefreshIndicator.onRefresh sudah cukup dipicu oleh invalidate ini untuk membuat provider fetch ulang.
2. Setelah perubahan, method _refresh() seharusnya jadi:
    Future<void> _refresh() async {
      ref.invalidate(_storefrontProvider);
      ref.invalidate(_walletProvider);
    }
3. PENTING: karena RefreshIndicator butuh Future yang selesai untuk menghilangkan animasi loading-nya, pastikan invalidate() tetap memberikan sinyal selesai yang tepat ke RefreshIndicator. Kalau perlu, tambahkan await ref.read(_storefrontProvider.future) dan await ref.read(_walletProvider.future) setelah invalidate (bukan fetch manual terpisah lewat repo) supaya RefreshIndicator menunggu sampai data baru benar-benar selesai di-load, baru animasi refresh berhenti.
4. Test manual: lakukan pull-to-refresh beberapa kali di halaman Shop, pastikan animasi refresh berhenti dengan benar (tidak macet) dan data ter-update, dan verifikasi (misal via log/breakpoint sementara) bahwa fetchStorefront/fetchWallet di StoreRemoteSource cuma terpanggil 1x per pull-to-refresh, bukan 2x.

Tunjukkan hasil implementasi final method _refresh() sebelum saya konfirmasi.
```

### 8.14 [RENDAH] Tambahkan unit test dasar untuk logic kritis

```
Di project Flutter Valapp, tambahkan unit test dasar untuk logic-logic non-trivial yang saat ini sama sekali tidak punya test coverage (file test/widget_test.dart cuma placeholder kosong).

Prioritas logic yang perlu ditest (urutkan sesuai dampak bug yang pernah ditemukan saat audit):
1. PlayerStats.kda di lib/features/match/domain/models/match_details.dart — test kasus normal (deaths > 0) dan kasus deaths = 0.
2. CompetitiveUpdate.isWin dan getter terkait di lib/features/rank/domain/models/player_mmr.dart — test kasus win, loss, dan draw/RR-nol.
3. TierColors.forName di lib/shared/utils/tier_colors.dart — test lookup by UUID dan by nama, termasuk kasus UUID/nama yang tidak dikenal (harus fallback ke Colors.grey).
4. PlayerMmr.fromJson di lib/features/rank/domain/models/player_mmr.dart — test parsing dari JSON sample yang punya LatestCompetitiveUpdate kosong (unranked) dan yang punya data lengkap, termasuk kasus fallback ke SeasonalInfoBySeasonID.
5. Storefront.fromJson di lib/features/shop/domain/models/storefront.dart — test parsing harga skin dari JSON sample yang representatif (pakai data yang mirip struktur asli response Riot storefront API).
6. Contract.fromJson di lib/features/contracts/domain/models/contracts.dart — test bahwa battlepass ke-detect dengan benar dan agent contract non-battlepass juga ke-parse dengan benar (progressionLevelReached, progressionTowardsNextLevel).
7. MatchHistoryEntry.mapDisplayName / method resolve map name yang baru (kalau task 8.11 sudah dikerjakan) — test semua alias codename map yang dikenal.

Untuk tiap poin di atas, buat file test terpisah di folder test/ (misal test/player_stats_test.dart, test/player_mmr_test.dart, dst) mengikuti konvensi Flutter test standar (import 'package:flutter_test/flutter_test.dart', group(), test(), expect()). Gunakan JSON sample yang realistis (bisa dikarang manual berdasarkan struktur field yang sudah diketahui dari model fromJson masing-masing, tidak perlu response asli dari API Riot).

Setelah semua test dibuat, jalankan `flutter test` dan pastikan semua lolos. Tunjukkan output lengkap flutter test dan seluruh file test yang dibuat untuk saya review.
```

---

**Cara pakai bagian ini:** tiap prompt di atas bisa langsung kamu paste ke sesi Claude Code baru (atau ke gua lagi di sini) satu per satu — jangan digabung semua sekaligus supaya progress-nya gampang di-review dan di-revert kalau ada yang meleset. Prompt 8.1 sampai 8.6 (Kritis) sebaiknya dikerjakan duluan karena langsung memperbaiki bug yang paling terasa dampaknya ke pengalaman pakai app sehari-hari.
