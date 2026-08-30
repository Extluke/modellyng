# Modellyng

Modellyng adalah workspace riset lokal untuk mengubah PDF akademik menjadi
pengetahuan terstruktur yang dapat diverifikasi. Produk ini menjaga rantai:

```text
hasil AI -> kutipan evidence -> blok/halaman sumber -> PDF privat asli
```

AI tidak pernah dianggap final otomatis. Semua komponen harus tetap dapat
ditinjau manusia melalui tindakan Accept, Edit, Reject, atau re-analysis.

> Status snapshot: 30 Agustus 2026. Ini adalah MVP lokal yang sudah dapat
> didemonstrasikan end-to-end, tetapi **belum siap untuk deployment publik atau
> dipakai sebagai sumber sintesis final**. Dua defect integritas P1 yang
> ditemukan pada QA 23 Agustus sudah diperbaiki dan dilindungi regression test.
> Baca `docs/QA_REPORT_2026-08-23.md`, `docs/QA_REPORT_2026-08-25.md`, dan
> `docs/PROJECT_STATUS.md` sebelum mengubah Review, Matrix, Maps, Chat, atau
> Export.

## Baca ini dahulu jika Anda AI/coding agent baru

Repository ini adalah produk yang sudah berjalan, bukan proyek greenfield.
Sebelum mengubah kode:

1. Baca `AGENTS.md`.
2. Baca `docs/PROJECT_STATUS.md`.
3. Baca `docs/ARCHITECTURE.md`.
4. Baca `docs/CONTRIBUTING.md`.
5. Periksa branch aktif dan `git status`.
6. Audit file dan test yang terkait langsung dengan task.

Jangan mengganti Flutter, Riverpod, `go_router`, Dio, FastAPI, Celery, Redis,
Supabase, atau Gemini tanpa architecture decision yang disetujui tim. Jangan
menonaktifkan RLS, membuat bucket PDF publik, memasukkan service-role/Gemini
key ke Flutter, atau menganggap output AI sebagai kebenaran final.

Snapshot ini disusun dari branch `codex/visual-research-workflow`. Kondisi
working tree dapat berubah setelah handoff, jadi selalu jalankan `git status`
sendiri dan jangan menghapus atau menimpa perubahan lokal yang bukan bagian
task Anda.

## Arsitektur yang dikunci

| Lapisan | Implementasi | Tanggung jawab |
|---|---|---|
| Client | Flutter web/mobile | UI responsif dan interaksi pengguna |
| State/navigation | Riverpod + `go_router` | Session-aware state dan route guard |
| HTTP | Dio | Bearer-token API requests dan upload |
| Auth | Supabase Auth | Registrasi, login, session |
| Product API | Python FastAPI | Authorization boundary dan product data |
| Database/storage | Local Supabase | PostgreSQL, private Storage, RLS |
| Background job | Celery + Redis | Pemrosesan PDF dan Gemini di luar API process |
| PDF parsing | PyMuPDF | Teks per halaman dan metadata lokal |
| AI | Gemini via backend | Ekstraksi JSON 11 komponen akademik |
| PDF/evidence viewer | `pdfrx` + preview PyMuPDF | Menampilkan PDF privat atau preview halaman evidence ter-highlight setelah otorisasi |

Trust boundary:

```text
Flutter
  |-- Supabase langsung: authentication/session saja
  `-- FastAPI + JWT pengguna: seluruh product data
       |-- Supabase anon key + JWT: operasi owner-scoped/RLS
       `-- Celery worker
            |-- service-role key: operasi worker tepercaya
            `-- Gemini API key: ekstraksi backend-only
```

## Struktur repository yang relevan

```text
frontend/
  lib/main.dart
  lib/src/
    config/                 # URL lokal dan publishable client config
    data/                   # Dio/Supabase repositories + Riverpod providers
    models/                 # project, paper, status, stage
    routing/                # /welcome, /auth, /app + auth guard
    screens/                # dashboard, projects, review, matrix, maps, chat,
                            # result, dan account
    theme/ dan widgets/     # design tokens dan reusable widgets
  test/widget_test.dart

backend/
  app/main.py               # FastAPI routes dan exception mapping
  app/repository.py         # authenticated user/RLS data adapter
  app/processing_repository.py # worker-only service-role adapter
  app/tasks.py              # Celery PDF/Gemini pipeline + retry
  app/pdf_processing.py     # PyMuPDF extraction
  app/ai_extraction.py      # prompt/schema/evidence verification/fallback
  app/chat_service.py       # grounded project chat + citation validation
  app/evidence_preview.py   # highlighted private-page PNG preview
  app/structured_results.py # table derivation for structured paper results
  app/structured_pdf.py     # authenticated structured-table PDF generation
  app/schemas.py            # explicit API models dan status enums
  tests/

