#!/usr/bin/env bash
# stream.sh — Streaming nyata ke YouTube Live via FFmpeg + RTMPS
# Dipakai oleh .github/workflows/live.yml
# Bisa juga dites lokal: TEST_MODE=1 bash scripts/stream.sh
#   (tanpa Stream Key, output ke test-output.flv selama 15 detik)
set -euo pipefail

# ---------- Konfigurasi dari environment / workflow inputs ----------
MODE="${MODE:-single}"                    # single | playlist | image-audio
QUALITY="${QUALITY:-720p}"               # 720p | 1080p | 480p
VIDEO_URL="${VIDEO_URL:-}"
IMAGE_URL="${IMAGE_URL:-}"
AUDIO_URL="${AUDIO_URL:-}"
DURATION_MINUTES="${DURATION_MINUTES:-330}"
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
  OUTPUT="test-output.flv"
  echo "=== TEST MODE: output ke $OUTPUT selama $TEST_SECONDS detik, TIDAK ke YouTube ==="
else
  if [ -z "$YT_STREAM_KEY" ]; then
    echo "ERROR: YT_STREAM_KEY kosong. Isi di GitHub Secrets, jangan tulis di file." >&2
    exit 1
  fi
  # RTMPS (terenkripsi, port 443) — sesuai rekomendasi YouTube 2026.
  # Alternatif plain RTMP: rtmp://a.rtmp.youtube.com/live2/<key>
  OUTPUT="rtmps://a.rtmps.youtube.com:443/live2/${YT_STREAM_KEY}"
  echo "=== LIVE MODE: tujuan YouTube RTMPS (key disembunyikan) ==="
fi

# ---------- Kualitas -> resolusi & bitrate (rekomendasi YouTube) ----------
case "$QUALITY" in
  1080p) WIDTH=1920; HEIGHT=1080; VBITRATE="4500k"; MAXRATE="4500k"; BUFSIZE="9000k" ;;
  480p)  WIDTH=854;  HEIGHT=480;  VBITRATE="1200k"; MAXRATE="1200k"; BUFSIZE="2400k" ;;
  720p|*) WIDTH=1280; HEIGHT=720; VBITRATE="2500k"; MAXRATE="2500k"; BUFSIZE="5000k" ;;
esac
echo "Mode=$MODE Quality=${WIDTH}x${HEIGHT} VideoBitrate=$VBITRATE Durasi=${DURATION_MINUTES} menit"

command -v ffmpeg >/dev/null || { echo "ERROR: ffmpeg tidak ditemukan" >&2; exit 1; }
command -v ffprobe >/dev/null || { echo "ERROR: ffprobe tidak ditemukan" >&2; exit 1; }

# Helper: cek file video valid (ada video stream + audio stream kalau ada)
check_video() {
  local f="$1"
  echo "--- ffprobe $f ---"
  ffprobe -v error -select_streams v:0 -show_entries stream=codec_name,width,height,r_frame_rate -of default=noprint_wrappers=1 "$f"
  ffprobe -v error -select_streams a:0 -show_entries stream=codec_name -of default=noprint_wrappers=1 "$f" || echo "(peringatan: file ini tidak ada audio stream)"
  echo "Ukuran: $(du -h "$f" | cut -f1)"
}

download_file() {
  local url="$1" out="$2"
  echo "Download: $url -> $out"
  curl -L --fail --retry 3 --connect-timeout 30 --max-time 1200 -o "$out" "$url"
  [ -s "$out" ] || { echo "ERROR: download gagal / file kosong: $url" >&2; exit 1; }
}

# Filter scale yang aman: pertahankan rasio, pad hitam jika perlu
SCALE_FILTER="scale=${WIDTH}:${HEIGHT}:force_original_aspect_ratio=decrease,pad=${WIDTH}:${HEIGHT}:(ow-iw)/2:(oh-ih)/2,format=yuv420p"

# ---------- Siapkan input sesuai mode ----------
FFMPEG_INPUT_ARGS=()

if [ "$MODE" = "single" ]; then
  VIDEO_FILE="video.mp4"
  if [ -n "$VIDEO_URL" ]; then
    download_file "$VIDEO_URL" "$VIDEO_FILE"
  elif [ -f "video.mp4" ]; then
    echo "Pakai video.mp4 dari repo"
  elif [ -f "videos/video.mp4" ]; then
    VIDEO_FILE="videos/video.mp4"
    echo "Pakai videos/video.mp4 dari repo"
  else
    echo "ERROR: Tidak ada video. Isi VIDEO_URL saat Run workflow, atau upload video.mp4 (max 100 MB per file GitHub) ke repo." >&2
    exit 1
  fi
  check_video "$VIDEO_FILE"
  # -re = baca real-time, -stream_loop -1 = loop selamanya sampai timeout/dibatalkan
  FFMPEG_INPUT_ARGS=(-re -stream_loop -1 -i "$VIDEO_FILE")

