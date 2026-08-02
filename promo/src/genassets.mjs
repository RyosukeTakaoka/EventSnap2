// 動画素材の下ごしらえ:
//  1) 実際に読み取れるQRコードをSVGで生成
//  2) assets/ 配下にユーザーが置いた差し替え素材をスキャンして manifest.json に書き出す
//
// ここで作った manifest.json を capture.mjs が scene.html に注入する。
// 素材が無いスロットは scene.html 側が自動でモックにフォールバックする。

import { mkdirSync, writeFileSync, readdirSync, existsSync } from "node:fs";
import { join, dirname, extname } from "node:path";
import { fileURLToPath } from "node:url";
import QRCode from "qrcode";

const SRC = dirname(fileURLToPath(import.meta.url));
const ROOT = join(SRC, "..");
const GEN = join(SRC, "gen");
const ASSETS = join(ROOT, "assets");

mkdirSync(GEN, { recursive: true });

// ---- 1) QRコード ------------------------------------------------------------
// QRCodeView.swift が生成するURL形式に合わせる:
//   https://<domain>/event/<eventID>
const QR_URL =
  process.env.PROMO_QR_URL || "https://eventsnap.app/event/8F3A21C7-EVENT";

const qrSvg = await QRCode.toString(QR_URL, {
  type: "svg",
  errorCorrectionLevel: "M",
  margin: 0,
  color: { dark: "#000000", light: "#00000000" },
});
writeFileSync(join(GEN, "qr.svg"), qrSvg);

// ---- 2) 差し替え素材のスキャン ------------------------------------------------
const IMG = new Set([".png", ".jpg", ".jpeg", ".webp"]);
const AUD = new Set([".m4a", ".mp3", ".wav", ".aac"]);

/** dir 内の該当拡張子ファイルを、scene.html から見た相対パスで返す */
function scan(dir, exts) {
  const abs = join(ASSETS, dir);
  if (!existsSync(abs)) return [];
  return readdirSync(abs)
    .filter((f) => !f.startsWith(".") && exts.has(extname(f).toLowerCase()))
    .sort()
    .map((f) => `../assets/${dir}/${f}`);
}

/** screens/ から特定の画面名の差し替えを探す (例: qr.png / 01_qr.jpg どちらでもヒット) */
function screenFor(name) {
  return scan("screens", IMG).find((p) =>
    p.split("/").pop().toLowerCase().includes(name),
  ) ?? null;
}

const manifest = {
  qrUrl: QR_URL,
  // イベント参加者が撮った写真 → アルバムのグリッドとカメラのプレビューに使う
  photos: scan("photos", IMG),
  // 実機スクリーンショットがあればモックUIの代わりに使う
  screens: {
    qr: screenFor("qr"),
    scan: screenFor("scan"),
    camera: screenFor("camera"),
    album: screenFor("album"),
  },
  // App Store 公式バッジ (Apple配布物を置いた場合のみ使用)
  badge: scan("badges", IMG).find((p) =>
    /appstore|app_store|app-store/i.test(p),
  ) ?? null,
};

writeFileSync(join(GEN, "manifest.json"), JSON.stringify(manifest, null, 2));

// 音声は ffmpeg 側で直接使うので、パスだけ標準出力に出す
const music = scan("music", AUD);
console.log(`✅ QRコード生成: ${QR_URL}`);
console.log(`   写真素材      : ${manifest.photos.length}枚 ${manifest.photos.length ? "" : "(モック使用)"}`);
console.log(`   実機スクショ  : ${Object.entries(manifest.screens).filter(([, v]) => v).map(([k]) => k).join(", ") || "なし (モックUI使用)"}`);
console.log(`   App Storeバッジ: ${manifest.badge ?? "なし (汎用バッジを描画)"}`);
console.log(`   BGM           : ${music[0] ?? "なし (無音で書き出し)"}`);
