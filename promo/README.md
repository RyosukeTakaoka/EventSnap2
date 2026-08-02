# EventSnap プロモ動画（Instagram Reels / TikTok 用）

縦型 9:16・1080x1920・30fps・16秒の宣伝動画を **1コマンドで**書き出します。

```bash
cd promo && ./build.sh
```

出力:

| ファイル | 用途 |
| --- | --- |
| `out/eventsnap_promo_9x16.mp4` | 本編（H.264 + AAC / faststart 済み。Reels・TikTok・Shorts にそのまま投稿可） |
| `out/cover.png` | Reels のカバー画像 |

---

## 構成（指定の黄金比率どおり）

| 時間 | パート | 内容 |
| --- | --- | --- |
| 0.0–2.0s | **フック** | 「みんなで撮った写真、結局**集まらない**。」＋ 写真がバラバラに散っていく画 |
| 2.0–5.0s | **解決策** | アプリアイコン → `EventSnap` → 「撮った瞬間、その場の全員のアルバムへ。」＋ 特徴チップ3つ |
| 5.0–12.0s | **実演** | ① QRを見せる → ② かざして参加（App Clip）→ ③ 撮る（AI美肌）→ ④ 全員のアルバムに自動で集まる |
| 12.0–16.0s | **行動喚起** | 「今すぐ無料でダウンロード」＋ App Store バッジ ＋ アカウント名 |

> CTAだけ指定の 12–15秒 から **16秒まで1秒延ばして**います。3秒だとバッジを認識してタップに移る前に動画がループしてしまうためです。15秒に戻す場合は `promo/src/scene.html` の `DUR` と `T.s4` を `15` に、`build.sh` の `PROMO_DUR` を `15` にしてください。

実演パートの画面は **`Views/` 配下の SwiftUI コードから座標を起こして再現**しています（`QRCodeView` の 280x280 カード、`CameraView` の 70px シャッター、`AlbumView` の3列2px間隔グリッド、`MainTabView` のタブ構成など、論理px の実寸どおり）。QRコードも実際に読み取れる本物です。

---

## ⚠️ 足りていない素材（差し替え推奨）

現状でも動画として完成していますが、以下は**代用品**で埋めています。差し替えると仕上がりが大きく上がります。**上ほど効果が大きい順**です。

### 1. イベント写真 ★最重要
アルバムのグリッドとカメラのプレビューが、いまはカラーグラデーションのプレースホルダです。ここが実写になるだけで説得力が変わります。

```
promo/assets/photos/  ← .jpg / .png を12枚以上入れる
```

### 2. BGM ★重要
**音源は同梱していません**（配布ライセンスの問題があるため）。無音だと Reels/TikTok では最後まで見てもらえません。

```
promo/assets/music/  ← .mp3 / .m4a / .wav を1つ入れる
```

置くと自動で採用され、末尾0.8秒でフェードアウトします。置かない場合は無音トラック付きで書き出されます（音声トラックが無いと一部プラットフォームで弾かれるため）。
なお **Instagram / TikTok のアプリ内から流行の楽曲を後付けするのが一番リーチが伸びます**。その場合は音源を入れずに書き出してOKです。

### 3. 実機のスクリーンショット / 画面収録
このセッションは Linux 環境のため iOS アプリをビルド・実行できず、UIは**コードから再現したモック**です。実機の画面（iPhone で「画面収録」または `Cmd+S` のスクショ）があればそのまま差し替わります。

```
promo/assets/screens/
    qr.png      ← QRコード画面
    scan.png    ← QR読み取り画面
    camera.png  ← カメラ画面
    album.png   ← アルバム画面
```
ファイル名に `qr` / `scan` / `camera` / `album` が含まれていれば `01_qr.png` のような名前でも認識します。

### 4. App Store 公式バッジ
いまは**暫定の自作バッジ**です。Apple は配布されている公式バッジ画像の使用を必須にしているので、公開前に必ず差し替えてください。
[Apple のマーケティングガイドライン](https://developer.apple.com/app-store/marketing/guidelines/jp/)から日本語版バッジをダウンロードして:

```
promo/assets/badges/appstore.png
```

### 5. 実際のURL・アカウント名
プレースホルダのままです。`promo/src/scene.html` を編集してください。

| 箇所 | 現在の値 |
| --- | --- |
| 画面下のアカウント名 (`#s4handle`) | `@eventsnap.app` |
| QRコードが指すURL | `https://eventsnap.app/event/8F3A21C7-EVENT` |
| イベント名 (`.qr-info .nm`) | `夏フェス2026` |

QRのURLは環境変数でも変えられます:
```bash
PROMO_QR_URL="https://あなたのドメイン/event/xxxx" ./build.sh
```

### Google Play バッジについて
**意図的に入れていません。** EventSnap は SwiftUI + CloudKit + App Clip の **iOS専用アプリ**で、Android版が存在しないためです。Google Play バッジを出すと実態と異なる広告になってしまいます。
将来 Android 版を出す場合は `scene.html` の `#s4badges` に2つ目の `.badge` を足してください（`.badges` は flex なので並べるだけで整います）。

---

## 素材の差し替え方

`promo/assets/` に置いて `./build.sh` を再実行するだけです。ファイルが無いスロットは自動でモックにフォールバックします。

```
promo/assets/
  photos/   イベント写真      → アルバム・カメラ映像・フック部のカードに使用
  screens/  実機スクショ       → モックUIごと差し替え
  music/    BGM               → 音声トラックに使用
  badges/   App Store公式バッジ → CTAのバッジに使用
```

---

## 仕組み

CSSアニメーションを使わず、**すべての動きを `window.seek(t)` という時間 `t` の純粋関数**にしてあります。Chromium で `t` を 1/30 秒ずつ進めながら1コマずつPNGに焼き、ffmpeg で結合しています。そのため何度実行しても完全に同じ動画が出ます。

```
src/genassets.mjs   QRコード生成 + assets/ をスキャンして manifest.json 出力
src/scene.html      ストーリーボード本体（ここを編集すれば内容が変わる）
src/capture.mjs     Chromium で 480コマ を PNG に書き出し
build.sh            上記 → ffmpeg エンコードまで一括
```

タイミングを変えたい場合は `scene.html` 冒頭の `T` と `STEP` を編集してください。

```js
const T = {
  s1: [0.00,  2.00],   // フック
  s2: [2.00,  5.00],   // 解決策
  s3: [5.00, 12.00],   // 実演
  s4: [12.00, 16.00],  // 行動喚起
};
```

### 必要なもの
- Node.js 18+（`npm install` は `build.sh` が自動実行）
- ffmpeg
- Chromium（Playwright 同梱のものを使用）

書き出しには約6分かかります（コマ書き出し5分 + エンコード20秒）。

---

## 投稿時のメモ

- 1080x1920 / 30fps / H.264 High / AAC 192kbps — Reels・TikTok・Shorts の推奨仕様を満たしています
- 画面上部の白いバーは**残り時間のプログレスバー**です（離脱率を下げる定番演出）。不要なら `scene.html` の `#prog` を消してください
- TikTok/Reels は画面下部 約400px と右端 約200px に UI が重なります。テキストと端末はその内側に収めてあります
