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

## 6. 今後の運用について

- 追加したイベントと、それが`docs/DEFENSIBILITY.md` §4のどの指標に対応するかは
  `Services/AnalyticsService.swift`のコメントを参照
- 新しいイベントを増やしたくなったら、**まず「それがJoin/First Photo/Contribution/
  Reel Generation/Reel Share/Repeat Organizerのどれに効くか」を先に言葉にしてから
  追加する**
- App Store提出前に、Firebase Analyticsが要求するプライバシー関連の申告
  （トラッキングの有無等）を`PrivacyInfo.xcprivacy`に反映する必要があるかもしれない。
  現時点（TestFlight配布前）では対応不要
