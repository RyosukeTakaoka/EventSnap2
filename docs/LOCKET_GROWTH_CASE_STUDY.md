# Locket Widget — 成長事例の深掘りと EventSnap への応用

[`ASKEN_GROWTH_CASE_STUDY.md`](ASKEN_GROWTH_CASE_STUDY.md)・[`TIMETREE_GROWTH_CASE_STUDY.md`](TIMETREE_GROWTH_CASE_STUDY.md)・
[`MIRO_GROWTH_CASE_STUDY.md`](MIRO_GROWTH_CASE_STUDY.md) の続き。

Locketは**ホーム画面ウィジェットへのリアルタイム配信**を成長の核にしたアプリであり、
EventSnapは既に `EventSnapWidget`（ホーム画面ウィジェット＋ロック画面/Dynamic Island Live Activity）
を持っている。**今回の3事例（あすけん・TimeTree・Miro）の中で、最も直接的に接続する事例である。**

## 0. Locketの規模と概要（事実）

| 項目 | 内容 | 出典 |
|---|---|---|
| 実績 | 2022年ローンチ、**8,000万ダウンロード**、DAU 900万超、2024年から黒字化 | [whatastartup.substack.com](https://whatastartup.substack.com/p/he-built-an-app-for-his-girlfriend-and-ended-up-having-80-million-total-downloads) |
| コア体験 | 親しい友達の写真が**ホーム画面ウィジェットに直接届く。アプリを開く必要がない** | 各種情報源 |
| 友達の上限 | 現在20人（以前は10人から引き上げ） | [mrhack.io](https://mrhack.io/is-there-a-limit-of-friends-you-can-add-in-locket-widget-app/) |
| 専用ウィジェット | 「Crush」「Best Friend」など、**特定の1人だけの写真を表示する個別ウィジェット**を設定できる | [mrhack.io](https://mrhack.io/how-to-add-up-to-20-friends-in-locket-widget-app/) |
| TikTok戦略 | ナノ/マイクロインフルエンサーへの一括発注＋自社26アカウントによる毎日の継続投稿で急拡散。動画の10%が中央値の10倍再生、3%超が50倍のバイラル再生 | [Social Growth Engineers](https://www.socialgrowthengineers.com/lockets-26-creators-298m-views-free-hook-dataset) |
| マネタイズ | サブスクリプション＋広告。広告SDK導入後5か月で広告収益+87% | [Moloco事例](https://www.moloco.com/case-studies/locket-widget) |

---

## 1. ウィジェット配信 — EventSnapは既に土台を持っている。使い方が違うだけ

Locketの最大の強みは、**アプリを開かせずに価値を届ける**ことである。
ホーム画面ウィジェットに写真が直接表示され、通知を見て開く手間すら不要になる。

### EventSnapへの示唆：Locketの使い方とEventSnapの使い方は目的が逆

EventSnapの `EventSnapWidget` は既に実装済みだが、その役割はLocketとは異なる。
README記載の機能は「イベントの進行状況を確認し、シャッターやアルバムへワンタップで戻れる」
——つまり**アプリを開かせるための入口**として設計されている。Locketは逆に
**アプリを開かせないこと自体が目的**である。

この違いは意図的であるべきで、**EventSnapがLocket化する必要はない**と判断する。
理由：EventSnapのイベントは**数時間〜数日で完結する一時的な熱量**であり、
Locketのような「1年365日ホーム画面に居座り続ける関係性」とは時間軸が違う。
イベント中はLive Activity/Dynamic Islandが既に「今どうなっているか」を
常時見える形で提供しており、**これはLocketの役割を、イベントという期間限定の文脈で
既に果たしている。**

**→ 判定：現状維持（確認）。** 新しい実装は不要。ただし1点、Locketから借りられる
発想がある：

> Locketは「最新の1枚が常に見える」ことに価値を置いた。EventSnapのウィジェットが
> 現在何を表示しているか（進行状況のテキストか、最新の1枚のサムネイルか）を見直す際、
> **「直近で誰が何を撮ったか」を一目で見せる**方向にウィジェットの表示内容を寄せると、
> Locketと同じ「今何が起きているか」の即時性を、イベントというEventSnap独自の文脈で再現できる。

**→ 判定：SHOULD（ウィジェット表示内容の見直し候補として記録）。**
実装コストは既存 `EventSnapWidget.swift` の表示ロジック変更程度で収まる見込み。

---

## 2. 専用ウィジェット（Crush/Best Friend）— イベント切り替えへの応用

Locketは「Crush」「Best Friend」など、**特定の1人専用のウィジェット**を設定できる。
関係性ごとに個別化されたウィジェットが、それぞれの相手との特別感を強めている。
[（出典）](https://mrhack.io/how-to-add-up-to-20-friends-in-locket-widget-app/)

### EventSnapへの示唆：「今参加している複数イベント」への応用

EventSnapは `EventSwitcherView` により複数イベントを行き来できる
（`docs/ASKEN_GROWTH_CASE_STUDY.md` §0）。Locketの「相手ごとの専用ウィジェット」という発想を、
**「イベントごとの専用ウィジェット」**に読み替えることができる：

```
Locket：友達Aのための専用ウィジェット、友達Bのための専用ウィジェット
EventSnap：文化祭イベントのための専用ウィジェット、旅行イベントのための専用ウィジェット
（複数のイベントに同時参加している場合、ホーム画面に複数個配置できる）
```

現状 `EventSnapWidget` がどのイベントを表示するかは恐らく単一の想定になっている可能性が高い
（未確認）。複数イベントに同時参加するユースケース（例：文化祭当日に、クラスの模擬店イベントと
学年全体イベントの両方に参加している）では、Locketの個別ウィジェットの発想が活きる。

**→ 判定：LATER。** 複数イベント同時参加という利用シーン自体がどれだけ発生するか
不明であり（計測が無い、`ASKEN_GROWTH_CASE_STUDY.md` §6）、優先度は低い。
まず計測を用意し、複数イベント同時参加の頻度を確認してから着手を判断する。

---

## 3. TikTokでの意図的な種まき — 「その場にいた人だけ」の思想と正面から衝突する

LocketはTikTokでナノインフルエンサーに統一フォーマットの動画を大量発注し、
後には自社アカウントで毎日投稿を続けることで急拡散した。
[（出典）](https://www.socialgrowthengineers.com/lockets-26-creators-298m-views-free-hook-dataset)

### EventSnapへの示唆：仕組みとして真似ることはできない

Locketが拡散させたのは**インフルエンサー個人の日常写真**であり、誰の写真でも成立する。
一方EventSnapのEvent Reelやタイムカプセルは、**特定の日に、特定の場所にいた
参加者だけの記録**である。README冒頭が明言する通り、
「招待コードのような、その場にいなくても入れる経路はあえて用意していません」。

第三者（インフルエンサー）にEventSnapのコンテンツを代わりに投稿させることは、
**このプロダクトの前提と正面から矛盾する。** あるインフルエンサーが「EventSnapで
自分のイベントの様子を撮った」という体裁の動画を作ることは可能かもしれないが、
それは**Locketの模倣であって、EventSnapの強みを活かした拡散ではない。**

**→ 判定：DON'T。** Rotash向け資料（[`LOCKET_GROWTH_CASE_STUDY.md`](https://github.com/RyosukeTakaoka/Rotash/blob/main/docs/LOCKET_GROWTH_CASE_STUDY.md) §3）と同じ結論。
ただし、`ASKEN_GROWTH_CASE_STUDY.md` §5 で提案した法人・団体展開（結婚式場等）の文脈でなら、
**実際にEventSnapを使った本物のイベント主催者・参加者が、自分の体験として投稿する**
形は問題ない——それはLocketのような「仕込み」ではなく、TimeTree §4のような
自然な導線（App Clipで先に体験する）の延長線上にある。**両者を混同しないこと。**

---

## 4. 広告によるマネタイズ

LocketはMoloco SDK導入で広告収益を87%伸ばした。
[（出典）](https://www.moloco.com/case-studies/locket-widget)

### EventSnapへの示唆

`ASKEN_GROWTH_CASE_STUDY.md` §5・[`TIMETREE_GROWTH_CASE_STUDY.md`](TIMETREE_GROWTH_CASE_STUDY.md) §5・
[`MIRO_GROWTH_CASE_STUDY.md`](MIRO_GROWTH_CASE_STUDY.md) §1 と同じ結論になる。
広告は「その場にいる人だけで完結する思い出」という体験の純度を下げるため採用しない。

**→ 判定：LATER（既存結論の維持）。**

---

## 5. まとめ

| 節 | 判定 | 既存資料との関係 |
|---|---|---|
| §1 ウィジェット配信 | **現状維持**（役割はLocketと逆）+ **SHOULD**（表示内容の見直し） | EventSnapは既にLive Activityで同等の即時性を持つ |
| §2 専用ウィジェット | **LATER** | 複数イベント同時参加の頻度が不明。計測が先 |
| §3 TikTok意図的な種まき | **DON'T** | Rotash向け資料と同じ結論。「その場にいた人だけ」の原則と衝突 |
| §4 広告マネタイズ | **LATER**（既存結論の維持） | 他3資料と結論一致 |

**この資料の結論：**
Locketは今回の4事例（あすけん・TimeTree・Miro・Locket）の中で、EventSnapの既存機能
（ウィジェット・Live Activity）と最も直接的に接続する事例だった。ただし調べてみると、
**EventSnapは既にLocketの目的（アプリを開かせず即時性を届ける）を、
Live Activityというより強力な形で実現済み**であることが分かった。
新しい実装課題として残るのは§1のウィジェット表示内容の見直し程度であり、
**Locketの最大の武器（TikTokでの意図的な種まき）はEventSnapの根本思想と
正面から衝突するため採用できない**、という否定的な結論も含めて記録した。

---

## 出典

- [From A Gift For His Girlfriend To 80M Downloads — What A Startup (Substack)](https://whatastartup.substack.com/p/he-built-an-app-for-his-girlfriend-and-ended-up-having-80-million-total-downloads)
- [Is there a LIMIT OF FRIENDS you can add in Locket Widget app? — mrhack.io](https://mrhack.io/is-there-a-limit-of-friends-you-can-add-in-locket-widget-app/)
- [How to add up to 20 friends in Locket widget app? — mrhack.io](https://mrhack.io/how-to-add-up-to-20-friends-in-locket-widget-app/)
- [How Locket Widget grew Moloco ad revenue 87% — Moloco Case Study](https://www.moloco.com/case-studies/locket-widget)
- [Locket Used 26 Creators To Get 298M Views — Social Growth Engineers](https://www.socialgrowthengineers.com/lockets-26-creators-298m-views-free-hook-dataset)
