# Audit Report — Valapp (Flutter Valorant Shop Monitor)

Tanggal: 2026-08-22 · Scope: `lib/**` (~90 file) · Verifikasi: `flutter analyze` = **No issues found**, `flutter test` = **119/119 passed**

> **Fix log (2026-08-22, pass 1):** H1 ✅, H3 ✅, H5 ✅, M1 ✅, M2 ✅, M7 ✅, M8 ✅ diperbaiki.
>
> **Fix log (2026-08-22, pass 2):** H2 (partial: freshness guard `saveIfCurrent` — token lintas-isolate tidak bisa lagi regresif), M3 ✅ (NM lookup 3 varian key), M4 ✅ (`normalizeDiscountPercent` terpusat di price_utils, format per-endpoint terdokumentasi), M5 ✅ (rollback klaim ledger), M6 ✅ (header injection retry 1×), M9 ✅ (403 tak lagi authPermanent; test spek lama diupdate), L3 ✅ (rate limiter hanya delay sisa gap), L7 ✅ (wishlist namespace dibersihkan saat hapus akun), L10 ✅.
>
> **Fix log (2026-08-22, pass 3):** L1 ✅ (MatchDetailLocalCache file-backed per-account: 1 JSON/match di application-support, tmp+rename atomic write, eviction 30 terbaru via mtime, fallback prefs blob utk legacy data & test env; purgeAccount dipanggil saat removeAccount), L2 ✅ (persist metadata skins+unified deduplikat: entry ditulis 1× per key kanonik lowercase, varian stripped-dash di-rebuild saat load — disk ±3× lebih kecil tanpa mengubah field apa pun yg dikonsumsi UI: chromas/levels/wallpaper aman), H4 partial-2 ✅ (`cookieReauth` kini menangkap header `Set-Cookie` dan upgrade backup cookie per-account dgn ssid fresh — HTTP client sah melihat HttpOnly, JS tidak).
>
> **Fix log (2026-08-22, pass 4):** L4 ✅ (`CredentialsLocalSource.loadCached()` — memo instance-local 2s khusus hot-path interceptor; inject+proactive kini 1× storage-read + JWT-decode per window, path pasca-reauth tetap `load()` segar; `const` constructor dilepas), L5 ✅ (`WishlistNotifier.toggle` resync dari state disk pasca-mutasi, bukan snapshot pra-mutasi), L6 ✅ (migrasi wishlist pindah ke `migrateLegacyWishlist` terkunci 'wishlist' dipanggil dari bootstrap notifier — read API tak lagi bermutasi; test kontrak lama diupdate + idempotency ditest), L8 ✅ (tertutup oleh pass 1: semua jalur reauth kini funnel ke `AuthRepository.reauth()` yang dedup), L9 ✅ (flag install-level `background_shop_baseline_seen`: first-run pasca-install baseline senyap; ganti akun tetap nge-notif reset).
>
> **Fix log (2026-08-22, pass 5 — FINAL):** **H4-full ✅** + **H2-full ✅**.
> - H4: platform channel `valapp/native_cookies` baru — `NativeCookieReader` (Dart, `lib/core/network/native_cookie_reader.dart`) → Android `CookieManager.getCookie()` (Kotlin `MainActivity.kt`) & iOS `WKWebsiteDataStore.httpCookieStore.getAllCookies` (Swift `AppDelegate.swift`; attach idempoten + retry root-VC aman implicit-engine). Login WebView kini menangkap cookie HttpOnly `ssid` lengkap sejak hari pertama — JS `document.cookie` turun jadi fallback desktop. **Verifikasi**: `gradlew :app:compileDebugKotlin` = **BUILD SUCCESSFUL** (pakai JBR 21; JDK 26 default PATH tidak kompatibel dgn Gradle project). Swift perlu Xcode → diverifikasi CI Codemagic saat build iOS berikutnya (API standar, risiko rendah).
> - H2: `CrossIsolateLock` (`lib/core/utils/cross_isolate_lock.dart`) — mutex lintas-isolate/process via atomic file `create(exclusive)` + stale-lock stealing 10s + fallback no-lock utk test env. Dipasang di `claimWishlistNotification`/rollback (double-guard dgn AsyncLock 'wishlist_notification_dedupe'). Skenario regressive-write token sudah diputus freshness guard pass 2 → matriks race lintas-isolate tertutup.
>
> Verifikasi pass 5: analyze 0 issue · test **130/130** (5 baru: serialisasi lock, paralel antar-key, release-on-error, claim konkuren tepat-1-winner, rollback-reclaim).
>
> **STATUS AKHIR: 24/24 TEMUAN SELESAI. Tidak ada temuan terbuka.**

