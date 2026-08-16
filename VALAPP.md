# Bug Report — App Force-Login saat Shop Reset Jam 7 Pagi

**Tanggal investigasi:** 2026-08-16
**Dilaporkan oleh:** Tosoon
**Gejala:** Setiap jam 7 pagi (waktu reset shop Valorant), app menampilkan error display, dan menekan tombol **SYSTEM RECONNECT** malah mengarahkan ke halaman login — padahal sesi seharusnya masih valid.
**Metode investigasi:** Baca ulang menyeluruh seluruh rantai file yang terlibat di flow reauth & error handling (bukan cuma grep pattern) — `app.dart`, `home_screen.dart`, `auth_repository.dart`, `silent_webview_reauth.dart`, `valorant_interceptor.dart`, `auth_remote_source.dart`, `oauth_flow.dart`, `credentials_local_source.dart`, `cache_storage.dart`, `store_repository.dart`, `store_remote_source.dart`, `store_local_cache.dart`, `countdown_timer.dart`, `webview_login_screen.dart`, `valorant_error_display.dart`, dan seluruh pemakaian `ValorantErrorDisplay` di 5 layar lain untuk pembanding.

---

## Ringkasan Eksekutif

Ini bukan 1 bug tunggal — ini **3 masalah yang saling memperkuat**, semuanya berpusat di `home_screen.dart` dan mekanisme reauth di sekitarnya. Kombinasi ketiganya membuat bug ini jauh lebih sering muncul **khusus** di jam 7 pagi dibanding waktu lain.

| # | Bug | Peran |
|---|---|---|
| 1 | `home_screen.dart` — exception handling terlalu kasar | **Penyebab langsung** kenapa muncul redirect ke login |
| 2 | Race condition ganda saat app resume (`_HomeScreenState` + `CountdownTimer` sama-sama trigger `_refresh()`) + `SilentWebviewReauth._isRunning` bukan proper mutex | **Penjelasan kenapa spesifik jam 7** — window itu = shop reset + banyak orang buka HP bersamaan |
| 3 | `fetchStorefrontRaw()` fallback v2→v3 bisa memicu 2x siklus reauth | Memperbesar peluang race #2 terjadi saat server API lagi sibuk |

---

## Bug #1 — Exception Handling Kasar di `home_screen.dart` (Root Cause Utama)

**File:** `lib/features/shop/presentation/home_screen.dart`, baris ~226–242

### Kode saat ini
```dart
error: (e, _) => SliverFillRemaining(
  hasScrollBody: false,
  child: Center(
    child: ValorantErrorDisplay(
      error: e,
      onRetry: () async {
        final router = GoRouter.of(context);
        try {
          final authRepo = await ref.read(authRepositoryProvider.future);
          await authRepo.reauth();
          await _refresh();
        } catch (e) {
          debugPrint('[HomeScreen] Reauth attempt failed: $e');
          // Do not clear active session on transient retry errors.
          // Allow the user to retry or tap Reconnect without wiping credentials.
          if (context.mounted) {
            router.push('/login/webview');
          }
        }
      },
      onReauth: () => context.push('/login/webview'),
      title: 'Gagal Memuat Toko Harian',
    ),
  ),
),
```

### Masalah
Komentar di kode ini bilang "Do not clear active session on transient retry errors" — **niatnya sudah benar**, tapi implementasinya salah. `catch (e)` generik menangkap **semua** jenis exception dan tetap `router.push('/login/webview')` untuk semuanya, padahal `AuthRepository.reauth()` (`lib/features/auth/domain/auth_repository.dart`) sudah didesain sengaja melempar 3 jenis exception berbeda (didefinisikan di `lib/core/exceptions/auth_exception.dart`):

| Exception | Makna | Harus redirect ke login? |
|---|---|---|
| `InvalidSessionException` | Server Riot menolak sesi secara definitif | **Ya** |
| `TokenExpiredException` | Token & cookie expired total, tidak ada local session sama sekali | **Ya** |
| `TransientReauthException` | Reauth gagal sementara (network/server sibuk) — kredensial harus dipertahankan | **Tidak** |

