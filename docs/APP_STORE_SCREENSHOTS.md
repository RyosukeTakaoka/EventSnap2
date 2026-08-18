# App Store提出用スクリーンショットの撮り方

EventSnapは実データがCloudKit上にあるため、そのままでは「アプリの価値が伝わる
画面」を再現性のある形で作れません。撮影モード（Screenshot Mode）は、
**本番のViewをそのまま使いながら**、固定されたイベント・写真・Event Reelを
注入して、何度撮っても同じ絵が出る状態を作ります。

---

## 1. しくみ

```
起動引数 -EventSnapScreenshot 1
        ↓
ScreenshotMode.isActive              ← Releaseビルドではコンパイル時 false
        ↓
EventSnapApp.init() → PreviewFixtureLoader.install(scene:)
        ↓
 ┌───────────────┬────────────────┬──────────────────┐
 │EventRepository│ PhotoRepository │ ShareCollageStore│  ← 既存シングルトンへ注入
 └───────────────┴────────────────┴──────────────────┘
        ↓  @Published が現在値を即時配信
   本番の AlbumView / CameraView / QRCodeView / SocialCardShareView
```

写真の実体は `Caches/EventSnapPreviewFixtures/` にJPEGとして書き出され、
`Photo.imageURL` にはその `file://` が入ります。CloudKitの `CKAsset.fileURL` と
同じ形なので、**画像読み込みのコード（`PhotoImageLoader`）は一切変更していません。**

撮影モードでは次が実行されません。

| 止めているもの | 場所 |
| --- | --- |
| CloudKitの読み書き | `PhotoRepository.fetchPhotos` / `setupSubscription`、`EventRepository.restoreEvent` / `loadRecentEvents`、`SyncCoordinator.refreshTimeCapsules` |
| 通知許可ダイアログ・ローカル通知予約 | `NotificationService.requestAuthorization` / `scheduleReveals` |
| カメラ権限ダイアログ・キャプチャ | `CameraViewModel.checkCameraPermission` / `startSession` / `capturePhoto` |
| Event Reelの自動生成 | `ShareCollageBuilder.buildIfNeeded` |
| イベントUUIDのデバッグ表示 | `QRCodeView` |

---

## 2. 5つのシーン

| シーン名 | 画面 | 伝える価値 | 構成 |
| --- | --- | --- | --- |
| `albumGrid` | AlbumView | みんなの写真が自動で集まる | 18枚中ロックは2枚だけ。実写がグリッドを埋める |
| `camera` | CameraView | 撮った瞬間に共有される | 「シェアOK」ON。Fixture画像を背景に本番のシャッターUI |
| `timeCapsule` | AlbumView | 一部の写真はあとから届く | 18枚中ロック7枚を**上位3行に集中**。砂時計が主役 |
| `eventReel` | SocialCardShareView | 自動編集されたシェア画像 | 本番の`MultiPhotoRenderer`が描いた1080×1920のReel |
| `invite` | QRCodeView | その場にいた人だけが参加 | 実在URLの本物のQR、12人/128枚 |

`albumGrid` と `timeCapsule` は同じ `AlbumView` を撮ります（専用のタイムカプセル
画面がアプリに無いため）。**写真の構成そのものを変える**ことで、2枚が明確に
別の価値を語るようにしてあります。

---

## 3. 撮影手順（シミュレータ・推奨）

シミュレータを推すのは、**ステータスバーを 9:41 / 電波フル / 満充電に固定できる**
ためです（実機では不可能）。App Storeはスクリーンショットが実機由来であることを
要求していません（実際のUIであることのみ）。

```bash
# ① Debug構成でシミュレータへインストール（Xcodeから一度Runするのが簡単）
# ② 5枚を自動撮影
./scripts/capture_screenshots.sh screenshots
```

機種を変える場合:

```bash
SCREENSHOT_DEVICE="iPhone 15 Pro Max" ./scripts/capture_screenshots.sh
```

