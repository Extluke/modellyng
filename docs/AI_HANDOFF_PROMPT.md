# Prompt Serah-Terima untuk Codex atau AI Coding Lain

Salin prompt berikut saat teman baru pertama kali membuka repository. Jalankan
prompt audit ini sebelum meminta AI menulis kode.

## Prompt audit awal — jangan coding

```text
Anda bergabung ke project tim Modellyng yang SUDAH berjalan. Project ini bukan
greenfield dan tidak boleh dibuat ulang dari nol.

Sebelum melakukan perubahan apa pun:
1. Baca AGENTS.md seluruhnya.
2. Baca docs/PROJECT_STATUS.md, docs/ARCHITECTURE.md, dan
   docs/CONTRIBUTING.md.
3. Periksa branch aktif, git status, struktur repository, file terkait, dan
   test yang sudah ada.
4. Jangan mengedit file dan jangan menjalankan operasi destruktif.

Setelah audit, laporkan kepada saya:
- ringkasan tujuan produk;
- teknologi yang terkunci dan trust boundary-nya;
- fitur yang sudah selesai;
- keterbatasan saat ini;
- prioritas P0 berikutnya dan definition of done;
- risiko konflik atau perubahan lokal yang belum di-commit;
- rencana implementasi kecil yang kompatibel, termasuk file yang kemungkinan
  berubah dan pengujian yang harus dijalankan.

Jangan mengganti Flutter, Riverpod, go_router, Dio, FastAPI, Celery, Redis,
Supabase, atau Gemini. Jangan menonaktifkan RLS, mengekspos key backend,
membuat bucket PDF menjadi publik, menghapus data/migration, atau menganggap
hasil AI final tanpa review manusia.

Berhenti setelah memberikan audit dan rencana. Tunggu persetujuan tim sebelum
coding.
```

## Prompt implementasi setelah rencana disetujui

```text
Lanjutkan task yang sudah disetujui pada branch terpisah. Ikuti AGENTS.md dan
acceptance criteria di docs/PROJECT_STATUS.md. Audit implementasi yang sudah
ada terlebih dahulu, gunakan perubahan terkecil yang kompatibel, lindungi
perubahan tim lain, dan jangan memperluas scope.

Sebelum menyerahkan hasil:
- tambahkan/update regression test;
- jalankan backend test dan Flutter analyze/test yang relevan;
- untuk perubahan web, build release dan uji flow desktop/mobile;
- untuk akses data, uji isolasi Account A dan Account B;
- perbarui docs/PROJECT_STATUS.md bila status fitur berubah;
- laporkan file yang berubah, hasil test, migration/env step, keterbatasan, dan
  hal yang masih perlu direview manusia.
```

## Cara memberinya task

Tambahkan satu tugas konkret setelah prompt implementasi, misalnya:

```text
Task: implementasikan bagian API read-only untuk Structured Paper Result sesuai
P0, tanpa membuat PDF viewer dahulu. Scope hanya endpoint, repository, schema,
dan authorization tests.
```

Memisahkan API, UI hasil, dan PDF viewer menjadi pull request kecil lebih aman
daripada meminta satu AI membangun seluruh backlog sekaligus.

