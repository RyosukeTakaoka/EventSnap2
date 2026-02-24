# EventSnap プロジェクト構造

このドキュメントでは、EventSnapプロジェクトのファイル構成と各コンポーネントの役割を説明します。

## ディレクトリ構造

```
EventSnap/
├── EventSnap/
│   ├── EventSnapApp.swift          # アプリエントリーポイント
│   ├── Info.plist                  # アプリ設定ファイル
│   │
│   ├── Models/                     # データモデル
│   │   ├── Event.swift            # イベントモデル
│   │   ├── Photo.swift            # 写真モデル
│   │   └── Participant.swift      # 参加者モデル
│   │
│   ├── ViewModels/                 # ビジネスロジック
│   │   ├── EventViewModel.swift   # イベント管理
│   │   ├── CameraViewModel.swift  # カメラ制御
│   │   └── AlbumViewModel.swift   # アルバム管理
│   │
│   ├── Views/                      # UI コンポーネント
│   │   ├── Home/
│   │   │   ├── HomeView.swift     # ホーム画面
│   │   │   ├── QRCodeView.swift   # QR表示画面
│   │   │   └── QRScannerView.swift # QR読取画面
│   │   ├── Camera/
│   │   │   ├── CameraView.swift   # カメラ画面
│   │   │   └── FilterPickerView.swift # フィルター選択
│   │   ├── Album/
│   │   │   └── AlbumView.swift    # アルバム画面
│   │   └── Components/
│   │       └── MainTabView.swift  # メインタブ
│   │
│   └── Services/                   # ビジネスサービス
│       ├── QRCodeService.swift    # QRコード生成
│       ├── EventRepository.swift  # イベントデータ管理
│       ├── PhotoRepository.swift  # 写真データ管理
│       └── AIFilterService.swift  # AI画像処理
│
├── EventSnap.entitlements          # アプリ権限設定
├── README.md                       # プロジェクト説明
├── SETUP_GUIDE.md                 # セットアップ手順
└── .gitignore                      # Git除外設定
```

## コンポーネント説明

### アプリエントリーポイント

#### EventSnapApp.swift
- SwiftUIアプリのメインエントリーポイント
- HomeViewを初期画面として設定

---

### Models（データモデル）

#### Event.swift
**役割**: イベント情報を管理

**プロパティ**:
- `id`: イベント一意識別子
- `name`: イベント名
- `createdAt`: 作成日時
- `creatorID`: 作成者ID
- `participantIDs`: 参加者IDリスト
- `photoCount`: 写真枚数
- `isActive`: アクティブ状態

**主要メソッド**:
- `toRecord()`: CloudKitレコードに変換
- `from(record:)`: CloudKitレコードから変換

#### Photo.swift
**役割**: 写真情報を管理

**プロパティ**:
- `id`: 写真一意識別子
- `eventID`: 所属イベントID
- `uploaderID`: アップロード者ID
- `uploadedAt`: アップロード日時
- `imageURL`: 画像URL
- `filterName`: 適用フィルター名
- `aiProcessed`: AI処理済みフラグ

#### Participant.swift
**役割**: 参加者情報を管理

**プロパティ**:
- `id`: 参加者ID（デバイスID）
- `deviceName`: デバイス名
- `joinedAt`: 参加日時
- `isActive`: アクティブ状態

---

### ViewModels（ビジネスロジック）

#### EventViewModel.swift
**役割**: イベントの作成・参加・管理

**主要メソッド**:
- `createEvent(name:)`: 新規イベント作成
- `joinEvent(eventID:)`: イベント参加
- `refreshEvent()`: イベント情報更新
- `endEvent()`: イベント終了

#### CameraViewModel.swift
**役割**: カメラ撮影とフィルター処理

**主要メソッド**:
- `checkCameraPermission()`: カメラ権限確認
- `setupCamera()`: カメラセッション設定
- `capturePhoto()`: 写真撮影
- `applySelectedFilter(to:)`: フィルター適用

**プロパティ**:
- `selectedFilter`: 選択中のフィルター
- `isProcessing`: 処理中フラグ
- `capturedImage`: 撮影画像

#### AlbumViewModel.swift
**役割**: アルバムの表示と写真管理

**主要メソッド**:
- `fetchPhotos()`: 写真一覧取得
- `setupRealtimeSync()`: リアルタイム同期設定
- `downloadImage(for:)`: 画像ダウンロード

---

### Views（UI コンポーネント）

#### HomeView.swift
**役割**: アプリ起動画面

**機能**:
- イベント作成ボタン
- QRコード読み取りボタン
- グラデーション背景

#### QRCodeView.swift
**役割**: QRコード表示画面

**機能**:
- イベントIDからQRコード生成
- イベント情報表示（参加者数、写真枚数）

#### QRScannerView.swift
**役割**: QRコード読み取り画面

**機能**:
- AVFoundationによるQR読み取り
- スキャンガイド表示
- 振動フィードバック

#### CameraView.swift
**役割**: カメラ撮影画面

**機能**:
- リアルタイムプレビュー
- シャッターボタン
- フィルター選択
- 処理中インジケーター