supabase/
  migrations/              # schema, indexes, triggers, RLS, private bucket
  config.toml               # local Supabase ports dan 50 MiB limit

docs/
  PROJECT_STATUS.md
  ARCHITECTURE.md
  CONTRIBUTING.md
  AI_HANDOFF_PROMPT.md
  QA_REPORT_2026-08-23.md
  QA_REPORT_2026-08-25.md
  decisions/                # accepted architecture decision records
```

`frontend/lib/src/screens/project_workspace_screen.dart` dan
`frontend/lib/src/data/demo_data.dart` adalah prototype berbasis data demo dan
tidak terhubung ke router aktif. Jangan menjadikannya bukti bahwa suatu fitur
sudah production-backed. Flow aktif masuk melalui `AppShell`.

## Status fitur: implementasi vs hasil QA

`Selesai implementasi` berarti UI/API/alur dasarnya sudah ada. Status tersebut
tidak otomatis berarti fitur bebas defect atau aman untuk data riset. Status QA
di bawah menggabungkan bukti browser, live API, dan regression test yang dirinci
di dua laporan QA serta `docs/PROJECT_STATUS.md`.

| Area | Implementasi | Status QA | Catatan nyata |
|---|---|---|---|
| Auth | Selesai | PASS | Register, login, logout, session guard Supabase |
| Project | Selesai | PASS | Create/list/open project dan dashboard owner-scoped |
| PDF upload | Selesai | PASS | Validasi ekstensi, signature, non-empty, maksimal 50 MB, private storage |
| PDF processing | Selesai | PASS dengan syarat | Celery worker wajib aktif; tanpa worker paper berhenti pada 0% |
| Gemini extraction | Selesai | PASS dengan fallback | Tepat 11 parameter; model primer sempat 503 dan fallback berhasil |
| Evidence verification | Selesai | PASS | Quote hanya disimpan bila cocok dengan blok pada halaman yang diklaim |
| Human Review Accept/Edit/Reject/Bulk Accept | Selesai | PASS | Alasan Reject wajib; “Terima semua” memakai konfirmasi, transaksi owner-scoped, dan audit trail |
| Re-analysis | Selesai | PASS | Riwayat lama dipertahankan; hasil job lengkap dipromosikan atomik sebagai satu versi aktif sehingga queue/progress tidak bercampur |
| Review history | Selesai terbatas | PASS | Read-only, maksimum 100 keputusan terbaru; akses dari Account belum langsung ke history |
| Structured Paper Result | Selesai | PASS | 11/11 nilai AI/final, tabel pertanyaan penelitian, tabel metodologi lima kolom, evidence, dan PDF tabel terautentikasi |
| Private Evidence PDF Viewer | Selesai | PASS dengan catatan | Viewer penuh tetap owner-scoped; citation chat memakai preview satu halaman ter-highlight dan jalur cepat terautentikasi |
| Comparative Paper Matrix | Selesai | PASS | Semua paper ready digabung dalam satu tabel responsif; hanya versi aktif `verified`/`edited` yang masuk |
| Concept/Evidence Map | Selesai | PASS | Rantai paper→concept→evidence memakai knowledge result aktif dan link PDF privat |
| Research Gap Map | Selesai | PASS | Flow paper→candidate→evidence→Yes/No→aksi berikutnya; keputusan owner-scoped tersimpan |
| Chatbot proyek | Selesai | PASS dengan ketergantungan provider | RAG memakai blok PDF owner-scoped, menolak pertanyaan tak ter-grounding, memvalidasi citation, dan memulihkan history permanen |
| Ekspor hasil | Selesai | PASS | DOCX/XLSX/CSV/PPTX valid; PDF tambahan tersedia untuk tabel pertanyaan/metodologi dan synthesis export hanya memakai data aktif terreview |
| Responsive UI | Selesai untuk flow aktif | PASS | Alur utama dipakai pada viewport mobile dan desktop tanpa overflow fatal |

Sebelas parameter ekstraksi:

```text
research_problem
research_objective
research_question
methodology
dataset_sample
variables_concepts
results_findings
contribution
limitations
future_work
key_claims
```

## Lifecycle dan status yang harus tetap konsisten

```text
upload PDF
  -> queued (0%)
  -> downloading (10%)
  -> extracting_text (45%)
  -> saving_blocks (80%)
  -> gemini_extraction (85%)
  -> retrying_gemini (85%, bila 429/503)
  -> saving_ai_results (95%)
  -> ai_extraction_complete (100%)
  -> paper/project needs_review
  -> 11 keputusan review manusia
  -> paper/project ready
