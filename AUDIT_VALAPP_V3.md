# AUDIT FINAL v3 — Valapp (Valorant Shop Checker App)

**Update penting:** Audit ini diverifikasi silang dengan **log asli dari game client Valorant** (`ShooterGame.log` dan `cef3.log`) yang di-upload langsung dari folder instalasi Riot Games di laptop kamu. Ini bukan lagi cuma dokumentasi API tidak resmi — beberapa temuan di bawah punya **bukti konkret dari traffic HTTP client resmi Riot**, sehingga tingkat kepercayaannya jauh lebih tinggi dari audit-audit sebelumnya.

**Scope:** 83 file `.dart` di `lib/`, ±18.400 baris, upload `Valapp-main.zip` (naik dari 66 file di audit sebelumnya — 4 fitur baru: Loadout, News, Account Health/Restrictions, plus design-system files).

**Status:** Murni dokumen audit. Belum ada perubahan kode yang dieksekusi berdasarkan dokumen ini.

---

# DAFTAR ISI

1. Metodologi Verifikasi via Log Game Asli
2. Progress Sejak Audit Sebelumnya (yang Sudah Diperbaiki ✅)
3. Bug Baru — Kritis
4. Bug Baru — Sedang
5. Bug Lama yang Masih Belum Diperbaiki
6. Temuan dari Verifikasi Log Game (Endpoint API)
7. Catatan Verifikasi (Bukan Bug)
8. Detailed Fix Prompts
9. Ringkasan Prioritas

---

# 1. METODOLOGI VERIFIKASI VIA LOG GAME ASLI

`ShooterGame.log` berisi baris log `LogPlatformCommon: Platform HTTP Query End` untuk setiap panggilan API yang dilakukan game client resmi Riot ke backend (`pd.<shard>.a.pvp.net`, `glz-<region>.a.pvp.net`, dll), lengkap dengan **nama query internal**, **URL lengkap**, dan **response code**. Ini memberi kepastian 100% tentang endpoint mana yang benar-benar dipakai dan didukung Riot saat ini — jauh lebih dapat diandalkan dibanding dokumentasi API tidak resmi (valapi.dev, dsb) yang bisa saja sudah usang.

`cef3.log` adalah log Chromium Embedded Framework (dipakai untuk in-game web overlay/modal) — tidak berisi traffic API game utama, tapi mengonfirmasi bahwa Riot memang menggunakan arsitektur situs statis berbasis **Gatsby + Sanity CMS** (terlihat dari pola `page-data.json` dan domain `cmsassets.rgpub.io/sanity/images/...`), yang relevan untuk menilai fitur News di Valapp.

Catatan keterbatasan: log ini berisi metadata query (URL, method, response code, timing) tapi **tidak berisi response body**, jadi tidak bisa dipakai untuk verifikasi struktur JSON detail (misalnya nilai pasti threshold XP per level). Untuk itu, verifikasi tetap memerlukan investigasi tambahan seperti yang direkomendasikan di prompt-prompt sebelumnya.

---

# 2. PROGRESS SEJAK AUDIT SEBELUMNYA (SUDAH DIPERBAIKI ✅)

| # | Bug (dari audit sebelumnya) | Status | Bukti |
|---|---|---|---|
| 1 | Harga notifikasi wishlist di background checker selalu hardcoded 1775 VP | ✅ **Diperbaiki** | `background_service.dart` sekarang membangun `priceMap` dari `SingleItemStoreOffers` dengan ID-matching yang benar, harga notifikasi sekarang akurat per skin |
| 2 | Nomor tier Battle Pass dihitung `chapterIndex * 5`, salah kalau chapter tidak selalu 5 level | ✅ **Diperbaiki** | `battlepass_carousel_modal.dart` sekarang menghitung `tierOffset` secara kumulatif dari `levels.length` chapter-chapter sebelumnya |
| 3 | Duplikasi 3 implementasi resolve nama map | ✅ **Sebagian besar diperbaiki** | `valorant_assets.dart.getMapsMap()` v4 sekarang jauh lebih robust (path-segment matching, alias codename tersentral); `match_history_screen.dart` sudah pakai `entry.getMapDisplayName()`. `match_detail_screen.dart` masih ada implementasi lokal terpisah (lihat Bagian 5) |
| 4 | Duplikasi tier-name (Iron/Bronze/dst) di 3 tempat berbeda | ✅ **Diperbaiki tuntas** | `TierNameUtil` baru dibuat dan dipakai konsisten di `profile_screen.dart`, `rank_screen.dart`, `shop_screen.dart` |
| 5 | Hardcoded UUID currency (VP/RP/KC) tersebar di banyak file | ✅ **Diperbaiki** | `ValorantCurrency` class baru di `wallet.dart` mengonsolidasikan semua UUID currency |
| 6 | Design system (AppColors) belum ada, warna hardcoded tersebar | ✅ **Diperbaiki** | `app_colors.dart` baru dibuat dengan palet tactical-minimalis yang terpusat, dipakai luas di seluruh redesign |
| 7 | Infrastruktur resolve Riot ID asli (`fetchDisplayName`) sudah ada tapi tidak pernah dipakai | 🟡 **Setengah diperbaiki** | `profile_screen.dart._displayNameProvider` sekarang memakainya dengan benar untuk tampilan profile utama — TAPI belum disambungkan ke alur login/multi-account (lihat Bagian 5) |

---

# 3. BUG BARU — KRITIS

## 3.1 Account Health / Restrictions: Kegagalan Network Disamarkan sebagai "Akun Bersih" (3 Lapisan Independen)

**Severity:** Kritis — false-positive pada fitur yang secara eksplisit soal status pelanggaran/ban akun.

**Lokasi:**
- `lib/features/profile/data/restrictions_remote_source.dart`
- `lib/features/profile/presentation/account_health_modal.dart` (provider `accountHealthProvider`)
- `lib/features/profile/presentation/profile_screen.dart` (`_AccountHealthBannerCard`)

**Penjelasan mendalam:**

Ada **tiga lapisan independen** yang semuanya secara default menganggap akun "bersih" ketika data sebenarnya gagal dimuat:

**Lapisan 1 — di remote source:**
```dart
final responses = await Future.wait([
  _dio.get<dynamic>('.../restrictions/v3/penalties')
      .then((r) => _toMap(r.data))
      .catchError((_) => <String, dynamic>{}),   // <-- gagal → map kosong, diam-diam
  _dio.get<dynamic>('.../restrictions/v1/avoidList')
      .then((r) => _toMap(r.data))
      .catchError((_) => <String, dynamic>{}),
]);
```

**Lapisan 2 — di provider:**
```dart
final accountHealthProvider = FutureProvider.autoDispose<AccountHealth?>((ref) async {
  try {
    ...
  } catch (_) {
    return const AccountHealth(isClean: true, penalties: [], avoidedPlayers: []); // <-- exception apapun → "bersih"
  }
});
```

**Lapisan 3 — di banner ringkasan Profile Screen:**
```dart
final isClean = health?.isClean ?? true;   // <-- masih loading/null → "bersih"
```

**Dampak nyata:** User bisa melihat badge hijau besar **"EXCELLENT // NO PENALTIES"** (di modal detail) atau **"HEALTHY // GOOD STANDING"** (di banner profile) dengan copy meyakinkan "Your account is in good standing with zero active restrictions" — padahal kenyataannya aplikasi mungkin sama sekali gagal mengambil data dari Riot (token basi, network mati, dsb). Untuk fitur yang secara eksplisit soal status pelanggaran akun, false-negative (menyembunyikan bahwa data gagal dimuat sebagai "tidak ada masalah") jauh lebih berbahaya daripada menampilkan error loading biasa.

**Catatan tambahan penting dari verifikasi log game asli:** log `ShooterGame.log` menunjukkan client resmi Riot memanggil **TIGA endpoint restrictions**, bukan dua:
1. `restrictions/v3/penalties` (`Restrictions_FetchPlayerRestrictionsV3`) — dipakai Valapp ✅
2. `restrictions/v1/avoidList` (`Restrictions_GetPlayerAvoidList`) — dipakai Valapp ✅
3. **`restrictions/v1/activeFutureInterventions`** (`Restrictions_GetPlayerInterventions`) — **TIDAK PERNAH dipanggil Valapp!**

Artinya `AccountHealth` di Valapp kemungkinan besar **tidak lengkap** secara data, terlepas dari bug false-positive di atas — ada kategori intervention/penalty yang sepenuhnya terlewat karena endpoint resminya tidak pernah dipanggil.

## 3.2 Background Wishlist Checker: Masih Memakai Endpoint Storefront yang Salah, Token Tanpa Refresh

**Severity:** Kritis — dikonfirmasi dengan bukti log resmi bahwa endpoint yang dipakai kemungkinan sudah usang/berisiko.

**Lokasi:** `lib/core/services/background_service.dart`

