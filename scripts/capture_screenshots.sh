#!/usr/bin/env bash
# App Store提出用スクリーンショットを5枚、シミュレータから撮影する。
#
#   ./scripts/capture_screenshots.sh [出力先ディレクトリ]
#
# 事前にDebug構成でシミュレータへインストールしておくこと:
#   xcodebuild -project EventSnap2.xcodeproj -scheme EventSnap2 \
#       -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 16 Pro Max' build
#   xcrun simctl install booted <ビルド成果物の.app>
#
# Xcodeから一度Runするのが最も簡単（Schemeの起動引数は不要。このスクリプトが
# `simctl launch`の引数として毎回渡すため）。

set -euo pipefail
cd "$(dirname "$0")/.."

OUT_DIR="${1:-screenshots}"
DEVICE="${SCREENSHOT_DEVICE:-iPhone 16 Pro Max}"
BUNDLE_ID="${SCREENSHOT_BUNDLE_ID:-app.takaoka.com.EventSnap2}"
# Fixture画像の生成とEvent Reelの描画が終わるまでの待ち時間（初回は長めに要る）
SETTLE="${SCREENSHOT_SETTLE:-6}"

SCENES=(
  "albumGrid:01_album"
  "camera:02_camera"
  "timeCapsule:03_time_capsule"
  "eventReel:04_event_reel"
  "invite:05_invite"
)

mkdir -p "$OUT_DIR"

echo "▶ シミュレータを起動: $DEVICE"
xcrun simctl boot "$DEVICE" 2>/dev/null || true
xcrun simctl bootstatus "$DEVICE" -b >/dev/null

echo "▶ ステータスバーを固定 (9:41 / 電波フル / 満充電)"
xcrun simctl status_bar "$DEVICE" override \
  --time "9:41" \
  --dataNetwork wifi \
  --wifiMode active --wifiBars 3 \
  --cellularMode active --cellularBars 4 \
  --batteryState charged --batteryLevel 100

for entry in "${SCENES[@]}"; do
  scene="${entry%%:*}"
  name="${entry##*:}"

  echo "▶ $scene を撮影"
  xcrun simctl terminate "$DEVICE" "$BUNDLE_ID" 2>/dev/null || true
  xcrun simctl launch "$DEVICE" "$BUNDLE_ID" \
    -EventSnapScreenshot 1 \
    -EventSnapScreenshotScene "$scene" >/dev/null

  sleep "$SETTLE"
  xcrun simctl io "$DEVICE" screenshot --type=png "$OUT_DIR/$name.png"
  echo "   → $OUT_DIR/$name.png"
done

xcrun simctl terminate "$DEVICE" "$BUNDLE_ID" 2>/dev/null || true

echo
echo "✅ 完成: $OUT_DIR"
if command -v sips >/dev/null; then
  for f in "$OUT_DIR"/*.png; do
    printf "   %s  " "$(basename "$f")"
    sips -g pixelWidth -g pixelHeight "$f" | awk '/pixel/ {printf "%s ", $2} END {print ""}'
  done
fi
echo
echo "ステータスバーの固定を解除するには:"
echo "  xcrun simctl status_bar \"$DEVICE\" clear"
