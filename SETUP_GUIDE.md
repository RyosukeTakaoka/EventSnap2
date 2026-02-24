# EventSnap セットアップガイド

このガイドでは、EventSnapアプリをゼロから構築する手順を詳しく説明します。

## 目次

1. [環境準備](#環境準備)
2. [Xcodeプロジェクト作成](#xcodeプロジェクト作成)
3. [ファイル追加](#ファイル追加)
4. [CloudKit設定](#cloudkit設定)
5. [動作確認](#動作確認)
6. [よくある問題](#よくある問題)

---

## 環境準備

### 必要なもの

- Mac (macOS Ventura 13.0以上)
- Xcode 15.0以上
- Apple Developer Program アカウント（年間12,980円）
- iPhone/iPad 実機（iOS 16.0以上）2台
- iCloudアカウント

### Apple Developer Programの登録

1. [Apple Developer](https://developer.apple.com/) にアクセス
2. "Account" をクリック
3. Apple IDでサインイン
4. "Enroll" から登録手続き
5. クレジットカードで支払い（年間12,980円）

---

## Xcodeプロジェクト作成

### Step 1: 新規プロジェクト作成

1. Xcodeを起動
2. "Create a new Xcode project" をクリック
3. テンプレート選択:
   - プラットフォーム: **iOS**
   - アプリケーション: **App**
   - 「Next」をクリック

4. プロジェクト設定:
   ```
   Product Name: EventSnap
   Team: (あなたのチームを選択)
   Organization Identifier: com.yourcompany
   Bundle Identifier: com.yourcompany.EventSnap
   Interface: SwiftUI
   Language: Swift
   Storage: None
   ```

5. プロジェクトの保存場所を選択

### Step 2: Deployment Target設定

1. プロジェクトナビゲーター（左側）で `EventSnap` を選択
2. `TARGETS` > `EventSnap` を選択
3. `General` タブ
4. `Deployment Info` セクション:
   - **Minimum Deployments**: `iOS 16.0` に変更
   - **Supported Destinations**: `iPhone` のみにチェック

---

## ファイル追加

### Step 1: 既存ファイルの削除

1. プロジェクトナビゲーターで以下を削除:
   - `ContentView.swift` (右クリック > Delete > Move to Trash)

### Step 2: 生成されたファイルをコピー

#### 方法A: ファインダーからドラッグ&ドロップ

1. Finderでこのリポジトリの `EventSnap/EventSnap/` フォルダを開く
2. すべてのファイルとフォルダを選択
3. Xcodeのプロジェクトナビゲーターにドラッグ&ドロップ
4. オプション設定:
   - ✅ **Copy items if needed**
   - ✅ **Create groups**
   - ✅ **Add to targets: EventSnap**

#### 方法B: 手動でファイル作成

各ファイルをXcodeで手動作成する場合:

1. プロジェクトナビゲーター右クリック > `New Group`
2. グループ名を入力（例: Models）
3. グループ右クリック > `New File`
4. `Swift File` を選択
5. ファイル名を入力（例: Event.swift）
6. このリポジトリの対応ファイルの内容をコピー&ペースト

### Step 3: ファイル構造確認

最終的に以下の構造になっていることを確認:

```
EventSnap/
├── EventSnapApp.swift
├── Info.plist
├── Models/
│   ├── Event.swift
│   ├── Photo.swift
│   └── Participant.swift
├── ViewModels/
│   ├── EventViewModel.swift
│   ├── CameraViewModel.swift
│   └── AlbumViewModel.swift
├── Views/
│   ├── Home/
│   │   ├── HomeView.swift
│   │   ├── QRCodeView.swift
│   │   └── QRScannerView.swift
│   ├── Camera/
│   │   ├── CameraView.swift
│   │   └── FilterPickerView.swift
│   ├── Album/
│   │   └── AlbumView.swift
│   └── Components/
│       └── MainTabView.swift
└── Services/
    ├── QRCodeService.swift
    ├── EventRepository.swift
    ├── PhotoRepository.swift
    └── AIFilterService.swift
```

---

## CloudKit設定

### Step 1: Capabilities追加

1. プロジェクトナビゲーターで `EventSnap` を選択
2. `TARGETS` > `EventSnap` を選択
3. `Signing & Capabilities` タブを開く
4. `+ Capability` ボタンをクリック

#### iCloud を追加

1. リストから `iCloud` を選択
2. Services:
   - ✅ **CloudKit** にチェック
3. Containers:
   - `+ Container` をクリック
   - `iCloud.com.yourcompany.EventSnap` と入力（Bundle IDと同じ）
   - または既存のコンテナを選択

#### Push Notifications を追加

1. `+ Capability` > `Push Notifications`

#### Background Modes を追加

1. `+ Capability` > `Background Modes`
2. 以下にチェック:
   - ✅ **Background fetch**
   - ✅ **Remote notifications**

#### App Groups を追加

1. `+ Capability` > `App Groups`
2. `+` ボタンをクリック
3. `group.com.yourcompany.EventSnap` と入力

### Step 2: Entitlementsファイル確認

`EventSnap.entitlements` が自動生成されているか確認:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.developer.icloud-container-identifiers</key>
	<array>
		<string>iCloud.com.yourcompany.EventSnap</string>
	</array>
	<key>com.apple.developer.icloud-services</key>
	<array>
		<string>CloudKit</string>
	</array>
	<key>aps-environment</key>
	<string>development</string>
	<key>com.apple.security.application-groups</key>
	<array>
		<string>group.com.yourcompany.EventSnap</string>
	</array>
</dict>
</plist>
```

### Step 3: CloudKit Dashboard設定

#### ダッシュボードにアクセス

1. [https://icloud.developer.apple.com/dashboard/](https://icloud.developer.apple.com/dashboard/) を開く
2. Apple IDでサインイン
3. あなたのコンテナ（`iCloud.com.yourcompany.EventSnap`）を選択

#### Development環境を選択

画面上部の環境セレクターで **Development** を選択

#### Event レコードタイプを作成

1. 左メニュー > `Schema` > `Record Types`
2. `+` ボタンをクリック
3. Name: `Event` と入力
4. `Add Field` で以下のフィールドを追加:

| Field Name | Type | Index |
|------------|------|-------|
| id | String | ✅ Queryable, Sortable |
| name | String | - |
| createdAt | Date/Time | ✅ Sortable |
| creatorID | String | - |
| participantIDs | String List | - |
| photoCount | Int(64) | - |
| isActive | Int(64) | - |
| endedAt | Date/Time | - |

5. `Save` をクリック

#### Photo レコードタイプを作成

1. `+` ボタンをクリック
2. Name: `Photo` と入力
3. `Add Field` で以下のフィールドを追加:

| Field Name | Type | Index |
|------------|------|-------|
| id | String | ✅ Queryable, Sortable |
| eventID | String | ✅ Queryable |
| uploaderID | String | - |
| uploadedAt | Date/Time | ✅ Sortable |
| imageAsset | Asset | - |
| thumbnailAsset | Asset | - |
| filterName | String | - |
| aiProcessed | Int(64) | - |

4. `Save` をクリック

#### パーミッション設定

1. 左メニュー > `Security Roles`
2. `World` を選択
3. 権限を設定:
   - Event: **Read** にチェック
   - Photo: **Read** にチェック

4. `Authenticated` を選択
5. 権限を設定:
   - Event: **Read**, **Write**, **Create** にチェック
   - Photo: **Read**, **Write**, **Create** にチェック

---

## 動作確認

### Step 1: ビルド

1. Xcodeでターゲットを実機に設定
2. メニューバー > `Product` > `Build` (または `Cmd + B`)
3. ビルドが成功することを確認

### Step 2: 実機で実行

1. iPhoneをMacに接続
2. Xcodeの上部ツールバーでデバイスを選択
3. `Product` > `Run` (または `Cmd + R`)
4. デバイスで "信頼" を選択
5. アプリが起動することを確認

### Step 3: 基本機能テスト

#### テスト1: イベント作成

1. アプリを起動
2. "新しいイベントを作成" をタップ
3. イベント名を入力
4. QRコードが表示されることを確認

#### テスト2: QR参加（2台目のデバイスで）

1. 2台目のiPhoneでアプリをインストール
2. "QRコードで参加" をタップ
3. 1台目のQRコードを読み取る
4. イベントに参加できることを確認

#### テスト3: 写真撮影

1. カメラタブに移動
2. シャッターボタンをタップ
3. 写真が撮影されることを確認
4. アルバムタブに写真が表示されることを確認

#### テスト4: リアルタイム同期

1. 1台目で写真を撮影
2. 2台目のアルバムタブをリフレッシュ
3. 1台目で撮った写真が表示されることを確認

---

## よくある問題

### ビルドエラー

#### "No such module 'CloudKit'"

**原因**: Capabilitiesでicloud (CloudKit) が有効になっていない

**解決**:
1. `Signing & Capabilities` タブを開く
2. `+ Capability` > `iCloud`
3. `CloudKit` にチェック

#### "Command PhaseScriptExecution failed"

**原因**: Signing certificateの問題

**解決**:
1. `Signing & Capabilities` タブ
2. `Automatically manage signing` にチェック
3. Teamを選択し直す

### 実行時エラー

#### "Account not found" (CloudKit)

**原因**: デバイスでiCloudにサインインしていない

**解決**:
1. 設定 > (ユーザー名) > iCloud
2. Apple IDでサインイン

#### カメラが黒い画面

**原因**: カメラ権限が許可されていない

**解決**:
1. 設定 > EventSnap > カメラ
2. "許可" を選択
3. アプリを再起動

#### 写真が同期されない

**原因**: CloudKit Dashboardの設定が不完全

**解決**:
1. CloudKit Dashboardでレコードタイプを確認
2. Indexが正しく設定されているか確認
3. パーミッションが正しく設定されているか確認

### デバッグ方法

#### CloudKitのレコードを確認

1. CloudKit Dashboard
2. `Data` > `Query Records`
3. Record Type: `Event` または `Photo` を選択
4. `Query` をクリック

#### Xcodeコンソールでログ確認

1. Xcode下部のコンソールエリアを表示
2. "✅" または "❌" でフィルタリング
3. エラーメッセージを確認

---

## 次のステップ

1. AI機能の実装（Vision, CoreML）
2. Live Activityの実装（ActivityKit）
3. UI/UXの改善
4. App Storeへの申請

詳細は [README.md](README.md) を参照してください。

---

## サポート

問題が解決しない場合:

1. このリポジトリのIssuesで検索
2. 新しいIssueを作成
3. Apple Developer Forumsで質問
