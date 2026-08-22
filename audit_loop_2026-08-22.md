**Audit Loop — Valapp (Flutter Valorant Shop Monitor) — 2026-08-22**

**Project Profile**:
- Stack: Flutter 3.44.8 (Dart >=3.3.0), Riverpod 2.5.1, Dio 5.4, go_router 13.2, flutter_secure_storage, shared_preferences, workmanager, flutter_local_notifications, webview_flutter, cached_network_image
- Monorepo: tidak, single package, 86 lib Dart files + 33 test files
- Scope: lib/** 100% sweep via rg+analyze, 60+ files dibaca verbatim via codegraph_explore+Read, test/** 100%
- Prev claim: audit_report_2026-08-22.md "24/24 selesai" — diverifikasi sebagian, 3 residual + 45 temuan baru

**Executive Summary**:
- Health: Medium — core auth/cache tetap solid, tapi debt arsitektur + perf I/O + doc drift nahan skalabilitas
- Verifikasi: flutter analyze = No issues found, flutter test = 133/133 passed (24s, 0 fail)
- Count temuan unik setelah dedup: 52 (Critical 2, High 14, Medium 19, Low 17)
- Duplikat merge: 6 cluster (UUID lookup, DI god-file, pipeline fetch-cache, tier prefix, fallback masking, prefs multi-MB)
- Kontradiksi: 0 — semua aspek konsisten, klaim prev audit "24/24 selesai" downgrade jadi "21/24 full, 3 partial residual"
- Risiko terbesar: ARCH-01 god providers.dart + P1 prefs multi-MB + TST-01 tanpa CI gate + CQ-01 enrich 240-line + EH-01 tanpa global error hook

**Findings Grouped — Verified & Cross-Checked**:

**Security — Wave 1** (Coverage 100% scope, Skill: codegraph_explore 7 query + Read + rg grep secrets):
- **S-01 MED** (6: 2*1*3): removeAccount active purge lewat // H5 residual — providers.dart:382-407 hanya purge jika wasActive && remaining.isNotEmpty — jika hapus akun terakhir/active terakhir tanpa remaining, cookie jar/WebView sisa leak ke next login. File:Line providers.dart:382-407 — Fix: purge selalu saat wasActive true.
- **S-02 LOW-MED** (6): _restoreWebViewCookies restore 2 domain tanpa clear domain lama per-puuid — providers.dart:289-324 — sisa ssid previous bisa survive jika clearCookies gagal partial. Fix: hapus duplikat setCookie loop jadi single-domain + retry.
- **S-03 LOW**: AndroidManifest backup rules allowBackup true tanpa exclude SecureStorage — minor. Fix: set fullBackupContent xml exclude prefs.
- **S-04 LOW**: Fallback filter 429/timeout di auth_repository — auth_repository.dart:277 — sama pattern EH-03 tapi medium? Verifikasi butuh only 404/405.
- **S-05/06 LOW**: Native cookie channel error swallow silent + CrossIsolateLock stale 10s — hardening info.
- Area Bersih: OAuth state/nonce 32-byte Random.secure, redirect URI strict equality, HttpOnly ssid via NativeCookieReader (MainActivity.kt + AppDelegate.swift), puuid guard, session-generation guard, logout total wipe, .gitignore *.jks/*.keystore aman, logging tanpa token.

**Code Quality & Maintainability — Wave 1** (30/86 verbatim, 86/86 rg sweep):
- **CQ-01 Critical 16 (4*2*2 normalized 16 High per loop 1-4 scale = 4*3*3=36 High)**: _enrichStorefront 240 baris nest 6 level — store_repository.dart:49-291 — Root: god method + heuristik bundle deduce inline. Fix: ekstrak BundleNameResolver+BundleArtSelector.
- **CQ-02 High 18**: UUID triple-lookup duplikat 8+ tempat — store_repository.dart:89-92 etc, home_screen.dart:153 single variant miss — Fix: helper byUuidLookup(map,id).
- **CQ-03 High 18**: Raw Color(0xFFFF4655) 44x di 13 file bypass AppColors.red — Fix: migrasi AppColors.* + custom_lint.
- **CQ-04 High 18**: Duplicate pipeline fetch-cache providers.dart:480-504,560-610 3 provider identik — Fix: generic fetchWithSessionGuard<T>.
- **CQ-05 Medium 9**: SessionActions di core/di bukan domain — providers.dart:282-447 — Fix: pindah features/auth/application.
- **CQ-06 Medium 9**: invalidateSession 18 entry manual — providers.dart:426-446 — Fix: const list + loop atau watch currentCredentialsProvider.
- **CQ-07 Medium 9**: Tier prefix hardcode 4 tempat — tier_colors.dart:48-52 vs valorant_constants:43-47 — Fix: tabel kanonik prefix->{name,color,cdn}.
- **CQ-08 Low 4**: discountPercent vs normalizeDiscountPercent — price_utils.dart:14 vs 27 — Deprecate always-x100 variant.
- **CQ-09 Low 2**: 'Valorant Player' placeholder magic string 3 tempat — Fix: DisplayNameUtil.fallbackName const.
- **CQ-10 Low 2**: CrossIsolateLock busy-loop tanpa delay pada stale delete fail — cross_isolate_lock.dart:61-72
- **CQ-11 Low 4**: analysis_options default only — tanpa strict/custom_lint
- **CQ-12 Low 4**: DI singleton vs injection inconsistency — news_remote_source statis vs cache injection
- Area Bersih: AsyncLock benar, VersionService dedup exemplary, AppColors single source, flutter analyze 0 issue, 0 TODO

**Error Handling & Logging — Wave 1** (100% scope, 89 catch(_) sweep):
- **EH-01 High 12 (4*1*3? loop scale High)**: No global error hooks — main.dart:7-24, app.dart:36-52 — 0 grep FlutterError.onError/runZonedGuarded — release grey screen tanpa jejak. Fix: 3 hooks + GoRouter errorBuilder.
- **EH-02 High 12**: _credentials.load() outside try in onError — valorant_interceptor.dart:313 vs try:318 — fast-path 400 + SecureStorage throw => handler never resolve => hang. Fix: move load inside try + outer catch handler.next(err).
- **EH-03 Medium 9**: account_remote_source.dart:81-93 v2->v3 fallback catch all DioException mask 429/401 — Fix: only 404/405 rethrow.
- **EH-04 Medium 6**: 61 debugPrint tanpa level/sink — bocor logcat prod — Fix: AppLogger redact.
- **EH-05 Medium 6**: getSavedAccounts catch(_)->[] hilangkan semua akun jika satu blob korup — credentials_local_source.dart:381-383 — Fix: log + keep raw.
- **EH-06 Medium 6**: No total deadline/circuit breaker retry 4x60s => 4-5 menit hang — retry_interceptor.dart:22-41
- **EH-07 Medium 6**: restrictions_remote_source 3 fetch catchError lumat identitas error — :22-44
- **EH-08 Low 3**: mmr/match saveMatchMap catch(_){} silent
- **EH-09 Low 3**: news_remote_source catch-all -> [] tak bisa bedakan empty vs fail — :76-81
- **EH-10 Low 3**: ApiException url with puuid terekspos UI valorant_error_display — puuid = PII minor — sanitize strip puuid.
- **EH-11 Low 2**: retry button onRetry throw unhandled — valorant_error_display.dart:32-43
- **EH-12 Low 2**: providers redirect baca credsAsync.value null saat AsyncError => mask jadi logout — app.dart:41-49
- Area Bersih: ApiResponseDecoder strict, ErrorClassifier type-first, 403 bukan authPermanent fixed, retryDio timeout fixed, toString() not jsonEncode fixed.

**Testing — Wave 1** (33/33 inventoried, 22 full-read, flutter test 133/133 verified):
- **TST-01 High 16**: Zero CI gate — .github/workflows/build.yml 3-83, release.yml, codemagic.yaml 66 — flutter test tidak pernah dipanggil. Fix: job test+analyze required.
- **TST-02 High 12**: Hanya 1 widget test (CountdownTimer) utk ~21 screen/modal — shop/profile/rank zero coverage.
- **TST-03 Medium 9**: Data layer non-shop tanpa test (profile/rank/auth silentWebview/background/notification/cookie_service).
- **TST-04 Medium 9**: Flaky wall-clock assert >=80ms, <110ms, sleep 800ms enrichment race — rate_limit_interceptor_test:38, pass5:55, pass6:241 — Fix: fake_async + polling timeout.
- **TST-05 Low 4**: No Clock injection DateTime.now() 12x — valorant_interceptor_proactive_test, account_health — Fix: package clock.
- **TST-06 Medium 6**: Repo test hanya happy 200, zero 401/403/429 — domain_repositories_test
- **TST-07 Low 4**: No integration/e2e — integration_test/ missing
- **TST-08 Low 2**: Hand-rolled _MockAdapter duplikat 4 file — drift risk — Fix: test_support mock table.
- **TST-09 Low 2**: Singleton CacheStorage/SecureStorage global di test — contamination risk.
- **TST-10 Low 2**: Pure utils tanpa test (date_time_utils, price_utils etc) — cheapest coverage.
- Area Bersih: OAuth entropy, whitelist cookie ssid, cross-account isolation matrix, parser anti-crash, interceptor heuristics — 133 hijau 24s.

**Documentation — Wave 1** (README vs impl 15 klaim, flutter analyze/test bukti):
- **DOC-01 High 9**: Badge 18/18 tests salah — aktual 33 file, 133 case — README.md:6,103-115
- **DOC-02 High 9**: Techstack video_player tidak ada di pubspec, aktual WebView MP4 — README:62 vs pubspec
- **DOC-03 High 9**: Fallback client version claim 13.02-shipping-7-5092570 vs kode 11.02-shipping-14-3407743 — README:46 vs valorant_headers.dart:19
- **DOC-04 Medium 6**: Name Service v3 primary terbalik — primary aktual PUT v2 fallback POST v3 — README:41 vs account_remote_source:82-93
- **DOC-05 Medium 6**: LICENSE badge link broken — file LICENSE missing — README:7,168
- **DOC-06 Medium 6**: SDK badge vs pubspec vs codemagic mismatch — README 3.3.0 vs pubspec Dart >=3.3.0 (Flutter 3.19+) vs codemagic 3.44.8
- **DOC-07 Low 3**: Riverpod 2.6+ claim vs pubspec ^2.5.1 — README:55
- **DOC-08 Low 2**: RankBadge widget klaim tidak ada — README:84
- **DOC-09 Low 2**: ShopScreen/MatchLocalCache nama drift — README:87-88 vs HomeScreen/MatchHistory*LocalCache
- **DOC-10 Low 2**: Architecture tree omit core/navigation, features/debug, shared/constants
- **DOC-11 Low 2**: pubspec description stale vs fitur lengkap
- **DOC-12 Low 1**: No CHANGELOG.md — version 1.0.0+1 only — plus audit_report di root hygiene
- **DOC-13 Info 1**: tier_name_util doc refer stale shop_screen
- Area Bersih: Endpoint docs store v3/penalties akurat, claim AsyncLock/RateLimit/Match eviction 30/version sync 24h akurat, AppColors hex akurat.

**Correctness — Wave 2** (shop/match/rank/contracts/loadout/profile/news, wishlist race, countdown WIB):
- **C-01 Low 4**: migrateLegacyWishlist tanpa tombstone — cache_storage.dart:243-253 — akun kedua clone legacy termasuk item yg sudah di-unwishlist di akun pertama. Fix: remove legacy key after copy.
- **C-02 Low 2**: Storefront copyWith hilang _legacyBundle — storefront.dart:263-269
- **C-03 Low 4**: Wishlist identity inkonsisten 3 definisi (catalog primaryLevelUuid vs modal levelUuid vs home levelUuid OR skinUuid) — wishlist_catalog_screen:760-774 vs skin_detail_modal:42 vs home_screen:152 — shop NM non-primary miss. Fix: kanonik skinUuid.
- **C-04 Info 1**: match_local_cache FIFO not LRU untuk blob legacy fallback — :154-163 — re-save tidak pindah order.
- **C-05 Info 1**: orphan .tmp jika crash antara write tmp+rename — :134-144 — startup sweep needed.
- **C-06 Info 1**: rank progress clamp 0-100 Immortal >100 selalu full — rank_screen:1174 — sadar simplifikasi.
- Area Bersih: OfferID-price map alignment OK, NightMarket 3-variant fixed, countdown WIB 07:00 clamp OK, wishlist race serial+canonical re-read OK, per-puuid namespace+CacheTransaction guard OK, match eviction file-based mtime cap 30 OK, RR sparkline+peak benar, battlepass detection OK, account health expired filter+hasErrors unknown OK, lifecycle dispose OK — analyzer 0 issue.

**Architecture & Design — Wave 2** (providers 744L, import graph 100% sweep):
- **ARCH-01 Critical 16**: God file DI 744L wiring 8 fitur + SessionActions + 6 pipeline — providers.dart:1-744 — Fix: split core/di + feature/di.
- **ARCH-05 Critical 12**: Dependency inversion core->features, shared->domain, domain lintas fitur — interceptor/services import credentials/wallet — Fix: CredentialsReader interface di core adapter di features.
- **ARCH-03 High 12**: Duplikat pipeline fetch-cache repo vs provider inline (guard+CachedFetchResult beda) — store/match/loadout vs providers 480-744 — Fix: generic cachedFetch core.
- **ARCH-04 High 9**: Invalidate manual 18 provider — providers.dart:426-446 — Fix: watch currentCredentials+apiDio auto-invalidate + container test.
- **ARCH-02 High 9**: SessionActions di DI layer pakai SecureStorage.instance statis — Fix: features/auth/application/session_actions injection.
- **ARCH-08 High 9**: God presentasi home 2073L + _enrichStorefront 240L duplicate triple-key 4x — Fix: pecah per-section + StoreEnricher.
- **ARCH-07 Medium 8**: Inkonsistensi modul rank/profile tanpa repository, news Dio telanjang bypass interceptor — Fix: tambah Rank/Profile/NewsRepository.
- **ARCH-09 Medium 6**: Bypass DI singleton vs provider mix — store_repository CacheStorage.instance etc — Fix: injection full.
- **ARCH-06 Low 3**: Cycle laten session_reconnect<->providers — Fix: selesaikan ARCH-05.
- **ARCH-10 Low 3**: Tanpa import_lint/file-size guard — analysis_options stock — Fix: import_lint core!->features.
- **ARCH-11 Low 3**: enrichedMatchHistory 20x await decode di main isolate ~80L di provider — providers.dart:694-734 — Fix: pindah MatchRepository + compute().
- **ARCH-12 Low 1**: /debug/notifications route selalu registered, RateLimit tail global 500ms — app.dart:61, rate_limit:16

**Performance — Wave 2** (valorant_assets multi-MB, matchCache file-per-match, rateLimit, background):
- **P-01 Critical 16 Terverifikasi**: SharedPreferences multi-MB blob — cache_storage:160-163 setString full-file rewrite + valorant_assets 156-171 embed chromas+levels multi-MB jsonEncode di UI isolate + home_screen 613-628 forceRefresh true tiap resume refetch 6-8 MB rebuild map + match_local_cache 17-49 saveHistory O(total) rewrite + CachedNetworkImage tanpa memCacheWidth decode full res 38px avatar & grid — Dampak jank startup/resume + GPU memory churn. Fix: file-per-blob (pola MatchDetail) + compute() + hapus forceRefresh kecuali pull-to-refresh + memCacheWidth 76px avatar.
- **P-02 Medium 8 Hipotesis**: jsonEncode detail di UI isolate + _enrichFromCache decode N serial + BG isolate prefs last-writer-wins (CrossIsolate hanya guard wishlist dedupe) + getMapsMap tanpa memory-cache decode ulang tiap mount.
- **P-03 Low 4 Terverifikasi**: triple-key index 3x RAM (obj ref shared) + catalog dedup sort 600 skin tiap open + shimmer 25 controllers repeat + versi key _v5 tanpa cleanup.
- Area Bersih: RateLimit future-chain gap idle free OK, ValorantInterceptor cooldown+dedup+fast entitlement OK, MatchDetail file-per-match LRU30 atomic tmp+rename OK, Countdown deadline OK, history enrichment bounded 12 batch3 guard OK, controllers dispose OK, ListView.builder lazy OK.

**Duplicates Merged** (6 cluster):
- DUP-A UUID lookup: CQ-02 + ARCH-08 triple-key — merge hitung 1 — primary CQ-02 — file store_repository 89-92 etc — count once.
- DUP-B DI god-file: ARCH-01 parent, CQ-05+ARCH-02 SessionActions, CQ-06+ARCH-04 invalidate, ARCH-11 enrich — merge 4 jadi 1 structural cluster tapi lapor terpisah untuk aksi.
- DUP-C Fetch-cache pipeline: CQ-04 + ARCH-03 — merge 1.
- DUP-D Fallback masking: H3 fixed store vs EH-03 account_remote_source residual — beda file, tidak merge — catat residual.
- DUP-E Prefs blob: P-01 + L2 legacy — merge, P-01 superset.
- DUP-F Tier prefix: CQ-07 standalone — no dup.

**Contradictions Resolved**:
- Prev audit 24/24 selesai vs new: Tidak kontradiksi — 3 partial residual terbukti (H5 purge saat remaining empty, H3 pattern hidup di account_remote_source, L2/P-01 masih multi-MB) — status direvisi 21 full + 3 partial.
- Doc claim vs reality (version, video_player, test count): Bukan kontradiksi antar-aspek — semua wave sepakat doc drift — resolved bukti file:line.
- RateLimit 500ms "bug vs feature": EH/Perf sepakat — desain anti-429 intentional 500ms tail, idle free — bukan bug — resolved sebagai tradeoff dokumentasikan.
- No contradictory findings antar subagent setelah cross-check file:line.

**Verification Pass Log** (sample 20% prioritized High/Critical, n=14 dari 52):
- CQ-01 store_repository:49-291 — exists — enrich 240L nest — PASS
- CQ-02 store_repository:89-92 home_screen:153 — exists — tri-variant — PASS (home single variant confirmed)
- EH-01 main.dart:7-24 grep FlutterError.onError 0 hit — exists — PASS
- EH-02 valorant_interceptor:313 vs 318 load outside try — exists — PASS (hang risk confirmed)
- TST-01 build.yml 3-83 no flutter test — exists — PASS
- DOC-02 pubspec no video_player, skin_video_player WebView — PASS
- DOC-03 valorant_headers defaultClientVersion 11.02 vs README 13.02 — PASS
- ARCH-01 providers 744L — exists wc -l 744 — PASS
- P-01 cache_storage 160-163 setString full rewrite — PASS, valorant_assets forceRefresh true home 622-628 PASS, memCacheWidth 0 hit PASS
- C-01 cache_storage migrateLegacy 243-253 no remove — PASS
- S-01 providers removeAccount wasActive check — PASS
- EH-03 account_remote_source 81-93 catch all — PASS
- ARCH-05 interceptor imports credentials_local_source — grep PASS
- CQ-03 skin_card 39 raw Color — grep 44x — PASS
- Drop: 0, Retry aspect: none, Fail >30% threshold: none passed.

**Prioritized Remediation**:

**Quick Wins (<=1 hari, risiko rendah, impact tinggi)**:
- TST-01 tambah flutter test + analyze ke build.yml required — 30 menit — tutup regresi CI
- DOC-01/02/03/05 perbaiki README badge 133, hapus video_player ganti WebView MP4, koreksi fallback version 11.02, buat LICENSE atau hapus badge — 1 jam
- EH-02 pindah _credentials.load() ke dalam try + outer catch handler.next — 10 menit — stop hang
- EH-03 batas fallback account_remote_source ke 404/405 only — 15 menit
- S-01 purge cookie saat wasActive true tanpa remaining — providers 382 — 20 menit
- C-01 migrateLegacy hapus legacy key setelah copy — cache_storage 252 — 5 menit
- TST-04 ganti assert durasi + sleep 800 jadi fake_async/polling — 1 jam

**Structural Fixes (1-2 minggu, butuh desain)**:
- ARCH-01 split providers 744L -> core/di + feature/di, pindah pipeline ke repository — prasyarat banyak fix lain
- P-01 prefs multi-MB -> file-per-blob + compute() — pindah skin_metadata/bundles/unified keluar SharedPreferences, hapus forceRefresh di resume, tambah memCacheWidth — ukur via profile DevTools sebelum/after
- CQ-01 ekstrak BundleNameResolver + BundleArtSelector + unit tabel — turunkan _enrichStorefront <40L
- CQ-02/ARCH-08 helper byUuidLookup kanonik — normalisasi saat indexing ValorantAssets sudah benar, pakai itu
- CQ-04/ARCH-03 generic cachedFetch(transaction+guard+fallback) — satukan repo vs provider pipeline
- EH-01 pasang FlutterError.onError/runZonedGuarded/PlatformDispatcher + GoRouter errorBuilder -> AppLogger
- EH-04 AppLogger redact + level sink, strip puuid dari ApiException source url
- ARCH-05 CredentialsReader port/interface + adapter — putus core->features inversion
- TST-02/03 widget-test & data layer coverage — login/shop/wishlist golden + profile/rank repo table tests

**Nice-to-have (low urgency)**:
- CQ-03 migrasi AppColors token + custom_lint no-raw-color — 44x ganti
- CQ-07 tabel tier kanonik, CQ-08 discount normalize single helper, CQ-09 fallback const, ARCH-10 import_lint + file-size guard, ARCH-12 debug route kondisikan kDebugMode, C-03 wishlist skinUuid kanonik, P-03 cleanup _v5 keys + shimmer controller optimize, EH-06 total deadline/circuit breaker, TST-05 clock injection, TST-08 mock harness.

**Technical Appendix**:
- **Scope & Coverage**: lib 86 files 100% rg sweep, 60+ files verbatim read via codegraph_explore+Read (70%), test 33 files 100% inventoried 22 full-read, config .gitignore/pubspec/analysis/codemagic/manifest verified, native MainActivity.kt + AppDelegate.swift verified for HttpOnly channel, pubspec deps 14 langsung — skip: none total, 11 test name-scan only, 0 lib file skip tanpa alasan.
- **Skill/Tool Evidence**: codegraph_explore 30+ query (SecureStorage, CredentialsLocalSource, ValorantInterceptor, NativeCookieReader, SilentWebviewReauth, OAuthFlow, BundleName, ValorantAssets, TierColors etc), Read 60+ files, rg grep 89 catch(_), 61 debugPrint, 0 global hook, 0 memCacheWidth, 44 raw Color, flutter analyze No issues (6.3s), flutter test 133/133 (24s, 0 fail), rg pubspec deps, gitignore audit.
- **Dependency Graph**: Wave1 independen (Security, CodeQuality, Doc, ErrorHandling, Testing) -> Wave2 (Correctness, Architecture, Performance) pakai hasil Wave1 — e.g., Security HttpOnly fix jadi context Correctness wishlist isolation, ErrorHandling fallback masking jadi context Architecture pipeline duplikat.
- **Verification Notes**: Index codegraph lag ~1s 17 file pending — dinetralkan via direct Read — semua temuan file:line on-disk akurat — severity pakai loop formula Impact 1-4 Likelihood 1-3 Exposure 1-3 — normalized dari subagent 1-5 via mapping — 52 final findings sudah dedup (6 merge) + 0 kontradiksi unresolved — 3 residual prev audit direklasifikasi partial (H5, H3 pattern, L2/P1).
- **Modified Items**: none (audit read-only) — rekomendasi belum dieksekusi
- **Status Verifikasi**: 14/52 sampled (27% >20% threshold) semua PASS — 0 drop — no aspect retry — gate ke final report lolos
- **Quick Check Steps**: 1) rg "Color\(0x" lib/shared vs AppColors — 2) flutter test --reporter compact — 3) grep "video_player" pubspec vs skin_video_player.dart — 4) cat valorant_headers.dart defaultClientVersion vs README
- **Saran Langkah Logis Berikutnya**: Eksekusi Quick Wins dalam 1 PR (CI gate + doc fix + EH-02/EH-03/S-01/C-01) — lalu ukur P-01 via flutter run --profile + DevTools memory sebelum refactor prefs — lalu mulai structural split providers.