**Bukti dari log game asli:**
```
QueryName: [Store_GetStorefrontV3], URL [POST https://pd.ap.a.pvp.net/store/v3/storefront/{puuid}], Response Code: [200]
```
Game client resmi **HANYA** memanggil `store/v3/storefront`. Tidak ada satupun baris log yang menunjukkan client memanggil `store/v2/storefront`.

**Masalah:** `background_service.dart` masih memanggil:
```dart
'https://pd.$shard.a.pvp.net/store/v2/storefront/$puuid',
```
Endpoint **v2**, bukan **v3** yang terbukti dipakai client resmi, dan **tanpa fallback** ke v3 sama sekali (berbeda dengan `store_remote_source.dart` yang setidaknya punya fallback, meski urutannya juga bermasalah — lihat Bagian 6.1).

Ditambah dengan masalah lama yang masih belum diperbaiki: token dibaca mentah dari `SecureStorage` tanpa cek expiry atau reauth apapun, memakai `Dio()` polos yang tidak melewati `ValorantInterceptor`. Karena task ini berjalan tiap 3 jam sementara token cuma bertahan ~15 menit, kombinasi (endpoint berisiko + token basi + tanpa reauth) membuat fitur ini kemungkinan besar gagal pada mayoritas eksekusinya, secara silent (`catch (_) { return; }`).

## 3.3 Endpoint Name-Service Memakai Versi API yang Sudah Usang (v2, Seharusnya v3)

**Severity:** Kritis — dikonfirmasi dengan bukti log resmi, berisiko fitur berhenti berfungsi kapan saja jika Riot mematikan v2.

**Lokasi:** `lib/features/profile/data/account_remote_source.dart`

**Bukti dari log game asli:**
```
QueryName: [DisplayNameService_UpdatePlayer], URL [POST https://pd.ap.a.pvp.net/name-service/v3/players], Response Code: [200]
```

**Masalah:** `AccountRemoteSource.fetchDisplayNames()` memanggil:
```dart
'https://pd.$cleanShard.a.pvp.net/name-service/v2/players',
```

Ini memakai **v2**, sedangkan game client resmi terbukti memakai **v3**. Riot punya pola konsisten melakukan versioning API dan pada akhirnya mematikan versi lama (persis seperti pola storefront v2→v3 di atas) — endpoint v2 untuk name-service berisiko dideprecate kapan saja tanpa peringatan, yang akan membuat seluruh fitur resolve display name (dipakai di Profile Screen dan seharusnya juga di multi-account) berhenti berfungsi sekaligus.

## 3.4 Multi-Account: Token Akun Non-Aktif Tidak Pernah Di-refresh; Nama Akun Masih Generik (Infrastruktur Sudah Ada Tapi Belum Disambungkan)

**Severity:** Kritis — bug lama, dan sekarang lebih menyesatkan karena solusinya sudah ada tapi tidak dipakai.

**Lokasi:**
- `lib/features/auth/presentation/account_switcher_modal.dart`
- `lib/features/auth/presentation/webview_login_screen.dart`
- `lib/features/profile/presentation/profile_screen.dart` (`_displayNameProvider` — referensi pola yang BENAR)

**Penjelasan:** Bug ini sudah teridentifikasi di audit sebelumnya dan **masih belum diperbaiki**. Yang membuat ini lebih signifikan sekarang: `profile_screen.dart._displayNameProvider` **sudah membuktikan pola yang benar bekerja dengan baik** — fetch display name, simpan ke cache, fallback yang aman kalau gagal. Pola ini tinggal disalin ke `webview_login_screen.dart` (saat login pertama kali) dan `account_switcher_modal.dart` (untuk refresh nama akun lain), tapi belum dilakukan. Developer sudah menyelesaikan setengah pekerjaan (di Profile Screen) tapi lupa menyambungkannya ke fitur multi-account yang jadi tempat masalah ini pertama kali muncul.

Masalah token akun non-aktif yang tidak pernah di-refresh (sehingga error saat pertama kali di-switch) juga **masih belum diperbaiki** — tidak ada pengecekan `isExpired` atau mekanisme `reauthForAccount()` di `account_switcher_modal.dart`.

## 3.5 Race Condition Read-Modify-Write — Masih Belum Diperbaiki, Masih Berisiko Kehilangan Data Kredensial

**Severity:** Kritis — bug lama, sudah 2 ronde audit belum ditangani.

**Lokasi:**
- `lib/features/match/data/match_local_cache.dart` (`MatchHistoryLocalCache.saveHistory`, `MatchDetailLocalCache.saveMatchDetail`)
- `lib/features/auth/data/credentials_local_source.dart` (`CredentialsLocalSource.save`)

**Penjelasan:** Confirmed masih persis sama seperti 2 ronde audit sebelumnya — pola read-modify-write tanpa lock di kedua file ini. `CacheStorage.saveMatchMap()` sendiri sudah punya mutex lock manual (`Completer`), tapi tidak pernah digeneralisasi menjadi solusi reusable, sehingga bug yang sama tetap ada di 2 tempat lain. Risiko terbesar tetap pada `CredentialsLocalSource.save()` — race condition di sini bisa menghilangkan/mengorupsi kredensial akun lain yang tersimpan di fitur multi-account.

---

# 4. BUG BARU — SEDANG

## 4.1 Loadout: Warna Chroma Tidak Pernah Ter-resolve (Selalu Fallback ke Warna Default)

**Lokasi:** `lib/features/loadout/presentation/loadout_screen.dart`

```dart
Color? chromaColor;
if (hasNonDefaultChroma && skinInfo?['chromas'] != null) {
  final chromas = skinInfo!['chromas'] as List<dynamic>? ?? [];
  for (final ch in chromas) {
    if (ch is Map && ch['uuid'] == weapon.chromaId) {
      final hex = ch['swatch'] as String?;
      if (hex != null) break;   // <-- BUG: 'hex' didapat tapi TIDAK PERNAH di-parse dan di-assign ke chromaColor
    }
  }
}
```

Variabel `hex` (warna swatch chroma dari API) diambil tapi tidak pernah dipakai untuk assign `chromaColor` — cuma dicek `!= null` lalu `break`. Akibatnya `chromaColor` **selalu tetap `null`**, dan badge "CHROMA" di UI selalu memakai warna fallback `AppColors.rpAmber`, bukan warna asli chroma yang seharusnya beda-beda per varian (misal merah, biru, dsb).

## 4.2 Loadout: Deteksi Pre-Round Spray Memakai `.contains('01')`, Bukan `.endsWith('01')`

**Lokasi:** `lib/features/loadout/domain/models/player_loadout.dart`

```dart
// Slot 0 = PreRound spray (SocketID ends with '01')
for (final s in spraySelections) {
  final sMap = _asMap(s);
  if ((sMap['SocketID'] as String? ?? '').contains('01')) {   // <-- harusnya endsWith, sesuai komentar sendiri
    preRoundSpray = sMap['SprayID'] as String?;
    break;
  }
}
```

Komentar kode sendiri menyatakan niatnya "SocketID ends with '01'", tapi implementasinya memakai `.contains('01')` — karena SocketID adalah UUID (hex string acak panjang), substring `'01'` bisa muncul di posisi manapun dalam UUID, bukan cuma di akhir. Ini rawan salah pilih spray slot kalau SocketID slot lain (bukan pre-round) kebetulan mengandung substring yang sama.

## 4.3 Peak Rank di Rank Screen Kemungkinan Tidak Akurat (Hanya dari Histori Terbatas)

**Lokasi:** `lib/features/rank/presentation/rank_screen.dart` (`_PeakRankCard`)

"Peak Rank" dihitung dengan membandingkan tier tertinggi dari `updates` (hasil `_competitiveUpdatesProvider`, yang berasal dari endpoint `fetchCompetitiveUpdatesRaw`). Endpoint competitive-updates Riot biasanya **hanya mengembalikan histori terbatas** (puluhan match terakhir, bukan seluruh act/karier). Label "Peak Rank" yang ditampilkan berpotensi menyesatkan — bukan peak sesungguhnya sepanjang act, cuma peak dari histori match yang kebetulan berhasil di-fetch.

## 4.4 Hardcoded Fallback Season yang Akan Menjadi Salah Seiring Waktu

**Lokasi:** `lib/shared/utils/valorant_assets.dart` (`getActiveSeason()`), dipakai aktif di `rank_screen.dart` (`_activeSeasonProvider`, 2 tempat UI)

```dart
if (episode.isEmpty) episode = 'EPISODE 9';
if (act.isEmpty) act = 'ACT 1';
```

Fallback ini dipakai baik ketika tidak ada season yang match rentang tanggal saat ini di data API, maupun ketika API call ke `valorant-api.com/v1/seasons` gagal total. Karena di-hardcode ke season spesifik, fallback ini **akan menjadi tidak akurat begitu Valorant memasuki episode/act berikutnya** — dan karena sudah dikonfirmasi dipakai aktif di 2 tempat UI Rank Screen, dampaknya nyata terlihat oleh user, bukan cuma edge-case teoretis.

