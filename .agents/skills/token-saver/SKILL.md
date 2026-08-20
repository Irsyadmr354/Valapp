---
name: token-saver
description: Autonomous context window optimization, targeted code slicing, terminal output filtering, and anti-hallucination verification workflow using CodeGraph. Activate when handling massive codebases, long conversation histories, large terminal outputs, or verifying strict factual grounding.
---

# Token Saver (Context Fortress & Zero-Hallucination)

**Role**: Context Optimization & Grounded Verification Specialist.

This skill guides the agent to systematically eliminate token waste, prevent context window bloat, and eradicate hallucinations through strict symbol grounding, targeted code slicing, and zero-redundancy reading.

---

## Strict Quality Gates

1. **Gate 1 (Global Rules Sync)**: Terapkan Global Rules Section 6 & 8 untuk efisiensi token, pembatasan output, anti-halusinasi, dan protokol subagent.
2. **Gate 2 (Search Bounding & Generated Exclusion)**: Dilarang membaca file generated, build artifacts, dan lockfiles tanpa filter.
3. **Gate 3 (Tool & Output Throttling)**: Wajib `replace_file_content` untuk perubahan parsial, batasi terminal output dengan compact reporter dan PowerShell piping.

---

## Activation Triggers

- **WHEN**: Menangani codebase besar, turn percakapan panjang, eksekusi test/build dengan output log masif, atau memverifikasi manifest/simbol kode.
- **WHEN NOT**: Modifikasi satu baris sederhana pada file kecil yang sudah ada di context, atau task lookup trivial.
- **COMPOSABILITY**: Cross-cutting discipline yang beroperasi berdampingan dengan semua skill lain (feature-builder, autonomous-debugger, smart-refactor).

---

## Workflow Phases

### Phase 1: Search Bounding & Symbol-Targeted Retrieval
1. **Bounded Search**:
   - Selalu tentukan `SearchDirectory` spesifik (misal `lib/features/<target>`) dan gunakan `MaxDepth`. Hindari pencarian tanpa batas di root repository.
2. **Generated & Artifact Blacklist**:
   - Dilarang membaca manual file generated dan build artifacts lintas tech stack (`*.g.dart`, `*.freezed.dart`, `dist/`, `build/`, `*.min.js`, `*.bundle.js`, `target/`, lockfiles seperti `pubspec.lock`, `package-lock.json`, `pnpm-lock.yaml`, `yarn.lock`, `Cargo.lock`, `poetry.lock`).
3. **Precision Slicing & Cache Awareness**:
   - Gunakan CodeGraph untuk mengambil potongan simbol verbatim, atau tentukan `StartLine` dan `EndLine` pada file >100 baris.
   - Dilarang membaca ulang file yang isinya belum berubah dalam sesi percakapan yang sama.

### Phase 2: Anti-Hallucination & Manifest Invariants
1. **Manifest Grounding**:
   - Verifikasi dependensi langsung pada manifest (`pubspec.yaml`, `package.json`, `requirements.txt`, `Cargo.toml`) sebelum menulis import baru.
2. **Explicit Uncertainty**:
   - Jika signature fungsi atau API pihak ketiga belum pasti, lakukan pencarian simbol terarah atau nyatakan ketidakpastian. Dilarang mengarang parameter atau method.

### Phase 3: Minimal Diff & Editing Tool Priority
1. **Granular Editing**:
   - Wajib gunakan `replace_file_content` untuk seluruh modifikasi parsial (<80% dari total baris) guna meminimalkan output tokens.
   - Gunakan `write_to_file` hanya saat membuat file baru atau melakukan total rewrite.
2. **Zero Code Echoing**:
   - Jangan mencetak ulang blok kode utuh di pesan respons jika perubahannya sudah tercatat pada output diff tools.

### Phase 4: Output Throttling & Lean Subagent Isolation
1. **Terminal Log Throttling (PowerShell & Cross-Stack)**:
   - Jalankan test dengan mode compact/targeted (`flutter test --reporter compact`, `npm test -- --bail`, `pytest -q`).
   - Batasi command output dengan limit atau piping PowerShell (`git log -n <N>`, `Select-Object -First <N>`, `Get-Content -Tail <N>`).
2. **Lean Subagent Contracts**:
   - Kirimkan instruksi delegasi yang ultra-spesifik (hanya target file path, simbol yang dimodifikasi, dan kriteria acceptance) tanpa menyalin seluruh riwayat chat.
   - Subagent dilarang mengembalikan dump kode penuh; kembalikan ringkasan ringkas perubahan dan status verifikasi.
