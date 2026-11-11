# YouTube Live via GitHub Actions — Tanpa VPS

Streaming video loop ke YouTube Live memakai runner gratis GitHub Actions.
Tidak perlu VPS, tidak perlu PC menyala. PC/laptop boleh dimatikan setelah klik Run.

> **Ini tools nyata, bukan simulasi.** Workflow `live.yml` benar-benar menjalankan
> FFmpeg dan mengirim RTMPS ke YouTube. Workflow `test.yml` benar-benar
> menjalankan FFmpeg lokal di runner dan memverifikasi file FLV hasilnya.
> Uji dulu dengan `bash scripts/test-local.sh` di laptopmu sebelum live beneran.

## Yang kamu masukkan — koreksi penting

| Yang dimasukkan | Di mana | Sekali / tiap live |
|---|---|---|
| **Stream Key YouTube** | GitHub repo → Settings → Secrets and variables → Actions → New repository secret, nama `YT_STREAM_KEY` | **Sekali saja**, sampai kamu Reset key di YouTube |
| **Link video MP4 sumber** | GitHub repo → Settings → Secrets and variables → Actions → New repository secret, nama `VIDEO_URL` (isi link download langsung MP4, misal Drive `uc?export=download&id=...`) | **Sekali saja**; jadwal harian pakai secret ini, jangan tulis link-nya di file |
| **Link YouTube (watch / channel)** | **TIDAK dimasukkan ke mana-mana** | — |

Link YouTube itu hasil, bukan input. Yang jadi input adalah **file video yang mau diputar**
— videomu sendiri, format MP4, link langsung yang bisa di-download.
Contoh link langsung yang benar:
`https://example.com/video.mp4`
`https://drive.google.com/uc?export=download&id=FILE_ID_KAMU`

Link yang **salah**: link halaman YouTube (`youtube.com/watch?v=...`), link halaman
Google Drive biasa (`drive.google.com/file/d/.../view`), link halaman nonton.
Itu bukan file MP4, FFmpeg tidak bisa download.

## Batasan nyata (biar tidak kaget saat uji)

- **1x run max 6 jam** di GitHub. Tools ini diset max **330 menit (5,5 jam)** supaya aman.
  Mau lebih lama? Run lagi manual setelah selesai — akan jadi live baru.
- **Repo ini Public, jadi Actions gratis tanpa batas menit** (runner standar
  GitHub tidak dihitung kuotanya di repo publik). Kalau repo diubah jadi Private,
  akun Free cuma dapat 2.000 menit/bulan.
- **YouTube:** channel harus terverifikasi nomor HP, dan aktivasi live pertama
  bisa butuh **tunggu sampai 24 jam**. Stream di atas 12 jam mungkin tidak tersimpan
  sebagai replay oleh YouTube.
- **Jangan pernah tulis Stream Key atau link video di file, chat, atau screenshot.**
  Keduanya disimpan di Secret GitHub (`YT_STREAM_KEY` dan `VIDEO_URL`), jadi aman
  meski repo Public. Stream Key itu = password channelmu. Kalau bocor, orang lain
  bisa live di channelmu. Bocor? Langsung Reset di YouTube Studio, lalu update Secret di GitHub.
- Pakai videomu sendiri / yang kamu punya haknya. Video berhak cipta bisa
  membuat live dihentikan YouTube.

## Isi repo ini

```
.github/workflows/live.yml            # Live manual: klik Run workflow
.github/workflows/live-scheduled.yml  # Live otomatis terjadwal (cron)
.github/workflows/test.yml            # Test FFmpeg otomatis tiap push, tanpa YouTube
scripts/stream.sh                     # Script utama FFmpeg -> YouTube RTMPS
scripts/test-local.sh                 # Uji lokal di laptop sebelum push
videos/playlist.example.txt           # Contoh playlist (salin jadi playlist.txt)
```

## Langkah 1 — Siapkan YouTube (5 menit, sekali saja)

