## Tujuan perubahan

Jelaskan satu masalah yang diselesaikan dan tautkan acceptance criteria/task.

## Perubahan

- 

## Verifikasi

- [ ] Backend tests lulus (`python -m pytest`), jika relevan
- [ ] Flutter analyze lulus, jika relevan
- [ ] Flutter tests lulus, jika relevan
- [ ] Flutter web release build lulus, jika relevan
- [ ] Flow desktop/mobile diuji, jika relevan
- [ ] Isolasi Account A/Account B diuji untuk perubahan akses data

## Keamanan dan arsitektur

- [ ] Mengikuti `AGENTS.md` dan `docs/ARCHITECTURE.md`
- [ ] Tidak mengganti teknologi yang dikunci tanpa keputusan tim
- [ ] Tidak menyertakan `.env`, API key, service-role key, PDF privat, atau log
- [ ] RLS dan private storage tetap aktif
- [ ] Evidence tetap dapat ditelusuri ke paper/page sumber
- [ ] Output AI tetap memerlukan review manusia

## Database / environment

Migration, env, atau langkah manual yang diperlukan (tulis "tidak ada" bila
tidak ada):

## Risiko dan rollback

Jelaskan risiko, kompatibilitas, serta cara membatalkan perubahan secara aman.