#### FilterPickerView.swift
**役割**: フィルター選択UI

**機能**:
- ボトムシート表示
- フィルター一覧
- 選択状態の表示

#### AlbumView.swift
**役割**: 写真アルバム画面

**機能**:
- 3列グリッド表示
- Pull to Refresh
- 写真詳細表示

#### MainTabView.swift
**役割**: メインタブナビゲーション

**タブ構成**:
1. QRコード
2. カメラ（デフォルト）
3. アルバム
4. 設定

---

### Services（ビジネスサービス）

#### QRCodeService.swift
**役割**: QRコード生成処理

**主要メソッド**:
- `generateQRCode(from:)`: 文字列からQRコード生成
- `addLogo(to:logo:)`: QRコードにロゴ追加（オプション）

**技術**: CoreImage の CIFilter.qrCodeGenerator()

#### EventRepository.swift
**役割**: イベントデータのCloudKit連携

**主要メソッド**:
- `createEvent(name:)`: イベントをCloudKitに作成
- `joinEvent(eventID:)`: 既存イベントに参加
- `refreshEvent()`: イベント情報を同期
- `endEvent()`: イベントを終了状態に更新

**技術**: CloudKit Public Database

#### PhotoRepository.swift
**役割**: 写真データのCloudKit連携

**主要メソッド**:
- `uploadPhoto(_:eventID:filterName:)`: 写真アップロード
- `fetchPhotos(for:)`: イベントの写真取得
- `setupSubscription(for:)`: リアルタイム更新設定

**技術**:
- CloudKit CKAsset（画像保存）
- CloudKit Subscription（リアルタイム通知）

#### AIFilterService.swift
**役割**: AI画像処理

**主要メソッド**:
- `applyBeautyFilter(to:)`: 美肌フィルター適用
- `detectFaces(in:)`: 顔検出
- `applyBrightnessFilter(to:)`: 明るさ調整
- `applyVintageFilter(to:)`: ビンテージフィルター
- `detectBestSmile(in:)`: ベストスマイル検出（オプション）

**技術**:
- Vision (VNDetectFaceRectanglesRequest)
- CoreImage (CIFilter)

---

## データフロー

### イベント作成フロー

```
HomeView
  ↓ createEvent()
EventViewModel
  ↓ createEvent(name:)
EventRepository
  ↓ save()
CloudKit
  ↓ publish
すべての参加者に通知
```

### 写真撮影フロー

```
CameraView
  ↓ capturePhoto()
CameraViewModel
  ↓ applySelectedFilter()
AIFilterService
  ↓ uploadPhoto()
PhotoRepository
  ↓ save()
CloudKit
  ↓ subscription
AlbumViewModel
  ↓ リアルタイム更新
AlbumView
```

### QR参加フロー

```
QRScannerView
  ↓ スキャン完了
EventViewModel
  ↓ joinEvent(eventID:)
EventRepository
  ↓ CloudKit query
既存イベント取得
  ↓ 参加者リストに追加
CloudKit
```

---

## アーキテクチャパターン

### MVVM (Model-View-ViewModel)

- **Model**: データ構造とビジネスルール（Event, Photo, Participant）
- **View**: UI表示（SwiftUIビュー）
- **ViewModel**: UIとデータの橋渡し（EventViewModel, CameraViewModel, AlbumViewModel）

### Repository パターン

- データソース（CloudKit）の抽象化
- ViewModelはRepositoryを通じてデータにアクセス
- データソースの変更が容易

---

## 今後の拡張

### Phase 2: AI機能強化
- CoreML独自モデルの統合
- 顔のランドマーク検出
- リアルタイムフィルタープレビュー

### Phase 3: Live Activity
- ActivityKit統合
- Dynamic Island対応
- ロック画面ウィジェット

### Phase 4: App Clip
- 軽量版アプリ
- QR参加の簡素化

---

## コーディング規約

### Swift Style Guide
- インデント: 4スペース
- 命名: キャメルケース
- アクセス修飾子: 明示的に記述
- コメント: 日本語OK

### ファイル構成
- 1ファイル1クラス/構造体
- グループ化: MARK コメント使用
- Import順: Foundation → UIKit → その他

### エラーハンドリング
- do-catch で明示的に処理
- print() でログ出力（"✅" or "❌" プレフィックス）
- ユーザーへのエラー表示

---

## テスト戦略

### 単体テスト（今後実装）
- ViewModelのビジネスロジック
- QRCodeServiceの生成処理
- AIFilterServiceのフィルター処理

### 統合テスト
- CloudKitとの連携
- リアルタイム同期
- 複数デバイス間の通信

### UIテスト
- 画面遷移
- ユーザーインタラクション
- エラー状態の表示

---

## パフォーマンス考慮事項

### 画像処理
- 画像リサイズ（最大1920px）
- JPEG圧縮（80%品質）
- サムネイル生成（300px）

### CloudKit
- バッチ処理
- ローカルキャッシュ
- Subscription活用

### メモリ管理
- weak/unowned参照
- ARC（自動参照カウント）
- 大きな画像の適切な解放

---

このドキュメントは、プロジェクトの成長に合わせて更新してください。