```

Gemini memakai model utama `gemini-flash-latest` dan fallback
`gemini-flash-lite-latest`. Error sementara 429/503 menggunakan retry Celery
dengan backoff 15, 30, lalu 60 detik. Jika seluruh retry habis, job dan paper
menjadi `failed` dengan pesan yang dapat dibaca; UI tidak boleh tertinggal pada
0% tanpa akhir.

Worker memerlukan service-role key. API menolak membuat job baru bila key
tersebut kosong, sehingga salah konfigurasi tidak lagi menghasilkan paper
`processing` yang tidak dapat diselesaikan.

## Endpoint FastAPI yang aktif

Semua endpoint `/api/v1` berikut membutuhkan bearer token pengguna kecuali
health checks:

```text
GET  /health
GET  /health/dependencies

POST /api/v1/projects
GET  /api/v1/projects
GET  /api/v1/projects/{project_id}

POST /api/v1/projects/{project_id}/papers
POST /api/v1/projects/{project_id}/papers/upload
GET  /api/v1/projects/{project_id}/papers
POST /api/v1/projects/{project_id}/papers/{paper_id}/process
GET  /api/v1/projects/{project_id}/papers/{paper_id}/result
GET  /api/v1/projects/{project_id}/papers/{paper_id}/pdf
GET  /api/v1/projects/{project_id}/papers/{paper_id}/evidence/{block_id}/preview.png
GET  /api/v1/projects/{project_id}/papers/{paper_id}/structured-tables.pdf

GET  /api/v1/projects/{project_id}/comparative-matrix
GET  /api/v1/projects/{project_id}/concept-evidence-map
GET  /api/v1/projects/{project_id}/research-gap-map
GET  /api/v1/projects/{project_id}/research-gap-decisions
PUT  /api/v1/projects/{project_id}/research-gaps/{paper_id}/{parameter}/decision
POST /api/v1/projects/{project_id}/chat
GET  /api/v1/projects/{project_id}/chat/messages
GET  /api/v1/projects/{project_id}/export/{docx|xlsx|csv|pptx}

GET  /api/v1/reviews
GET  /api/v1/reviews/history
POST /api/v1/reviews/accept-all
POST /api/v1/reviews/{component_id}
```

FastAPI product operations selalu memakai JWT pengguna dan RLS. Hanya
`PdfProcessingRepository` di worker yang boleh memakai service-role key.

## Database dan privasi

Migration yang sudah ada membentuk:

- `profiles`
- `projects`
- `papers`
- `paper_blocks`
- `analysis_jobs`
- `extracted_components`
- `evidence_spans`
- `review_actions`
- `research_gap_decisions`
- `project_chat_messages`
- private bucket `private-papers`

RLS aktif untuk seluruh tabel product. Storage policy terbaru memverifikasi
folder pengguna sekaligus kepemilikan project. Ada unique active-job index per
paper dan relasi job/paper/project yang menjaga scope. Jangan mengedit migration
yang sudah diterapkan; perubahan schema berikutnya harus migration timestamped
baru.

## Cara menjalankan lokal

### 1. Redis

```powershell
docker compose up -d
docker compose ps
```

Redis tersedia di `127.0.0.1:6380`.

### 2. Supabase

```powershell
npx supabase start
npx supabase status
```

Local API: `http://127.0.0.1:54321`. Studio: `http://127.0.0.1:54323`.

### 3. Backend environment

Repository saat snapshot ini belum memiliki `backend/.env.example`. Buat
`backend/.env` secara lokal, lalu isi nilai berikut secara privat:

```dotenv
MODELLYNG_SUPABASE_URL=http://127.0.0.1:54321
MODELLYNG_SUPABASE_ANON_KEY=
MODELLYNG_SUPABASE_SERVICE_ROLE_KEY=
MODELLYNG_REDIS_URL=redis://localhost:6380/0
MODELLYNG_ALLOWED_ORIGINS=["http://localhost:3000","http://127.0.0.1:3000","http://localhost:8082","http://127.0.0.1:8082"]
GEMINI_API_KEY=
MODELLYNG_GEMINI_MODEL=gemini-flash-latest
MODELLYNG_GEMINI_FALLBACK_MODEL=gemini-flash-lite-latest
MODELLYNG_GEMINI_MAX_INPUT_CHARS=400000
MODELLYNG_GEMINI_CHAT_TIMEOUT_MS=12000
```