Selain 3 itu, ada juga exception generik lain yang bisa lolos dari `reauth()` tanpa dibungkus jadi salah satu tipe di atas:
- `Exception('Silent reauth already in progress')` dari `SilentWebviewReauth` (lihat Bug #2).
- `AuthException` polos dari `OAuthFlow.parseTokenRedirect()` kalau parsing redirect URL gagal (state/nonce mismatch, format URL rusak).
- `StateError('Active session changed during reauth')` kalau `saveIfCurrent()` gagal karena sesi berubah di tengah proses (`lib/features/auth/domain/auth_repository.dart` baris 175–179).
- `StateError('Storefront request started outside the active session')` dari `store_repository.dart` kalau cache transaction generation berubah di tengah fetch.

**Semua ini jatuh ke `catch (e)` generik dan dipukul rata: push ke `/login/webview`.**

Penting: `ValorantErrorDisplay` sendiri (`lib/shared/widgets/valorant_error_display.dart`) sebenarnya sudah menerima parameter `onReauth` yang terpisah dari `onRetry` — tapi parameter itu **tidak pernah dipakai oleh tombol apapun di dalam widget itu sendiri** (cuma ada 1 tombol "SYSTEM RECONNECT" yang manggil `onRetry`). Jadi pemisahan retry vs reauth yang sudah disiapkan di level widget ini gagal termanfaatkan karena `home_screen.dart` menggabungkan semuanya jadi satu `onRetry`.

### Perbandingan dengan 4 layar lain
Untuk konfirmasi ini bukan pola yang tersebar, saya cek semua 6 pemakaian `ValorantErrorDisplay` di seluruh app:

| File | Pola reauth | Status |
|---|---|---|
| `home_screen.dart` | Manggil `authRepo.reauth()` manual + `catch (e)` generik | **BUG** |
| `loadout_screen.dart` | `ref.invalidate()` → serahkan ke `ValorantInterceptor` | Aman (interceptor sudah benar membedakan exception) |
| `rank_screen.dart` | `ref.invalidate()` → serahkan ke `ValorantInterceptor` | Aman |
| `match_history_screen.dart` | `ref.invalidate()` → serahkan ke `ValorantInterceptor` | Aman |
| `wishlist_catalog_screen.dart` | `ref.invalidate()`, endpoint publik non-auth | Aman |
| `account_switcher_modal.dart` | Tombol "Add Account" disengaja | Aman |

**`home_screen.dart` adalah satu-satunya tempat yang manual memanggil `reauth()` sendiri di UI layer.**

### Fix
```dart
error: (e, _) => SliverFillRemaining(
  hasScrollBody: false,
  child: Center(
    child: ValorantErrorDisplay(
      error: e,
      onRetry: () async {
        final router = GoRouter.of(context);
        try {
          final authRepo = await ref.read(authRepositoryProvider.future);
          await authRepo.reauth();
          await _refresh();
        } on InvalidSessionException catch (e) {
          debugPrint('[HomeScreen] Session invalid — must re-login: $e');
          if (context.mounted) router.push('/login/webview');
        } on TokenExpiredException catch (e) {
          debugPrint('[HomeScreen] Token expired — must re-login: $e');
          if (context.mounted) router.push('/login/webview');
        } catch (e) {
          // TransientReauthException, race "already in progress",
          // parse error, StateError sesi berubah, dll.
          // JANGAN paksa login — sesi masih valid, cuma butuh coba lagi.
          debugPrint('[HomeScreen] Transient failure, session preserved: $e');
          if (context.mounted) await _refresh();
        }
      },
      onReauth: () => context.push('/login/webview'),
      title: 'Gagal Memuat Toko Harian',
    ),
  ),
),
```

Tambah import di bagian atas file:
```dart
import '../../../core/exceptions/auth_exception.dart';
```

---

## Bug #2 — Race Condition Ganda saat App Resume

**Files:**
- `lib/features/shop/presentation/home_screen.dart` (`didChangeAppLifecycleState`, baris ~117–124)
- `lib/shared/widgets/countdown_timer.dart` (`didChangeAppLifecycleState`, baris ~94–103)
- `lib/features/auth/data/silent_webview_reauth.dart` (`_isRunning`, baris 23, 29–32)

### Masalah

**2a. Dua widget berbeda sama-sama trigger `_refresh()` independen saat resume**

`_HomeScreenState` (di `home_screen.dart`) mendaftar sebagai `WidgetsBindingObserver` dan pada `AppLifecycleState.resumed` **selalu** panggil `_refresh()`:
```dart
@override
void didChangeAppLifecycleState(AppLifecycleState state) {
  if (state == AppLifecycleState.resumed) {
    // Always invalidate on resume — the shop may have rotated while the
    // app was in the background (daily reset at 07:00 WIB / 00:00 UTC).
    _refresh();
  }
}
```

`CountdownTimer` (dipakai di `home_screen.dart` untuk timer "REFRESHES IN") **juga** mendaftar sebagai `WidgetsBindingObserver` sendiri, dan pada resume, kalau waktu sudah lewat deadline, dia panggil `widget.onExpired?.call()` — yang di-wire ke `_refresh` juga:
```dart
@override
void didChangeAppLifecycleState(AppLifecycleState state) {
  if (state == AppLifecycleState.resumed) {
    _updateRemaining();
    if (_remaining <= 0) {
      _timer?.cancel();
      _notifyExpired();  // -> widget.onExpired?.call() -> _refresh di home_screen.dart
    }
  }
}
```

**Skenario konkret:** HP kamu terkunci/di-background sebelum jam 7, lalu kamu buka app pas atau sesudah jam 7.
1. `AppLifecycleState.resumed` terjadi → **kedua** listener kepicu hampir bersamaan (sibling widget, sama-sama observer).
2. `_HomeScreenState.didChangeAppLifecycleState` → panggil `_refresh()` (panggilan #1).
3. `_CountdownTimerState.didChangeAppLifecycleState` → deteksi shop sudah reset (`_remaining <= 0`) → `_notifyExpired()` → `_refresh()` lagi (panggilan #2).
4. **Kedua panggilan `_refresh()` jalan konkuren** — tidak ada guard/lock di level `_refresh()` sendiri.
5. Masing-masing panggil `authRepo.ensureValidSession()` sendiri-sendiri → kalau token dianggap near-expiry (masuk akal setelah HP lama di-lock), **dua panggilan `reauth()` konkuren**.

**2b. `SilentWebviewReauth._isRunning` bukan proper mutex**

```dart
bool _isRunning = false;

Future<String> refreshTokens(OAuthAttempt attempt, {String? puuid}) async {
  if (_isRunning) {
    throw Exception('Silent reauth already in progress');  // <-- langsung gagal, bukan nunggu
  }
  _isRunning = true;
  // ...
}
```

Ini cuma boolean flag. Kalau panggilan kedua datang saat panggilan pertama masih jalan, dia **langsung melempar exception generik** alih-alih menunggu hasil panggilan pertama selesai (padahal pola yang benar untuk kasus ini — shared in-flight Future — sudah dipakai dengan benar di tempat lain seperti `ValorantInterceptor._reauthInFlight` dan `ValorantInterceptor._proactiveCheckInFlight`).

Exception generik `Exception('Silent reauth already in progress')` ini bukan salah satu dari 3 tipe (`InvalidSessionException`/`TokenExpiredException`/`TransientReauthException`) — di `auth_repository.dart`, exception non-`InvalidSessionException` dari jalur WebView akan trigger fallback ke `cookieReauth()` (baris 128–144). Kalau fallback ini **juga** gagal (masuk akal kalau server API lagi under load jam 7, atau race yang sama masih berlangsung), hasil akhirnya jadi `TransientReauthException` — yang seharusnya aman (tidak redirect login) **kecuali** kamu keburu nekan tombol SYSTEM RECONNECT manual, yang lalu kena Bug #1.

**Kenapa spesifik jam 7:** window itu = shop reset (`CountdownTimer` expire) **DAN** waktu orang-orang biasa mulai aktivitas pagi (buka HP dari kunci/background = `AppLifecycleState.resumed`). Dua kondisi ini bertepatan tepat di jam yang sama, jauh lebih sering dibanding waktu-waktu lain dalam sehari.

### Fix

**2a — Cegah `_refresh()` dobel di `home_screen.dart`:**
```dart
class _HomeScreenState extends ConsumerState<HomeScreen>
    with WidgetsBindingObserver {
  bool _isRefreshing = false;

  // ...

  Future<void> _refresh() async {
    if (_isRefreshing) return;
    _isRefreshing = true;
    try {
      // ...isi _refresh() yang sudah ada, tidak berubah...
    } finally {
      _isRefreshing = false;
    }
  }
}
```

**2b — Ganti `_isRunning` jadi shared in-flight Future di `silent_webview_reauth.dart`:**
```dart
class SilentWebviewReauth {
  SilentWebviewReauth._();
  static final instance = SilentWebviewReauth._();

  WebViewController? _controller;
  Future<String>? _inFlight;

  Future<String> refreshTokens(OAuthAttempt attempt, {String? puuid}) async {
    final existing = _inFlight;
    if (existing != null) return existing; // ikut nunggu hasil yang sama

    final operation = _doRefreshTokens(attempt, puuid: puuid);
    _inFlight = operation;
    try {
      return await operation;
    } finally {
      if (identical(_inFlight, operation)) _inFlight = null;
    }
  }

  Future<String> _doRefreshTokens(OAuthAttempt attempt, {String? puuid}) async {
    // ...isi lama refreshTokens() (dari 'final completer = Completer<String>();'
    // sampai akhir method), TANPA blok if (_isRunning) / _isRunning = true di awal
    // dan TANPA _isRunning = false di finally...
  }
}
```

---

## Bug #3 — Fallback Storefront v2→v3 Memperbesar Peluang Race

**File:** `lib/features/shop/data/store_remote_source.dart`, baris 9–26

```dart
Future<Map<String, dynamic>> fetchStorefrontRaw(
    String shard, String puuid) async {
  // Primary: storefront v2
  try {
    final response = await _dio.post<dynamic>(
      'https://pd.$shard.a.pvp.net/store/v2/storefront/$puuid',
      data: {},
    );
    return _validateStorefront(response.data, 'storefront v2');
  } catch (_) {
    // Fallback: storefront v3
    final response = await _dio.post<dynamic>(
      'https://pd.$shard.a.pvp.net/store/v3/storefront/$puuid',
      data: {},
    );
    return _validateStorefront(response.data, 'storefront v3');
  }
}
```

### Masalah
Kalau request v2 gagal karena **apapun** (termasuk setelah `ValorantInterceptor` sudah mencoba reauth+retry sendiri dan tetap gagal), kode ini otomatis coba lagi ke v3 — yang juga lewat interceptor yang sama, berpotensi memicu siklus reauth **kedua**. Saat server Riot API sedang sibuk (jam reset shop), ini menggandakan jumlah percobaan request+reauth dalam satu pemanggilan `fetchStorefrontRaw()`, yang memperbesar peluang race di Bug #2 benar-benar kejadian.

### Catatan
Ini **bukan bug yang perlu diperbaiki sendiri** — fallback v2→v3 itu sendiri adalah desain yang wajar (v3 memang endpoint pengganti resmi v2). Yang perlu diperbaiki adalah akar masalahnya di Bug #1 dan #2; begitu itu selesai, dampak dari poin ini otomatis berkurang karena reauth concurrent tidak lagi menyebabkan force-login.

---

## Ringkasan Perubahan yang Diperlukan

| File | Perubahan |
|---|---|
| `lib/features/shop/presentation/home_screen.dart` | 1) Bedakan `InvalidSessionException`/`TokenExpiredException` vs exception lain di `onRetry`. 2) Tambah guard `_isRefreshing` di `_refresh()`. 3) Tambah import `auth_exception.dart`. |
| `lib/features/auth/data/silent_webview_reauth.dart` | Ganti `_isRunning` boolean jadi shared in-flight `Future<String>?` (`_inFlight`), pola sama seperti `ValorantInterceptor._reauthInFlight`. |

