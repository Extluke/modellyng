# Laporan RECON (Tahap 1)

## 1.A Pemetaan File
- **Model DB (Supabase):** `supabase/migrations/20261006111500_knowledge_graph_schema.sql` (Tabel `knowledge_graph_nodes` dan `knowledge_graph_edges`)
- **Skema `KnowledgeGraphNodeRead`:** `backend/app/schemas.py` (Baris 473)
- **Ekstraksi AI:** `backend/app/ai_extraction.py`
- **Endpoint Graf (Repository):** `backend/app/repository.py` (`get_knowledge_graph`)
- **Endpoint Proyek (Repository):** `backend/app/repository.py` (`get_project`)
- **Model Dart (Frontend):** `frontend/lib/src/models/research_models.dart` (`KnowledgeGraphNode` dan `KnowledgeGraphEdge`)
- **Git Status:** Bersih (hanya ada modifikasi pada `to-do.[txt`).

## 1.B Catatan Kolom Node/Edge (Sudah Ada vs Belum)
Tabel perbandingan antara kebutuhan filter UI dengan kondisi tabel/skema *Backend* saat ini:

| Kolom Kebutuhan UI | Status di DB/Skema | Keterangan |
| :--- | :--- | :--- |
| `gap_type` | **SUDAH ADA** | Bernama `gap_typology` (Tipe data: Text / Enum) |
| `saturation_status` | **SUDAH ADA** | Bernama `saturation_status` (Tipe data: Text / Enum) |
| `zone_category` | **SUDAH ADA** | Bernama `zone_category` (Tipe data: Text) |
| `confidence_score` | **SUDAH ADA** | Bernama `confidence_score` (Tipe data: NUMERIC(5,2)) |
| `evidence` | **SUDAH ADA** | Bernama `evidence` (Tipe data: JSONB) |
| `x` | **SUDAH ADA** | Bernama `x` (Tipe data: NUMERIC) |
| `y` | **SUDAH ADA** | Bernama `y` (Tipe data: NUMERIC) |
| `method_cluster` | **BELUM ADA** | Harus ditambahkan di DB, schema, dan Dart |
| `object_cluster` | **BELUM ADA** | Harus ditambahkan di DB, schema, dan Dart |

## 1.C Alur Ekstraksi AI & Status Nomor Halaman
**Ringkasan Alur AI:**
1. PDF diekstrak menjadi `blocks` teks per halaman.
2. `blocks` diumpan ke `extract_academic_components` (menjalankan AI Prompt: `academic-components-v3-routing-fuzzy`).
3. Output AI di-_parse_ ke pydantic `AiPaperExtraction` (termasuk `AiComponent`, `AiResearchGap`).
4. Data dilewatkan ke validasi kutipan menjadi `VerifiedPaperExtraction`.
5. `repository.py` menyimpan hasil tersebut ke tabel DB.

**Status Nomor Halaman:**
- **AMAN (TIDAK HILANG).** Teks hasil ekstraksi PDF (`blocks`) masih menyimpan field `page_number: int`.
- `VerifiedEvidence` di `ai_extraction.py` memiliki field `page_number`.
- `AiComponent` dan `AiResearchGap` juga dilatih untuk mengeluarkan `page_number: int`.
- Ini menjamin Poin 6 pada `to-do.[txt` dapat berjalan dengan baik (sistem akan bisa menampilkan nomor halaman dari bukti kutipan).

## 1.D Cara Migrasi & Eksekusi Test (Baseline)
- **Migrasi:** Menggunakan raw SQL script di folder `supabase/migrations/`. Pembaruan skema harus berupa file SQL baru di folder tersebut.
- **Eksekusi Test:** Dijalankan dengan perintah `.venv\Scripts\pytest` dari dalam folder `backend/`. 
- **Status Baseline:** `pytest` gagal pada fase _collection_ karena file `test_query.py` (yang berada di luar folder `tests/`) mencoba mengimpor modul lama `app.dependencies` yang sudah tidak ada. Secara keseluruhan ada 127 _test items_ yang ditemukan sebelum error.

## 1.F Gaya Penamaan Field JSON
- **Backend (Pydantic):** Menggunakan `snake_case` (misal: `gap_typology`, `saturation_status`).
- **Frontend (Dart `fromJson`):** Membaca _key_ JSON dalam bentuk `snake_case` (misal: `json['gap_typology']`).
- **Kesimpulan:** Tidak ada _mismatch_ akibat casing. Keduanya sepakat menggunakan `snake_case` pada payload API.
