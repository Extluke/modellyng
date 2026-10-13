# Requirements Document

## Introduction

Revisi dari reviewer pada menu Matriks dan Sintesis: sel pada tabel "B. Struktur Penulisan" saat ini menampilkan emoji beserta teks keterangan (misalnya "✅ (Urutan 1)", "❌ (Tidak Ada)", "🔗 (Digabung dengan Introduction)"). Tampilan ini disederhanakan menjadi ikon saja, yaitu ikon centang, silang, dan link dari pustaka RemixIcon (`ri-check-line`, `ri-close-line`, `ri-link`), dengan warna yang sama seperti sebelumnya.

Perubahan hanya menyentuh presentasi sel. Logika penentuan status (hasIntro, hasMethod, hasResults, hasConclusion, dan aturan discussion/literature review) tetap sama. Header tabel dan label baris juga tetap sama.

## Glossary

- **Structure_Table**: Tabel "B. Struktur Penulisan" pada layar detail matriks proyek (`ProjectMatrixDetailScreen`), berisi satu baris per bagian struktur dan satu kolom per paper.
- **Structure_Cell**: Satu sel di Structure_Table untuk kombinasi satu bagian struktur dan satu paper.
- **Structure_Status**: Status hasil logika penentuan yang sudah ada untuk satu Structure_Cell, bernilai salah satu dari: Present, Merged, Absent.
- **Present**: Status ketika bagian struktur terdeteksi ada (sebelumnya ditampilkan sebagai "✅ (Urutan N)").
- **Merged**: Status ketika bagian struktur dianggap digabung dengan bagian lain (sebelumnya ditampilkan sebagai "🔗 (Digabung dengan ...)").
- **Absent**: Status ketika bagian struktur tidak terdeteksi (sebelumnya ditampilkan sebagai "❌ (Tidak Ada)").
- **Check_Icon**: Ikon RemixIcon `ri-check-line`.
- **Close_Icon**: Ikon RemixIcon `ri-close-line`.
- **Link_Icon**: Ikon RemixIcon `ri-link`.
- **RemixIcon_Package**: Paket font ikon RemixIcon untuk Flutter yang ditambahkan sebagai dependensi frontend dengan versi yang dipin.
- **Semantic_Label**: Label aksesibilitas yang dibacakan oleh pembaca layar (TalkBack/VoiceOver) untuk sebuah ikon.
- **Legacy_Status_Text**: Teks tampilan lama di Structure_Cell, yaitu emoji ✅, ❌, 🔗 dan teks dalam kurung "(Urutan N)", "(Tidak Ada)", "(Digabung dengan Introduction)", "(Digabung dengan Results)".

## Requirements

### Requirement 1: Ikon Status pada Sel Struktur

**User Story:** Sebagai peneliti, saya ingin sel tabel Struktur Penulisan hanya menampilkan ikon centang, silang, atau link, sehingga tabel lebih ringkas dan mudah dipindai.

#### Acceptance Criteria

1. IF Structure_Status sebuah Structure_Cell bernilai Present, THEN THE Structure_Cell SHALL menampilkan Check_Icon berwarna AppColors.green.
2. IF Structure_Status sebuah Structure_Cell bernilai Absent, THEN THE Structure_Cell SHALL menampilkan Close_Icon berwarna Colors.red.
3. IF Structure_Status sebuah Structure_Cell bernilai Merged, THEN THE Structure_Cell SHALL menampilkan Link_Icon berwarna Colors.blue.
4. THE Structure_Cell SHALL menampilkan tepat satu ikon status.
5. WHEN Structure_Table dirender, THE Structure_Cell SHALL menampilkan ikon status tanpa Legacy_Status_Text dan tanpa karakter teks atau emoji lain yang terlihat di dalam sel.

### Requirement 2: Logika Penentuan Status Tetap

**User Story:** Sebagai peneliti, saya ingin hasil deteksi struktur tetap sama seperti sebelumnya, sehingga hanya tampilannya yang berubah.

#### Acceptance Criteria

