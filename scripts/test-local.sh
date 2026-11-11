#!/usr/bin/env bash
# test-local.sh — Uji nyata di laptop/PC sendiri SEBELUM push ke GitHub
# 1. Generate video test 5 detik
# 2. Jalankan stream.sh dalam TEST_MODE (output ke test-output.flv, bukan YouTube)
# 3. Verifikasi file output bisa diputar
# Pakai: bash scripts/test-local.sh
set -euo pipefail
cd "$(dirname "$0")/.."

command -v ffmpeg >/dev/null || { echo "Install dulu ffmpeg: sudo apt install ffmpeg (Ubuntu) / brew install ffmpeg (Mac)"; exit 1; }

echo "=== 1/3 Buat video test ==="
ffmpeg -y -f lavfi -i testsrc=size=1280x720:rate=30:duration=5 \
  -f lavfi -i sine=frequency=440:duration=5 \
  -c:v libx264 -pix_fmt yuv420p -c:a aac -shortest video.mp4
ls -lh video.mp4

echo "=== 2/3 Jalankan stream.sh TEST_MODE ==="
MODE=single QUALITY=720p TEST_MODE=1 TEST_SECONDS=10 bash scripts/stream.sh

echo "=== 3/3 Verifikasi output ==="
ls -lh test-output.flv
ffprobe -v error -show_entries format=duration -show_entries stream=codec_name,width,height -of default=noprint_wrappers=1 test-output.flv
echo ""
echo "TEST LOKAL LULUS. Kalau ini lulus, workflow GitHub-nya juga akan jalan — tinggal isi YT_STREAM_KEY dan VIDEO_URL yang benar."
echo "Bersihkan file test: rm -f video.mp4 test-output.flv"
