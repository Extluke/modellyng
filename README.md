# Modellyng

Modellyng adalah workspace riset lokal untuk mengubah PDF akademik menjadi
pengetahuan terstruktur yang dapat diverifikasi. Produk ini menjaga rantai:

```text
hasil AI -> kutipan evidence -> blok/halaman sumber -> PDF privat asli
```

AI tidak pernah dianggap final otomatis. Semua komponen harus tetap dapat
ditinjau manusia melalui tindakan Accept, Edit, Reject, atau re-analysis.

> Status snapshot: 22 Agustus 2026. Ini adalah MVP lokal yang sudah dapat
> didemonstrasikan end-to-end, tetapi belum siap untuk deployment publik.

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

Working tree saat snapshot ini berada di branch `codex/review-reanalysis` dan
memiliki banyak perubahan fitur yang belum di-commit. Selalu jalankan
`git status` sendiri; jangan menghapus atau menimpa perubahan lokal tersebut.

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
| PDF viewer | `pdfrx` | Menampilkan byte PDF privat yang sudah diotorisasi |

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
    screens/                # dashboard, projects, review, matrix, maps, account
    theme/ dan widgets/     # design tokens dan reusable widgets
  test/widget_test.dart

backend/
  app/main.py               # FastAPI routes dan exception mapping
  app/repository.py         # authenticated user/RLS data adapter
  app/processing_repository.py # worker-only service-role adapter
  app/tasks.py              # Celery PDF/Gemini pipeline + retry
  app/pdf_processing.py     # PyMuPDF extraction
  app/ai_extraction.py      # prompt/schema/evidence verification/fallback
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
```

`frontend/lib/src/screens/project_workspace_screen.dart` dan
`frontend/lib/src/data/demo_data.dart` adalah prototype berbasis data demo dan
tidak terhubung ke router aktif. Jangan menjadikannya bukti bahwa suatu fitur
sudah production-backed. Flow aktif masuk melalui `AppShell`.

## Fitur yang sudah selesai dan aktif

| Area | Status | Implementasi nyata |
|---|---|---|
| Auth | Selesai | Register, login, logout, session guard Supabase |
| Project | Selesai | Create/list/open project, dashboard totals owner-scoped |
| PDF upload | Selesai | Validasi ekstensi, signature, non-empty, maksimal 50 MB, private storage |
| PDF processing | Selesai | Celery/Redis, private download, PyMuPDF, page count, metadata, language |
| Gemini extraction | Selesai | Tepat 11 parameter, structured schema, primary + fallback Flash model |
| Evidence verification | Selesai | Quote hanya disimpan bila ditemukan di blok pada halaman yang diklaim |
| Human Review | Selesai | Accept/Edit/Reject, grouped by paper, progress dan project filter |
| Re-analysis | Selesai | Alasan wajib, job Celery baru, AI lama dan audit history dipertahankan |
| Review history | Selesai terbatas | Read-only, maksimum 100 keputusan terbaru |
| Structured Paper Result | Selesai | Nilai AI/final, confidence, status, evidence, metadata |
| Private Evidence PDF Viewer | Selesai | Authenticated bytes, bucket tetap private, navigasi ke halaman evidence |
| Comparative Paper Matrix | Selesai | Membandingkan latest reviewed values dari minimal dua paper `ready` |
| Concept/Evidence Map | Selesai | Paper -> concept -> evidence; mobile dan interactive desktop view |
| Research Gap Map | Selesai terbatas | Kandidat dari reviewed `limitations`/`future_work`, bukan kesimpulan otomatis |
| Responsive UI | Selesai untuk flow aktif | Mobile bottom navigation dan desktop sidebar/layout |

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

GET  /api/v1/projects/{project_id}/comparative-matrix
GET  /api/v1/projects/{project_id}/concept-evidence-map
GET  /api/v1/projects/{project_id}/research-gap-map

GET  /api/v1/reviews
GET  /api/v1/reviews/history
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

- Backend: **29 tests passed**.
- Flutter: **static analysis clean**.
- Flutter: **10 widget tests passed**.
- Flutter web release: **build succeeded**.
- Redis dan local Supabase: healthy.
- Runtime recovery test: dua PDF masing-masing menghasilkan 11 komponen dan
  berpindah ke `needs_review`.
- Manual browser QA: register/login flow, dashboard, projects, Review, Matrix,
  Concept/Evidence Map, Research Gap Map, mobile dan desktop layouts.

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

1. Hanya PDF dengan searchable text yang didukung. Scanned/image-only PDF belum
   memiliki OCR.
2. PDF viewer baru menavigasi ke halaman evidence; exact quote highlighting
   atau bounding-box overlay belum diterapkan.
3. Gemini masih dapat mengalami quota/high demand. Retry dan fallback sudah
   tersedia, tetapi provider eksternal tidak dapat dijamin selalu berhasil.
4. Project Overview melakukan polling hanya ketika job yang sedang tersimpan
   masih `queued/processing`. Bila status database diubah dari luar flow UI
   (misalnya manual recovery), kartu dapat stale sampai provider di-invalidasi,
   halaman dibuka ulang, atau browser direload.
5. Review history read-only dan hanya 100 keputusan terbaru; belum ada pagination.
6. Belum ada filter Review berdasarkan parameter/status dan belum ada safe bulk
   accept dengan konfirmasi eksplisit.
7. Comparative Matrix dan maps hanya memakai paper `ready`; paper yang masih
   `needs_review` sengaja tidak ikut.
8. Concept Map belum melakukan semantic merging untuk konsep ekuivalen dengan
   wording berbeda antar-paper.
9. Research Gap Map bukan generator kesimpulan lintas-paper. Ia menampilkan
   reviewed limitations/future work sebagai kandidat yang tetap harus divalidasi.
10. `ProjectWorkspaceScreen`/`DemoData` adalah prototype mati yang belum
    dipisahkan atau dihapus dari source.
11. Belum ada production domain, HTTPS deployment, monitoring, backups,
    retention/deletion workflow, atau production privacy operations.
12. Belum ada enforcement paket/quota nyata; kartu plan/account masih bersifat
    presentasional.
13. `backend/.env.example` belum tersedia; onboarding environment masih harus
    mengikuti daftar variabel di README ini tanpa menyalin nilai secret.

## Yang belum dikerjakan / backlog berikutnya

Urutan yang disarankan:

1. Perbaiki refresh terminal-state Project Overview agar manual/external retry
   tidak meninggalkan kartu stale; tambahkan regression test latest-job/history.
2. Review UX lanjutan: parameter/status filters, paginated history, safe bulk
   actions dengan confirmation dan audit trail.
3. Human-curated cross-paper gap synthesis serta keputusan eksplisit atas
   kandidat gap; jangan otomatis menjadikannya final.
4. Export Word, Excel/CSV, dan presentation-ready report dengan evidence links.
5. OCR untuk scanned PDF beserta review kualitas OCR.
6. Exact quote highlighting/bounding-box overlay pada viewer PDF.
7. Plan/quota enforcement dan usage reporting berbasis data backend.
8. Production hardening: HTTPS, secret management, rate limiting, monitoring,
   backup/restore, deletion/retention policy, dan privacy review.
9. Hapus atau isolasi prototype `ProjectWorkspaceScreen` dan `DemoData` setelah
   memastikan tidak ada desain yang masih ingin dipertahankan.
10. Tambahkan `backend/.env.example` tanpa nilai secret dan validasi startup
    dependency yang lebih eksplisit untuk onboarding developer baru.

## Checklist handoff untuk AI berikutnya

- Jangan menganggap screenshot/demo data sebagai database-backed behavior.
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