### 手で1枚だけ撮る場合

Xcodeの Scheme > Run > Arguments > Arguments Passed On Launch に追加します。

```
-EventSnapScreenshot 1
-EventSnapScreenshotScene timeCapsule
```

`-EventSnapScreenshotScene` に指定できるのは
`albumGrid` / `camera` / `timeCapsule` / `eventReel` / `invite` です。

---

## 4. 必要な解像度

このアプリは `TARGETED_DEVICE_FAMILY = 1`（iPhone専用）なので、**iPad用は不要**です。

| スロット | 解像度 | 機種 |
| --- | --- | --- |
| 6.9"（必須） | 1290 × 2796 または 1320 × 2868 | iPhone 16 Pro Max / 15 Pro Max |
| 6.5"（任意） | 1242 × 2688 | 未指定なら6.9"から自動縮小される |

> App Store Connectが要求する解像度は改定されることがあります。
> **提出直前に App Store Connect の実画面で必ず確認してください。**

---

## 5. 提出前チェックリスト

- [ ] `Preview/Fixtures/README.md` に従って**実写の写真に差し替えた**
      （プレースホルダのグラデーション画像のままでは価値が伝わりません）
- [ ] 写っている人物全員から掲載の同意を得ている
- [ ] イベントUUID・端末名・デバッグ表示が写り込んでいない
- [ ] ステータスバーが 9:41 / 電波フル / 満充電になっている
- [ ] 解像度がApp Store Connectの要求どおり
- [ ] 2回撮って同じ絵になる（下記）

### 再現性の確認

```bash
./scripts/capture_screenshots.sh /tmp/shot-a
./scripts/capture_screenshots.sh /tmp/shot-b
diff <(cd /tmp/shot-a && shasum *.png) <(cd /tmp/shot-b && shasum *.png)
```

差分が出たら、非決定的な要素（乱数・現在時刻依存・Vision解析）が
どこかに混ざっています。

---

## 6. Xcode Canvas での確認

ビルド→起動→タップの往復をせずにレイアウトを詰めたい場合は、
`Preview/ScreenshotScenes.swift` を開いてCanvasを使ってください。
5シーンすべてのPreviewが入っています。

---

## 7. 開発時の注意

- **初回起動は1〜3秒ほど余分にかかります。** 18枚の画像生成とEvent Reel 3件の
  描画を`init()`で同期的に行うためです。2回目以降は画像がキャッシュされます
  （`PreviewImageFactory.version` を上げると作り直されます）。
- 撮影モードは `ShareCollageStore` に実際に書き込みます。ただし書き込み先は
  **固定UUIDのFixtureイベント配下だけ**で、注入のたびに `deleteAll(for:)` して
  から作り直すため、開発中の実イベントのEvent Reelには影響しません。
- `UserDefaults` の `currentEventID` / `joinedEventIDs` / `displayName` は
  一切書き換えません。
- 起動引数を付けない通常のDebug起動は、これまでと完全に同じ挙動です。

---

## 8. Widget / Live Activity のスクリーンショット

現時点では対象外です（5シーンはすべてアプリ内画面）。撮る場合は実機が必要で、
`EventSnapSharedState` にApp Group経由で状態を書き込む処理を追加する必要が
あります。Widgetは完全に受動的（App Groupを読むだけ）な設計なので、
`EventSnapSharedState.updateEventState` / `updateLatestReel` を呼ぶ
シーダーを1つ足せば実現できます。

---

## 9. プロモ動画との連携

`promo/` の縦型プロモ動画パイプラインは、UIを**コードから起こしたHTMLモック**で
再現しています（`promo/README.md` 参照）。ここで撮った実機スクリーンショットを

```
promo/assets/screens/qr.png
promo/assets/screens/camera.png
promo/assets/screens/album.png
```

に置いて `cd promo && ./build.sh` を実行すると、動画側のモック画面も
本物に差し替わります。
