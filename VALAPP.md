# PROMPT: Hunting Bug Tersembunyi via Sinyal Kualitas Kode — Valapp

## Konteks
Audit-audit sebelumnya di project ini (fungsional, race condition, dead code, konsistensi arsitektur) sudah beberapa ronde dan hasilnya bagus. Sesi ini beda pendekatan: **bukan** cari bug dengan menyusuri call graph satu-satu, tapi cari bug dengan **membaca kualitas kode sebagai sinyal**. Intuisinya: tempat-tempat di mana kode "berbau" (code smell) — duplikasi yang mestinya satu sumber tapi jadi dua, magic value yang gampang typo, penanganan error yang tidak konsisten antar file yang mirip, abstraksi yang bocor, nama yang menyesatkan — adalah tempat yang secara statistik paling sering menyembunyikan bug nyata, bahkan kalau tidak ada satupun test/linter yang bunyi.

**Prinsip kerja:** kualitas kode yang buruk BUKAN tujuan pelaporan itu sendiri (ini bukan audit gaya/style). Code smell di sini dipakai murni sebagai **radar** untuk menemukan lokasi yang layak diperiksa lebih dalam untuk bug fungsional konkret. Kalau suatu smell ternyata tidak menyembunyikan bug apapun (misal duplikasi yang sengaja dan aman), laporkan sebagai "smell tanpa bug" secara singkat, jangan dipaksakan jadi temuan.

---

## ATURAN CAKUPAN — WAJIB DIBACA DULU, INI BUKAN OPSIONAL

**Ini adalah instruksi paling penting di seluruh prompt ini. Pelanggaran terhadap aturan ini membuat seluruh audit tidak valid, terlepas seberapa bagus temuan yang dilaporkan.**

1. **Setiap file `.dart` di `lib/` harus dibuka dan dibaca sampai baris terakhir (EOF), tanpa terkecuali.** Tidak ada file yang "kelihatannya aman" boleh dilewati hanya berdasarkan nama file, ukuran file, atau kesan dari audit sebelumnya. File yang sudah pernah dibaca di sesi audit lain **tetap harus dibaca ulang penuh di sesi ini** — sesi ini punya sudut pandang berbeda (code smell, bukan bug fungsional), jadi bacaan sebelumnya tidak menggugurkan kewajiban baca ulang.
2. **Dilarang keras** membaca file hanya lewat `grep`/`view_range` sepotong-sepotong sebagai pengganti baca penuh. Grep boleh dipakai untuk **mencari kandidat lokasi** (misal cari semua kemunculan pola tertentu), tapi begitu ada kandidat, file yang bersangkutan **wajib dibuka utuh dari baris 1 sampai baris terakhir** untuk memastikan konteks penuh tidak terlewat — smell sering baru kelihatan kalau dibandingkan dengan bagian lain file yang sama yang tidak ikut ke-grep.
3. **Sebelum menulis laporan akhir, wajib menunjukkan bukti cakupan**: buat daftar centang (checklist) semua file di `lib/` di awal sesi kerja, dan tandai satu per satu begitu selesai dibaca sampai EOF. Laporan akhir HARUS menyertakan checklist ini dalam keadaan lengkap (semua tercentang), atau — kalau memang ada file yang sengaja dilewati karena alasan tertentu (misal file generated/auto-generated) — jelaskan eksplisit alasannya per file, bukan diam-diam dilewati.
4. **File besar (>300 baris) tidak boleh cuma dibaca bagian awal/akhir.** Kalau satu kali panggilan `view` terpotong/truncated di tengah karena batas panjang, WAJIB lanjutkan membaca sisa file dengan `view_range` sampai baris terakhir benar-benar terlihat — jangan berhenti di potongan pertama dan berasumsi sisanya "kemungkinan sama".
5. **Setelah membaca satu file sampai EOF, sebelum pindah ke file berikutnya**, jawab pertanyaan berikut secara implisit lewat proses kerja (tidak perlu ditulis untuk setiap file di laporan akhir, tapi harus benar-benar dilakukan): apakah ada bagian dari file ini yang terlewat scan mata karena panjang/membosankan/terlihat generic? Kalau ragu, baca ulang bagian itu sekali lagi sebelum lanjut.
6. **Definisi "selesai"**: sesi ini baru boleh dianggap selesai kalau (a) checklist semua file tercentang, DAN (b) setiap kategori smell (1-7 di bawah) sudah benar-benar diperiksa lintas SEMUA file yang relevan, bukan cuma sample beberapa file yang paling mencolok.