## 4.5 Matchresult (Victory/Defeat/Draw) di Profile Dihitung Manual dari Ronde, Bukan Field Resmi

**Lokasi:** `lib/features/profile/presentation/profile_screen.dart` (`_profileMatchesProvider`)

```dart
final myWins = details.roundResults.where((r) => r.winningTeam.toLowerCase() == pt).length;
final oppWins = details.roundResults.length - myWins;
matchResult = myWins > oppWins ? MatchResult.victory : myWins < oppWins ? MatchResult.defeat : MatchResult.draw;
```

Hasil match dihitung ulang dari jumlah ronde yang dimenangkan, bukan memakai field hasil resmi dari response Riot (yang biasanya menyediakan field eksplisit untuk hasil akhir tim). Untuk mode non-Competitive (Deathmatch, Spike Rush) atau kasus edge seperti forfeit/surrender, penghitungan manual berbasis ronde ini berpotensi menghasilkan status Menang/Kalah yang salah.

## 4.6 Endpoint Storefront: Urutan Primary/Fallback Terbalik (v2 dipakai duluan, seharusnya v3)

**Lokasi:** `lib/features/shop/data/store_remote_source.dart`

Berdasarkan bukti log game asli (`Store_GetStorefrontV3` — hanya v3 yang dipakai client resmi), urutan di `store_remote_source.dart` yang mencoba **v2 dulu**, baru fallback ke **v3** kalau gagal (400), adalah **terbalik**. v3 seharusnya jadi endpoint utama karena itu yang terbukti didukung dan dipakai Riot; memanggil v2 dulu menambah latency tambahan (1 request gagal dulu) di jalur normal dan berisiko kalau v2 benar-benar dimatikan Riot suatu saat (semua request Shop akan gagal 400 dulu sebelum fallback berhasil — bisa jadi kontributor tambahan untuk pola gejala 400 error yang jadi root cause original masalah kamu di awal-awal audit).

---

# 5. BUG LAMA YANG MASIH BELUM DIPERBAIKI

| # | Bug | Lokasi | Catatan |
|---|---|---|---|
| 5.1 | Race condition read-modify-write di cache & kredensial akun | `match_local_cache.dart`, `credentials_local_source.dart` | Lihat Bagian 3.5 — masih paling kritis, 2 ronde audit belum ditangani |
| 5.2 | Multi-account: token akun non-aktif tidak di-refresh, nama akun generik | `account_switcher_modal.dart`, `webview_login_screen.dart` | Lihat Bagian 3.4 — infrastruktur sudah ada di Profile Screen, tinggal disambungkan |
| 5.3 | Harga per-item skin di dalam Featured Bundle selalu 0 VP | `storefront.dart` (`FeaturedBundle.fromJson`), `bundle_detail_modal.dart` | Masih persis sama, `itemIds` masih `List<String>` tanpa harga per-item |
| 5.4 | Threshold XP account level (`xpPerLevel = 5000`) belum diverifikasi ke sumber resmi | `account_xp.dart` | Masih klaim "flat across all levels" tanpa bukti/sumber |
| 5.5 | Mission title selalu generik "Mission" | `contracts.dart` (`Mission.fromJson`) | Field `xpGrant` baru ditambahkan (progress kecil), tapi title masih belum di-resolve dari sumber lain |
| 5.6 | Duplikasi resolve nama map — `match_detail_screen.dart` masih implementasi lokal terpisah | `match_detail_screen.dart` (`_mapName()`) | Sebagian sudah dikonsolidasi (match history), match detail masih belum |
| 5.7 | Klaim "Stay Signed In" di login screen belum disinkronkan dengan realita background reauth | `login_screen.dart` | Masih relevan mengingat bug 3.2 (background checker) masih ada |
| 5.8 | Dead code: login manual + MFA | `login_controller.dart`, `mfa_screen.dart`, route `/mfa` | Masih ada, belum ada keputusan hapus/aktifkan |
| 5.9 | Sistem notification-rules kini **sebagian aktif** tapi tanpa UI untuk mengatur | `notification_rule_service.dart`, `background_service.dart` | **Berubah status** — lihat Bagian 6.2 untuk detail |
| 5.10 | Zero test coverage | `test/widget_test.dart` | Belum diverifikasi ulang di ronde ini, kemungkinan masih placeholder |

---

# 6. TEMUAN DARI VERIFIKASI LOG GAME (ENDPOINT API)

## 6.1 Tabel Perbandingan Endpoint: Valapp vs Bukti Log Game Resmi

| Fitur | Endpoint dipakai Valapp | Endpoint dipakai game client (dari log) | Status |
|---|---|---|---|
| Storefront (Shop utama) | `v2` primary → `v3` fallback | **`v3` saja** (`Store_GetStorefrontV3`) | ⚠️ Urutan terbalik (Bagian 4.6) |
| Storefront (Background checker) | `v2` saja, tanpa fallback | **`v3` saja** | 🔴 Salah total (Bagian 3.2) |
| Wallet | `store/v1/wallet/{puuid}` | `store/v1/wallet/{puuid}` (`Store_GetWallet`) | ✅ Benar |
| MMR/Rank | `mmr/v1/players/{puuid}` | `mmr/v1/players/{puuid}` (`MMR_FetchPlayer`) | ✅ Benar |
| Account XP | `account-xp/v1/players/{puuid}` | `account-xp/v1/players/{puuid}` (`AccountXP_GetPlayer`) | ✅ Benar |
| Contracts (battlepass/mission) | `contracts/v1/contracts/{puuid}` | `contracts/v1/contracts/{puuid}` (`Contracts_FetchContracts`) | ✅ Benar |
| Loadout | `personalization/v3/players/{puuid}/playerloadout` | sama (`playerLoadoutUpdate`) | ✅ Benar |
| Restrictions (penalties) | `restrictions/v3/penalties` | sama (`Restrictions_FetchPlayerRestrictionsV3`) | ✅ Benar |
| Restrictions (avoid list) | `restrictions/v1/avoidList` | sama (`Restrictions_GetPlayerAvoidList`) | ✅ Benar |
| Restrictions (interventions) | **Tidak dipanggil sama sekali** | `restrictions/v1/activeFutureInterventions` (`Restrictions_GetPlayerInterventions`) | 🔴 Endpoint hilang total (Bagian 3.1) |
| Display Name | `name-service/v2/players` | **`name-service/v3/players`** (`DisplayNameService_UpdatePlayer`) | 🔴 Versi API usang (Bagian 3.3) |

## 6.2 Fitur yang Tersedia di Game Client Tapi Belum Ada di Valapp (Peluang Fitur Baru)

Dari log game asli, ditemukan beberapa fitur/endpoint yang aktif dipakai client resmi tapi **belum diimplementasikan** di Valapp sama sekali:

- **Premier** (mode kompetitif tim/liga) — endpoint `premier/v1/affinities/{region}/conferences`, `premier/v1/affinities/{region}/premier-seasons`, `premier/v2/players/{puuid}`, `premier/v3/players/{puuid}` semuanya aktif dipanggil client. Kalau kamu main Premier, ini bisa jadi fitur baru yang berguna (tim, jadwal, standing liga).
- **Daily Ticket** (semacam daily login reward/streak) — endpoint `daily-ticket/v1/{puuid}/renew` dan `daily-ticket/v1/queue-config`.
- **Agent Storefront** — endpoint terpisah `store/v1/storefronts/agent` untuk gear/item spesifik agent (bukan skin senjata biasa).
- **Favorites** — endpoint `favorites/v1/players/{puuid}/favorites`, kemungkinan untuk skin/item yang di-favorite di dalam game (mirip konsep wishlist tapi native dari Riot, berpotensi bisa disinkronkan dengan fitur wishlist Valapp yang sudah ada).

## 6.3 Konfirmasi Independen: Fitur News Memakai Pola Arsitektur yang Memang Dipakai Riot (Tapi Tetap Rapuh)

`cef3.log` mengonfirmasi bahwa Riot memang menggunakan Gatsby (terlihat dari pola URL `page-data/*.json`, `page-data/sq/d/*.json`) dan CMS berbasis Sanity.io (`cmsassets.rgpub.io/sanity/images/.../news_live/...`) untuk halaman-halaman web mereka termasuk kemungkinan `playvalorant.com/news`. Ini menguatkan (bukan membantah) kekhawatiran audit sebelumnya soal `news_remote_source.dart`: pendekatan scraping `page-data.json` memang **konsisten dengan arsitektur nyata Riot**, tapi tetap merupakan **artefak build internal yang tidak di-versioning/didukung secara resmi** — bisa berubah struktur kapan saja tanpa pemberitahuan setiap kali Riot redeploy situsnya (upgrade Gatsby, restrukturisasi skema Sanity, dll).

---

# 7. CATATAN VERIFIKASI (BUKAN BUG, PERLU DIKETAHUI)

