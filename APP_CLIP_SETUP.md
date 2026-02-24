# App Clip セットアップガイド

このガイドでは、EventSnapにApp Clipを追加する手順を説明します。App Clipを使用すると、ユーザーはアプリをインストールせずにQRコードからイベントに参加できます。

## 📋 必要なもの

- Xcode 15.0以上
- iOS 16.0以上対応の実機
- Apple Developer Program（有料アカウント）
- 自分で管理できるドメイン（テスト用にはローカルでも可）

## 🎯 App Clipとは

App Clipは、アプリの一部を軽量版として提供する機能です：
- **サイズ制限**: 15MB以下
- **即座に起動**: ダウンロード・インストール不要
- **フル機能への誘導**: 完全版アプリのダウンロードを促せる

## 📝 セットアップ手順

### ステップ1: App Clipターゲットを作成

1. Xcodeで `EventSnap2.xcodeproj` を開く
2. プロジェクトナビゲーターで `EventSnap2` プロジェクトを選択
3. 下部の `+` ボタンをクリック → `Target...` を選択
4. `iOS` > `App Clip` を選択
5. 以下を入力:
   - **Product Name**: `EventSnapClip`
   - **Bundle Identifier**: `app.takaoka.com.EventSnap2.Clip`
   - **Embed in Application**: `EventSnap2` を選択
6. `Finish` をクリック

### ステップ2: 作成済みファイルをターゲットに追加

すでに以下のファイルが作成されています：
- `EventSnapClip/EventSnapClipApp.swift`
- `EventSnapClip/EventSnapClipView.swift`
- `EventSnapClip/EventSnapClip.entitlements`
- `EventSnapClip/Info.plist`

これらのファイルをXcodeプロジェクトに追加します：

1. Xcodeのプロジェクトナビゲーターで `EventSnapClip` フォルダを右クリック
2. `Add Files to "EventSnap2"...` を選択
3. `EventSnapClip` フォルダ内の全ファイルを選択
4. **重要**: `Target` で `EventSnapClip` にチェックを入れる
5. `Add` をクリック

### ステップ3: 共有コードをApp Clipターゲットに追加

App Clipでもメインアプリのコードを使用するため、以下のファイルをApp Clipターゲットにも含めます：

1. 以下の各ファイルをクリック → 右側の `File Inspector` を開く
2. `Target Membership` セクションで `EventSnapClip` にもチェックを入れる

**追加が必要なファイル:**
- `Models/Event.swift`
- `Models/Photo.swift`
- `Models/Participant.swift`
- `Services/EventRepository.swift`
- `Services/QRCodeService.swift`
- `ViewModels/EventViewModel.swift`
- `ViewModels/CameraViewModel.swift`
- `Views/Camera/CameraView.swift`
- `Assets.xcassets` (アセットカタログ)

### ステップ4: EntitlementsとInfo.plistを設定

#### App Clipターゲットの設定

1. `EventSnapClip` ターゲットを選択
2. `Signing & Capabilities` タブを開く
3. 以下を確認・追加:

**iCloud**
- Services: `CloudKit` にチェック
- Containers: `iCloud.app.takaoka.com.EventSnap2`

**App Groups**
- `group.app.takaoka.com.EventSnap2`

**Associated Domains**
- `appclips:eventsnap.example.com`
  - ⚠️ 本番環境では自分のドメインに変更してください

**Push Notifications**
- 追加するだけでOK

4. `Build Settings` タブで以下を確認:
   - **Info.plist File**: `EventSnapClip/Info.plist`
   - **Code Signing Entitlements**: `EventSnapClip/EventSnapClip.entitlements`

#### メインアプリのEntitlements更新

メインアプリの `EventSnap.entitlements` には既に以下が追加されています：
```xml
<key>com.apple.developer.associated-domains</key>
<array>
    <string>appclips:eventsnap.example.com</string>
    <string>webcredentials:eventsnap.example.com</string>
</array>
```

### ステップ5: ドメインの設定

#### オプション1: テスト用（ローカル環境）

開発中は実際のドメインがなくてもテストできます：

1. Xcodeで `Local Experiences` を使用
2. `Settings` > `Developer` > `Local Experiences` でApp Clip URLを設定

#### オプション2: 本番環境

実際のドメインを使用する場合：

1. 自分のドメインのルートに `.well-known/apple-app-site-association` ファイルを配置:

```json
{
  "appclips": {
    "apps": ["TEAMID.app.takaoka.com.EventSnap2.Clip"]
  },
  "applinks": {
    "apps": [],
    "details": [
      {
        "appID": "TEAMID.app.takaoka.com.EventSnap2",
        "paths": ["/event/*"]
      }
    ]
  }
}
```

