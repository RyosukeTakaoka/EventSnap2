# TimeTree — 成長事例からの構造抽出と EventSnap への応用

[`docs/ASKEN_GROWTH_CASE_STUDY.md`](ASKEN_GROWTH_CASE_STUDY.md) の続き。
今回扱う TimeTree（世界7,000万人の共有カレンダーアプリ）は、あすけん（個人の日々の習慣アプリ）とは
性質が違い、**「複数人が同じ1つのオブジェクト（カレンダー）を共同編集し続ける」**設計である。
EventSnap（複数人が同じ1つのイベントに写真を集め続ける）と構造がかなり近い。

## 0. TimeTreeの規模と概要（事実）

| 項目 | 内容 | 出典 |
|---|---|---|
| 登録ユーザー数 | 2022年8月に4,000万人突破 → 2026年1月発表時点で**世界7,000万人**、200以上の国・地域 | [40million](https://timetreeapp.com/intl/ja/newsroom/2022-08-10/40-million), [TimeTreeリニューアル発表](https://timetreeapp.com/intl/ja/newsroom/2026-01-13/timetree-renewal) |
| コア機能 | 複数人でカレンダーを共有・共同編集。予定の作成・変更がリアルタイム通知され、予定にコメント・写真を添付できる | 各種利用ガイド |
| 招待方法 | カレンダー作成直後に招待画面。**メール・SMS・QRコード・URLの4経路**から選べる | [sungrove.co.jp](https://www.sungrove.co.jp/timetree-share/) |
| 収益モデル | 広告収入 ＋ 2022年開始の有料プラン（広告非表示・カレンダー数拡張・AI機能） | [TimeTreeプレミアム発表](https://timetreeapp.com/intl/ja/newsroom/2022-04-19/timetree-premium) |
| 利用規模の上限 | 1カレンダー最大200人・1アカウント最大20カレンダー。**個人・家族から仕事利用まで同一プロダクトで対応** | [jicoo.com](https://www.jicoo.com/magazine/blog/timetree) |
| セグメント別展開 | 「家族・パートナー」等、利用シーン別に使い方ガイドを多数公開（SEO/コンテンツマーケティング） | [timetreeapp.com/usages](https://timetreeapp.com/intl/ja/usages/category/family-partner) |

---

## 1. 招待が「作成の続き」である設計 — EventSnapは既に体現している

TimeTreeは**カレンダー作成直後に招待画面**を出し、メール・SMS・QR・URLの4経路を用意している。
[（出典）](https://www.sungrove.co.jp/timetree-share/)

### EventSnapへの示唆：確認のみ。むしろEventSnapの方が摩擦が少ない

`docs/ASKEN_GROWTH_CASE_STUDY.md` §0/§4 で既に確認した通り、EventSnapは
**イベント作成と同時にQRコードが表示され**、参加はQRを読むだけである。
さらに**App Clipにより未インストールでも中身を先に見られる**——これはTimeTreeの
「メール・SMS・QR・URL」という複数経路より一歩進んでおり、**「招待を受け取った人が
アプリを持っていなくても離脱しない」**という点でTimeTreeにも無い強みである。

**→ 判定：現状維持（確認）。** 新しい実装は不要。この一致は、EventSnapの招待設計が
7,000万人規模のプロダクトと同じ方向で正しく作られていることの裏付けとして記録しておく。

---

## 2. 予定にコメント・写真が残る — EventSnapの「その場だけ」という制約との違い

TimeTreeでは各予定にコメント・写真を添付でき、**予定が思い出の入れ物になる。**
家族旅行やカップルの記念日の記録として使われている。
[（出典）](https://fukucale.ai/labo/time-tree/how-to-use)

### EventSnapへの示唆：EventSnapは意図的にこれをやっていない。理由を確認する

TimeTreeの「予定というオブジェクトに、後から誰でもコメント・写真を積み重ねられる」設計は、
一見EventSnapのリアクション機能（絵文字）を強化するヒントに見える。
しかし README冒頭の思想を思い出す必要がある：

> 「招待コードのような、その場にいなくても入れる経路はあえて用意していません」

TimeTreeのカレンダーは**時間が経っても誰でも書き足せる、開かれたオブジェクト**である。
一方EventSnapのイベントは、**その場にいた人だけで完結し、後から人を増やさない、
閉じたオブジェクト**として設計されている。この違いは意図的であり、崩すべきではない。

```
TimeTreeの予定：いつでも・誰でも書き足せる（開いている）
EventSnapのイベント：その場にいた人だけの記録（閉じている）
```

**→ 判定：DON'T（「後から誰でもコメントを書き足せる」ような開かれた拡張はしない）。**
現在のリアクション機能（参加者限定・絵文字のみ）は、この閉じた設計の範囲内に収まっており、
変更の必要はない。**TimeTreeとの比較によって、この制約が意図的な設計判断であることを
明文化できた**という点に価値がある。

---

## 3. 個人〜家族〜仕事への用途拡張 — EventSnapに直接使える示唆

TimeTreeは最大200人・20カレンダーまで対応することで、
**個人 → 家族 → カップル → 仕事**へと、同一プロダクトのまま用途を広げてきた。
[（出典）](https://www.jicoo.com/magazine/blog/timetree)

### EventSnapへの示唆：これは`ASKEN_GROWTH_CASE_STUDY.md` §5を補強する

Rotash向けの同種の資料では、この「上限を外して用途拡大する」戦略は
**Rotashの核（7人上限）と矛盾するため反面教師**という結論になった。
**EventSnapは事情が異なる。** EventSnapには元々人数上限が無く（`docs/ASKEN_GROWTH_CASE_STUDY.md` §0の
事実表の通り）、**「その場にいる全員」という単位が、文化祭でもコンサートでも結婚式でも
社内イベントでも自然に伸縮する。**

TimeTreeが「個人カレンダー」のまま仕事用途（会議カレンダー、掃除当番）にまで広がったのと同じように、
EventSnapも「文化祭の模擬店」から「結婚式の披露宴」「社内運動会」まで、**コード変更なしに
そのまま対応できる。** これは `ASKEN_GROWTH_CASE_STUDY.md` §5 が提案した
**法人・団体配布チャネル（学園祭実行委員会・結婚式場・旅行代理店・企業総務部）**の妥当性を、
もう1つの大規模事例（TimeTreeの用途拡張の実績）で裏付けるものである。

**→ 判定：`ASKEN_GROWTH_CASE_STUDY.md` §5 の優先度をさらに補強。**
新しい実装課題は生まれないが、**「EventSnapは複数の利用シーンに自然に対応できる」という
主張の説得力が増した。** 団体への提案資料を作る際、「文化祭でも結婚式でも社内イベントでも、
同じアプリがそのまま使える」という訴求はTimeTreeの実績が裏付けている。

---

## 4. 利用シーン別のコンテンツマーケティング

TimeTreeは「家族・パートナー」のようにシーン別の使い方ガイドを多数公開し、
検索経由での自然流入を作っている。
[（出典）](https://timetreeapp.com/intl/ja/usages/category/family-partner)

### EventSnapへの示唆：新規のLATER施策として提案

EventSnapには現状、利用シーン別のコンテンツ（文化祭での使い方、結婚式での使い方、
サークル合宿での使い方等）が存在しない（`promo/` ディレクトリはプロモーションサイトの
ビルドを持つが、シーン別ガイドの有無は未確認）。

TimeTreeの実例は、**「イベントの種類ごとに、検索から辿り着ける入口を作る」**ことが
大規模化したサービスでも有効な施策であり続けることを示す。

**→ 判定：LATER。** `ASKEN_GROWTH_CASE_STUDY.md` §6（計測）が先。
計測が無い状態でコンテンツを増やしても、どのシーン別ページが実際に招待やイベント作成に
つながっているか分からない。計測を先に用意してから着手する。

---

## 5. フリーミアム＋広告という収益モデル

TimeTreeは広告収入とプレミアムプラン（月額300〜480円、広告非表示・機能拡張）の
二本立てで収益化している。
[（出典）](https://timetreeapp.com/intl/ja/newsroom/2022-04-19/timetree-premium)

### EventSnapへの示唆

EventSnapは現状マネタイズ設計を持たない（`ASKEN_GROWTH_CASE_STUDY.md` §0 の事実表の通り）。
TimeTreeの事例から引ける教訓は、Rotash向け資料と同じ結論になる：

- **広告はEventSnapの世界観と相性が悪い。** 「その場にいる人だけで完結する」思い出の中に
  広告が挟まるのは、TimeTreeのカレンダー（実用ツール）とは違い、**思い出という感情的な
  体験の純度を下げる**
- 有料化を検討するなら、**コア体験（QR参加・自動共有・タイムカプセル・Event Reel）は無料のまま**、
  Event Reelの追加テンプレートやタイムカプセルの公開期間カスタマイズなど、
  **コアを損なわない拡張だけを課金対象にする**方向が、TimeTreeにもあすけんにも共通する
  フリーミアムの型として妥当

**→ 判定：LATER。** 現時点でのマネタイズ設計は範囲外。

---

## 6. まとめ

| 節 | 判定 | 既存資料との関係 |
|---|---|---|
| §1 招待が作成の続きである設計 | **現状維持（確認）** | EventSnapは既にApp Clipでこれを上回る形で実現済み |
| §2 予定にコメント・写真が残る | **DON'T**（開かれた拡張はしない） | EventSnapの「その場にいた人だけ」という閉じた設計が意図的であることを確認 |
| §3 個人〜仕事への用途拡張 | **`ASKEN_GROWTH_CASE_STUDY.md` §5を補強** | 法人・団体配布チャネルの説得力を高める実例 |
| §4 シーン別コンテンツ | **LATER** | 計測(§6)の後に着手 |
| §5 フリーミアム＋広告 | **LATER** | 広告は不採用。有料化はコア機能を避ける方向で検討 |

**この資料の結論：**
TimeTreeはEventSnapに構造が近い事例でありながら、招待導線（§1）は既にEventSnapの方が
App Clipで一歩進んでおり、真似る必要は無かった。**唯一新しく得られた実務的な示唆は§3**——
TimeTreeが個人カレンダーのまま仕事用途まで自然に広がった実績は、EventSnapが
`ASKEN_GROWTH_CASE_STUDY.md` §5 で提案した法人・団体展開（学園祭・結婚式・企業イベント）が
**構造的に無理のない拡張である**ことを、もう1つの角度から裏付けている。

一方§2は、TimeTreeとの違いを通じて**EventSnapが「あえてやらないこと」（後から誰でも
書き足せる開かれた記録にしない）を再確認できた**という点で価値がある。

---

## 出典

- [40million突破 — TimeTree公式ニュース](https://timetreeapp.com/intl/ja/newsroom/2022-08-10/40-million)
- [サービスのUI/UXをリニューアル、新機能「みつける」— TimeTree公式ニュース](https://timetreeapp.com/intl/ja/newsroom/2026-01-13/timetree-renewal)
- [TimeTree（タイムツリー）の共有は便利？やり方やよくある質問 — sungrove.co.jp](https://www.sungrove.co.jp/timetree-share/)
- [有料プラン「TimeTreeプレミアム」スタート — TimeTree公式ニュース](https://timetreeapp.com/intl/ja/newsroom/2022-04-19/timetree-premium)
- [TimeTree（タイムツリー）の使い方！家族・カップル・仕事で便利な活用法 — fukucale.ai](https://fukucale.ai/labo/time-tree/how-to-use)
- [【最新・完全版】TimeTree徹底完全ガイド — Jicoo](https://www.jicoo.com/magazine/blog/timetree)
- [家族・パートナーカテゴリの使い方記事一覧 — TimeTree](https://timetreeapp.com/intl/ja/usages/category/family-partner)