- `_profileCardProvider` (Profile Screen) dan `_IdentityCard` (Loadout Screen) **keduanya secara independen fetch data loadout mentah** (`fetchLoadoutRaw`) untuk keperluan yang tumpang tindih (player card info). Ini duplikasi network call kalau kedua screen dibuka dalam sesi yang sama — tidak fatal, tapi boros dan bisa dikonsolidasi.
- `isMvp` di `profile_screen.dart._profileMatchesProvider` dan `matchMvpPuuid` di `match_detail_screen.dart` sama-sama menghitung MVP berdasarkan skor tertinggi secara independen — konsisten hasilnya, tapi duplikasi implementasi.
- `LogPersonalizationManagerV2: Warning: Skin ... incompatible with equippable ...` ditemukan di log game asli — mengonfirmasi bahwa **client resmi Riot melakukan validasi kompatibilitas skin-vs-weapon-slot**. Valapp (`loadout_screen.dart`) tidak melakukan validasi serupa, meski ini kemungkinan besar tidak relevan untuk read-only display (Valapp cuma menampilkan loadout, bukan mengubahnya), jadi bukan bug — cuma catatan arsitektur.
- `NewsRemoteSource` sengaja memakai `Dio()` standalone (bukan `apiDioProvider`) — ini benar secara desain karena News tidak butuh autentikasi Riot Games (domain berbeda, tidak perlu token).
- `LoadoutRemoteSource` dan `RestrictionsRemoteSource` sudah benar memakai `apiDioProvider` (yang dilengkapi `ValorantInterceptor` dengan proactive refresh) — jadi keduanya **tidak** kena masalah token-mentah seperti `background_service.dart`.

---

# 8. DETAILED FIX PROMPTS

## 8.1 [KRITIS] Perbaiki Account Health — Hilangkan False-Positive di 3 Lapisan, Tambahkan Endpoint yang Hilang

```
Di project Flutter Valapp, perbaiki fitur Account Health/Restrictions yang saat ini menyembunyikan kegagalan network sebagai "akun bersih" di 3 lapisan berbeda, dan tambahkan endpoint restrictions yang terkonfirmasi hilang dari log game asli.

KONTEKS LENGKAP:
File yang terlibat:
- lib/features/profile/data/restrictions_remote_source.dart
- lib/features/profile/presentation/account_health_modal.dart (provider accountHealthProvider)
- lib/features/profile/presentation/profile_screen.dart (_AccountHealthBannerCard)
- lib/features/profile/domain/models/account_health.dart

BUKTI DARI LOG GAME ASLI (ShooterGame.log): client resmi Riot memanggil TIGA endpoint restrictions:
1. GET https://pd.{shard}.a.pvp.net/restrictions/v3/penalties (QueryName: Restrictions_FetchPlayerRestrictionsV3) — SUDAH dipakai Valapp
2. GET https://pd.{shard}.a.pvp.net/restrictions/v1/avoidList (QueryName: Restrictions_GetPlayerAvoidList) — SUDAH dipakai Valapp
3. GET https://pd.{shard}.a.pvp.net/restrictions/v1/activeFutureInterventions (QueryName: Restrictions_GetPlayerInterventions) — TIDAK PERNAH dipanggil Valapp sama sekali

MASALAH 1 — 3 lapisan silent-failure yang membuat "isClean" jadi false-positive:

Lapisan A (restrictions_remote_source.dart):
    .catchError((_) => <String, dynamic>{})
Ini membuat kegagalan network pada salah satu/kedua request restrictions diam-diam dianggap "tidak ada data" alih-alih diteruskan sebagai error.

Lapisan B (account_health_modal.dart, provider accountHealthProvider):
    } catch (_) {
      return const AccountHealth(isClean: true, penalties: [], avoidedPlayers: []);
    }
Exception apapun (termasuk currentCredentialsProvider gagal) langsung dianggap "akun bersih".

Lapisan C (profile_screen.dart, _AccountHealthBannerCard):
    final isClean = health?.isClean ?? true;
Ketika data masih loading atau null, ditampilkan sebagai "bersih" alih-alih "belum diketahui".

YANG PERLU DIKERJAKAN:

LANGKAH 1 — Tambahkan endpoint activeFutureInterventions yang hilang:
Di restrictions_remote_source.dart, tambahkan request ketiga ke Future.wait yang sudah ada:
    _dio.get<dynamic>('https://pd.$cleanShard.a.pvp.net/restrictions/v1/activeFutureInterventions')
        .then((r) => _toMap(r.data))
        .catchError((_) => <String, dynamic>{}),
Update fetchAccountHealth() untuk mengembalikan 3 hasil, dan update AccountHealth.fromJson() di account_health.dart untuk menerima parameter ketiga (interventionsJson) dan menggabungkan datanya ke dalam daftar penalties (cek struktur response — kemungkinan field bernama 'activeFutureInterventions' atau serupa berisi list intervention yang perlu di-parse mirip AccountPenalty.fromJson yang sudah ada; investigasi struktur response ini dulu sebelum implementasi, karena log tidak menyediakan response body).

LANGKAH 2 — Hilangkan silent-failure, ganti dengan status eksplisit "unknown/failed":
Ubah AccountHealth di account_health.dart supaya punya state ketiga selain isClean=true/false, misalnya:
    enum AccountHealthStatus { clean, hasRestrictions, unknown }
Ganti field isClean (bool) menjadi status (AccountHealthStatus). Di restrictions_remote_source.dart, JANGAN gunakan .catchError((_) => <String, dynamic>{}) yang menelan error — biarkan exception dari masing-masing request naik, tangkap di level fetchAccountHealth() dan tandai request mana yang gagal (misalnya kembalikan record/tuple berisi data dan flag sukses per-endpoint), sehingga AccountHealth.fromJson() bisa tahu apakah datanya benar-benar lengkap atau sebagian gagal dimuat.

LANGKAH 3 — Update provider accountHealthProvider:
Hapus fallback catch yang mengembalikan AccountHealth(isClean: true, ...). Ganti dengan rethrow (biarkan error asli naik ke UI) ATAU kembalikan AccountHealth dengan status AccountHealthStatus.unknown secara eksplisit jika ingin tetap menampilkan sesuatu tanpa spinner error penuh — tapi JANGAN pernah default ke status "bersih".

LANGKAH 4 — Update UI (account_health_modal.dart dan profile_screen.dart):
Untuk status AccountHealthStatus.unknown, tampilkan state visual yang jelas berbeda dari "bersih" maupun "ada masalah" — misalnya ikon abu-abu netral dengan teks "STATUS UNKNOWN — Unable to verify" alih-alih ikon hijau/merah. Update _AccountHealthBannerCard supaya final isClean = health?.isClean ?? true diganti dengan logic yang menampilkan status unknown ketika healthAsync belum ada data (loading atau error), bukan default ke true.

Tunjukkan hasil investigasi struktur response activeFutureInterventions (Langkah 1) dan implementasi enum AccountHealthStatus (Langkah 2) sebelum saya konfirmasi perubahan lengkap.
```

## 8.2 [KRITIS] Perbaiki Endpoint Storefront — Utamakan v3, Perbaiki Background Checker

```
Di project Flutter Valapp, perbaiki penggunaan endpoint storefront yang saat ini tidak konsisten dengan bukti log game resmi: game client HANYA memanggil v3, tidak pernah v2.

KONTEKS LENGKAP:
BUKTI DARI LOG GAME ASLI (ShooterGame.log):
    QueryName: [Store_GetStorefrontV3], URL [POST https://pd.ap.a.pvp.net/store/v3/storefront/{puuid}], Response Code: [200]
Tidak ada satupun baris log yang menunjukkan client resmi memanggil store/v2/storefront.

File yang terlibat:
- lib/features/shop/data/store_remote_source.dart (fitur Shop utama — endpoint v2 dipanggil DULUAN, v3 cuma fallback)
- lib/core/services/background_service.dart (background checker — HANYA memanggil v2, tanpa fallback sama sekali)

MASALAH 1 — store_remote_source.dart: urutan primary/fallback terbalik.
Endpoint v2 dipanggil sebagai request utama, v3 cuma dipanggil kalau v2 gagal dengan 400. Berdasarkan bukti log, v3 seharusnya jadi primary karena itu satu-satunya endpoint yang terbukti didukung dan dipakai client resmi saat ini.

MASALAH 2 — background_service.dart: hanya memanggil v2, tanpa fallback ke v3 sama sekali.
Ini membuat background checker berisiko gagal total kalau v2 benar-benar sudah/akan dideprecate Riot.

YANG PERLU DIKERJAKAN:

LANGKAH 1 — Balik urutan di store_remote_source.dart:
Tukar urutan pemanggilan sehingga store/v3/storefront/{puuid} menjadi request PERTAMA yang dicoba. Pertahankan fallback ke v2 SEBAGAI CADANGAN (bukan dihapus total) untuk berjaga-jaga terhadap kemungkinan v3 punya masalah sementara di sisi Riot — tapi v2 sekarang jadi fallback, bukan primary. Method HTTP kemungkinan tetap POST untuk v3 (sesuai bukti log 'POST https://pd.ap.a.pvp.net/store/v3/storefront/{puuid}') — cek dan pastikan method yang dipakai kode saat ini sudah benar POST, bukan GET, untuk endpoint v3.

LANGKAH 2 — Tambahkan v3 sebagai endpoint di background_service.dart:
Ubah runCheck() supaya memanggil store/v3/storefront/{puuid} dengan method POST sebagai request utama. Pastikan struktur response yang di-parse (SkinsPanelLayout, SingleItemOffers, dst) tetap kompatibel — cek apakah response v3 punya struktur field yang identik dengan v2 untuk bagian yang dipakai kode ini (kemungkinan besar sama karena StoreRepository di fitur Shop utama sudah menangani v3 dengan struktur field yang sama), sesuaikan parsing jika ada perbedaan struktur.

LANGKAH 3 — Verifikasi:
Setelah perubahan, jalankan flutter analyze. Test manual dengan membuka Shop Screen dan memicu BackgroundWishlistChecker (bisa lewat tombol debug sementara) untuk memastikan storefront berhasil di-fetch dengan endpoint v3 sebagai primary di kedua tempat.

Tunjukkan diff lengkap kedua file sebelum saya konfirmasi final.
```