**Tidak perlu ubah:** `store_remote_source.dart`, `auth_repository.dart`, `auth_remote_source.dart`, `valorant_interceptor.dart`, `cache_storage.dart` — semua sudah berperilaku benar, cuma jadi korban dari 2 bug di atas.

---

## Rencana Verifikasi Setelah Fix

1. **Simulasi race reauth konkuren** — trigger `didChangeAppLifecycleState(resumed)` dua kali berturut-turut dalam waktu singkat (atau pause app lalu resume tepat saat `CountdownTimer` di ambang 0 detik) → pastikan panggilan kedua ikut menunggu hasil yang pertama (via `_inFlight`), bukan langsung melempar exception.
2. **Pastikan sesi benar-benar invalid tetap redirect ke login** — simulasikan `InvalidSessionException` (mis. lewat `notification_debug_screen.dart` kalau ada tool simulate expired, atau revoke sesi dari sisi Riot) → pastikan tombol SYSTEM RECONNECT tetap mengarahkan ke `/login/webview` seperti seharusnya.
3. **Tes jam 7 sungguhan (atau ubah jam sistem HP untuk simulasi)** — kunci HP sebelum jam 7, buka lagi setelah jam 7 → pastikan tidak lagi muncul force-login untuk transient error; error display (jika muncul) tetap bisa di-retry tanpa kehilangan sesi.
4. Jalankan `flutter analyze` setelah perubahan untuk memastikan tidak ada import/syntax error baru.

---

## Catatan Metodologi

Investigasi ini dilakukan dengan membaca isi lengkap tiap file yang relevan (bukan cuma grep nama fungsi/pattern), termasuk menelusuri call graph konkret dari titik pemicu (`CountdownTimer.onExpired`, `didChangeAppLifecycleState`) sampai ke exception yang akhirnya diterima `home_screen.dart`. Belum ada perubahan kode yang dieksekusi — dokumen ini murni laporan temuan + rencana fix untuk direview terlebih dahulu.