**重要**: `TEAMID` を自分のTeam IDに置き換えてください
- Team IDは Apple Developer Portal で確認できます

2. ファイルをHTTPSで配信（`https://yourdomain.com/.well-known/apple-app-site-association`）

3. すべてのファイルで `eventsnap.example.com` を自分のドメインに置き換える:
   - `EventSnapClip/EventSnapClipApp.swift`
   - `EventSnapClip/EventSnapClip.entitlements`
   - `EventSnap.entitlements`
   - `Views/Home/QRCodeView.swift`

### ステップ6: ビルドとテスト

1. **App Clipターゲットをビルド**
   ```
   Product > Build (Cmd + B)
   ```

2. **実機でテスト**
   - App Clipは実機でのみテスト可能（シミュレータ不可）
   - Scheme を `EventSnapClip` に変更
   - 実機を接続して Run

3. **QRコードでテスト**
   - メインアプリでイベントを作成
   - 生成されたQRコードを別のデバイスでスキャン
   - App Clipが起動することを確認

### ステップ7: App Store Connect設定（リリース時）

App Clipをリリースする際は：

1. App Store Connectでアプリを作成
2. `App Clip` セクションで以下を設定:
   - App Clip Experience URL: `https://yourdomain.com/event/*`
   - Header Image: 3000x2000px
   - Subtitle: App Clipの説明

3. TestFlightでベータテスト
4. App Reviewに提出

## 🔍 トラブルシューティング

### App Clipが起動しない

**確認事項:**
- Associated Domainsが正しく設定されているか
- `.well-known/apple-app-site-association` が正しく配信されているか
- Bundle Identifierが `{メインアプリ}.Clip` の形式になっているか

### ビルドエラー

**よくあるエラー:**
- `No such module 'CloudKit'`
  → Capabilitiesで iCloud (CloudKit) を有効化

- `Cannot find 'Event' in scope`
  → `Models/Event.swift` をApp Clipターゲットに追加

- Signing error
  → Team設定とProvisioning Profileを確認

### URLが認識されない

**デバッグ方法:**
1. Xcodeのコンソールでログを確認
   ```
   📥 App Clip起動 URL: ...
   ✅ イベントID抽出成功: ...
   ```

2. URL形式を確認
   - 正: `https://yourdomain.com/event/{UUID}`
   - 誤: `http://yourdomain.com/event/{UUID}` (HTTPSが必須)

## 📱 使い方

### ユーザー側の流れ

1. **イベント作成者:**
   - メインアプリでイベントを作成
   - QRコードが表示される（App Clip URL付き）

2. **参加者:**
   - QRコードをスキャン（カメラアプリで可）
   - App Clipが自動で起動
   - アプリをインストールせずにイベント参加
   - 写真撮影・共有が可能
   - 完全版アプリのダウンロードを促される

## 🎨 カスタマイズ

### App Clip UIの変更

`EventSnapClip/EventSnapClipView.swift` を編集して、App ClipのUIをカスタマイズできます。

### URLパターンの変更

別のURL形式を使いたい場合：

1. `extractEventID()` 関数を各ファイルで更新
2. `.well-known/apple-app-site-association` のパスを更新
3. QRコード生成部分を更新

### App Storeオーバーレイ

`EventSnapClipView.swift` の `YOUR_APP_STORE_ID` を実際のApp Store IDに変更してください。

## 📚 参考資料

- [Apple公式: App Clips](https://developer.apple.com/app-clips/)
- [Human Interface Guidelines: App Clips](https://developer.apple.com/design/human-interface-guidelines/app-clips)
- [Associated Domains](https://developer.apple.com/documentation/xcode/supporting-associated-domains)

## ⚠️ 注意事項

1. **サイズ制限**: App Clipは15MB以下に抑える必要があります
2. **機能制限**: 一部のAPIはApp Clipでは使用できません
3. **プライバシー**: App Clipでも適切なプライバシーポリシーが必要です
4. **期限**: App Clipのデータは一時的で、自動的に削除されます

## ✅ 完了チェックリスト

- [ ] App Clipターゲットを作成
- [ ] ファイルをプロジェクトに追加
- [ ] 共有コードをターゲットに追加
- [ ] Entitlementsを設定
- [ ] Associated Domainsを設定
- [ ] ドメインに `.well-known/apple-app-site-association` を配置
- [ ] 実機でApp Clipをテスト
- [ ] QRコードからの起動をテスト
- [ ] フルアプリへの移行をテスト
- [ ] App Store Connectで設定（リリース時）

---

何か問題があれば、Xcodeのコンソールログを確認してください。詳細なデバッグ情報が出力されています。