## 8.3 [KRITIS] Perbaiki Endpoint Name-Service dari v2 ke v3

```
Di project Flutter Valapp, perbaiki endpoint name-service yang saat ini memakai versi API usang (v2), sedangkan bukti log game resmi menunjukkan client memakai v3.

KONTEKS LENGKAP:
BUKTI DARI LOG GAME ASLI (ShooterGame.log):
    QueryName: [DisplayNameService_UpdatePlayer], URL [POST https://pd.ap.a.pvp.net/name-service/v3/players], Response Code: [200]

File: lib/features/profile/data/account_remote_source.dart, method fetchDisplayNames()

Kode saat ini memanggil:
    'https://pd.$cleanShard.a.pvp.net/name-service/v2/players',

YANG PERLU DIKERJAKAN:

1. Ganti URL endpoint dari name-service/v2/players menjadi name-service/v3/players.
2. PENTING: cek apakah struktur request body dan response body berbeda antara v2 dan v3 (biasanya perubahan versi major API disertai perubahan struktur, bukan cuma path). Karena log game tidak menyediakan response body, cari dokumentasi API tidak resmi terkini (valapi.dev atau proyek open-source lain yang sudah menangani v3 name-service) untuk memastikan format request/response v3 sebelum mengubah parsing di kode. Jika ternyata format v3 berbeda dari v2 (misalnya field nama berbeda, atau bentuk response array vs object berbeda), sesuaikan parsing di fetchDisplayNames() sesuai format v3 yang benar.
3. Method HTTP tetap POST (sesuai bukti log), pastikan body request tetap dikirim sebagai array PUUID seperti pola yang sudah ada.
4. Setelah perubahan, jalankan flutter analyze. Test manual: buka Profile Screen dan pastikan display name masih ter-resolve dengan benar (bandingkan dengan nama Riot ID asli akun kamu).

Tunjukkan hasil investigasi format request/response v3 (langkah 2) sebelum melanjutkan implementasi, supaya saya bisa konfirmasi tidak ada breaking change struktur yang terlewat.
```

## 8.4 [KRITIS] Sambungkan Infrastruktur Resolve Display Name ke Multi-Account (Sesuai Pola yang Sudah Terbukti Bekerja)

```
Di project Flutter Valapp, sambungkan infrastruktur resolve Riot ID asli (yang sudah terbukti bekerja dengan baik di Profile Screen) ke fitur multi-account, yang saat ini masih menampilkan nama generik "Account (xxxxxx)".

KONTEKS LENGKAP:
File referensi pola yang SUDAH BENAR: lib/features/profile/presentation/profile_screen.dart, provider _displayNameProvider:
    final _displayNameProvider = FutureProvider.autoDispose<CachedFetchResult<String>?>((ref) async {
      final creds = await ref.watch(currentCredentialsProvider.future);
      if (creds == null) return null;
      final source = await ref.watch(accountRemoteSourceProvider.future);
      final cache = ref.watch(accountLocalCacheProvider);
      try {
        final name = await source.fetchDisplayName(creds.shard, creds.puuid);
        if (name != null && name.isNotEmpty) {
          await cache.saveDisplayName(creds.puuid, name);
          return CachedFetchResult(name);
        }
        throw StateError('Display name unavailable');
      } catch (_) {
        final cached = await cache.loadDisplayName(creds.puuid);
        if (cached != null && cached.isNotEmpty) {
          return CachedFetchResult(cached, fromCache: true);
        }
        if (creds.puuid.length >= 8) {
          return CachedFetchResult('Player (${creds.puuid.substring(0, 6)}...)');
        }
        return const CachedFetchResult('Valorant Player');
      }
    });

File yang PERLU diubah:
- lib/features/auth/presentation/webview_login_screen.dart
- lib/features/auth/presentation/account_switcher_modal.dart
- lib/features/auth/data/credentials_local_source.dart (method save())

YANG PERLU DIKERJAKAN:

LANGKAH 1 — Sambungkan saat login pertama kali:
Di webview_login_screen.dart, cari method yang memanggil repo.completeLoginFromWebView(...). Setelah berhasil mendapat Credentials, panggil AccountRemoteSource.fetchDisplayName(creds.shard, creds.puuid) (didapat lewat accountRemoteSourceProvider dari providers.dart) mengikuti pola try/catch yang identik dengan _displayNameProvider di atas. Jika berhasil, panggil ulang CredentialsLocalSource.save() dengan parameter displayName yang benar (Riot ID asli) untuk meng-update SavedAccountProfile yang baru dibuat. Jika gagal, biarkan fallback default (yang sudah ada di credentials_local_source.dart) tetap dipakai.

LANGKAH 2 — Retry otomatis di Account Switcher untuk akun dengan nama masih generik:
Di account_switcher_modal.dart, setiap kali modal dibuka, cek semua SavedAccountProfile yang displayName-nya masih berformat fallback lama (cek dengan startsWith('Account (') atau pola serupa yang sudah dipakai sebagai default). Untuk masing-masing, panggil fetchDisplayName() secara async di background (tidak blocking UI pembukaan modal) dan update profile-nya kalau berhasil kali ini, memakai pola cache-and-fallback yang sama seperti _displayNameProvider.

LANGKAH 3 — Refresh token akun non-aktif sebelum switch (bagian kedua dari masalah lama ini):
Di account_switcher_modal.dart, sebelum memanggil source.save(acc.credentials, ...) untuk menjadikan akun tersebut aktif, cek dulu apakah acc.credentials.isExpired (atau field sejenis untuk entitlement expiry). Jika true, JANGAN langsung switch — tampilkan loading indicator kecil di item akun tersebut, lalu coba refresh token untuk akun spesifik itu SEBELUM melanjutkan switch. Ini membutuhkan investigasi terlebih dahulu terhadap bagaimana PersistCookieJar (lib/core/network/cookie_service.dart) menangani sesi multi-akun — apakah cookie jar dipakai bersama untuk semua akun (berisiko salah sasaran saat reauth akun non-aktif) atau terisolasi per-akun. WAJIB investigasi ini dan laporkan hasilnya sebelum mengimplementasikan mekanisme refresh token akun non-aktif, karena pendekatan yang aman sangat bergantung pada jawaban ini.

Tunjukkan hasil investigasi cookie jar di Langkah 3 SEBELUM implementasi refresh token akun non-aktif — Langkah 1 dan 2 (resolve nama) bisa dikerjakan dan ditunjukkan terpisah lebih dulu karena risikonya lebih rendah dan tidak bergantung pada investigasi cookie jar.
```

## 8.5 [KRITIS] Konsolidasi Mutex Lock Generik untuk Semua Read-Modify-Write Cache

