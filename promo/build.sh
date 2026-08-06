#!/usr/bin/env bash
# EventSnap 縦型プロモ動画ビルド (Instagram Reels / TikTok 用)
#   出力: promo/out/eventsnap_promo_9x16.mp4  (1080x1920 / 30fps / H.264+AAC)
#
# 使い方:
#   cd promo && ./build.sh
#
# 素材を差し替えたい場合は promo/assets/ にファイルを置いてから再実行するだけ。
# 詳細は promo/README.md を参照。

set -euo pipefail
cd "$(dirname "$0")"

FPS="${PROMO_FPS:-30}"
DUR="${PROMO_DUR:-16}"
OUT_DIR="out"
OUT="$OUT_DIR/eventsnap_promo_9x16.mp4"
FRAMES="src/gen/frames"

mkdir -p "$OUT_DIR"

echo "▶ 1/3  素材を準備"
[ -d node_modules ] || npm install --silent
PROMO_QR_URL="${PROMO_QR_URL:-}" node src/genassets.mjs

echo "▶ 2/3  コマ書き出し (Chromium)"
PROMO_FPS="$FPS" PROMO_DUR="$DUR" node src/capture.mjs

echo "▶ 3/3  エンコード (ffmpeg)"
# BGMは assets/music/ の先頭ファイルを使う。無ければ無音トラックを付ける
MUSIC="$(find assets/music -maxdepth 1 -type f \( -iname '*.mp3' -o -iname '*.m4a' -o -iname '*.wav' -o -iname '*.aac' \) 2>/dev/null | sort | head -n1 || true)"

VIDEO_ARGS=(-framerate "$FPS" -i "$FRAMES/f%05d.png")

if [ -n "$MUSIC" ]; then
  echo "   BGM: $MUSIC"
  AUDIO_IN=(-i "$MUSIC")
  # 末尾0.8秒でフェードアウトし、動画長ぴったりで切る
  AUDIO_FILTER=(-filter:a "afade=t=out:st=$(echo "$DUR - 0.8" | bc):d=0.8,aformat=sample_fmts=fltp:sample_rates=48000:channel_layouts=stereo")
else
  echo "   BGM: なし → 無音トラックを付与 (SNS投稿時に音無し扱いされないため)"
  AUDIO_IN=(-f lavfi -i "anullsrc=channel_layout=stereo:sample_rate=48000")
  AUDIO_FILTER=()
fi

ffmpeg -y -loglevel error -stats \
  "${VIDEO_ARGS[@]}" \
  "${AUDIO_IN[@]}" \
  -t "$DUR" \
  -map 0:v:0 -map 1:a:0 \
  "${AUDIO_FILTER[@]}" \
  -vf "scale=1080:1920:flags=lanczos,format=yuv420p" \
  -c:v libx264 -profile:v high -level 4.0 -preset slow -crf 18 \
  -x264-params "keyint=60:min-keyint=30:scenecut=0" \
  -r "$FPS" \
  -c:a aac -b:a 192k -ar 48000 -ac 2 \
  -movflags +faststart -shortest \
  "$OUT"

# Reelsのカバー画像 (ロゴが出ている 2.9秒地点)
ffmpeg -y -loglevel error -i "$OUT" -ss 2.9 -frames:v 1 "$OUT_DIR/cover.png"

echo
echo "✅ 完成: $OUT"
ffprobe -v error -select_streams v:0 \
  -show_entries stream=width,height,r_frame_rate,codec_name,nb_frames \
  -show_entries format=duration,size -of default=nw=1 "$OUT"
echo "   カバー画像: $OUT_DIR/cover.png"