1. IF Structure_Cell berada pada baris introduction dan paper memiliki konten pada minimal satu dari parameter research_problem, research_objective, atau research_question, THEN THE Structure_Table SHALL menetapkan Structure_Status Present untuk Structure_Cell tersebut.
2. IF Structure_Cell berada pada baris literature_review, THEN THE Structure_Table SHALL menetapkan Structure_Status Merged untuk Structure_Cell tersebut, termasuk ketika paper tidak memiliki konten pada parameter mana pun.
3. IF Structure_Cell berada pada baris method dan paper memiliki konten pada minimal satu dari parameter methodology atau dataset_sample, THEN THE Structure_Table SHALL menetapkan Structure_Status Present untuk Structure_Cell tersebut.
4. IF Structure_Cell berada pada baris results dan paper memiliki konten pada parameter results_findings, THEN THE Structure_Table SHALL menetapkan Structure_Status Present untuk Structure_Cell tersebut.
5. IF Structure_Cell berada pada baris discussion dan paper memiliki konten pada parameter results_findings serta pada minimal satu dari parameter limitations atau future_work, THEN THE Structure_Table SHALL menetapkan Structure_Status Merged untuk Structure_Cell tersebut.
6. IF Structure_Cell berada pada baris conclusion dan paper memiliki konten pada minimal satu dari parameter contribution, limitations, atau future_work, THEN THE Structure_Table SHALL menetapkan Structure_Status Present untuk Structure_Cell tersebut.
7. IF tidak ada kondisi pada kriteria 1 sampai 6 yang terpenuhi untuk sebuah Structure_Cell, THEN THE Structure_Table SHALL menetapkan Structure_Status Absent untuk Structure_Cell tersebut, termasuk Structure_Cell pada baris discussion untuk paper yang hanya memiliki konten pada limitations atau future_work tanpa results_findings, dan untuk paper yang hanya memiliki konten pada results_findings tanpa limitations maupun future_work.
8. THE Structure_Table SHALL memperlakukan sebuah parameter sebagai tidak memiliki konten untuk sebuah paper jika matriks tidak memiliki baris untuk parameter tersebut, baris tersebut tidak memiliki sel untuk paper tersebut, atau nilai tampilan sel setelah trim berupa string kosong atau tepat sama dengan "-".
9. THE Structure_Table SHALL menetapkan tepat satu Structure_Status dari {Present, Merged, Absent} untuk setiap Structure_Cell, ditentukan hanya dari sel matriks milik paper pada kolom tersebut.
10. WHEN pengguna mengubah daftar paper yang ditampilkan melalui filter paper, THE Structure_Table SHALL mempertahankan Structure_Status yang sama untuk setiap Structure_Cell dari paper yang tetap ditampilkan.

### Requirement 3: Aksesibilitas Ikon

**User Story:** Sebagai pengguna pembaca layar, saya ingin setiap ikon status memiliki label yang dibacakan, sehingga informasi status tetap tersampaikan meskipun teks terlihat dihapus.

#### Acceptance Criteria

1. IF Structure_Status sebuah Structure_Cell bernilai Present, THEN THE Structure_Cell SHALL menyediakan tepat satu Semantic_Label persis "Ada" sebagai satu-satunya label yang dibacakan pembaca layar (TalkBack/VoiceOver) untuk Structure_Cell tersebut.
2. IF Structure_Status sebuah Structure_Cell bernilai Absent, THEN THE Structure_Cell SHALL menyediakan tepat satu Semantic_Label persis "Tidak ada" sebagai satu-satunya label yang dibacakan pembaca layar (TalkBack/VoiceOver) untuk Structure_Cell tersebut.
3. IF Structure_Status sebuah Structure_Cell bernilai Merged, THEN THE Structure_Cell SHALL menyediakan tepat satu Semantic_Label persis "Digabung" sebagai satu-satunya label yang dibacakan pembaca layar (TalkBack/VoiceOver) untuk Structure_Cell tersebut.
4. THE Structure_Cell SHALL menampilkan ikon status dengan ukuran 20 logical pixel.
5. THE Structure_Cell SHALL menampilkan ikon dengan bentuk berbeda untuk masing-masing tiga Structure_Status, sehingga status dapat dibedakan tanpa bergantung pada warna saja.

### Requirement 4: Tata Letak Tabel Tidak Berubah

**User Story:** Sebagai peneliti, saya ingin header dan label baris tabel tetap sama, sehingga saya tetap mengenali struktur tabel.

#### Acceptance Criteria