Kalau di tengah proses ternyata jumlah file terlalu banyak untuk diselesaikan dalam satu sesi respons, **jangan memotong cakupan diam-diam** — laporkan progres apa adanya (file mana saja yang sudah tercentang, mana yang belum) dan tanyakan apakah lanjut di sesi berikutnya atau dipersempit scope-nya secara eksplisit oleh developer. Cakupan parsial yang dilaporkan sebagai "selesai" adalah pelanggaran paling serius terhadap prompt ini.

---

## CHECKLIST FILE WAJIB (83 file, `lib/` per 2026-08-16)

Salin persis checklist ini ke laporan akhir dan centang satu per satu. **Jangan generate ulang daftar ini dari `find`/`ls` sendiri** — pakai daftar berikut apa adanya sebagai sumber kebenaran, supaya tidak ada file baru/lama yang keliru masuk-keluar cakupan tanpa sadar. Kalau ternyata ada file baru di repo yang tidak ada di daftar ini (karena repo berubah sejak prompt ini dibuat), tambahkan ke checklist secara eksplisit dan sebutkan di laporan bahwa daftar ini di-update.

- [ ] `lib/app.dart`
- [ ] `lib/core/di/providers.dart`
- [ ] `lib/core/exceptions/api_exception.dart`
- [ ] `lib/core/exceptions/auth_exception.dart`
- [ ] `lib/core/navigation/navigator_key.dart`
- [ ] `lib/core/network/api_dio.dart`
- [ ] `lib/core/network/api_response_decoder.dart`
- [ ] `lib/core/network/auth_dio.dart`
- [ ] `lib/core/network/cookie_service.dart`
- [ ] `lib/core/network/interceptors/rate_limit_interceptor.dart`
- [ ] `lib/core/network/interceptors/retry_interceptor.dart`
- [ ] `lib/core/network/interceptors/valorant_interceptor.dart`
- [ ] `lib/core/network/valorant_headers.dart`
- [ ] `lib/core/services/background_service.dart`
- [ ] `lib/core/services/notification_service.dart`
- [ ] `lib/core/storage/cache_storage.dart`
- [ ] `lib/core/storage/cached_fetch_result.dart`
- [ ] `lib/core/storage/secure_storage.dart`
- [ ] `lib/core/utils/async_lock.dart`
- [ ] `lib/features/auth/data/auth_remote_source.dart`
- [ ] `lib/features/auth/data/credentials_local_source.dart`
- [ ] `lib/features/auth/data/oauth_flow.dart`
- [ ] `lib/features/auth/data/silent_webview_reauth.dart`
- [ ] `lib/features/auth/domain/auth_repository.dart`
- [ ] `lib/features/auth/domain/models/credentials.dart`
- [ ] `lib/features/auth/presentation/account_switcher_modal.dart`
- [ ] `lib/features/auth/presentation/login_screen.dart`
- [ ] `lib/features/auth/presentation/webview_login_screen.dart`
- [ ] `lib/features/contracts/data/contracts_local_cache.dart`
- [ ] `lib/features/contracts/data/contracts_remote_source.dart`
- [ ] `lib/features/contracts/domain/models/contracts.dart`
- [ ] `lib/features/contracts/presentation/battlepass_carousel_modal.dart`
- [ ] `lib/features/contracts/presentation/contracts_screen.dart`
- [ ] `lib/features/debug/presentation/notification_debug_screen.dart`
- [ ] `lib/features/loadout/data/loadout_local_cache.dart`
- [ ] `lib/features/loadout/data/loadout_remote_source.dart`
- [ ] `lib/features/loadout/domain/models/player_loadout.dart`
- [ ] `lib/features/loadout/presentation/loadout_screen.dart`
- [ ] `lib/features/match/data/match_local_cache.dart`
- [ ] `lib/features/match/data/match_remote_source.dart`
- [ ] `lib/features/match/domain/models/match_details.dart`
- [ ] `lib/features/match/domain/models/match_history.dart`
- [ ] `lib/features/match/presentation/match_detail_screen.dart`
- [ ] `lib/features/match/presentation/match_history_screen.dart`
- [ ] `lib/features/news/data/news_remote_source.dart`
- [ ] `lib/features/news/domain/models/news_article.dart`
- [ ] `lib/features/profile/data/account_local_cache.dart`
- [ ] `lib/features/profile/data/account_remote_source.dart`
- [ ] `lib/features/profile/data/restrictions_remote_source.dart`
- [ ] `lib/features/profile/domain/models/account_health.dart`
- [ ] `lib/features/profile/domain/models/account_xp.dart`
- [ ] `lib/features/profile/presentation/account_health_modal.dart`
- [ ] `lib/features/profile/presentation/profile_screen.dart`
- [ ] `lib/features/rank/data/mmr_local_cache.dart`
- [ ] `lib/features/rank/data/mmr_remote_source.dart`
- [ ] `lib/features/rank/domain/models/player_mmr.dart`
- [ ] `lib/features/rank/presentation/rank_screen.dart`
- [ ] `lib/features/shop/data/store_local_cache.dart`
- [ ] `lib/features/shop/data/store_remote_source.dart`
- [ ] `lib/features/shop/domain/models/skin_offer.dart`
- [ ] `lib/features/shop/domain/models/storefront.dart`
- [ ] `lib/features/shop/domain/models/wallet.dart`
- [ ] `lib/features/shop/domain/store_repository.dart`
- [ ] `lib/features/shop/presentation/bundle_detail_modal.dart`
- [ ] `lib/features/shop/presentation/home_screen.dart`
- [ ] `lib/features/shop/presentation/skin_detail_modal.dart`
- [ ] `lib/features/shop/presentation/skin_video_player.dart`
- [ ] `lib/features/shop/presentation/wishlist_catalog_screen.dart`
- [ ] `lib/features/shop/presentation/wishlist_provider.dart`
- [ ] `lib/main.dart`
- [ ] `lib/shared/utils/app_colors.dart`
- [ ] `lib/shared/utils/display_name_util.dart`
- [ ] `lib/shared/utils/price_utils.dart`
- [ ] `lib/shared/utils/tier_colors.dart`
- [ ] `lib/shared/utils/tier_name_util.dart`
- [ ] `lib/shared/utils/valorant_assets.dart`
- [ ] `lib/shared/utils/version_service.dart`
- [ ] `lib/shared/widgets/cache_data_banner.dart`
- [ ] `lib/shared/widgets/countdown_timer.dart`
- [ ] `lib/shared/widgets/loading_shimmer.dart`
- [ ] `lib/shared/widgets/skin_card.dart`
- [ ] `lib/shared/widgets/valorant_error_display.dart`
- [ ] `lib/shared/widgets/valorant_icons.dart`