```
Di project Flutter Valapp, perbaiki race condition read-modify-write yang masih ada di 2 tempat kritis (belum diperbaiki sejak 2 ronde audit sebelumnya), dengan membuat mekanisme lock generik yang reusable.

KONTEKS LENGKAP:
CacheStorage.saveMatchMap() di lib/core/storage/cache_storage.dart sudah punya mutex lock manual (field _saveMatchMapLock dengan Completer) untuk mencegah race condition — TAPI solusi ini spesifik untuk satu method saja, tidak digeneralisasi. Pola read-modify-write tanpa lock masih ada persis sama di:
1. lib/features/match/data/match_local_cache.dart — MatchHistoryLocalCache.saveHistory(), MatchDetailLocalCache.saveMatchDetail()
2. lib/features/auth/data/credentials_local_source.dart — CredentialsLocalSource.save() (PALING KRITIS — menyimpan kredensial akun multi-account, race di sini bisa menghilangkan/mengorupsi kredensial akun lain)

YANG PERLU DIKERJAKAN:

LANGKAH 1 — Buat kelas lock generik reusable:
Buat file baru lib/core/utils/async_lock.dart:
    import 'dart:async';

    /// A simple per-key async mutex. Ensures only one async operation
    /// runs at a time for a given key, queuing others until it completes.
    class AsyncLock {
      static final Map<String, Future<void>> _locks = {};

      static Future<T> run<T>(String key, Future<T> Function() action) async {
        while (_locks[key] != null) {
          try {
            await _locks[key];
          } catch (_) {}
        }
        final completer = Completer<void>();
        _locks[key] = completer.future;
        try {
          return await action();
        } finally {
          completer.complete();
          _locks.remove(key);
        }
      }
    }

LANGKAH 2 — Refactor CacheStorage.saveMatchMap() untuk memakai AsyncLock:
Ganti implementasi Completer manual yang sudah ada dengan:
    Future<void> saveMatchMap(String matchId, String mapId) async {
      await AsyncLock.run('cache_match_map', () async {
        final current = await getMatchMaps();
        current[matchId] = mapId;
        await setJson(keyMatchMapCache, current);
      });
    }
Hapus field _saveMatchMapLock yang lama karena sudah tidak dipakai. JANGAN ubah signature publik method ini, JANGAN hapus getMatchMaps() karena masih dipakai aktif oleh MatchRemoteSource.fetchMatchDetailsRaw().

LANGKAH 3 — Terapkan AsyncLock ke MatchHistoryLocalCache dan MatchDetailLocalCache:
Di match_local_cache.dart, bungkus body saveHistory() dan saveMatchDetail() masing-masing dengan AsyncLock.run() memakai key unik berbeda untuk tiap cache (misal 'match_history_cache' dan 'match_detail_cache'), mempertahankan logic read-modify-write yang sudah ada persis sama di dalam closure.

LANGKAH 4 — Terapkan AsyncLock ke CredentialsLocalSource.save():
Bungkus bagian getSavedAccounts() → modify list → _saveProfiles() di dalam save() dengan AsyncLock.run('credentials_save', () async { ... }).

LANGKAH 5 — Verifikasi dengan test konkuren:
Tulis test sementara yang memanggil MatchDetailLocalCache.saveMatchDetail() dari 2 Future berbeda secara bersamaan (Future.wait) dengan matchId berbeda, verifikasi keduanya tersimpan tanpa saling menimpa. Lakukan hal serupa untuk CredentialsLocalSource.save() dengan 2 akun berbeda dipanggil bersamaan.

Setelah semua langkah, jalankan flutter analyze. Tunjukkan implementasi AsyncLock, hasil refactor ketiga file, dan hasil test konkuren dari Langkah 5, sebelum saya konfirmasi final.
```

## 8.6 [SEDANG] Perbaiki Warna Chroma yang Tidak Pernah Ter-resolve di Loadout Screen

```
Di project Flutter Valapp, perbaiki bug dimana warna chroma di Loadout Screen selalu memakai warna fallback, tidak pernah warna asli chroma yang sedang di-equip.

KONTEKS LENGKAP:
File: lib/features/loadout/presentation/loadout_screen.dart, class _WeaponSkinTile

Kode saat ini:
    Color? chromaColor;
    if (hasNonDefaultChroma && skinInfo?['chromas'] != null) {
      final chromas = skinInfo!['chromas'] as List<dynamic>? ?? [];
      for (final ch in chromas) {
        if (ch is Map && ch['uuid'] == weapon.chromaId) {
          final hex = ch['swatch'] as String?;
          if (hex != null) break;
        }
      }
    }
Variabel hex diambil tapi tidak pernah dipakai untuk assign chromaColor — badge "CHROMA" selalu memakai AppColors.rpAmber (warna fallback), bukan warna asli.

YANG PERLU DIKERJAKAN:

1. Cek dulu format string 'swatch' dari valorant-api.com — biasanya berbentuk hex color dengan format seperti 'FF5733FF' (8 karakter, RRGGBBAA) atau '#FF5733' (dengan/tanpa alpha). Investigasi contoh response chromas dari endpoint weapons/skins untuk memastikan format persis.

2. Tambahkan helper method untuk parsing hex string ke Color Flutter, contoh (sesuaikan dengan format yang ditemukan di langkah 1):
    Color? _parseHexColor(String? hex) {
      if (hex == null || hex.isEmpty) return null;
      var cleaned = hex.replaceAll('#', '');
      if (cleaned.length == 6) cleaned = 'FF$cleaned'; // tambahkan alpha jika tidak ada
      final value = int.tryParse(cleaned, radix: 16);
      return value != null ? Color(value) : null;
    }

3. Perbaiki blok kode yang mengambil chromaColor supaya benar-benar assign hasil parsing:
    Color? chromaColor;
    if (hasNonDefaultChroma && skinInfo?['chromas'] != null) {
      final chromas = skinInfo!['chromas'] as List<dynamic>? ?? [];
      for (final ch in chromas) {
        if (ch is Map && ch['uuid'] == weapon.chromaId) {
          chromaColor = _parseHexColor(ch['swatch'] as String?);
          break;
        }
      }
    }

4. Pastikan badge "CHROMA" di UI (baris yang memakai chromaColor ?? AppColors.rpAmber) tetap punya fallback ke rpAmber jika parsing gagal atau chroma tidak ditemukan di array chromas — jangan hilangkan fallback ini, cuma pastikan kasus normal (chroma ditemukan dan hex valid) benar-benar memakai warna asli.

5. Test manual: equip senjata dengan chroma non-default di game, buka Loadout Screen di Valapp, pastikan warna dot kecil di badge "CHROMA" sesuai dengan warna chroma asli yang di-equip.

Tunjukkan hasil investigasi format hex 'swatch' (langkah 1) sebelum implementasi, supaya parsing warnanya benar dari awal.
```

## 8.7 [SEDANG] Perbaiki Deteksi Pre-Round Spray yang Salah Pakai `.contains()`

```
Di project Flutter Valapp, perbaiki deteksi slot pre-round spray yang saat ini memakai .contains('01') padahal seharusnya .endsWith('01') sesuai komentar kode sendiri, untuk menghindari salah pilih spray akibat UUID yang kebetulan mengandung substring tersebut di posisi manapun.

KONTEKS LENGKAP:
File: lib/features/loadout/domain/models/player_loadout.dart, factory PlayerLoadout.fromJson()

Kode saat ini:
    // Slot 0 = PreRound spray (SocketID ends with '01')
    String? preRoundSpray;
    for (final s in spraySelections) {
      final sMap = _asMap(s);
      if ((sMap['SocketID'] as String? ?? '').contains('01')) {
        preRoundSpray = sMap['SprayID'] as String?;
        break;
      }
    }

YANG PERLU DIKERJAKAN:

1. Ganti .contains('01') menjadi .endsWith('01') sesuai komentar yang sudah ada, karena SocketID adalah UUID dan substring '01' bisa muncul di posisi manapun, bukan cuma di akhir sebagai penanda slot.

2. PENTING — sebelum mengandalkan endsWith('01') sepenuhnya, verifikasi dulu asumsi ini benar dengan mencari referensi struktur SocketID untuk spray slots dari dokumentasi API tidak resmi (valapi.dev atau proyek serupa) atau dari raw JSON response personalization/playerloadout jika tersedia contohnya. Pastikan slot 0 (pre-round) memang selalu memiliki SocketID yang berakhiran '01', dan bukan pola lain (misalnya '_0', atau index numerik terpisah di field lain).

3. Jika hasil investigasi menunjukkan ada cara yang lebih robust untuk identifikasi slot pre-round (misalnya field terpisah seperti 'SocketIndex' atau 'Slot' alih-alih parsing string SocketID), gunakan pendekatan itu sebagai gantinya — lebih baik daripada bergantung pada string matching UUID sama sekali.

4. Pertahankan fallback yang sudah ada (kalau tidak ditemukan spray dengan SocketID yang cocok, pakai spray pertama dalam list) sebagai graceful degradation.

Tunjukkan hasil investigasi struktur SocketID (langkah 2) sebelum melakukan perubahan, dan jelaskan pendekatan mana yang akhirnya dipakai (endsWith yang diperbaiki, atau pendekatan field terpisah yang lebih robust).
```

## 8.8 [SEDANG] Perbaiki Label "Peak Rank" agar Tidak Menyesatkan (Histori Terbatas)

