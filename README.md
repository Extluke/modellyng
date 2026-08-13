# Modellyng

Modellyng adalah workspace *evidence-centered academic knowledge modeling* untuk mengubah paper menjadi data penelitian terstruktur, membandingkan banyak paper, memetakan kandidat *research gap*, dan memverifikasi setiap hasil AI terhadap sumber asli.

## Yang sudah tersedia

- Flutter UI responsif untuk mobile, tablet, dan web.
- Dashboard, project wizard, daftar paper, Structured Paper Model, Comparative Matrix, Gap Map, dan human review.
- Kontrak FastAPI untuk project, paper, dan asynchronous analysis job.
- Celery + Redis worker boundary untuk pipeline analisis berdurasi panjang.
- Skema PostgreSQL/pgvector untuk paper blocks, extracted components, evidence spans, serta reviewer actions.
- Docker Compose untuk PostgreSQL, Redis, API, dan worker.

Data pada Flutter masih merupakan data demonstrasi terkontrol. API menggunakan repository memori untuk pengembangan awal; migrasi PostgreSQL sudah disiapkan sebagai kontrak persistensi untuk vertical slice berikutnya.

## Menjalankan Flutter

Pastikan Flutter 3.44 atau lebih baru tersedia, lalu jalankan:

```powershell
flutter pub get
flutter run -d web-server --web-port 8081
```

Buka `http://localhost:8081`. Port 8081 digunakan karena pada mesin pengembangan awal port 8080 dipakai oleh Apache/httpd.

Validasi kode:

```powershell
flutter analyze
flutter test
```

## Menjalankan API lokal

Dari folder `backend`:

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
Copy-Item .env.example .env
uvicorn app.main:app --reload --port 8000
```

Dokumentasi OpenAPI tersedia di `http://localhost:8000/docs` dan health check di `http://localhost:8000/health`.

## Menjalankan infrastruktur

```powershell
docker compose up --build
```

Service yang dibuka:

- Flutter web: port `8081` jika dijalankan terpisah.
- FastAPI: port `8000`.
- PostgreSQL + pgvector: port `5432`.
- Redis: port `6379`.

## Struktur penting

```text
lib/src/
  data/       data demo untuk product validation
  models/     domain models Flutter
  screens/    seluruh alur MVP
  theme/      design system Modellyng
  widgets/    komponen UI reusable

backend/
  app/        FastAPI, schemas, repository, dan Celery task
  migrations/ PostgreSQL + pgvector schema
```

## Batas keamanan

- API key AI tidak boleh disimpan di Flutter atau di-commit ke repository.
- Paper produksi harus berada di private object storage dan diakses melalui signed URL.
- Setiap claim harus mempertahankan hubungan `Result → Evidence → Paper Block → Page → Original File`.
- Koreksi manusia disimpan sebagai reviewer action; keluaran awal AI tidak ditimpa secara diam-diam.
