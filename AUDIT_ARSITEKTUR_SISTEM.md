# Audit Arsitektur & Logika Sistem Valapp

**Tanggal:** 18 Agustus 2026  
**Scope:** Rotasi toko, reauth/token, multi-account, UI error/offline, batasan iOS Keychain  
**Metode:** Verifikasi path → baca file sampai EOF → trace eksekusi dari kode aktual

---

## Executive Summary

| Metrik | Skor | Keterangan |
|--------|------|------------|
| **Kesehatan arsitektur keseluruhan** | **79 / 100** | Pola inti (SWR cache, session generation guard, shared-future reauth lock) sudah matang |
| **Konsistensi reauth lintas layar** | **68 / 100** | `HomeScreen` lengkap; layar lain hanya `invalidate` provider |

### Ringkasan kondisi

Arsitektur inti sudah melewati beberapa ronde perbaikan. Stale-while-revalidate toko, mutex refresh, pemisahan entitlement vs WebView reauth, dan isolasi cache per-`puuid` sudah terimplementasi dengan bukti kode.

Temuan paling serius saat ini:

1. **Race condition dua lifecycle listener** saat unlock pasca jam 07:00 WIB — buffer 2,5 detik rotasi bisa terlewat.
2. **Fallback cookie global** `riot_cookies_raw` masih bisa bocor antar akun saat silent reauth.
3. **Klasifikasi error UI** berbasis string-matching (false positive auth).