Jangan menaruh nilai key sebenarnya di README, Git, Flutter, test, screenshot,
atau log. `backend/.env` harus tetap ignored.

### 4. FastAPI

```powershell
cd backend
python -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install -r requirements.txt
python -m uvicorn app.main:app --reload --port 8000
```

API docs: `http://127.0.0.1:8000/docs`.

### 5. Celery worker

Buka terminal lain:

```powershell
cd backend
.\.venv\Scripts\Activate.ps1
python -m celery -A app.celery_app:celery_app worker --pool=solo --loglevel=INFO
```

Gunakan `--pool=solo` di Windows. Setelah `.env`, task, model, atau konfigurasi
worker berubah, restart Celery; worker tidak hot-reload.

### 6. Flutter web

```powershell
cd frontend
flutter pub get
flutter run -d web-server --web-port 3000
```

Buka `http://127.0.0.1:3000/#/app`. Port 8082 juga didukung bila origin backend
dan command Flutter memakai port tersebut.

`pdfrx` memerlukan Windows Developer Mode untuk symlink plugin pada target
desktop. Build web tidak bergantung pada konfigurasi tersebut.

## Verifikasi terakhir

Baseline terakhir yang benar-benar dijalankan:

- Backend: **62 tests passed**.
- Flutter: **static analysis clean**.
- Flutter: **19 widget tests passed**.
- Flutter web release: **build succeeded**.
- Redis dan local Supabase: healthy.
- Runtime recovery test: dua PDF masing-masing menghasilkan 11 komponen dan
  berpindah ke `needs_review`.
- Manual browser QA nyata pada iterasi 2026-08-23: login, membuat project,
  mengunggah dua PDF, menunggu worker/Gemini, Structured Result, viewer PDF,
  Accept/Edit/Reject/re-analysis, history, Matrix, kedua Maps, empat format
  export, search/filter, Account/privacy, logout, serta layout mobile/desktop.
- Project QA: `243ba792-bd27-43ba-926b-45a19ae7b0cb`; detail langkah, bukti,
  defect, dan kondisi akhir ada di `docs/QA_REPORT_2026-08-23.md`.
- Authenticated live smoke pada 2026-08-25: login akun QA, tabel terstruktur,
  Matrix gabungan dengan status aktif terreview, flow gap No→Yes, chatbot
  evidence-linked, dan PDF 2 halaman. Detail ada di
  `docs/QA_REPORT_2026-08-25.md`.
- Regression 2026-08-30 mencakup grounded-chat refusal, citation guards,
  penyimpanan history chat owner-scoped, preview evidence satu halaman, dan
  validasi transaksional “Terima semua”.

Perintah wajib sebelum handoff:

```powershell
cd backend
python -m pytest

cd ..\frontend
flutter analyze
flutter test
flutter build web --release
```

Untuk perubahan authorization, tambahkan test isolasi Account A/Account B.
Untuk perubahan web, uji flow yang berubah pada lebar mobile dan desktop.

## Known issues dan keterbatasan nyata

1. **P2 — Kuota masih presentasional.** Setelah dua PDF diproses, Dashboard dan
   Account tetap menampilkan `0 / 5 paper hari ini`.
2. **P3 — Initial render PDF penuh pada mobile dapat lambat.** Jalur citation
   chat sudah memakai preview satu halaman dan cache byte berbatas waktu, tetapi
   viewer dokumen penuh masih dapat menampilkan “Menyiapkan PDF privat…” selama
   15–20 detik tanpa persentase atau timeout.
3. **P3 — Audit log sulit ditemukan pada antrean panjang.** Aksi Account hanya
   membuka halaman Review; pengguna tetap harus menggulir ke expansion history.
4. Hanya PDF dengan searchable text yang didukung. Scanned/image-only PDF belum
   memiliki OCR.
5. Citation chat mencoba menyorot kutipan pada preview/halaman sumber dan tetap
   jujur bila pencocokan teks gagal. Evidence non-chat masih mengutamakan
   navigasi halaman; bounding-box presisi lintas semua jalur belum tersedia.