```
Di project Flutter Valapp, perbaiki label "Peak Rank" di Rank Screen yang saat ini berpotensi menyesatkan karena dihitung hanya dari histori competitive-updates yang terbatas, bukan peak rank sesungguhnya sepanjang act/karier.

KONTEKS LENGKAP:
File: lib/features/rank/presentation/rank_screen.dart, class _PeakRankCard

Peak rank dihitung dengan membandingkan tierAfterUpdate dari updates (hasil _competitiveUpdatesProvider yang memanggil fetchCompetitiveUpdatesRaw). Endpoint Riot untuk competitive updates biasanya hanya mengembalikan sejumlah match terakhir (puluhan, bukan seluruh histori act), sehingga "Peak Rank" yang ditampilkan bisa jadi bukan peak sesungguhnya kalau pemain sempat naik lebih tinggi di luar rentang histori yang ter-fetch.

YANG PERLU DIKERJAKAN:

1. Cek response endpoint mmr/v1/players/{puuid} (yang sudah dipakai untuk _mmrProvider) — biasanya field seasonal/PlayerMmr sudah menyediakan data 'peak rank' resmi dari Riot untuk season/act saat ini (kemungkinan field seperti 'CompetitiveTier' tertinggi dalam SeasonalInfoBySeasonID, atau field eksplisit bernama 'peak' semacamnya). Investigasi struktur response ini (lihat player_mmr.dart yang sudah ada untuk referensi field apa saja yang sudah di-parse).

2. Jika ternyata ada field resmi untuk peak rank per season dari Riot sendiri (bukan dihitung manual dari histori terbatas), gunakan field tersebut sebagai sumber utama untuk _PeakRankCard alih-alih menghitung ulang dari updates.

3. Jika field resmi tidak ada dan perhitungan manual dari histori tetap menjadi satu-satunya cara, UBAH LABEL UI supaya tidak menyesatkan — misalnya ganti 'PEAK RANK' menjadi 'PEAK RANK (Recent Matches)' atau tambahkan subtitle kecil seperti '(based on last N ranked matches)' untuk memberi konteks yang jujur ke user tentang keterbatasan data ini, bukan mengklaim ini adalah peak rank absolut sepanjang act.

4. Update kode dan/atau label sesuai hasil investigasi langkah 1-2.

Tunjukkan hasil investigasi field peak rank resmi di response mmr/v1/players (langkah 1) sebelum memutuskan pendekatan mana yang dipakai — pakai field resmi jika ada, atau perbaiki labelnya jika tidak ada.
```

## 8.9 [SEDANG] Perbaiki Hardcoded Fallback Season yang Akan Menjadi Salah Seiring Waktu

```
Di project Flutter Valapp, perbaiki fallback season yang di-hardcode ke "EPISODE 9 // ACT 1" dan akan menjadi tidak akurat begitu Valorant memasuki episode/act berikutnya.

KONTEKS LENGKAP:
File: lib/shared/utils/valorant_assets.dart, method getActiveSeason(), dipakai aktif di lib/features/rank/presentation/rank_screen.dart (_activeSeasonProvider, 2 tempat UI)

Kode saat ini:
    if (episode.isEmpty) episode = 'EPISODE 9';
    if (act.isEmpty) act = 'ACT 1';
Dipakai baik sebagai fallback ketika tidak ada season yang match rentang tanggal saat ini, maupun ketika API call gagal total.

YANG PERLU DIKERJAKAN:

1. Untuk kasus API call gagal total (network error) — pertahankan fallback ke CACHE terakhir yang berhasil (cached != null check sudah ada di blok catch), ini sudah benar. Cuma perbaiki fallback TERAKHIR (ketika bahkan cache juga tidak ada, kasus paling ekstrem seperti instalasi baru tanpa internet) — daripada hardcode ke season spesifik, ubah jadi label yang jujur mengindikasikan data tidak tersedia, misalnya:
    return {'episode': '', 'act': '', 'label': 'Season data unavailable'};

2. Untuk kasus tidak ada season yang match rentang tanggal (logic pencarian season yang gagal menemukan match) — investigasi dulu KENAPA ini bisa terjadi. Kemungkinan penyebab: field 'type' dari API tidak selalu persis 'EAresSeasonType::Episode'/'EAresSeasonType::Act' di semua versi, atau ada gap tanggal antar season. Perbaiki logic pencarian season supaya lebih toleran (misalnya jika tidak ada yang benar-benar 'sedang berlangsung', ambil season dengan endTime paling baru/terdekat dari sekarang sebagai fallback yang lebih masuk akal daripada hardcode).

3. Update UI di rank_screen.dart (kedua tempat yang memakai _activeSeasonProvider) supaya menangani kasus label kosong/tidak tersedia dengan baik (misalnya sembunyikan section season sepenuhnya jika label kosong, alih-alih menampilkan label yang berpotensi salah).

4. Pertimbangkan menambahkan mekanisme sederhana untuk mendeteksi bahwa fallback hardcoded ini sudah usang — misalnya cek apakah DateTime.now() sudah lewat jauh dari waktu build aplikasi (bisa disimpan sebagai konstanta build-time), dan jika iya, jangan tampilkan fallback hardcoded sama sekali, tampilkan 'Season data unavailable' saja.

Tunjukkan hasil investigasi logic pencarian season yang gagal (langkah 2) sebelum implementasi, termasuk skenario spesifik apa yang menyebabkan pencarian season tidak menemukan match.
```

## 8.10 [SEDANG] Ganti Perhitungan Match Result Manual dengan Field Resmi dari Riot

```
Di project Flutter Valapp, perbaiki perhitungan hasil match (Victory/Defeat/Draw) di Profile Screen yang saat ini dihitung manual dari jumlah ronde, berpotensi salah untuk mode non-Competitive atau kasus forfeit/surrender.

KONTEKS LENGKAP:
File: lib/features/profile/presentation/profile_screen.dart, provider _profileMatchesProvider

Kode saat ini:
    MatchResult matchResult = MatchResult.unknown;
    if (details.roundResults.isNotEmpty) {
      final pt = player.teamId.toLowerCase();
      final myWins = details.roundResults.where((r) => r.winningTeam.toLowerCase() == pt).length;
      final oppWins = details.roundResults.length - myWins;
      matchResult = myWins > oppWins ? MatchResult.victory : myWins < oppWins ? MatchResult.defeat : MatchResult.draw;
    }

YANG PERLU DIKERJAKAN:

1. Cek struktur response match-details Riot (lib/features/match/domain/models/match_details.dart, MatchDetails.fromJson) — cari apakah ada field resmi untuk hasil tim yang eksplisit, biasanya berupa array 'Teams' dengan field seperti 'TeamID' dan 'Won' (boolean) atau 'RoundsWon'/'RoundsPlayed' di level tim (bukan dihitung dari roundResults per-ronde individual). Field semacam ini jika ada akan jauh lebih akurat dan mencakup kasus non-Competitive serta forfeit dengan benar, karena itu adalah keputusan final resmi dari Riot, bukan inferensi dari data ronde.

2. Jika field resmi ditemukan, tambahkan field tersebut ke model MatchDetails (jika belum ada), dan ganti logic di _profileMatchesProvider supaya memakai field resmi ini alih-alih menghitung ulang dari roundResults.

3. Jika field resmi TIDAK ditemukan di response match-details (kemungkinan API Riot memang tidak menyediakannya secara eksplisit untuk semua mode), pertahankan perhitungan manual sebagai fallback, TAPI tambahkan penanganan khusus untuk mode yang diketahui tidak berbasis ronde standar (Deathmatch, Escalation, dll — cek field queueId/gameMode di response untuk deteksi mode), dan untuk mode tersebut gunakan logic yang sesuai (misalnya berdasarkan skor/kill count, bukan ronde) alih-alih memaksakan logic ronde yang cuma valid untuk mode seperti Competitive/Unrated/Spike Rush.

4. Tulis unit test yang memverifikasi matchResult benar untuk beberapa skenario: kemenangan normal, kekalahan normal, draw, dan (jika relevan) mode non-ronde seperti Deathmatch.

Tunjukkan hasil investigasi struktur response match-details untuk field hasil resmi (langkah 1) sebelum melanjutkan implementasi.
```

## 8.11 [SEDANG] Perbaiki Harga Per-Item Skin di Dalam Featured Bundle yang Masih 0 VP (Belum Diperbaiki dari Audit Sebelumnya)