1. Buka [YouTube Studio](https://studio.youtube.com) → **Create → Go live**.
2. Kalau baru pertama kali: verifikasi channel pakai nomor HP di
   `youtube.com/verify`, lalu tunggu sampai live aktif (maks 24 jam).
3. Di Live Control Room, pilih **Stream key → Default stream key**.
   Klik ikon Copy di sebelahnya. **Jangan share ke siapa pun.**
4. Catat juga Stream URL-nya, harusnya `rtmp://a.rtmp.youtube.com/live2`
   (tools ini pakai versi amannya `rtmps://a.rtmps.youtube.com:443/live2`).

## Langkah 2 — Buat repo GitHub (5 menit, sekali saja)

1. GitHub → New repository → nama `youtube-live-public` → **Public** → Create.
2. Upload semua file di folder ini ke repo itu (drag & drop di web GitHub, atau `git push`).
   Jangan upload video besar ke repo: GitHub menolak file >100 MB.
   Video taruh di Google Drive / Dropbox / GitHub Release, lalu pakai link langsungnya.
3. Repo → **Settings → Secrets and variables → Actions → New repository secret**
   - Name: `YT_STREAM_KEY`
   - Secret: paste Stream Key dari Langkah 1 → Add secret.
   Buat satu secret lagi dengan cara yang sama:
   - Name: `VIDEO_URL`
   - Secret: paste link download langsung video MP4 (misal Drive `uc?export=download&id=...`).
   Jangan tulis Stream Key atau link video di file mana pun.
4. Cek test otomatis: repo → tab **Actions → Test Streaming** — harus hijau.
   Kalau merah, jangan lanjut live dulu, lihat log errornya.

## Langkah 3 — Uji lokal dulu (disarankan, 2 menit)

```bash
bash scripts/test-local.sh
```

Harus keluar `TEST LOKAL LULUS` dan file `test-output.flv` terbentuk.
Ini membuktikan perintah FFmpeg-nya valid, sebelum kamu buang kuota GitHub.

## Langkah 4 — Live manual (tiap kali mau live)

1. Repo → tab **Actions → YouTube Live Streaming → Run workflow**.
2. Isi:
   - `video_url`: link MP4 langsung (kosongkan kalau sudah upload `video.mp4` ke repo)
   - `mode`: `single` (1 video di-loop), `playlist` (banyak video), atau `image-audio` (gambar diam + musik)
   - `quality`: `720p` (disarankan, hemat kuota), `1080p`, atau `480p`
   - `duration_minutes`: misal `120` untuk 2 jam, max `330`
   - `image_url` / `audio_url`: hanya untuk mode `image-audio`
3. Klik **Run workflow** (tombol hijau).
4. Buka YouTube Studio → Live Control Room, tunggu **30–60 detik**.
   Status harus **Good / Excellent**, preview video muncul. Kalau ada tombol
   **Go Live**, klik itu.
5. Berhenti: tab Actions → run yang sedang jalan → **Cancel run**.
   Atau biarkan habis sesuai durasi, dia berhenti sendiri.

### Mode playlist

1. Salin `videos/playlist.example.txt` jadi `videos/playlist.txt`.
2. Isi satu URL MP4 per baris.
3. Run workflow dengan `mode: playlist`, `video_url` boleh dikosongkan.

### Mode image-audio (musik / kajian / radio)

Upload `cover.jpg` dan `audio.mp3` ke folder `videos/`, atau isi
`image_url` dan `audio_url` saat Run. Gambar akan diam, audio di-loop.

## Langkah 5 — Jadwal live streaming (2 jadwal, jangan tertukar)

Ada **2 jadwal yang berbeda**, keduanya perlu diatur:

### A. Jadwal di YouTube Studio (judul, tanggal, jam tayang)

Ini yang dilihat penonton.

1. YouTube Studio → Create → Go live → isi **Title, Description, Thumbnail**,
   pilih **Schedule** → tanggal & jam **WIB** → Create.
2. Tetap pakai **Default stream key** yang sama (jangan buat key baru tiap jadwal).
3. Saat jam tayang tiba, buka Live Control Room dan pastikan feed sudah masuk,
   lalu klik **Go Live** kalau masih diminta. GitHub tidak bisa mengklik tombol
   ini untukmu — ini satu-satunya langkah manual di YouTube.

### B. Jadwal otomatis di GitHub (kapan FFmpeg mulai kirim feed)

Ini yang menyalakan mesinnya.

1. Link video sudah diambil dari Secret `VIDEO_URL` (lihat Langkah 2) — jangan
   tulis link-nya di file ini.
2. Atur `cron`. **Cron GitHub pakai UTC, bukan WIB. WIB = UTC+7.**
   Jadwal aktif saat ini: `50 14 * * *` = tiap hari 21:50 WIB, target live
   22:00 WIB, durasi 330 menit (video 2 jam 44 menit di-loop 2x, selesai
   sekitar 03:30 WIB).
3. Set cron **10 menit sebelum** jadwal YouTube, karena GitHub bisa telat 5–15 menit.
4. Push file itu. Workflow akan jalan sendiri sesuai cron.
5. Jangan aktifkan `live.yml` manual dan `live-scheduled.yml` di jam yang sama.

> Kalau jadwalmu tidak rutin (cuma sekali-sekali), **tidak usah pakai
> live-scheduled.yml**. Cukup atur jadwal A di YouTube Studio, lalu
> klik Run manual di `live.yml` 10 menit sebelum jam tayang. Lebih simpel dan
> tidak berisiko dobel.

## Troubleshooting — uji nyata

| Gejala | Penyebab paling mungkin | Perbaiki |
|---|---|---|
| Workflow gagal di step "Cek Stream Key" | Secret `YT_STREAM_KEY` belum dibuat / salah nama | Buat ulang di Settings → Secrets, nama harus persis `YT_STREAM_KEY` |
| Workflow gagal di step "Cek Secret" / video tidak ter-download | Secret `VIDEO_URL` belum dibuat / salah nama / link bukan file MP4 langsung | Buat ulang di Settings → Secrets, nama harus persis `VIDEO_URL`, isi link download langsung (`uc?export=download&id=...` untuk Drive) |
| FFmpeg error `401 / Unauthorized` / tidak connect | Stream Key salah, atau key sudah di-Reset di YouTube | Copy ulang Default stream key, update Secret |
| FFmpeg error download / `404` | `video_url` bukan file MP4 langsung | Pakai link `uc?export=download&id=...` untuk Drive, `?dl=1` untuk Dropbox |
| Live tidak muncul di Studio setelah 2 menit | Live belum aktif (tunggu 24 jam pertama), atau feed belum sampai | Cek log Actions: ada baris `frame=...` berarti FFmpeg jalan. Cek Studio di tab Stream yang sama |
| Video jalan tapi tanpa suara | File sumber tidak ada audio | Pakai video yang ada audio, atau mode `image-audio` dengan `audio.mp3` |
| Run berhenti di tengah | Kuota / durasi habis, atau GitHub menghentikan | Itu normal di batas 6 jam. Run lagi untuk lanjut |
| Test workflow merah | `ffmpeg` gagal install / script error | Buka log test.yml, kirimkan baris error terakhirnya saat minta bantuan |

## Cek cepat sebelum live beneran

- [ ] Channel YouTube terverifikasi & live sudah aktif
- [ ] Secret `YT_STREAM_KEY` dan `VIDEO_URL` sudah diisi, repo Public
- [ ] `bash scripts/test-local.sh` → LULUS, atau Actions `Test Streaming` → hijau
- [ ] Link di `VIDEO_URL` bisa dibuka di browser dan langsung download / play (bukan halaman)
- [ ] Jadwal YouTube Studio sudah dibuat (kalau pakai jadwal)
- [ ] Durasi & kualitas sudah sesuai (720p, 330 menit per run, video loop 2x)