**Total: 83 file. Laporan akhir tidak sah kalau jumlah file tercentang di section 1 laporan kurang dari 83 (kecuali ada file yang sudah dijelaskan alasan eksklusinya secara eksplisit).**

---

## Kategori Smell yang Harus Diburu (dengan alasan kenapa tiap kategori sering nyimpen bug)

### 1. Duplikasi Logic yang Berpotensi Divergen
Bukan duplikasi UI/widget (itu sudah dicek di audit sebelumnya) — fokus ke **duplikasi logic bisnis**: perhitungan, validasi, parsing, kondisi boundary, mapping status/enum.

Kenapa ini sering nyimpen bug: begitu ada 2 tempat yang menghitung hal yang sama dengan cara terpisah (bukan lewat 1 fungsi bersama), risiko keduanya diam-diam **berbeda** makin lama makin besar — satu diupdate pas ada fix, satunya lupa. Bug jenis ini nggak akan pernah ketahuan dari membaca satu tempat saja, harus dibandingkan.

**Cara mencari:**
- Grep pattern matematis yang mirip (pembagian, perkalian, modulo, `.clamp(`, format tanggal, kalkulasi persentase/RR/XP/harga) di file berbeda, lalu bandingkan literal per literal — apakah rumus, konstanta, dan urutan operasinya PERSIS sama.
- Grep kondisi if/else yang menentukan kategori sesuatu (tier skin, status akun, tipe kontrak, dsb) — kalau logic pengelompokan yang sama muncul di >1 tempat dengan urutan kondisi/fallback yang beda, itu red flag.
- Cek apakah ada helper/util function yang sebenarnya sudah ada (`price_utils.dart`, `tier_colors.dart`, dsb) tapi salah satu tempat malah re-implement manual alih-alih pakai itu — itu tanda kuat drift sudah/akan terjadi.

