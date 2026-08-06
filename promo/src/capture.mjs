// scene.html の window.seek(t) を 1/FPS 秒ずつ進めて 1コマずつPNGに焼く。
// CSS animation を使わず時間の純粋関数にしてあるので、何度回しても同じ絵になる。

import { chromium } from "playwright";
import { mkdirSync, rmSync, readFileSync, existsSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const SRC = dirname(fileURLToPath(import.meta.url));
const GEN = join(SRC, "gen");
const FRAMES = join(GEN, "frames");

const W = 1080, H = 1920;
const FPS = Number(process.env.PROMO_FPS ?? 30);
const DUR = Number(process.env.PROMO_DUR ?? 16);
const TOTAL = Math.round(FPS * DUR);

rmSync(FRAMES, { recursive: true, force: true });
mkdirSync(FRAMES, { recursive: true });

const manifest = JSON.parse(readFileSync(join(GEN, "manifest.json"), "utf8"));
const qrSvg = existsSync(join(GEN, "qr.svg")) ? readFileSync(join(GEN, "qr.svg"), "utf8") : "";

const browser = await chromium.launch({
  args: ["--force-color-profile=srgb", "--font-render-hinting=none", "--disable-lcd-text"],
});
const page = await browser.newPage({
  viewport: { width: W, height: H },
  deviceScaleFactor: 1,
});

// scene.html のインラインスクリプトより先に素材を渡す
await page.addInitScript(
  ([m, q]) => { window.__MANIFEST__ = m; window.__QR_SVG__ = q; },
  [manifest, qrSvg],
);

await page.goto(pathToFileURL(join(SRC, "scene.html")).href, { waitUntil: "load" });
await page.waitForFunction(() => document.documentElement.dataset.ready === "1");
await page.waitForTimeout(400); // 画像/フォントの解決待ち

const pad = n => String(n).padStart(5, "0");
const t0 = Date.now();

for (let i = 0; i < TOTAL; i++) {
  const t = i / FPS;
  await page.evaluate(tt => window.seek(tt), t);
  await page.screenshot({ path: join(FRAMES, `f${pad(i)}.png`), type: "png" });

  if (i % 30 === 0 || i === TOTAL - 1) {
    const pct = ((i + 1) / TOTAL * 100).toFixed(0);
    process.stdout.write(`\r  フレーム書き出し ${i + 1}/${TOTAL} (${pct}%)  `);
  }
}

await browser.close();
console.log(`\n✅ ${TOTAL}コマ / ${DUR}秒 @ ${FPS}fps  (${((Date.now() - t0) / 1000).toFixed(1)}s)`);
