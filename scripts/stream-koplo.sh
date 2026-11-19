#!/usr/bin/env bash
# stream-koplo.sh — Streaming video dangdut koplo ke YouTube Live via FFmpeg + RTMPS
# Dipakai oleh .github/workflows/live-koplo-scheduled.yml (live harian 05:30 WIB).
# Video diputar 2x (LOOP 2x): -stream_loop 1 = file diputar 2 kali total,
# durasi ±221 menit (video ±111 menit x 2), lalu ffmpeg berhenti sendiri.
# Timeout 240 menit sebagai pengaman bila putaran ke-2 molor.
# Video bisa datang dalam 2 bagian (VIDEO_URL + VIDEO_URL_2): kedua bagian
# diunduh lalu digabung jadi satu file sebelum streaming (19 Nov 2026 —
# upload 1,4 GB utuh berulang gagal, dipecah ~700 MB per bagian).
# Bisa dites lokal: TEST_MODE=1 bash scripts/stream-koplo.sh
#   (tanpa Stream Key, output ke test-output-koplo.flv selama 15 detik)
set -euo pipefail

# ---------- Konfigurasi dari environment ----------
QUALITY="${QUALITY:-720p}"               # 720p | 1080p | 480p
VIDEO_URL="${VIDEO_URL:-}"
VIDEO_URL_2="${VIDEO_URL_2:-}"
DURATION_MINUTES="${DURATION_MINUTES:-255}"
YT_STREAM_KEY="${YT_STREAM_KEY:-}"
TEST_MODE="${TEST_MODE:-0}"               # 1 = uji lokal, tidak kirim ke YouTube
TEST_SECONDS="${TEST_SECONDS:-15}"

# Validasi durasi: angka, 1..350
if ! [[ "$DURATION_MINUTES" =~ ^[0-9]+$ ]] || [ "$DURATION_MINUTES" -lt 1 ] || [ "$DURATION_MINUTES" -gt 350 ]; then
  echo "ERROR: DURATION_MINUTES harus angka 1-350, dapat: $DURATION_MINUTES" >&2
  exit 1
fi

# ---------- Tujuan output ----------
if [ "$TEST_MODE" = "1" ]; then
  OUTPUT="test-output-koplo.flv"
  echo "=== TEST MODE: output ke $OUTPUT selama $TEST_SECONDS detik, TIDAK ke YouTube ==="
else
  if [ -z "$YT_STREAM_KEY" ]; then
    echo "ERROR: YT_STREAM_KEY kosong. Isi di GitHub Secrets, jangan tulis di file." >&2
    exit 1
  fi
  # RTMPS (terenkripsi, port 443) — sesuai rekomendasi YouTube 2026.
  OUTPUT="rtmps://a.rtmps.youtube.com:443/live2/${YT_STREAM_KEY}"
  echo "=== LIVE MODE: tujuan YouTube RTMPS (key disembunyikan) ==="
fi

# ---------- Kualitas -> resolusi & bitrate (rekomendasi YouTube) ----------
case "$QUALITY" in
  1080p) WIDTH=1920; HEIGHT=1080; VBITRATE="4500k"; MAXRATE="4500k"; BUFSIZE="9000k" ;;
  480p)  WIDTH=854;  HEIGHT=480;  VBITRATE="1200k"; MAXRATE="1200k"; BUFSIZE="2400k" ;;
  720p|*) WIDTH=1280; HEIGHT=720; VBITRATE="2500k"; MAXRATE="2500k"; BUFSIZE="5000k" ;;
esac
echo "Quality=${WIDTH}x${HEIGHT} VideoBitrate=$VBITRATE Durasi=${DURATION_MINUTES} menit (loop 2x)"

command -v ffmpeg >/dev/null || { echo "ERROR: ffmpeg tidak ditemukan" >&2; exit 1; }
command -v ffprobe >/dev/null || { echo "ERROR: ffprobe tidak ditemukan" >&2; exit 1; }

download_file() {
  local url="$1" out="$2"
  echo "Download: $url -> $out"
  curl -L --fail --retry 3 --connect-timeout 30 --max-time 1200 -o "$out" "$url"
  [ -s "$out" ] || { echo "ERROR: download gagal / file kosong: $url" >&2; exit 1; }
}

# ---------- Siapkan input ----------
VIDEO_FILE="video-koplo.mp4"
if [ -n "$VIDEO_URL_2" ]; then
  # Dua bagian: unduh keduanya lalu gabung jadi satu file.
  [ -n "$VIDEO_URL" ] || { echo "ERROR: VIDEO_URL_2 ada tapi VIDEO_URL kosong." >&2; exit 1; }
  download_file "$VIDEO_URL" "video-koplo-1.mp4"
  download_file "$VIDEO_URL_2" "video-koplo-2.mp4"
  printf "file 'video-koplo-1.mp4'\nfile 'video-koplo-2.mp4'\n" > concat-koplo.txt
  ffmpeg -hide_banner -v error -f concat -safe 0 -i concat-koplo.txt -c copy "$VIDEO_FILE" -y \
    || { echo "ERROR: gabung 2 bagian gagal." >&2; exit 1; }
  JOINED_DUR="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$VIDEO_FILE")"
  echo "Durasi gabungan: $JOINED_DUR detik (harus ±6622)"
  # Penjaga: gabungan harus utuh (±111 menit); bila pendek, salah satu bagian rusak/tak lengkap.
  python3 -c "import sys; d=float('$JOINED_DUR'); sys.exit(0 if d >= 6500 else 1)" \
    || { echo "ERROR: durasi gabungan $JOINED_DUR terlalu pendek — gabung gagal." >&2; exit 1; }