### 2. Magic Number & Magic String yang Rawan Salah Ketik
Kenapa ini sering nyimpen bug: angka/string yang di-hardcode berulang kali (bukan lewat konstanta bernama) itu gampang salah ketik di SALAH SATU tempat tanpa ketahuan — compiler nggak akan protes, cuma nanti perilakunya beda tipis dari yang lain.

**Cara mencari:**
- Cari angka "ajaib" yang dipakai berulang untuk hal yang sama (durasi timeout, threshold near-expiry, batas index, nilai maksimum XP/RR, dsb) — pastikan SEMUA kemunculannya konsisten nilainya. Kalau ada satu yang beda (misal satu tempat pakai `300` detik, tempat lain pakai `5 * 60`), verifikasi apakah itu memang disengaja beda atau salah ketik/inkonsistensi.
- Cari string key (nama field JSON, key SecureStorage/CacheStorage, nama route) yang di-hardcode langsung sebagai literal alih-alih lewat konstanta — walau cuma dipakai sekali, ini risiko kalau nanti ada yang nambah pemakaian kedua dan salah ketik.
- Perhatikan khusus: angka yang berkaitan dengan **waktu** (durasi cache TTL, cooldown, timeout, threshold expiry) — ini kategori paling rawan salah ketik unit (detik vs milidetik vs menit) dan paling susah ketahuan dari testing biasa karena baru kelihatan efeknya setelah durasi tertentu berlalu.

### 3. Error Handling yang Tidak Konsisten Antar Kode yang Mirip
Kenapa ini sering nyimpen bug: kalau ada 5 tempat yang secara struktural mirip (misal 5 provider yang fetch-lalu-cache data user, atau 5 fromJson parser) tapi caranya menangani error BEDA-BEDA tanpa alasan jelas, salah satu dari mereka kemungkinan besar adalah yang "lupa di-update" saat pola penanganan errornya diperbaiki di tempat lain — atau sebaliknya, salah satu adalah yang jadi kasus khusus tapi nggak terdokumentasi kenapa.

**Cara mencari:**
- Kumpulkan SEMUA file yang punya struktur serupa (misal semua `*_local_cache.dart`, semua provider yang fetch dari Riot API, semua `fromJson` model parser) dan bandingkan baris-per-baris caranya handle exception: apakah semua catch block sama luasnya (catch spesifik vs catch generik), apakah semua fallback ke cache dengan cara yang sama, apakah semua melempar ulang jenis exception yang konsisten.
- Cari tempat yang punya `catch (e)` generik BERDAMPINGAN dengan tempat lain yang serupa fungsinya tapi pakai `on SpecificException catch (e)` — itu kandidat kuat untuk exception yang salah ditangani (baik terlalu luas atau terlalu sempit).
- Perhatikan tempat yang secara diam-diam "menelan" error (return default/null tanpa log atau tanpa propagate) VS tempat serupa yang mempertahankan/report error — kalau nggak ada alasan jelas kenapa beda, salah satu kemungkinan bug.

### 4. Parameter/Flag yang Di-declare Tapi Tidak Konsisten Dipakai
Kenapa ini sering nyimpen bug: parameter/callback yang di-pass ke suatu function/widget tapi ternyata tidak semua caller memakainya dengan cara yang sama (atau tidak dipakai sama sekali di beberapa tempat) itu tanda ada asumsi yang berubah di tengah jalan pengembangan tapi nggak semua tempat ikut di-update.

