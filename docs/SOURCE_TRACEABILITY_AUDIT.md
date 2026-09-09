# Audit komponen Source Traceability & Human-in-the-loop

Tanggal: 7 September 2026. Referensi: enam diagram yang diberikan pengguna.
Diagram dipakai sebagai kebutuhan fitur, bukan sebagai instruksi operasional.

## Pemetaan kebutuhan

| Diagram | Sebelum perubahan | Implementasi sekarang |
|---|---|---|
| 1. Paper Validation | Validasi file PDF, metadata dasar, dan status pemrosesan; belum ada validasi bibliografi | Panel **Validasi paper & sumber** pada hasil paper, pemeriksaan keberadaan DOI di Crossref/DataCite, perbandingan judul, penulis, tahun, jurnal/conference, DOI, penerbit dan status publikasi bila tersedia; hasil tetap membutuhkan review manusia |
| 2. Source Verification | Belum ada integrasi registri eksternal | Pemeriksaan DOI dengan endpoint tetap, sumber dan waktu pemeriksaan tersimpan, fallback DataCite, status berbeda untuk sumber ditemukan/tidak ditemukan/layanan gagal, catatan sumber yang belum dapat diverifikasi |
| 3. Metadata Verification | Title, authors, year, journal, DOI diekstrak; publisher hanya kolom database | Model, ekstraksi, API dan UI untuk title, authors, publication year, journal/conference, volume, issue, pages, DOI, publisher; pemeriksaan setiap field terhadap snapshot registri. `pages` adalah halaman publikasi, terpisah dari jumlah halaman PDF |
| 4. Claim Identification | Sudah ada 11 parameter akademik dan Accept/Edit/Reject | Dipertahankan: research problem, objective, question, method, dataset, variables, results, contribution, limitation, future work, key claims. Seluruh 11 kartu menampilkan nilai AI/final, status, confidence dan evidence, termasuk question/methodology yang juga memiliki tabel |
| 5. Evidence Matching | Kutipan verbatim dicocokkan ke blok pada halaman yang diklaim | Jenis `text`, `table`, `figure`, `equation`, `result`. Label objek harus ada pada kutipan sumber yang lolos pencocokan; label palsu dibuang dan jenis turun menjadi teks. Result evidence dibatasi ke parameter results/findings |
| 6. Source Location | Page dan block ID aktif; section/subsection hanya tersedia dalam schema | Section/subsection dideteksi dari heading teks sebelum kutipan; label figure/table/equation disimpan sebagai `source_label`. UI hasil dan Review menampilkan lokasi. Klik evidence membuka halaman PDF privat dan mencoba menyorot kutipan |

## Cara memakai

1. Terapkan migrasi baru dan restart API/worker dengan kode terbaru.
2. Buka proyek → hasil paper → **Validasi paper & sumber**.
3. Periksa metadata dan DOI paper utama. Klik **Periksa sumber**. Hanya DOI yang
   dikirim ke registri; PDF privat dan teksnya tidak dikirim ke registri tersebut.
4. Bandingkan nilai **Paper** dan **Registri**. Periksa URL sumber yang dapat
   disalin, termasuk bila judul/penulis/tahun berbeda atau informasi tidak tersedia.
5. Tinjau PDF, isi catatan, lalu pilih **Terima sumber** atau **Tolak sumber**.
   Keputusan tersimpan sebagai riwayat; tidak mengubah temuan mesin atau
   menyelesaikan review klaim AI. Dropdown memuat 20 pemeriksaan terbaru.
6. Gunakan kartu komponen dan lokasi evidence untuk kembali ke PDF asli.

Hasil lama tetap dapat dibuka sebagai evidence teks. Metadata dan jenis/lokasi
tambahan dihasilkan pada analisis berikutnya; gunakan re-analysis yang sudah ada
jika diperlukan. Tidak ada re-analysis massal, penggantian hasil lama, atau
pemanggilan Gemini otomatis oleh pemeriksaan registri.

## Kontrak API dan data

Prefix: `/api/v1/projects/{project_id}/papers/{paper_id}`. Semua endpoint memakai
JWT pengguna, memeriksa pemilik proyek/paper sebelum request registri, dan tetap
melewati RLS menggunakan anon key + JWT pengguna.

| Method/path | Request | Response |
|---|---|---|
| GET `/source-verifications` | — | Maksimal 20 `SourceVerificationRead`, terbaru dahulu, beserta review |
| POST `/source-verifications` | `{"doi":"10.…/…"}`; null memakai DOI paper | HTTP 201, snapshot `VerificationReport` beserta ID dan waktu |
| POST `/source-verifications/{id}/reviews` | `{"decision":"accept atau reject","note":"catatan wajib"}` | HTTP 201, identitas reviewer dari JWT dan waktu keputusan |

Report: `matched`, `mismatch`, `incomplete`, atau `unverifiable`. Setiap field:
`match`, `mismatch`, `missing_local`, `missing_source`, atau `unverifiable`.
Normalisasi perbandingan hanya huruf besar/kecil, spasi dan tanda baca; tidak ada
fuzzy matching yang otomatis menyatakan dua metadata setara.