elif [ -n "$VIDEO_URL" ]; then
  download_file "$VIDEO_URL" "$VIDEO_FILE"
elif [ -f "video-koplo.mp4" ]; then
  echo "Pakai video-koplo.mp4 dari repo"
else
  echo "ERROR: Tidak ada video. Isi VIDEO_URL (link MP4 langsung)." >&2
  exit 1
fi

echo "--- ffprobe $VIDEO_FILE ---"
ffprobe -v error -select_streams v:0 -show_entries stream=codec_name,width,height,r_frame_rate -of default=noprint_wrappers=1 "$VIDEO_FILE"
ffprobe -v error -select_streams a:0 -show_entries stream=codec_name -of default=noprint_wrappers=1 "$VIDEO_FILE" || echo "(peringatan: file ini tidak ada audio stream)"
echo "Ukuran: $(du -h "$VIDEO_FILE" | cut -f1)"
ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1 "$VIDEO_FILE"

# Filter scale yang aman: pertahankan rasio, pad hitam jika perlu
SCALE_FILTER="scale=${WIDTH}:${HEIGHT}:force_original_aspect_ratio=decrease,pad=${WIDTH}:${HEIGHT}:(ow-iw)/2:(oh-ih)/2,format=yuv420p"

# ---------- Jalankan FFmpeg ----------
# -g 60 = keyframe tiap 2 detik pada 30fps (rekomendasi YouTube: 2 detik, max 4 detik)
# -preset veryfast = ringan untuk runner GitHub (2 vCPU)
# -f flv = container yang diminta YouTube untuk RTMP/RTMPS
# -stream_loop 1 = file diputar 2 kali total (LOOP 2x), lalu ffmpeg berhenti sendiri.
echo "--- Mulai FFmpeg ---"
echo "Waktu mulai: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"

if [ "$TEST_MODE" = "1" ]; then
  set +e
  timeout "$TEST_SECONDS" ffmpeg -hide_banner \
    -re -stream_loop 1 -i "$VIDEO_FILE" \
    -vf "$SCALE_FILTER" \
    -c:v libx264 -preset veryfast -b:v "$VBITRATE" -maxrate "$MAXRATE" -bufsize "$BUFSIZE" \
    -pix_fmt yuv420p -g 60 -r 30 \
    -c:a aac -b:a 128k -ar 44100 \
    -f flv "$OUTPUT" -y
  code=$?
  set -e
  # timeout mengembalikan 124 kalau proses dimatikan setelah waktu habis = normal untuk test ini
  echo "FFmpeg test selesai, exit code: $code (124 = dihentikan timeout, normal)"
  if [ -s "$OUTPUT" ]; then
    echo "OK: $OUTPUT terbentuk, ukuran $(du -h "$OUTPUT" | cut -f1)"
    ffprobe -v error -show_entries format=duration,size -show_entries stream=codec_name,width,height -of default=noprint_wrappers=1 "$OUTPUT"
    echo "TEST BERHASIL: perintah encoding valid."
  else
    echo "GAGAL: $OUTPUT tidak terbentuk / kosong" >&2
    exit 1
  fi
else
  DURATION_SECONDS=$((DURATION_MINUTES * 60))
  echo "Streaming selama max $DURATION_MINUTES menit (video loop 2x = ±221 menit), lalu berhenti otomatis."
  echo "Untuk berhenti manual: GitHub Actions > run ini > Cancel run."
  set +e
  timeout "$DURATION_SECONDS" ffmpeg -hide_banner -loglevel info \
    -re -stream_loop 1 -i "$VIDEO_FILE" \
    -vf "$SCALE_FILTER" \
    -c:v libx264 -preset veryfast -b:v "$VBITRATE" -maxrate "$MAXRATE" -bufsize "$BUFSIZE" \
    -pix_fmt yuv420p -g 60 -r 30 \
    -c:a aac -b:a 128k -ar 44100 \
    -f flv "$OUTPUT"
  code=$?
  set -e
  echo "FFmpeg berhenti, exit code: $code (124 = durasi habis, normal. 0 = selesai 2x putaran. Lainnya = cek log di atas)"
  echo "Waktu selesai: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
  if [ "$code" -ne 0 ] && [ "$code" -ne 124 ]; then
    echo "Kemungkinan penyebab: Stream Key salah / YouTube belum Go Live / video rusak / koneksi putus." >&2
    exit "$code"
  fi
fi