Audit fokus: logic bugs, race conditions, auth lifecycle, concurrency, caching, security.

---

## Legenda
- **P0/HIGH** — bug nyata, reproducible, dampak user langsung
- **MED** — race/logic gap pada kondisi tertentu
- **LOW/PERF** — quality, latency, memory

---

## HIGH

### H1. Shared in-flight reauth future ↔ per-caller OAuth state/nonce mismatch
- **Lokasi**: `lib/features/auth/data/silent_webview_reauth.dart:28-39`, `lib/features/auth/domain/auth_repository.dart:135-198`
- **Bug**: `SilentWebviewReauth.refreshTokens(attempt)` mendedup concurrent caller dengan cara mengembalikan future milik caller PERTAMA. Caller kedua membuat `OAuthAttempt` sendiri (state/nonce beda), lalu menerima redirect URL yang berisi `state` milik caller pertama → `parseTokenRedirect(expectedState: attemptB.state)` selalu throw `OAuth state validation failed`.
- **Trigger**: dua jalur reauth hampir bersamaan — `HomeScreen._refresh()` → `ensureValidSession()` → `reauth()` DAN `ValorantInterceptor.onError(401)` → `_runSharedReauth()` (dua choke-point berbeda, tidak saling kenal).
- **Dampak**: reauth gagal palsu, error transient, kadang user diminta login ulang padahal cookie valid.
- **Fix**: dedup di SATU choke point (mis. singleton `ReauthCoordinator` yang menerima attempt dari pemangilik pertama dan me-return kredensial final, bukan URL mentah), atau jangan share URL — share hasil `Credentials`.

### H2. Cross-isolate race: Workmanager isolate vs main isolate
- **Lokasi**: `lib/core/services/background_service.dart:18-34,78-231`, `lib/core/utils/async_lock.dart`
- **Bug**: `AsyncLock`, `CacheStorage._activePuuid/_sessionGeneration`, `SilentWebviewReauth._inFlight` semuanya **per-isolate**. Background isolate (workmanager) dan main isolate bisa menulis resource yang sama bersamaan:
  - `SecureStorage.keyActiveSession` ditulis bg (`saveIfCurrent`) bersamaan dgn reauth foreground → last-writer-wins antara dua token berbeda usia (keduanya valid, tapi `entitlementExpiresAt` bisa mundur).
  - Ledger `wishlist_notification_dedupe` + `background_last_shop_ids` read-modify-write tanpa lock lintas-isolate → duplikasi notifikasi mungkin jika foreground shop-check jalan bareng bg task.
- **Dampak**: notifikasi ganda, expiry timestamp regresif, state cache inkonsisten sesekali.
- **Fix**: bandingkan `issuedAt`/monotonic stamp sebelum overwrite snapshot; pindahkan claim ledger ke atomic compare-and-set berbasis timestamp; atau jalankan bg check lewat method-channel ke main isolate bila app hidup.

### H3. Storefront v3→v2 fallback menelan SEMUA error
- **Lokasi**: `lib/features/shop/data/store_remote_source.dart:14-27`
- **Bug**: `catch (_)` di sekeliling panggilan v3 menelan 401/403/429/timeout/network error, lalu blind-retry v2 dengan auth yang sama-sama rusak. Kontras dengan implementasi background (`background_service.dart:145-156`) yang benar: fallback hanya untuk 404/405.
- **Dampak**: error asli ter-masker (UI dapat error v2), latensi 2×, 429 ganda → makin sering kena rate-limit.
- **Fix**: samakan pola dgn bg checker — `on DioException catch (e) { if (![404,405].contains(e.response?.statusCode)) rethrow; }`.

