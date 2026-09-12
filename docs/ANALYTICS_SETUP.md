# Firebase Analytics 導入 — セットアップ手順

`docs/ASKEN_GROWTH_CASE_STUDY.md` §6・`docs/DEFENSIBILITY.md` §4が指摘した
「計測が1行も無い」状態を解消するため、Firebase Analytics（Google Analytics
for Firebase）を導入した。**無料**で、イベント数の上限なくログを送れる
（詳細は[公式の料金ページ](https://firebase.google.com/pricing)を参照。有料なのは
BigQueryへの生データエクスポート等の追加機能で、標準の集計・ダッシュボード閲覧は無料）。

このドキュメントは**Xcodeでの作業手順**（コードはこの変更で既に実装済み）をまとめる。
実装したコードの内容は [`Services/AnalyticsService.swift`](../Services/AnalyticsService.swift) を参照。

---

## 前提：EventSnapはFirebaseを一度も使っていない

Rotashと違い、EventSnapはCloudKitのみでFirebaseを使ったことがない。
**新しくFirebaseプロジェクトを1つ作る必要がある。**

---

## 1. Firebaseコンソールでの作業

1. [Firebaseコンソール](https://console.firebase.google.com/)を開き、
   「プロジェクトを追加」から新しいプロジェクトを作る（例: `EventSnap`）
   - Google アナリティクスの有効化を聞かれたら**有効にする**（今回の目的そのもののため）
2. プロジェクトが作られたら、左上の歯車アイコン →「プロジェクトの設定」を開く
3. 「マイアプリ」セクションで「アプリを追加」→ iOSのアイコンを選ぶ
4. 「iOSバンドルID」に **`app.takaoka.com.EventSnap2`**（`project.yml`の
   `PRODUCT_BUNDLE_IDENTIFIER`と同じ値。App Clip・Widgetのバンドルidではなく、
   **メインアプリ本体**のもの）を入力する。ニックネームは任意（例: EventSnap）
5. 「アプリを登録」を押すと、**`GoogleService-Info.plist`** というファイルが
   ダウンロードできるようになる。これをダウンロードしておく
   （この後のXcode作業で使う）
6. 「Firebase SDKを追加」という画面が出るが、**その先の指示は無視してよい**
   （このドキュメントの手順3で改めて説明する）。「次へ」を押して登録を完了する

---

## 2. `GoogleService-Info.plist` をXcodeプロジェクトに追加する

1. Xcodeで `EventSnap2.xcodeproj` を開く
2. 左のファイルナビゲータで、**`EventSnap2` メインアプリのグループ**
   （`EventSnapWidget`や`EventSnapClip`ではない方）を右クリック →
   「Add Files to "EventSnap2"...」
3. 手順1でダウンロードした `GoogleService-Info.plist` を選択する
4. ダイアログで以下を必ず確認してからAddを押す：
   - **「Copy items if needed」にチェックが入っている**
   - **「Add to targets」で `EventSnap2`（メインアプリ）だけにチェックが入っている**
     （`EventSnapWidget`・`EventSnapClip`にはチェックしない。今回は
     メインアプリだけに計測を入れるため）

> **Gitへのコミットについて**：`GoogleService-Info.plist`は秘密鍵ではなく、
> Rotashの`SyncConfig.swift`にあるFirebase APIキーと同じ性質の
> 公開前提のクライアント設定値。このプロジェクトは一人で開発しているため、
> **そのままコミットして問題ない。**

---

## 3. Firebase SDKをXcodeに追加する（File > Add Package Dependencies）

**重要**：`project.yml`は現在3ターゲット構成（メインアプリ・Widget・App Clip）を
反映しておらず、実際のビルドは`.xcodeproj`を直接開いて行っている。
**`xcodegen generate`は実行しないこと**（実行すると`project.yml`に書かれていない
Widget/App Clipターゲットが消えてしまう）。そのため`project.yml`は今回変更せず、
**Xcodeのパッケージ管理から直接追加する。**

1. Xcodeのメニューから **File → Add Package Dependencies...** を選ぶ
2. 右上の検索欄に以下のURLを貼り付ける：
   ```
   https://github.com/firebase/firebase-ios-sdk
   ```
3. 「Dependency Rule」は **Up to Next Major Version** のまま、バージョンは
   `11.0.0` 以上を指定してAddを押す
4. パッケージの内容が表示されたら、**「Add to Target」の列で
   `EventSnap2`（メインアプリ）にだけ**、以下の2つのProductを追加する：
   - **FirebaseCore**
   - **FirebaseAnalytics**
   （`EventSnapWidget`・`EventSnapClip`には追加しない。
   他のProductにもチェックしない）
5. 「Add Package」を押すと、ダウンロード・リンクが始まる（数分かかることがある）

---

## 4. ビルドして確認する

1. 実機（またはシミュレータ）でビルド・実行する
2. コンソールログに `📊 event_created [...]` のような行が、
   イベント作成・参加・撮影・Event Reel生成・シェアのたびに出ていれば、
   計測コードは動いている（`AnalyticsService.swift`がDEBUGビルドで
   `print`するようにしてある）

### FirebaseコンソールでリアルタイムのDebugViewを見る

通常のAnalyticsレポートは**反映まで最大24時間かかる**。今すぐ動作確認したい場合は
DebugViewを使う。

1. Xcodeで **Product → Scheme → Edit Scheme...** を開く
2. 「Run」→「Arguments」タブ →「Arguments Passed On Launch」に以下を追加：
   ```
   -FIRAnalyticsDebugEnabled
   ```
3. アプリを実行し、Firebaseコンソール →「Analytics」→「DebugView」を開く
4. 操作するたびに、送信したイベント（`event_created`等）がほぼリアルタイムで
   表示される
5. **確認が終わったら、Schemeに追加した`-FIRAnalyticsDebugEnabled`は削除しておく**
   （付けたままだと通常の集計データにデバッグ扱いの印がついてしまう）

---

## 5. 現時点で計測できていないもの（限界）

- **App Clipでの閲覧そのもの**：App ClipにはFirebase SDKを追加していない
  （追加する場合は容量制限等App Clip特有の対応が別途必要になるため、今回は見送った）。
  そのため「QRを見た人のうち何%がApp Clipプレビューまで到達したか」は計測できず、
  `event_joined`（フルアプリでの参加）から先しか見えない
- **Event Reelの共有完了**：`SocialCardShareView`は`ShareLink`（SwiftUI標準API）を
  使っており、Rotashの`work_share_completed`のような「実際に送信されたか」の
  判定ができない。計測できるのは「シェアボタンを押した」という事実まで

これらは`docs/DEFENSIBILITY.md`のMUST/SHOULD整理と合わせて、
今後の改善候補として記録しておく。

---

## 6. App Store Connect側で必要になる設定

Firebase Analyticsを追加すると、**2つの別々の仕組み**でプライバシー対応が必要になる。
混同しやすいので分けて説明する。

### 6-1. Privacy Manifest（`PrivacyInfo.xcprivacy`）— コードレベルの申告

Appleは2024年5月以降、`UserDefaults`のような「Required Reason API」を使うアプリに、
その理由をアプリ自身の`PrivacyInfo.xcprivacy`で申告するよう義務付けている。

**Firebase SDK自身が使うAPIは、Firebase側が自分のマニフェストを既に同梱しているため
対応不要。** ただし、**EventSnap自身のコード**が`UserDefaults`を多数の場所
（`DeviceIdentity.swift`・`NotificationService.swift`・`EventRepository.swift`等）で
直接使っており、しかも既存の`PrivacyInfo.xcprivacy`はこの申告が**空のまま**だった
（Firebase追加とは無関係に、以前から埋まっていなかった申告）。

今回、以下の2つの理由コードを追加した：

- **`CA92.1`**：アプリ自身だけがアクセスする設定値の読み書き（通常の`UserDefaults.standard`）
- **`1C8F.1`**：App Groupを介して、Widget/Live Activityと共有する設定値の読み書き
  （`EventSnapSharedState.swift`が`UserDefaults(suiteName:)`でApp Groupを使っているため）

この変更はメインアプリの`PrivacyInfo.xcprivacy`のみに対するもの。
`EventSnapWidget`・`EventSnapClip`が別途独自の`PrivacyInfo.xcprivacy`を持っている場合は、
そちらは今回変更していないので、別途確認が必要な場合がある。

### 6-2. App Store Connectの「App Privacy」（プライバシー"栄養成分表示"）— 手動の申告

これは`.xcprivacy`ファイルとは別物で、**App Store Connectの管理画面で手作業で
回答するアンケート**。App Store公開ページに表示される、あの表のことである。

Firebase Analyticsを追加すると、一般的に次のような申告が必要になる
（Google公式ガイド[Prepare for Apple's App Store data disclosure requirements](https://firebase.google.com/docs/ios/app-store-data-collection)に
最新の対応表がある。**このページを直接確認してから回答すること**。この文書を書いた
時点ではネットワーク制限により当該ページを直接開けなかったため、正確な最新表現は
必ず公式ページで確認してほしい）：

| データ種別 | 目的 | 備考 |
|---|---|---|
| 識別子（デバイスID相当） | 分析（Analytics） | Firebaseの「App Instance ID」がこれに該当 |
| 使用状況データ（製品とのやり取り） | 分析（Analytics） | どの画面・操作が行われたか |

**トラッキング（Appleが定義する意味でのTracking）には該当しない。**
EventSnapは広告SDK（Google Mobile Ads等）を導入しておらず、広告IDを収集する設定も
していない。Apple ATT（App Tracking Transparencyのポップアップ）は、**他社アプリ・
Webサイトを横断してユーザーを追跡する場合**にのみ必要で、自社アプリの利用状況を
見るだけのFirebase Analyticsは対象外である。**`NSUserTrackingUsageDescription`の
追加やATT許諾ダイアログの実装は不要。**

### 6-3. プライバシーポリシーのURL

App Store Connectでアプリ情報を登録する際、データを収集するアプリには
**プライバシーポリシーのURL**の入力が必須になる。現時点（TestFlight配布前）では
急ぎではないが、実際に配布する段階では必要になる。

### 6-4. 今すぐやる必要があるか

**いいえ。** これらはすべて「App Store Connectで審査に出す・TestFlightで
社外の人に配布する」段階で必要になるものであり、**今のように自分の端末で
ビルド・実行して試すだけの段階では一切関係ない。**

---

## 7. 今後の運用について

- 追加したイベントと、それが`docs/DEFENSIBILITY.md` §4のどの指標に対応するかは
  `Services/AnalyticsService.swift`のコメントを参照
- 新しいイベントを増やしたくなったら、**まず「それがJoin/First Photo/Contribution/
  Reel Generation/Reel Share/Repeat Organizerのどれに効くか」を先に言葉にしてから
  追加する**
- 配布段階が近づいたら、§6-2の申告内容をGoogle公式ページで再確認し、
  `PrivacyInfo.xcprivacy`の`NSPrivacyCollectedDataTypes`（現在は空のまま）も
  合わせて埋める
