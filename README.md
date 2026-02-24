# EventSnap

イベント専用の一時的な思い出共有アプリ

## 概要

EventSnapは、文化祭・旅行・遊びなどの少人数イベントで、写真をリアルタイムに共有できるiOSアプリです。

### 主な機能

- **QRコードによる即席グループ生成**: アプリ起動と同時にQRコードを表示、友達が読み取るだけで参加
- **撮影と同時の自動共有**: 写真撮影と同時にグループへ自動送信
- **AI顔加工・フィルター**: Vision/CoreMLによる美肌処理と各種フィルター
- **Live Activity連携**: ロック画面でイベントの進行状況を確認

## 技術スタック

- **フロントエンド**: SwiftUI
- **データ同期**: CloudKit (完全無料)
- **カメラ**: AVFoundation
- **AI処理**: Vision + CoreML
- **リアルタイム通知**: ActivityKit

## 必要要件

- Xcode 15.0以上
- iOS 16.0以上
- Apple Developer Program アカウント
- 実機2台以上（テスト用）

## セットアップ手順

### 1. Xcodeプロジェクトの作成

1. Xcodeを開く
2. `File` > `New` > `Project`
3. `iOS` > `App` を選択
4. 以下の設定を入力:
   - Product Name: `EventSnap`
   - Team: あなたのチームを選択
   - Organization Identifier: `com.yourcompany`（任意）
   - Interface: `SwiftUI`
   - Language: `Swift`
   - Minimum Deployment: `iOS 16.0`

### 2. 生成されたファイルをプロジェクトに追加

1. このリポジトリの `EventSnap/EventSnap/` 内のファイルをすべて、Xcodeプロジェクトにドラッグ&ドロップ
2. "Copy items if needed" にチェック
3. フォルダ構造を維持するため "Create groups" を選択

### 3. Capabilities設定

Xcodeで以下のCapabilitiesを有効化:

1. プロジェクトナビゲーターで `EventSnap` を選択
2. `Signing & Capabilities` タブを開く
3. `+ Capability` をクリックして以下を追加:

   - **iCloud**
     - Services: `CloudKit` にチェック
     - Containers: `iCloud.com.yourcompany.EventSnap` を追加

   - **Push Notifications**

   - **Background Modes**
     - `Background fetch` にチェック
     - `Remote notifications` にチェック

   - **App Groups**
     - `group.com.yourcompany.EventSnap` を追加

### 4. CloudKit設定

1. [CloudKit Dashboard](https://icloud.developer.apple.com/dashboard/) にアクセス
2. あなたのアプリのコンテナを選択
3. `Schema` > `Record Types` で以下を作成:

#### Event レコードタイプ
```
Field Name        | Type      | Index
-----------------------------------
id                | String    | Queryable
name              | String    | -
createdAt         | Date/Time | Sortable
creatorID         | String    | -
participantIDs    | String    | -
photoCount        | Int(64)   | -
isActive          | Int(64)   | -
endedAt           | Date/Time | -
```

#### Photo レコードタイプ
```
Field Name        | Type      | Index
-----------------------------------
id                | String    | Queryable
eventID           | String    | Queryable
uploaderID        | String    | -
uploadedAt        | Date/Time | Sortable
imageAsset        | Asset     | -
thumbnailAsset    | Asset     | -
filterName        | String    | -
aiProcessed       | Int(64)   | -
```

4. `Security Roles` タブで `Public` を選択
5. 各レコードタイプの権限を設定:
   - Read: `World`
   - Write: `Authenticated`

### 5. ビルド設定

1. Xcodeでターゲットを実機に設定
2. `Product` > `Build` または `Cmd + B`
3. エラーが出た場合:
   - Bundle Identifierが正しいか確認
   - Team設定が正しいか確認
   - Signing certificateが有効か確認

### 6. 実機でテスト

1. iPhone/iPadを接続
2. Xcodeでデバイスを選択
3. `Product` > `Run` または `Cmd + R`
4. 2台目のデバイスでも同様にインストール
5. 1台目でイベント作成 → QRコード表示
6. 2台目でQRコードを読み取って参加

## トラブルシューティング

### CloudKitエラー

**症状**: "CloudKit error: Account not found"
**解決**: デバイスでiCloudにサインインしているか確認

**症状**: "Permission denied"
**解決**: CloudKit Dashboardでパーミッション設定を確認

### カメラが起動しない

**症状**: 黒い画面のまま
**解決**:
1. Info.plistに `NSCameraUsageDescription` が設定されているか確認
2. デバイスの設定 > プライバシー > カメラ で権限を確認

### ビルドエラー

**症状**: "No such module 'CloudKit'"
**解決**: Capabilitiesで iCloud (CloudKit) が有効になっているか確認

## 開発ロードマップ

### Phase 1: MVP実装（3週間）
- [x] データモデル
- [x] QRコード生成・読み取り
- [x] カメラ撮影
- [x] CloudKit同期
- [x] アルバム表示

### Phase 2: AI機能（2週間）
- [ ] Vision 顔検出
- [ ] 美肌フィルター
- [ ] 基本フィルター実装

### Phase 3: 仕上げ（2週間）
- [ ] Live Activity実装
- [ ] UI/UX改善
- [ ] エラーハンドリング
- [ ] パフォーマンス最適化

### Phase 4: リリース準備（1週間）
- [ ] テスト
- [ ] App Store申請

## ライセンス

このプロジェクトはMITライセンスの下で公開されています。

## 作者

アプリ甲子園2024参加者

## サポート

問題が発生した場合は、Issuesセクションで報告してください。