### H4. `document.cookie` tidak bisa membaca HttpOnly `ssid`
- **Lokasi**: `lib/features/auth/presentation/webview_login_screen.dart:152-161`
- **Bug**: Riot menandai cookie sesi kritis (`ssid`) sebagai HttpOnly. `runJavaScriptReturningResult('document.cookie')` hanya mengembalikan cookie non-HttpOnly → backup per-account di Keychain kemungkinan BESAR tanpa `ssid`.
- **Dampak**: restore cookie saat switch account / silent reauth (yang mengandalkan backup ini) tidak punya sesi valid → `InvalidSessionException` → user dipaksa login ulang, fitur multi-account seamless rusak di skenario cold-start.
- **Fix**: ambil cookie via platform channel: Android `WebViewCookieManager`/`CookieManager.getInstance().getCookie('https://auth.riotgames.com')`, iOS `WKWebsiteDataStore.defaultDataStore.httpCookieStore.getAllCookies`.

### H5. `removeAccount` aktif → auto-switch TANPA membersihkan/restore cookie
- **Lokasi**: `lib/features/auth/data/credentials_local_source.dart:347-368`, `lib/core/di/providers.dart:357-362`
- **Bug**: saat akun AKTIF dihapus, `_saveInternal(profiles.first.credentials)` langsung menulis snapshot akun lain, tapi:
  - in-memory cookie jar TIDAK di-`deleteAll` (cookie akun lama masih di jar),
  - cookies akun target TIDAK direstore ke native WebView store.
- **Dampak**: reauth berikutnya bisa mengembalikan token akun LAMA (yang sudah dihapus) → guard `refreshedPuuid != old.puuid` melempar `InvalidSessionException` → `onAuthFailed` menghapus session → user dilempar ke login padahal akun cadangan tersimpan valid.
- **Fix**: jalankan alur yang sama dengan `SessionActions.switchAccount` (jar.deleteAll + restore cookie target) sebelum/menisahkan snapshot.

---

## MEDIUM

### M1. `clearActiveSessionOnly()` tidak dikunci
- **Lokasi**: `lib/features/auth/data/credentials_local_source.dart:393-414`
- Read current puuid → delete keys TANPA `'credentials_save'`/`'active_session_action'` lock. Jika bersamaan dengan login/switch yang menulis snapshot baru, deletes bisa menghapus session BARU (torn state). Fix: bungkus dengan `AsyncLock.run('active_session_action', ...)`.

### M2. `switchAccount` tidak clear cookie native sebelum restore
- **Lokasi**: `lib/core/di/providers.dart:299-333`
- `jar.deleteAll()` dibersihkan, tapi WebViewCookieManager tidak di-clear. Jika akun target TIDAK punya backup cookie, `ssid` akun lama tetap hidup → silent reauth mengeluarkan token akun salah → guard menolak → switch gagal. Fix: `clearCookies()` dulu, baru restore backup target.

### M3. Night Market enrichment kehilangan satu varian key UUID
- **Lokasi**: `lib/features/shop/domain/store_repository.dart:269-277`
- Daily offers & bundles mencoba 3 varian (exact, lowercase, stripped-dash-lowercase); night market hanya 2. Skin dengan metadata tersimpan di key stripped tidak ter-enrich (nama/ikon kosong).

### M4. Inkonsistensi normalisasi discountPercent
- **Lokasi**: `lib/shared/utils/price_utils.dart:13` vs `lib/features/shop/domain/models/storefront.dart:203-205`
- `price_utils` selalu ×100 (asumsi Riot fraksi); `NightMarketOffer` pakai heuristik `>1 ? round : ×100`. Jika suatu hari Riot mengirim persen utuh di `TotalDiscountPercent`, bundle card menampilkan `-2200%`. Satukan lewat satu helper.

### M5. Claim ledger sebelum notifikasi tampil
- **Lokasi**: `lib/core/services/notification_service.dart:141-162`
- `claimWishlistNotification` mengonsumsi slot dedupe SEBELUM `_notifications.show`. Jika init/permission gagal, slot hangus — skin itu tidak akan dinotif lagi di rotasi yang sama. Fix: claim ulang/rollback jika `show` throw.

### M6. `onRequest` menelan semua exception lalu jalan tanpa header auth
- **Lokasi**: `lib/core/network/interceptors/valorant_interceptor.dart:60-85`
- Gagal load kredensial/version → request diteruskan tanpa `Authorization` → 401 pasti → memicu siklus reauth sia-sia. Minimal: fail-fast atau tandai request sebagai anonim-only.

### M7. Potensi unhandled error di `onError` (jsonEncode body)
- **Lokasi**: `lib/core/network/interceptors/valorant_interceptor.dart:221-262`
- `_isLikelyAuthError` memanggil `jsonEncode(data)` tanpa try/catch; body non-encodable melempar keluar dari `onError` async → handler tidak pernah complete → request menggantung. Fix: gunakan `data.toString().toLowerCase()`.