`paper_source_verifications` dan `paper_source_reviews` bersifat append-only bagi
pengguna terautentikasi. Snapshot lokal dan eksternal tidak menimpa metadata
paper. Review atas snapshot lama tidak mengesahkan hasil re-analysis baru.
Review komponen, status proyek/paper, dashboard, dan batas 50 MB tetap mengikuti
alur sebelumnya. Tidak ada perubahan dependensi atau kunci baru.

## Migrasi dan pemeriksaan database

Migrasi tambahan: `supabase/migrations/20260907090000_source_traceability.sql`.
Jalankan dari root saat Docker dan Supabase lokal tersedia:

```powershell
supabase migration up --local
```

Jalankan `supabase/tests/source_traceability.sql` dengan `psql -v ON_ERROR_STOP=1`
terhadap database Supabase lokal. Tes menggunakan dua akun dalam satu transaksi
dan `ROLLBACK`: akses lintas pemilik, spoofing reviewer, serta perubahan/penghapusan
riwayat harus ditolak. Jangan menjalankan reset database.

Rollback aplikasi harus dilakukan sebelum menghapus kolom/tabel tambahan, dan
data verifikasi harus dibackup terlebih dahulu. Migrasi lama tidak diubah.

## Batas kemampuan yang disengaja

- Keberadaan DOI dan kecocokan metadata bukan jaminan keaslian isi PDF, kualitas
  jurnal, atau tidak adanya retraksi. Status publikasi yang tidak eksplisit
  dinyatakan **tidak tersedia**, bukan diasumsikan published/valid. Status
  `findable` milik DataCite tidak dianggap status publikasi.
- DOI tidak ditemukan atau provider gagal tidak berarti paper palsu. Paper tanpa
  DOI ditandai belum dapat diverifikasi dan tetap bisa diperiksa manusia.
- Figure/table/equation evidence berasal dari teks/caption/referensi yang dapat
  dicari di PDF. Pembacaan piksel, OCR, pembuktian matematis, dan validasi semantik
  otomatis antara setiap klaim dan bukti belum tersedia. PDF asli tetap menjadi
  tempat reviewer memeriksa objek visual.
- Heading dikenali secara konservatif dari teks bernomor/nama section umum;
  layout ambigu bisa menghasilkan lokasi section yang kosong atau perlu koreksi
  interpretasi manusia. Kutipan dan nomor halaman tetap diperiksa secara ketat.
- Klaim masih dikelompokkan ke 11 komponen akademik dengan maksimal tiga evidence
  per komponen; belum ada editor daftar klaim atomik tak terbatas.
- Source verification dipicu pengguna dan membutuhkan internet. Tidak ada
  pemantauan retraksi berkala atau pencarian kemiripan/plagiarisme.

## Bukti verifikasi 7 September 2026

- Backend: 95 tes lulus; mencakup seluruh jenis evidence, lokasi, persistensi
  worker, auth sebelum registry call, DOI invalid, fallback, timeout, respons
  malformed, redirect, DOI berbeda, serta review append-only.
- Pemeriksaan jaringan nyata: DOI Crossref `10.1037/0003-066X.59.1.29` ditemukan;
  DOI DataCite `10.14454/qdd3-ps68` berhasil melalui fallback setelah Crossref 404.
- Flutter: `flutter analyze --no-pub` bersih; seluruh 31 tes lulus;
  `flutter build web --release --no-wasm-dry-run` aplikasi utama berhasil.
- Tes widget panel berhasil di lebar 390 dan 1280 px, termasuk metadata,
  perbandingan, request verifikasi, catatan wajib, keputusan, dan error pemuatan.
- Browser QA: panel produksi dirender dengan fixture sintetis pada desktop dan
  mobile 390 px. Metadata, perbandingan, dan validasi catatan wajib berfungsi
  tanpa error konsol. Entrypoint fixture dihapus setelah pemeriksaan; hasil ini
  bukan replay full-stack terhadap data pengguna.
- Migrasi dan tes RLS live belum dijalankan: Docker Desktop gagal startup pada
  socket runtime `sailor-ingest.sock` yang tidak dapat diakses. Data lokal tidak
  direset. Tes otorisasi API dengan mock sudah lulus; ini tidak menggantikan
  pengujian dua akun pada database nyata sebelum merge.

## Pembaruan verifikasi 8 September 2026

Docker berhasil dipulihkan dengan mempertahankan volume dan data pengguna.
Supabase lokal dipindah ke API 18021/database 18022 karena port sebelumnya
dicadangkan Windows. Migrasi source traceability telah diterapkan dan tes SQL
RLS dua akun berhasil; fixture transaksi di-rollback. Alur HTTPS beta juga lolos
login, upload/download PDF privat, penolakan akses lintas akun, ekstraksi nyata
Celery/Gemini menjadi 11 komponen `needs_review`, dan logout. Fixture sintetis
dibersihkan setelah pemeriksaan. Detail APK dan batas beta ada di
`docs/BETA_ANDROID.md`.

Referensi integrasi: [Crossref REST API](https://github.com/Crossref/rest-api-doc)
dan [DataCite single DOI](https://support.datacite.org/docs/api-get-doi).