```
Di project Flutter Valapp, perbaiki harga individual skin di dalam Featured Bundle yang MASIH ditampilkan sebagai 0 VP — ini adalah bug lama dari audit sebelumnya yang belum diperbaiki.

KONTEKS LENGKAP:
File yang terlibat:
- lib/features/shop/domain/models/storefront.dart, class FeaturedBundle, factory FeaturedBundle.fromJson() — MASIH cuma mengambil itemIds (List<String>), tidak ada harga per-item
- lib/features/shop/presentation/bundle_detail_modal.dart — MASIH hardcode price: 0 untuk setiap SkinOffer yang dibuat dari item bundle

CATATAN: model NightMarketOffer di file yang sama SUDAH punya pola yang benar untuk basePrice/discountedPrice/discountPercent per-item — gunakan itu sebagai referensi struktur.

YANG PERLU DIKERJAKAN:

1. Cek struktur JSON asli response FeaturedBundle.Items dari Riot storefront API v3 (setelah endpoint diperbaiki ke v3 sesuai prompt 8.2) — cari field harga per-item (kemungkinan BasePrice/DiscountedPrice/DiscountPercent per entry, mengikuti pola Cost map dengan key currency VP yang sama seperti di tempat lain: '85ad13f7-3d1b-5128-9eb2-7cd8ee0b5741', sekarang tersedia sebagai ValorantCurrency.vpUuid).

2. Buat class baru BundleItem di storefront.dart:
    class BundleItem {
      final String itemId;
      final int basePrice;
      final int discountedPrice;
      final int discountPercent;
      const BundleItem({required this.itemId, required this.basePrice, required this.discountedPrice, required this.discountPercent});
    }

3. Ubah FeaturedBundle supaya punya field List<BundleItem> items, sediakan getter itemIds => items.map((i) => i.itemId).toList() untuk backward compatibility dengan kode yang sudah memakai itemIds.

4. Update FeaturedBundle.fromJson() untuk mem-parsing harga per-item memakai ValorantCurrency.vpUuid sebagai key, ikuti pola yang sama persis dengan NightMarketOffer.fromJson() di file yang sama.

5. Update bundle_detail_modal.dart supaya memakai harga asli dari BundleItem yang berkorespondensi (bukan hardcode price: 0).

6. Tulis unit test untuk FeaturedBundle.fromJson() dengan JSON sample yang merepresentasikan struktur harga per-item bundle.

Tunjukkan hasil investigasi struktur JSON harga per-item (langkah 1) sebelum melanjutkan implementasi.
```

## 8.12 [RENDAH] Konsolidasi Duplikasi Fetch Loadout antara Profile Screen dan Loadout Screen

```
Di project Flutter Valapp, hilangkan duplikasi network call untuk data loadout yang saat ini di-fetch secara independen oleh Profile Screen dan Loadout Screen untuk keperluan yang tumpang tindih.

KONTEKS LENGKAP:
File yang terlibat:
- lib/features/profile/presentation/profile_screen.dart, provider _profileCardProvider — fetch loadout raw untuk keperluan player card saja
- lib/features/loadout/presentation/loadout_screen.dart, provider _loadoutProvider — fetch loadout raw lengkap (weapons, spray, title, card)

Kedua provider secara independen memanggil source.fetchLoadoutRaw(creds.shard, creds.puuid) — kalau user membuka Profile Screen lalu Loadout Screen (atau sebaliknya) dalam sesi yang sama, data yang secara fungsional sama di-fetch dua kali dari network.

YANG PERLU DIKERJAKAN:

1. Evaluasi apakah _profileCardProvider di profile_screen.dart bisa diganti untuk membaca dari LoadoutLocalCache (lib/features/loadout/data/loadout_local_cache.dart) yang sudah ada, alih-alih fetch mandiri. Karena kedua provider ini pakai autoDispose dan scope Riverpod yang berbeda (beda file), pertimbangkan memindahkan _loadoutProvider (dari loadout_screen.dart) ke lokasi yang bisa diakses bersama (misalnya providers.dart sebagai provider global, bukan private ke masing-masing screen), sehingga Profile Screen dan Loadout Screen sama-sama watch provider yang sama dan Riverpod otomatis men-dedupe fetch-nya (karena provider yang sama tidak akan fetch dua kali selama masih ada consumer aktif).

2. Jika opsi 1 terlalu invasif untuk struktur kode saat ini, alternatif minimal: pastikan _profileCardProvider melakukan cache-first check ke LoadoutLocalCache sebelum fetch mandiri, supaya kalau LoadoutScreen sudah pernah dibuka dan menyimpan cache, Profile Screen tidak perlu fetch ulang selama cache masih fresh.

3. Pilih salah satu pendekatan, implementasikan, dan jalankan flutter analyze.

Jelaskan pendekatan mana (opsi 1 atau 2) yang dipilih dan alasannya sebelum implementasi, karena ini melibatkan trade-off antara kompleksitas refactor vs penghematan network call.
```

## 8.13 [RENDAH] Beri UI untuk Notification Rules atau Hapus Sepenuhnya (Keputusan Produk)

```
Di project Flutter Valapp, tentukan nasib sistem notification-rules yang sekarang SEBAGIAN AKTIF (dipakai oleh background checker) tapi TIDAK ADA UI untuk user mengaturnya, dan punya inkonsistensi default kategori antara dua tempat.

KONTEKS LENGKAP:
File yang terlibat:
- lib/features/shop/presentation/notification_rule_service.dart (notificationRulesProvider, NotificationRulesNotifier — constructor punya default kategori: wishlist, melee, vandal, phantom, nightMarket)
- lib/core/services/background_service.dart (fallback default kategori jika rulesList null: wishlist, melee, vandal, phantom — TIDAK termasuk nightMarket, TIDAK konsisten dengan default di atas)

STATUS SAAT INI: notificationRulesProvider tidak pernah di-watch dari widget manapun, sehingga tidak pernah diinisialisasi Riverpod, sehingga toggleCategory() tidak pernah bisa dipanggil user. Tapi background_service.dart membaca key cache yang sama (keyNotificationRules) dan punya fallback hardcoded sendiri yang BERBEDA dari default constructor NotificationRulesNotifier.

TANYAKAN KE SAYA TERLEBIH DAHULU sebelum eksekusi mana dari 2 opsi berikut yang dipilih:

OPSI A — Bangun UI settings untuk fitur ini:
1. Tambahkan section baru di Profile Screen (atau halaman Settings baru jika belum ada) berisi toggle switch untuk setiap NotificationCategory (wishlist, melee, vandal, phantom, operator, sheriff, nightMarket), memakai ref.watch(notificationRulesProvider) dan ref.read(notificationRulesProvider.notifier).toggleCategory(category).
2. Perbaiki inkonsistensi default: samakan default kategori antara NotificationRulesNotifier constructor dan fallback di background_service.dart — pastikan keduanya identik, dan idealnya background_service.dart membaca sepenuhnya dari cache (yang sekarang sudah bisa diisi lewat UI baru) tanpa perlu fallback hardcoded terpisah sama sekali, kecuali untuk kasus benar-benar belum pernah di-set (first-run).

OPSI B — Sederhanakan, hapus kompleksitas kategori:
1. Hapus seluruh sistem kategori (melee/vandal/phantom/operator/sheriff/nightMarket toggle), pertahankan hanya notifikasi wishlist yang sudah pasti berguna dan sudah teruji.
2. Hapus notification_rule_service.dart sepenuhnya, dan hapus logic evaluateAlerts-style di background_service.dart yang bergantung padanya, sederhanakan runCheck() supaya cuma fokus ke wishlist matching.

Tunggu konfirmasi saya (Opsi A atau B) sebelum mengeksekusi perubahan apapun terkait fitur ini.
```

---

# 9. RINGKASAN PRIORITAS

## Tahap 1 — Kritis (kerjakan dulu)
1. **8.1** — Account Health: hilangkan 3 lapisan false-positive, tambahkan endpoint yang hilang
2. **8.2** — Storefront: utamakan v3 sesuai bukti log resmi, perbaiki background checker
3. **8.3** — Name-service: v2 → v3 sesuai bukti log resmi
4. **8.4** — Sambungkan resolve display name + refresh token ke multi-account
5. **8.5** — Konsolidasi mutex lock generik (race condition, sudah 2 ronde belum ditangani)

## Tahap 2 — Sedang
6. **8.6** — Warna chroma di Loadout tidak pernah ter-resolve
7. **8.7** — Deteksi pre-round spray salah pakai `.contains()`
8. **8.8** — Label "Peak Rank" berpotensi menyesatkan
9. **8.9** — Hardcoded fallback season akan jadi salah seiring waktu
10. **8.10** — Match result dihitung manual, ganti dengan field resmi jika ada
11. **8.11** — Harga per-item bundle masih 0 VP (bug lama, belum diperbaiki)

## Tahap 3 — Rendah / Housekeeping
12. **8.12** — Konsolidasi duplikasi fetch loadout Profile vs Loadout Screen
13. **8.13** — Keputusan produk: bangun UI notification-rules atau hapus

## Belum punya fix prompt tersendiri (dari audit sebelumnya, masih berlaku)
- Threshold XP account level belum diverifikasi ke sumber resmi (5.4)
- Mission title selalu generik "Mission" (5.5)
- Duplikasi resolve map name di match detail screen (5.6)
- Klaim "Stay Signed In" belum disinkronkan dengan realita (5.7) — kerjakan setelah 8.2 selesai
- Dead code login manual + MFA (5.8) — keputusan produk
- Zero test coverage (5.10)

---

**Catatan penutup:** Simpan file ini di repo (`docs/AUDIT.md` atau serupa) supaya tidak hilang lagi. Log game asli yang dipakai untuk verifikasi (`ShooterGame.log`, `cef3.log`) adalah bukti berharga — kalau kamu punya log lain dari sesi bermain berbeda (terutama yang mencakup buka Shop, cek Match History, atau proses reauth/login), itu bisa dipakai untuk memverifikasi lebih banyak endpoint lagi, termasuk struktur response body kalau kamu bisa dapatkan lewat network capture (mitmproxy/Charles/Fiddler) alih-alih cuma log query.