elif [ "$MODE" = "playlist" ]; then
  PLAYLIST_FILE="videos/playlist.txt"
  if [ ! -f "$PLAYLIST_FILE" ]; then
    echo "ERROR: Mode playlist butuh file videos/playlist.txt (satu URL per baris). Lihat videos/playlist.example.txt" >&2
    exit 1
  fi
  mkdir -p videos/downloaded
  : > videos/concat.txt
  i=0
  while IFS= read -r url || [ -n "$url" ]; do
    # Lewati baris kosong & komentar
    url="$(echo "$url" | tr -d '\r' | xargs)"
    [ -z "$url" ] && continue
    case "$url" in \#*) continue ;; esac
    i=$((i+1))
    out="videos/downloaded/part${i}.mp4"
    download_file "$url" "$out"
    check_video "$out"
    echo "file '$out'" >> videos/concat.txt
  done < "$PLAYLIST_FILE"
  [ "$i" -ge 1 ] || { echo "ERROR: playlist.txt kosong" >&2; exit 1; }
  echo "Playlist: $i video, daftar di videos/concat.txt"
  # concat demuxer + loop, lalu re-encode semua ke format yang sama (jangan -c copy, beda codec bisa putus)
  FFMPEG_INPUT_ARGS=(-re -stream_loop -1 -f concat -safe 0 -i videos/concat.txt)

elif [ "$MODE" = "image-audio" ]; then
  IMAGE_FILE="cover.jpg"
  AUDIO_FILE="audio.mp3"
  if [ -n "$IMAGE_URL" ]; then download_file "$IMAGE_URL" "$IMAGE_FILE"; fi
  if [ -n "$AUDIO_URL" ]; then download_file "$AUDIO_URL" "$AUDIO_FILE"; fi
  if [ ! -f "$IMAGE_FILE" ] && [ -f "videos/cover.jpg" ]; then IMAGE_FILE="videos/cover.jpg"; fi
  if [ ! -f "$IMAGE_FILE" ] && [ -f "videos/cover.png" ]; then IMAGE_FILE="videos/cover.png"; fi
  if [ ! -f "$AUDIO_FILE" ] && [ -f "videos/audio.mp3" ]; then AUDIO_FILE="videos/audio.mp3"; fi
  [ -f "$IMAGE_FILE" ] || { echo "ERROR: gambar cover tidak ditemukan (cover.jpg/png atau IMAGE_URL)" >&2; exit 1; }
  [ -f "$AUDIO_FILE" ] || { echo "ERROR: audio tidak ditemukan (audio.mp3 atau AUDIO_URL)" >&2; exit 1; }
  check_video "$AUDIO_FILE" || true
  echo "Gambar: $IMAGE_FILE | Audio: $AUDIO_FILE"
  # -loop 1 = gambar diam, audio di-loop, -shortest dihapus karena loop tak berujung
  FFMPEG_INPUT_ARGS=(-loop 1 -framerate 30 -i "$IMAGE_FILE" -re -stream_loop -1 -i "$AUDIO_FILE")

else
  echo "ERROR: MODE tidak dikenal: $MODE (pilih single / playlist / image-audio)" >&2
  exit 1
fi

# ---------- Jalankan FFmpeg ----------
# -g 60 = keyframe tiap 2 detik pada 30fps (rekomendasi YouTube: 2 detik, max 4 detik)
# -preset veryfast = ringan untuk runner GitHub (2 vCPU)
# -f flv = container yang diminta YouTube untuk RTMP/RTMPS
echo "--- Mulai FFmpeg ---"
echo "Waktu mulai: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"

if [ "$TEST_MODE" = "1" ]; then
  # Uji lokal: batasi 15 detik, output file, cek file terbentuk & bisa diputar
  set +e
  timeout "$TEST_SECONDS" ffmpeg -hide_banner \
    "${FFMPEG_INPUT_ARGS[@]}" \
    -vf "$SCALE_FILTER" \
    -c:v libx264 -preset veryfast -b:v "$VBITRATE" -maxrate "$MAXRATE" -bufsize "$BUFSIZE" \
    -pix_fmt yuv420p -g 60 -r 30 \
    -c:a aac -b:a 128k -ar 44100 \
    -f flv "$OUTPUT" -y
  code=$?
  set -e
  # timeout mengembalikan 124 kalau proses dimatikan setelah waktu habis = normal untuk test ini
  # ffmpeg sendiri keluar 0 kalau selesai sendiri
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
  echo "Streaming selama max $DURATION_MINUTES menit, lalu berhenti otomatis."
  echo "Untuk berhenti manual: GitHub Actions > run ini > Cancel run."
  echo "Cek di YouTube Studio > Live Control Room, tunggu 30-60 detik sampai status Good/Excellent."
  set +e
  timeout "$DURATION_SECONDS" ffmpeg -hide_banner -loglevel info \
    "${FFMPEG_INPUT_ARGS[@]}" \
    -vf "$SCALE_FILTER" \
    -c:v libx264 -preset veryfast -b:v "$VBITRATE" -maxrate "$MAXRATE" -bufsize "$BUFSIZE" \
    -pix_fmt yuv420p -g 60 -r 30 \
    -c:a aac -b:a 128k -ar 44100 \
    -f flv "$OUTPUT"
  code=$?
  set -e
  echo "FFmpeg berhenti, exit code: $code (124 = durasi habis, normal. 0 = selesai. Lainnya = cek log di atas)"
  echo "Waktu selesai: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
  if [ "$code" -ne 0 ] && [ "$code" -ne 124 ]; then
    echo "Kemungkinan penyebab: Stream Key salah / YouTube belum Go Live / video rusak / koneksi putus. Lihat README bagian Troubleshooting." >&2
    exit "$code"
  fi
fi