1. WHEN ProjectMatrixDetailScreen menampilkan Structure_Table dengan minimal 1 paper terfilter, THE Structure_Table SHALL menampilkan baris header sebagai baris pertama, dengan sel pertama berteks persis "Bagian Struktur" diikuti tepat satu sel header per paper terfilter berisi judul paper, dalam urutan yang sama dengan daftar paper terfilter.
2. WHEN ProjectMatrixDetailScreen menampilkan Structure_Table dengan minimal 1 paper terfilter, THE Structure_Table SHALL menampilkan tepat 6 baris konten di bawah header, dengan label berurutan "Introduction", "Literature Review", "Method", "Results", "Discussion", "Conclusion" sesuai structureLabels, dan setiap baris berisi tepat satu Structure_Cell per paper terfilter dalam urutan kolom yang sama.
3. THE Structure_Cell SHALL dirender dengan lebar tetap 280 logical pixel, padding horizontal 16 dan vertikal 16, border kanan dan bawah AppColors.border tanpa border atas maupun kiri, latar putih, dan perataan centerLeft.
4. IF daftar paper terfilter kosong, THEN THE Structure_Table SHALL tidak dirender sama sekali.

### Requirement 5: Dependensi Ikon RemixIcon

**User Story:** Sebagai developer, saya ingin ikon diambil dari RemixIcon dengan versi terkunci, sehingga tampilan ikon sesuai referensi reviewer dan build tetap stabil.

#### Acceptance Criteria

1. THE frontend/pubspec.yaml SHALL mencantumkan RemixIcon_Package di bagian `dependencies` dengan satu versi eksak berformat `MAJOR.MINOR.PATCH` tanpa operator rentang (tanpa `^`, `>=`, `<`, `>`, atau `any`).
2. WHEN `flutter pub get` dijalankan di direktori frontend, THE frontend SHALL me-resolve RemixIcon_Package ke versi yang sama persis dengan versi di pubspec.yaml dan selesai tanpa error resolusi.
3. THE Structure_Cell SHALL merender Check_Icon, Close_Icon, dan Link_Icon hanya dari glyph RemixIcon_Package, tanpa Material Icons maupun CupertinoIcons sebagai pengganti.
4. WHEN `flutter analyze` dan `flutter test` dijalankan setelah penambahan RemixIcon_Package, THE frontend SHALL menyelesaikan keduanya tanpa error yang berasal dari RemixIcon_Package atau dari pemakaian Check_Icon, Close_Icon, dan Link_Icon.

### Requirement 6: Pengujian Widget

**User Story:** Sebagai developer, saya ingin ada widget test untuk sel struktur, sehingga regresi tampilan ikon terdeteksi otomatis.

#### Acceptance Criteria

1. WHEN widget test merender Structure_Cell secara terpisah untuk masing-masing tiga Structure_Status, THE widget test SHALL memverifikasi tepat satu ikon per Structure_Cell, yaitu Check_Icon berwarna AppColors.green untuk Present, Link_Icon berwarna Colors.blue untuk Merged, dan Close_Icon berwarna Colors.red untuk Absent, sesuai Requirement 1.
2. WHEN widget test merender Structure_Table dengan minimal 2 paper yang bersama-sama menghasilkan ketiga Structure_Status, THE widget test SHALL memverifikasi bahwa Legacy_Status_Text tidak ditemukan, yaitu emoji ✅, ❌, 🔗, teks "(Urutan N)" untuk nilai N berapa pun, "(Tidak Ada)", "(Digabung dengan Introduction)", dan "(Digabung dengan Results)".
3. WHEN widget test merender Structure_Cell untuk masing-masing tiga Structure_Status, THE widget test SHALL memverifikasi tepat satu Semantic_Label persis "Ada" untuk Present, "Digabung" untuk Merged, dan "Tidak ada" untuk Absent, sesuai Requirement 3.
4. THE test suite SHALL memverifikasi, untuk setiap bagian struktur (6 bagian) dan seluruh 512 kombinasi ada/tidaknya konten pada 9 parameter (research_problem, research_objective, research_question, methodology, dataset_sample, results_findings, limitations, future_work, contribution), bahwa Structure_Status yang dihasilkan sama dengan aturan Requirement 2 kriteria 1 sampai 7.
5. WHEN test suite menguji parameter bernilai string kosong, hanya berisi spasi, atau "-", THE test suite SHALL memverifikasi bahwa parameter tersebut diperlakukan sebagai tidak memiliki konten sesuai Requirement 2 kriteria 8.
6. WHEN widget test merender Structure_Cell untuk masing-masing tiga Structure_Status, THE widget test SHALL memverifikasi ukuran ikon status 20 logical pixel.
7. WHEN developer menjalankan `flutter test` tanpa jaringan dan tanpa backend, THE test suite SHALL lulus untuk kriteria 1 sampai 6.
8. IF ikon, warna, Semantic_Label, Legacy_Status_Text, ukuran ikon, atau Structure_Status menyimpang dari Requirement 1, 2, atau 3, THEN THE test suite SHALL melaporkan test terkait sebagai gagal.