### M8. `_retryDio` tanpa timeout
- **Lokasi**: `lib/core/network/interceptors/valorant_interceptor.dart:45`
- Bare `Dio()` default connect/receive timeout = null. Retry pasca-reauth bisa menggantung tanpa batas, sedangkan request original punya 15s/30s. Fix: `Dio(BaseOptions(connectTimeout: 15s, receiveTimeout: 30s))`.

### M9. HTTP 403 diperlakukan authPermanent
- **Lokasi**: `lib/core/network/interceptors/valorant_interceptor.dart:180`, `lib/shared/utils/error_classifier.dart:54`
- Riot juga memakai 403 untuk IP-block/geo-block. Alur sekarang memicu reauth penuh + berpotensi wipe session untuk blok jaringan yang bukan masalah token. Pertimbangkan whitelist heuristic (header/body) sebelum klasifikasi permanen.

---

## LOW / PERF

| # | Lokasi | Catatan |
|---|--------|---------|
| L1 | `match_local_cache.dart:77-97` | ±30 match detail (ratusan KB each) dalam SATU string SharedPreferences — load penuh di startup, rewrite file utuh tiap save. Pertimbangkan file-per-match via `path_provider`. |
| L2 | `valorant_assets.dart:94-118` | Setiap level entry menyematkan array `chromas`+`levels` lengkap → blob metadata multi-MB, jsonEncode/Decode di UI isolate → jank saat cold start & pull-to-refresh force-refresh. |
| L3 | `rate_limit_interceptor.dart:27-38` | Fixed 500ms delay untuk SETIAP request termasuk saat idle → semua API minimal +500ms. Gunakan timestamp last-request; delay hanya jika gap < interval. |
| L4 | `valorant_interceptor.dart:63-66,113-114` | Kredensial dibaca 2× per request (proactive check + inject) + 2× JWT decode per load. Cache in-memory dgn TTL pendek. |
| L5 | `wishlist_provider.dart:30-42` | `toggle()` menulis state dari snapshot `current` pra-mutasi → penambahan writer lain bisa hilang dari UI sampai reload (disk tetap benar). |
| L6 | `cache_storage.dart:228-243` | Legacy wishlist migration menulis di read-path tanpa `'wishlist'` lock — benign tapi inkonsisten dgn add/remove. |
| L7 | `cache_storage.dart:345-380` + `credentials_local_source.dart:347` | `removeAccount` tidak menghapus wishlist namespace puuid terkait → orphan keys menumpang di prefs. |
| L8 | `home_screen.dart:583-643` + `auth_repository.ensureValidSession` | Reauth belum punya choke-point global; bergantung pada dedup SilentWebviewReauth yang cacat (lihat H1). |
| L9 | `background_service.dart:208-231` | First-run bg check selalu fire "shop reset" notification (lastOffers kosong) — terasa spam pasca-install. |
| L10 | `webview_login_screen.dart:190-193` | `dispose()` memanggil `loadRequest` tanpa try/catch → noise platform exception saat controller sudah dibebaskan. |

---

## Yang SUDAH Solid (patut dipertahankan)
- Atomic session snapshot `keyActiveSession` (satu write, anti-torn) + fallback migration keys.
- `CacheTransaction` generational guard (`beginUserTransaction` + `runUserTransaction` re-validasi generation di bawah lock) — mencegah stale write lintas akun.
- `ApiResponseDecoder` strict — anti poison-cache oleh body HTML/kosong.
- OAuth state + nonce + sub-subject validation di `parseTokenRedirect`; guard puuid-mismatch pasca reauth.
- Cooldown + in-flight dedup di interceptor (meski perlu satukan choke point, lihat H1).
- `AsyncLock` completer-chain menghindari error propagation antar waiter.

## Priority Fix Order (saran)
1. H1 (choke-point reauth tunggal) — paling banyak jejak error palsu.
2. H3 (fallback v2 hanya 404/405) — trivial, dampak langsung.
3. H4 + H5 + M2 (paket cookie/multi-account) — sekali refactor, sekaligus.
4. M1, M7, M8 — hardening kecil, risiko rendah.
5. H2 (cross-isolate) — desain; mulai dari monotonik stamp di snapshot.