Gejala *"harus login ulang setelah re-sideload dengan signing identity berbeda"* adalah **keterbatasan platform iOS Keychain**, bukan bug Dart — lihat [Area 5](#area-5--batasan-platform-ios-keychain).

### Catatan path

| Path di prompt | Status |
|----------------|--------|
| `lib/shared/widgets/countdown_timer.dart` | ✅ Benar (bukan di `shop/presentation/widgets/`) |
| `ios/**/*.entitlements` | ❌ Tidak ada di repo |
| `lib/features/shop/presentation/widgets/` | ❌ Folder tidak ada |

---

## Critical Findings (P0/P1)

### P1-01 — Race resume + countdown: buffer rotasi 2,5s hilang

**Severity:** P1  
**Dampak:** Toko harian bisa fetch terlalu cepat setelah reset; transient error atau shop lama saat traffic Riot tinggi.

#### Bukti kode

| File | Baris | Peran |
|------|-------|-------|
| `lib/features/shop/presentation/home_screen.dart` | 122–130 | `didChangeAppLifecycleState(resumed)` → `_refresh()` (600ms) |
| `lib/features/shop/presentation/home_screen.dart` | 582–593 | Guard `_isRefreshing` + delay 2500ms vs 600ms |
| `lib/shared/widgets/countdown_timer.dart` | 94–102 | Observer lifecycle sendiri → `_notifyExpired()` |
| `lib/features/shop/presentation/home_screen.dart` | 504–509 | `onExpired` → `_refresh(isScheduledRotation: true)` |

#### Skenario eksekusi

1. HP dikunci sebelum 07:00 WIB, dibuka setelah 07:00 WIB.
2. `HomeScreen` resume → `_refresh()` → `_isRefreshing = true` → delay **600ms**.
3. `CountdownTimer` resume → `_remaining <= 0` → `onExpired` → `_refresh(isScheduledRotation: true)`.
4. Panggilan kedua menabrak `if (_isRefreshing) return;` (baris 583) dan **return tanpa buffer 2500ms**.

#### Solusi A — Recommended: deteksi shop expired di resume

Jangan panggil refresh generik jika shop sudah expired; biarkan `CountdownTimer.onExpired` memimpin dengan buffer penuh.

```dart
// lib/features/shop/presentation/home_screen.dart

@override
void didChangeAppLifecycleState(AppLifecycleState state) {
  if (state == AppLifecycleState.resumed) {
    final storefront = ref.read(_storefrontProvider).asData?.value;
    // Shop sudah lewat reset → CountdownTimer.onExpired akan memicu
    // _refresh(isScheduledRotation: true) dengan buffer 2.5s.
    if (storefront != null && storefront.isExpired) return;
    _refresh();
  }
}
```

#### Solusi B — Alternatif: jangan drop scheduled rotation saat guard aktif

Tambahkan flag pending agar refresh berikutnya tetap pakai buffer rotasi:

```dart
// lib/features/shop/presentation/home_screen.dart — state class

bool _isRefreshing = false;
bool _pendingScheduledRotation = false;

Future<void> _refresh({bool isScheduledRotation = false}) async {
  if (_isRefreshing) {
    if (isScheduledRotation) _pendingScheduledRotation = true;
    return;
  }
  _isRefreshing = true;
  try {
    final useRotationBuffer =
        isScheduledRotation || _pendingScheduledRotation;
    _pendingScheduledRotation = false;

    if (useRotationBuffer) {
      await Future<void>.delayed(const Duration(milliseconds: 2500));
    } else {
      await Future<void>.delayed(const Duration(milliseconds: 600));
    }
    // ... sisa logic _refresh() tidak berubah
  } finally {
    _isRefreshing = false;
  }
}
```

#### Verifikasi setelah fix

1. Mock/set `storefront.isExpired == true`, lock app, unlock setelah jam 7.
2. Log timestamp: fetch storefront harus ≥ 2500ms setelah `onExpired`, bukan 600ms.
3. Pastikan hanya **satu** invalidation `_storefrontProvider` per siklus unlock.

---

### P1-02 — Fallback cookie global bocor antar akun

**Severity:** P1  
**Dampak:** Silent reauth gagal / false auth error saat switch akun; bukan session hijack (ada guard puuid).

#### Bukti kode

| File | Baris | Perilaku |
|------|-------|----------|
| `lib/features/auth/presentation/webview_login_screen.dart` | 175–182 | Simpan ke `keyRiotCookiesFor(puuid)` **dan** `keyRiotCookiesRaw` |
| `lib/features/auth/data/silent_webview_reauth.dart` | 99–104 | Fallback ke `keyRiotCookiesRaw` jika per-akun kosong |
| `lib/core/di/providers.dart` | 267–274 | `switchAccount`: clear WebView/jar, **tidak** update cookie SecureStorage global |
| `lib/features/auth/domain/auth_repository.dart` | 171–176 | Guard puuid-mismatch → `InvalidSessionException` |

#### Skenario eksekusi

1. Login Akun B → cookie global = cookie B.
2. Switch ke Akun A → WebView cookies cleared, entitlement refreshed.
3. Silent reauth A → per-akun cookie kosong → inject cookie B dari global.
4. Reauth return token B → mismatch puuid → gagal meski token A masih valid di Keychain.

#### Solusi — 3 perubahan terkoordinasi

**1. Hapus fallback global di silent reauth**

```dart
// lib/features/auth/data/silent_webview_reauth.dart

final cookieKey = (puuid != null && puuid.isNotEmpty)
    ? SecureStorage.keyRiotCookiesFor(puuid)
    : null;
if (cookieKey == null) return; // tanpa puuid, jangan inject cookie legacy

var rawCookies = await SecureStorage.instance.read(cookieKey);
// HAPUS baris fallback:
// rawCookies ??= await SecureStorage.instance.read(SecureStorage.keyRiotCookiesRaw);
```

**2. Saat switch akun: hapus global + restore cookie akun target (opsional)**

```dart
// lib/core/di/providers.dart — SessionActions.switchAccount

await SecureStorage.instance.delete(SecureStorage.keyRiotCookiesRaw);

// Opsional — restore cookie akun target ke WebView sebelum save:
final savedRaw = await SecureStorage.instance.read(
  SecureStorage.keyRiotCookiesFor(account.puuid),
);
if (savedRaw != null && savedRaw.isNotEmpty) {
  // reuse logic inject cookie dari silent_webview_reauth.dart
}
```

**3. Saat login: tulis hanya per-akun (deprecate global)**

```dart
// lib/features/auth/presentation/webview_login_screen.dart

await SecureStorage.instance.write(
  SecureStorage.keyRiotCookiesFor(creds.puuid),
  toSave,
);
// HAPUS write ke SecureStorage.keyRiotCookiesRaw
// Migrasi one-time: saat app start, jika global ada & per-akun kosong, pindahkan ke per-akun lalu hapus global.
```

**4. `clearActiveSessionOnly`: hapus semua cookie keys aktif**

```dart
// lib/features/auth/data/credentials_local_source.dart

Future<void> clearActiveSessionOnly() async {
  final currentPuuid = (await load())?.puuid;
  final deletes = <Future<void>>[
    // ... existing deletes ...
  ];
  if (currentPuuid != null) {
    deletes.add(_storage.delete(SecureStorage.keyRiotCookiesFor(currentPuuid)));
  }
  deletes.add(_storage.delete(SecureStorage.keyRiotCookiesRaw)); // legacy cleanup
  await Future.wait(deletes);
}
```

#### Verifikasi setelah fix

1. Login A → login B → switch ke A → trigger reauth → log cookie key yang dipakai harus `_puuidA` only.
2. Pastikan tidak ada read `riot_cookies_raw` tanpa suffix puuid di codebase (`grep keyRiotCookiesRaw`).

---

### P1-03 — Klasifikasi error auth via string-matching

**Severity:** P1 (UX / misdiagnosis)  
**Dampak:** Error non-auth (termasuk `"400"` di message) ditampilkan sebagai "Sesi Autentikasi Terputus".

#### Bukti kode

```287:306:lib/shared/widgets/valorant_error_display.dart
  _ErrorDetail _parseError(Object error) {
    final str = error.toString();

    if (str.contains('401') ||
        str.contains('403') ||
        str.contains('400') ||
        // ...
```

Rank screen memperparah: exception dikonversi ke `String` sebelum parser (`rank_screen.dart:196`).

#### Solusi — Type-based error parser

Buat helper shared (mis. `lib/shared/utils/error_classifier.dart`):

```dart
import 'package:dio/dio.dart';
import '../../core/exceptions/auth_exception.dart';
import '../../core/exceptions/api_exception.dart';

enum ErrorCategory { authPermanent, authTransient, network, rateLimit, unknown }

ErrorCategory classifyError(Object error) {
  if (error is InvalidSessionException || error is TokenExpiredException) {
    return ErrorCategory.authPermanent;
  }
  if (error is TransientReauthException) {
    return ErrorCategory.authTransient; // BUKAN permanent — jangan wipe sesi
  }
  if (error is RateLimitedException) {
    return ErrorCategory.rateLimit;
  }
  if (error is DioException) {
    final code = error.response?.statusCode;
    if (code == 401 || code == 403) return ErrorCategory.authPermanent;
    if (code == 429) return ErrorCategory.rateLimit;
    if (_isNetworkDio(error)) return ErrorCategory.network;
    // 400 PD endpoint: biarkan interceptor handle; UI tampilkan generic/retry
  }
  if (_isNetworkString(error.toString())) return ErrorCategory.network;
  return ErrorCategory.unknown;
}

bool _isNetworkDio(DioException e) =>
    e.type == DioExceptionType.connectionTimeout ||
    e.type == DioExceptionType.receiveTimeout ||
    e.type == DioExceptionType.connectionError;
```

Update `ValorantErrorDisplay._parseError`:

```dart
_ErrorDetail _parseError(Object error) {
  switch (classifyError(error)) {
    case ErrorCategory.authPermanent:
      return _ErrorDetail(/* ... */, isAuthRelated: true);
    case ErrorCategory.authTransient:
      return _ErrorDetail(
        code: 'ERR // RECONNECT_PENDING',
        headline: 'Sambungan Riot Sementara Gagal',
        explanation: 'Sesi masih tersimpan. Tekan SYSTEM RECONNECT untuk mencoba lagi.',
        isAuthRelated: false, // jangan tampilkan LOGIN ULANG untuk transient
      );
    case ErrorCategory.network:
      return _networkDetail();
    // ...
  }
}
```

Update rank screen — pass exception asli, bukan string:

```dart
// lib/features/rank/presentation/rank_screen.dart
error: (e, _) => _ErrorCard(error: e), // bukan e.toString()

class _ErrorCard extends ConsumerWidget {
  const _ErrorCard({required this.error});
  final Object error;
  // ...
  child: ValorantErrorDisplay(error: error, ...),
}
```

---

## Medium / Minor Improvements (P2/P3)

### P2-01 — Inkonsistensi reauth lintas layar `ValorantErrorDisplay`

| Layar | File | Pola saat ini |
|-------|------|---------------|
| Home | `home_screen.dart:226-261` | `refreshEntitlementOnly` → `reauth` → `_refresh` + `onReauth` |
| Match History | `match_history_screen.dart:357-363` | Hanya `invalidate` provider |
| Rank | `rank_screen.dart:1332-1339` | Hanya `invalidate` |
| Loadout | `loadout_screen.dart:101-107` | Hanya `invalidate` |
| Wishlist | `wishlist_catalog_screen.dart:760-767` | Hanya `invalidate` |

#### Solusi — Shared reconnect helper

```dart
// lib/features/auth/domain/session_reconnect.dart

Future<void> reconnectAndInvalidate(
  WidgetRef ref, {
  required void Function() invalidateData,
  void Function()? onPermanentAuthFailure,
}) async {
  try {
    final local = ref.read(credentialsLocalSourceProvider);
    final creds = await local.load();
    if (creds != null && !creds.isExpired) {
      final authRepo = await ref.read(authRepositoryProvider.future);
      await authRepo.refreshEntitlementOnly(creds);
    } else if (creds != null) {
      final authRepo = await ref.read(authRepositoryProvider.future);
      await authRepo.reauth();
    }
    ref.invalidate(currentCredentialsProvider);
    invalidateData();
  } on InvalidSessionException catch (_) {
    onPermanentAuthFailure?.call();
  } on TokenExpiredException catch (_) {
    onPermanentAuthFailure?.call();
  } catch (_) {
    // Transient — preserve session, retry fetch only
    ref.invalidate(currentCredentialsProvider);
    invalidateData();
  }
}
```

Pakai di semua layar:

```dart
onRetry: () => reconnectAndInvalidate(
  ref,
  invalidateData: () => ref.invalidate(_matchHistoryProvider),
  onPermanentAuthFailure: () => context.push('/login/webview'),
),
onReauth: () => context.push('/login/webview'),
```

---

### P2-02 — Proactive interceptor: full reauth padahal entitlement saja expired

**Lokasi:** `lib/core/network/interceptors/valorant_interceptor.dart:120-131`

Reactive path sudah benar (entitlement dulu, baris 175-180). Proactive path selalu `onReauth()` (WebView ~15s).

#### Solusi

```dart
// lib/core/network/interceptors/valorant_interceptor.dart — _checkAndMaybeReauth

final accessValid = !credentials.isExpired;
final entitlementStale = credentials.isEntitlementExpired;

if (entitlementStale && accessValid && onRefreshEntitlement != null) {
  await onRefreshEntitlement!();
  _lastReauthCheckAt = DateTime.now();
  return;
}

if (credentials.isExpired) {
  await _runSharedReauth();
  _lastReauthCheckAt = DateTime.now();
}
```

---

### P2-03 — Login screen tidak menawarkan saved account setelah session clear

**Lokasi:** `lib/app.dart:49`, `lib/features/auth/presentation/login_screen.dart`

`clearActiveSessionOnly` menghapus active session tapi `valapp_saved_accounts_v1` masih berisi token. User dipaksa WebView login padahal bisa `switchAccount`.

#### Solusi

Tampilkan daftar saved account di `LoginScreen` (reuse data dari `getSavedAccounts()`), tap → `sessionActionsProvider.switchAccount(profile)`.

---

### P3-01 — Wishlist global (bukan per-akun)

**Lokasi:** `lib/core/storage/cache_storage.dart:119`, `lib/features/shop/presentation/wishlist_provider.dart`

#### Solusi

```dart
static String wishlistKeyFor(String puuid) => userKeyFor('wishlist_skin_ids', puuid);
```

Load/save wishlist keyed by `currentCredentialsProvider.puuid`. Migrasi: copy global list ke active user key sekali saat upgrade.

---

### P3-02 — Background task skip saat entitlement expired

**Lokasi:** `lib/core/services/background_service.dart:89-93`

#### Solusi (opsional)

Jika `!credentials.isExpired && credentials.isEntitlementExpired`, panggil `AuthRemoteSource.fetchEntitlementToken` + update snapshot sebelum fetch storefront — tanpa WebView.

---

## Area 5 — Batasan Platform iOS Keychain

> **Ini bukan bug kode.** Jangan paksakan fix Dart untuk masalah signing identity.

### Temuan

| Aspek | Status |
|-------|--------|
| File `.entitlements` / `keychain-access-groups` | Tidak ada — default = Bundle ID + Team ID |
| `KeychainAccessibility` | `first_unlock` (`secure_storage.dart:13`) |
| Android | `encryptedSharedPreferences` — tidak terikat signing identity |

### Behavior yang diharapkan

| Skenario | Hasil |
|----------|-------|
| Re-sideload, **Team ID sama** | Keychain terbaca, sesi persist |
| Re-sideload, **signing identity berbeda** | `load()` → null → redirect login |
| Sesi hilang, signing **identik** | Curigai bug kode / snapshot corrupt |

### Alur saat Keychain tidak terbaca

```
CredentialsLocalSource.load() → null
  → AuthRepository.reauth() → TokenExpiredException (auth_repository.dart:137-138)
  → Interceptor onAuthFailed → clearActiveSessionOnly (providers.dart:136-143)
  → GoRouter redirect /login (app.dart:49)
```

### Rekomendasi non-kode untuk developer sideload

1. **Catat Team ID** setiap build sideload (Xcode → Signing & Capabilities).
2. **Expected login ulang** jika provisioning profile 7-hari expired dan app di-sign ulang dengan identity berbeda.
3. **Bandingkan dengan Android** — jika hanya iOS terkena, anggap platform limitation.
4. **Jangan pakai `first_unlock_this_device_only`** kecuali sengaja menolak restore backup iCloud.
5. Untuk testing stabil: gunakan **Team ID tetap** (Apple Developer Program paid) atau TestFlight.

---

## Stress-Test Analysis

### Koneksi putus-nyambung saat reauth

| Mekanisme | Implementasi | File:Line |
|-----------|--------------|-----------|
| Shared Future reauth | Caller kedua **menunggu**, bukan fail | `silent_webview_reauth.dart:28-38` |
| Interceptor lock | `_reauthInFlight` | `valorant_interceptor.dart:143-155` |
| Transient tidak wipe | Hanya `TokenExpiredException` / `InvalidSessionException` | `valorant_interceptor.dart:322-324` |
| WebView timeout | 15 detik → `TransientReauthException` | `silent_webview_reauth.dart:164-169` |

### Switch akun spam-tap

- `AccountSwitcherModal._actionInProgress` — `account_switcher_modal.dart:32,55`
- `AsyncLock.run('active_session_action')` — `providers.dart:261`

### Unlock pasca jam 7 + background overnight

- **Risiko utama:** P1-01 (dual lifecycle listener)
- **Mitigasi partial:** retry 2000ms — `home_screen.dart:614-618`
- **Reauth concurrent:** shared future mencegah duplicate WebView

---

## Verifikasi Area Audit (Checklist)

### Area 1 — Rotasi toko 07:00 WIB

- [x] Buffer 2,5s ada (`home_screen.dart:587-589`)
- [x] Delay resume 600ms ada (`home_screen.dart:591-592`)
- [x] `allowExpired: true` ada (`home_screen.dart:39`, `store_local_cache.dart:22-47`)
- [x] Fetch-then-replace, tidak delete-before-fetch (`store_repository.dart:27-34`)
- [x] Banner offline ada (`home_screen.dart:448-479`)
- [ ] Race dual listener — **perlu fix P1-01**

### Area 2 — Reauth & token

- [x] Entitlement 55 menit (`secure_storage.dart:42`)
- [x] `refreshEntitlementOnly` tanpa WebView (`auth_repository.dart:120-131`)
- [x] `TransientReauthException` tidak wipe sesi
- [x] HTTP 401/403 dari response asli (bukan string match) di interceptor
- [x] Mutex = shared Future

### Area 3 — Multi-account

- [x] WebView login bersih sebelum OAuth (`webview_login_screen.dart:89-92`)
- [x] Cookie per-akun namespaced (`secure_storage.dart:38`)
- [x] Entitlement sync saat switch (`providers.dart:277-281`)
- [x] `beginUserTransaction` konsisten
- [ ] Cookie global fallback — **perlu fix P1-02**

### Area 4 — UI error

- [ ] Klasifikasi robust — **perlu fix P1-03**
- [x] Home: smart reconnect
- [ ] Layar lain konsisten — **perlu fix P2-01**

### Area 5 — iOS Keychain

- [x] Dokumentasi platform limitation (section di atas)
- [x] Tidak ada solusi kode yang dipaksakan

---

## Roadmap Implementasi

| Urutan | ID | Effort | File utama |
|--------|-----|--------|------------|
| 1 | P1-01 | ~30 menit | `home_screen.dart` |
| 2 | P1-02 | ~1 jam | `silent_webview_reauth.dart`, `webview_login_screen.dart`, `providers.dart`, `credentials_local_source.dart` |
| 3 | P1-03 | ~1 jam | `valorant_error_display.dart`, `rank_screen.dart`, helper baru |
| 4 | P2-01 | ~2 jam | helper `session_reconnect.dart` + 4 layar |
| 5 | P2-02 | ~30 menit | `valorant_interceptor.dart` |
| 6 | P2-03 | ~2 jam | `login_screen.dart` |
| 7 | P3-* | backlog | wishlist, background |

---

## Bukti Cakupan — File Dibaca Sampai EOF

### Path sesuai prompt

- `lib/features/shop/presentation/home_screen.dart`
- `lib/shared/widgets/countdown_timer.dart`
- `lib/features/shop/data/store_local_cache.dart`
- `lib/features/shop/domain/store_repository.dart`
- `lib/features/shop/domain/models/storefront.dart`
- `lib/features/auth/domain/auth_repository.dart`
- `lib/features/auth/data/auth_remote_source.dart`
- `lib/features/auth/data/silent_webview_reauth.dart`
- `lib/features/auth/data/credentials_local_source.dart`
- `lib/core/network/interceptors/valorant_interceptor.dart`
- `lib/core/storage/secure_storage.dart`
- `lib/core/di/providers.dart`
- `lib/features/auth/presentation/account_switcher_modal.dart`
- `lib/features/auth/presentation/webview_login_screen.dart`
- `lib/core/storage/cache_storage.dart`
- `lib/shared/widgets/valorant_error_display.dart`

### Tambahan (Area 4 & supporting)

- `lib/features/loadout/presentation/loadout_screen.dart`
- `lib/features/match/presentation/match_history_screen.dart`
- `lib/features/rank/presentation/rank_screen.dart`
- `lib/features/shop/presentation/wishlist_catalog_screen.dart`
- `lib/shared/widgets/cache_data_banner.dart`
- `lib/core/exceptions/auth_exception.dart`
- `lib/features/auth/domain/models/credentials.dart`
- `lib/core/utils/async_lock.dart`
- `lib/app.dart`
- `lib/features/auth/presentation/login_screen.dart`
- `lib/core/services/background_service.dart`
- `lib/features/shop/data/store_remote_source.dart`
- `lib/core/network/cookie_service.dart`
- `lib/features/shop/presentation/wishlist_provider.dart`
- `lib/features/contracts/presentation/contracts_screen.dart` (provider block)
- `lib/features/profile/presentation/profile_screen.dart` (header + logout)

---

## Changelog dokumen

| Versi | Tanggal | Perubahan |
|-------|---------|-----------|
| 1.0 | 2026-08-18 | Audit awal — 5 area, 3 P1, roadmap fix |