**Cara mencari:**
- Untuk tiap widget/function reusable yang punya parameter opsional (`bool`, `Callback?`, dsb), cek SEMUA call site — apakah semuanya memberi nilai yang konsisten secara logis, atau ada yang ngasih `true`/`false`/`null` yang kelihatannya "sembarang"/tidak dipikirkan?
- Cari parameter yang di-declare di constructor tapi ternyata cuma dipakai sebagian dari method dalam class yang sama — itu tanda parameter tersebut mungkin harusnya mempengaruhi lebih banyak behavior daripada yang sekarang, atau ada method yang lupa diupdate saat parameter itu ditambahkan.

### 5. Penamaan yang Menyesatkan (Misleading Names)
Kenapa ini sering nyimpen bug: nama variabel/fungsi yang tidak lagi mencerminkan apa yang benar-benar dia lakukan (biasanya karena fungsi itu direfactor/diperluas scope-nya tapi namanya nggak ikut diubah) bikin pembaca lain — termasuk kamu sendiri 2 bulan kemudian — salah asumsi soal efek sampingnya, dan itu tempat paling gampang muncul bug regresi berikutnya.

**Cara mencari:**
- Untuk tiap fungsi bernama `getX`/`loadX`/`fetchX`, cek isi fungsinya — apakah dia BENAR-BENAR cuma baca data (tidak ada efek samping seperti write/mutate state), atau ternyata ada side-effect tersembunyi (menulis cache, mengubah state global, memicu network call) yang tidak tercermin dari nama "get/load"-nya.
- Untuk fungsi bernama `validateX`/`checkX`/`isX`, pastikan dia benar-benar cuma mengembalikan hasil pengecekan (bukan sekaligus melakukan aksi/mutasi).
- Untuk boolean flag/variable, pastikan nama dan makna sebenarnya konsisten (misal `isLoading` yang ternyata juga `true` di kondisi lain yang bukan loading).

### 6. Kompleksitas Kondisional Tinggi (Nested If / Long Boolean Expression)
Kenapa ini sering nyimpen bug: makin banyak nested if-else atau boolean expression panjang (`&&`/`||` berantai) di satu tempat, makin besar kemungkinan salah satu kombinasi kondisi tidak pernah dites/dipikirkan pembuatnya — terutama kombinasi yang jarang terjadi di real-world tapi valid secara teori (edge case gabungan).

**Cara mencari:**
- Temukan fungsi dengan nested-if lebih dari 3 level atau boolean expression dengan lebih dari 3 operator logika berantai.
- Untuk tiap yang ditemukan, coba secara manual susun **tabel kombinasi** semua variabel boolean yang terlibat, lalu telusuri: apakah SEMUA baris tabel itu menghasilkan perilaku yang masuk akal? Fokus khusus ke kombinasi yang terlihat "tidak biasa" atau "harusnya nggak akan pernah kejadian" — sering kali justru itu yang belum ditangani dengan benar.

### 7. Copy-Paste Fingerprint (Komentar/Nama Variabel yang "Ketinggalan")
Kenapa ini sering nyimpen bug: kalau ada blok kode yang jelas hasil copy-paste dari tempat lain (komentar yang menyebut konteks berbeda, nama variabel yang tidak cocok sama fungsinya, TODO yang menyebut fitur lain), itu sinyal kuat bug "lupa disesuaikan" — bagian yang seharusnya diubah pas paste tapi terlewat.

**Cara mencari:**
- Grep semua komentar (`//`) dan cocokkan isi komentar dengan kode di bawahnya — apakah komentar itu benar-benar menjelaskan kode yang ada, atau menyebut sesuatu yang tidak relevan (bekas hasil copy dari tempat lain).
- Perhatikan penamaan variabel yang generic banget (`temp`, `data2`, `result_`) yang biasanya muncul saat seseorang copy kode terus nambahin variabel baru buru-buru.

---

## Format Pelaporan per Temuan

