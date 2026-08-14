# Modellyng

Monorepo MVP lokal untuk ekstraksi PDF berbantuan AI. Flutter menjadi klien,
FastAPI menjadi API, Celery memakai Redis untuk pekerjaan asinkron, Supabase
menyimpan data privat, dan Gemini mengekstrak komponen akademik yang wajib
ditinjau manusia.

## Struktur monorepo

```text
modellying/
|-- frontend/                 # Flutter application
|   |-- lib/
|   |   |-- main.dart
|   |   `-- src/             # app, data, models, screens, theme, widgets
|   |-- test/
|   |-- android/ ios/ web/   # Flutter platform targets
|   `-- pubspec.yaml
|-- backend/                  # Python 3.10+ application
|   |-- app/
|   |   |-- main.py          # FastAPI entry point
|   |   |-- ai_extraction.py # Gemini schema + evidence verification
|   |   |-- celery_app.py    # Celery configuration
|   |   `-- tasks.py         # PDF + Gemini background pipeline
|   |-- tests/
|   |-- .env.example
|   `-- requirements.txt
|-- supabase/                 # Local database, auth, storage, and migrations
|-- docker-compose.yml        # Redis only
`-- README.md
```

## 1. Start Redis

Dari root repository:

```powershell
docker compose up -d
docker compose ps
```

Redis hanya tersedia pada komputer lokal di `localhost:6380`.

## 2. Start Supabase lokal

```powershell
npx supabase start
npx supabase status
```

Salin URL serta anon/publishable key dan service-role key dari `supabase status`
ke `backend/.env`. Jangan pernah menaruh service-role key di Flutter atau Git.

## 3. Start FastAPI

Untuk setup pertama kali:

```powershell
cd backend
python -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install -r requirements.txt
Copy-Item .env.example .env  # hanya jika backend/.env belum ada
```

Untuk menjalankan API:

```powershell
cd backend
.\.venv\Scripts\Activate.ps1
python -m uvicorn app.main:app --reload --port 8000
```

Tes service di `http://127.0.0.1:8000/health`. Status Redis dan Supabase ada di
`http://127.0.0.1:8000/health/dependencies`, sedangkan dokumentasi API ada di
`http://127.0.0.1:8000/docs`.

## 4. Start Celery worker

Buka PowerShell lain:

```powershell
cd backend
.\.venv\Scripts\Activate.ps1
python -m celery -A app.celery_app:celery_app worker --pool=solo --loglevel=INFO
```

`solo` dipakai agar Celery stabil di Windows. Setelah PDF diunggah, worker
mengekstrak teks dan nomor halaman secara lokal, lalu mengirim teks tersebut ke
Gemini. Gemini mengembalikan 11 komponen akademik dalam JSON terstruktur.
Kutipan yang tidak benar-benar ditemukan pada halaman sumber akan dibuang
sebelum hasil disimpan.

Semua komponen tetap berstatus **Perlu ditinjau** sampai pengguna memilih
Terima, Edit, atau Tolak pada halaman Review.

## 5. Start Flutter web

```powershell
cd frontend
flutter pub get
flutter run -d web-server --web-port 8082
```

Buka `http://127.0.0.1:8082/#/app`.

## 6. Konfigurasi Gemini

Isi nilai berikut pada `backend/.env` dan jangan memakai tanda kutip:

```dotenv
GEMINI_API_KEY=
MODELLYNG_GEMINI_MODEL=gemini-flash-latest
MODELLYNG_GEMINI_MAX_INPUT_CHARS=400000
```

Karena API key pernah dibagikan melalui percakapan, buat key pengganti sebelum
demo publik. Setelah mengganti key, restart FastAPI dan Celery agar konfigurasi
baru dibaca.

## 7. Pemeriksaan sebelum presentasi

Jalankan backend test dari folder `backend/`:

```powershell
python -m pytest
```

Jalankan pemeriksaan Flutter dari folder `frontend/`:

```powershell
flutter analyze
flutter test
flutter build web --release
```

Urutan normal menyalakan aplikasi setiap kali pengembangan adalah Redis,
Supabase, FastAPI, Celery, lalu Flutter.

## 8. Kerja tim dan coding assistant

Sebelum developer atau coding assistant baru melakukan perubahan, baca:

1. [`AGENTS.md`](AGENTS.md) — aturan wajib seluruh repository.
2. [`docs/PROJECT_STATUS.md`](docs/PROJECT_STATUS.md) — yang sudah dan belum
   dibangun serta prioritas P0.
3. [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — teknologi dan batas
   keamanan yang dikunci.
4. [`docs/CONTRIBUTING.md`](docs/CONTRIBUTING.md) — branch, test, dan pull
   request workflow.
5. [`docs/AI_HANDOFF_PROMPT.md`](docs/AI_HANDOFF_PROMPT.md) — prompt siap
   ditempel untuk Codex atau AI lain.

Jangan mulai kerja tim dari salinan folder atau checkout lama. Pastikan seluruh
progres telah di-commit dan di-push ke repository bersama, lalu kerjakan satu
task per branch dan review melalui pull request.