6. Gemini masih dapat mengalami quota/high demand. Ekstraksi memakai retry dan
   fallback terikat; chat memakai dua percobaan singkat dengan timeout dan gagal
   secara eksplisit, tetapi provider eksternal tetap tidak dapat dijamin.
7. Project Overview melakukan polling hanya ketika job yang sedang tersimpan
   masih `queued/processing`. Bila status database diubah dari luar flow UI
   (misalnya manual recovery), kartu dapat stale sampai provider di-invalidasi,
   halaman dibuka ulang, atau browser direload.
8. Review history read-only dan hanya 100 keputusan terbaru; belum ada pagination.
9. Belum ada filter Review berdasarkan parameter/status. Bulk accept
   terkonfirmasi sudah tersedia untuk filter proyek yang sedang terlihat.
10. Comparative Matrix dan maps hanya memakai paper `ready`; paper yang masih
    `needs_review` sengaja tidak ikut.
11. Concept Map belum melakukan semantic merging untuk konsep ekuivalen dengan
    wording berbeda antar-paper.
12. Research Gap Map bukan generator kesimpulan lintas-paper. Fitur ini hanya
    menampilkan `verified`/`edited` limitations/future work sebagai kandidat
    yang harus divalidasi manusia; bukan kesimpulan otomatis.
13. `ProjectWorkspaceScreen`/`DemoData` adalah prototype mati yang belum
    dipisahkan atau dihapus dari source.
14. Belum ada production domain, HTTPS deployment, monitoring, backups,
    retention/deletion workflow, atau production privacy operations.
15. `backend/.env.example` belum tersedia; onboarding environment masih harus
    mengikuti daftar variabel di README ini tanpa menyalin nilai secret.

## Yang belum dikerjakan / backlog berikutnya

Urutan yang disarankan:

1. Ulangi direct browser QA visual workflow 2026-08-25 ketika tersedia tab
   browser segar yang dapat dikontrol; runtime browser saat implementasi terkunci
   pada URL error internal dan menolak navigasi sesuai security policy.
2. Perbaiki refresh terminal-state Project Overview agar manual/external retry
   tidak meninggalkan kartu stale; tambahkan regression test latest-job/history.
3. Review UX lanjutan: parameter/status filters dan paginated history.
4. Hubungkan plan/quota UI ke usage backend atau tandai jelas sebagai belum aktif.
5. Perbaiki PDF render feedback/timeout dan deep-link Audit log.
6. Human-curated synthesis lintas kandidat gap yang sudah dipilih; jangan
   otomatis menjadikannya final.
7. OCR untuk scanned PDF beserta review kualitas OCR.
8. Bounding-box presisi untuk evidence non-chat dan fallback highlight yang
   lebih informatif ketika kutipan tidak cocok persis.
9. Production hardening: HTTPS, secret management, rate limiting, monitoring,
    backup/restore, deletion/retention policy, dan privacy review.
10. Hapus atau isolasi prototype `ProjectWorkspaceScreen` dan `DemoData` setelah
    memastikan tidak ada desain yang masih ingin dipertahankan.
11. Tambahkan `backend/.env.example` tanpa nilai secret dan validasi startup
    dependency yang lebih eksplisit untuk onboarding developer baru.

## Checklist handoff untuk AI berikutnya

- Jangan menganggap screenshot/demo data sebagai database-backed behavior.
- Synthesis view wajib tetap memakai satu versi aktif dan hanya status
  `verified`/`edited`; jangan menghapus filter tersebut saat refactor.
- Baca `docs/QA_REPORT_2026-08-23.md` untuk defect asal dan
  `docs/QA_REPORT_2026-08-25.md` untuk bukti perbaikan serta visual workflow.
- Jangan mengubah applied migrations; buat migration baru.
- Jangan mematikan RLS untuk menyelesaikan authorization bug.
- Jangan memakai service-role key dari Flutter.
- Jangan menghapus AI value lama ketika reviewer mengedit hasil.
- Jangan menyimpan evidence yang tidak cocok dengan source block/page.
- Saat status berubah, audit konsistensi project, paper, analysis job,
  extracted component, dashboard, Review, Matrix, dan Maps.
- Preserve perubahan working tree yang bukan milik task Anda.
- Laporkan changed files, test evidence, env/migration steps, limitation, dan
  pekerjaan yang masih membutuhkan keputusan manusia.

Dokumen status detail ada di `docs/PROJECT_STATUS.md`; kontrak teknis ada di
`docs/ARCHITECTURE.md`; workflow tim ada di `docs/CONTRIBUTING.md`.