Untuk SETIAP temuan, WAJIB isi struktur ini (jangan cuma bilang "kode ini bau"):

1. **Smell yang terdeteksi** — kategori dari daftar di atas + lokasi (`file:line`).
2. **Kenapa ini smell** — 1-2 kalimat kenapa pola ini secara umum berisiko.
3. **Verifikasi konkret** — WAJIB, ini bagian terpenting: telusuri smell ini sampai ketemu **bug nyata atau bukti bahwa itu aman**. Tidak boleh berhenti di "kelihatannya berisiko" — harus dibuktikan dengan membaca actual behavior-nya (trace ke pemanggil, bandingkan dengan implementasi serupa, atau jelaskan skenario eksekusi konkret kalau memang ada bug).
4. **Hasil:**
   - **BUG DIKONFIRMASI** — kalau smell itu memang menyembunyikan bug nyata. Sertakan skenario eksekusi konkret + before/after fix.
   - **SMELL TANPA BUG** — kalau setelah ditelusuri ternyata aman/disengaja. Jelaskan singkat kenapa aman (jangan dihapus dari laporan — ini tetap informasi berguna supaya tidak dicek ulang di masa depan).
   - **PERLU KEPUTUSAN MANUAL** — kalau ambigu (butuh konteks bisnis yang cuma developer yang tahu).

## Prioritas
Untuk temuan **BUG DIKONFIRMASI**, prioritaskan dengan skema yang sama seperti audit sebelumnya: **Critical (data corruption/crash/security) → High (logic salah tapi tidak crash) → Medium → Low**.

## Yang TIDAK termasuk scope sesi ini
- Jangan ulang temuan yang sudah dilaporkan di audit-audit sebelumnya (dead code, race condition di `AsyncLock`/`CacheStorage`/interceptor — itu semua sudah clean, tidak perlu dicek ulang kecuali smell baru mengarah ke tempat yang sama dengan sudut pandang berbeda).
- Jangan laporkan smell murni gaya penulisan (formatting, penamaan yang cuma "kurang idiomatic" tapi tidak menyesatkan, dsb) — HANYA laporkan smell yang punya jalur konkret ke potensi bug.
- Jangan ubah kode apapun di sesi ini — audit dulu, laporkan, baru nanti fix terpisah setelah saya review.

## Output akhir
Laporan markdown dengan struktur:
1. **Checklist cakupan file** — daftar LENGKAP semua file `.dart` di `lib/` dengan tanda selesai-dibaca-sampai-EOF untuk masing-masing. Ini section PERTAMA di laporan, bukan lampiran di akhir. Kalau ada file yang dilewati, alasan eksplisit wajib ditulis di baris yang sama dengan file tersebut.
2. Ringkasan eksekutif (jumlah temuan per kategori smell, jumlah yang jadi bug dikonfirmasi vs smell-tanpa-bug).
3. Temuan per kategori (1-7 di atas), diurutkan prioritas bug di dalamnya.
4. Lampiran: daftar smell-tanpa-bug (supaya tidak dicek ulang lain kali).

## Definisi Selesai (Definition of Done) — cek ulang sebelum mengirim laporan final
Sebelum menyatakan audit ini selesai, jawab jujur untuk diri sendiri:
- [ ] Apakah SEMUA file di checklist section 1 benar-benar sudah kubuka dan kubaca sampai baris terakhir (bukan cuma di-grep)?
- [ ] Untuk file yang panjangnya di atas satu layar tampilan tool, apakah aku benar-benar melanjutkan baca sampai baris terakhir, bukan berhenti di potongan awal?
- [ ] Untuk tiap dari 7 kategori smell, apakah aku sudah menyisir SEMUA file yang relevan untuk kategori itu, bukan cuma file yang paling mencolok/gampang ditemukan?
- [ ] Apakah setiap temuan yang kutulis sebagai "BUG DIKONFIRMASI" benar-benar sudah kuverifikasi dengan membaca actual behavior-nya, bukan dugaan dari nama fungsi/variabel saja?

Kalau ada satu saja jawaban "tidak" atau "belum yakin", audit belum selesai — lanjutkan dulu sebelum mengirim laporan final.