# Miro — 成長事例からの構造抽出と EventSnap への応用

[`ASKEN_GROWTH_CASE_STUDY.md`](ASKEN_GROWTH_CASE_STUDY.md)・[`TIMETREE_GROWTH_CASE_STUDY.md`](TIMETREE_GROWTH_CASE_STUDY.md) の続き。
Miroはオンラインホワイトボードの**B2B SaaS**であり、今までの2つ（個人習慣アプリ／
個人〜家族向け共有ツール）とは異なり、「プロダクト主導成長（PLG）」の代表事例として語られる。
EventSnapへの直接的な機能移植先ではないが、**§5で検討した法人・団体展開に、
Miroの成長の型から重要な示唆が得られる。**

## 0. Miroの規模と概要（事実）

| 項目 | 内容 | 出典 |
|---|---|---|
| 顧客数の伸び | 2020年9月〜2021年9月の1年間で、顧客数4万社→11万8,000社（+195%）、ユーザー数800万人→2,500万人（+212%） | [ascii.jp](https://ascii.jp/elem/000/004/075/4075677/) |
| ユーザー数 | **現在3,500万人以上、有料顧客13万社以上**。Fortune 100企業の95%がMiroユーザー | [How Miro Grows — Medium](https://medium.com/pm101/how-miro-grows-tactical-lessons-from-the-17-5b-whiteboard-f56ec812f500) |
| 無料プランの制限 | 編集・共有できるボードは**3枚まで**。チームメンバーは無制限に招待できる | [アプリの達人](https://app-tatsujin.com/miro-free-plan-features-limitations-2026/) |
| テンプレート数 | 300種類以上 | [aslead.nri.co.jp](https://aslead.nri.co.jp/products/miro/column/miro-function-plan-explanation.html) |
| 成長運用 | 「1人のユーザーが何人を新たに連れてくるか」を最重要指標として執拗に追跡・改善 | [AllStar SaaS Blog](https://blog.allstarsaas.com/posts/miro-plg) |

---

## 1. フリーミアムの軸を「人数」ではなく「資源」に置く設計

Miroは無料プランでもチームメンバーを無制限に招待できる一方、**ボード数（3枚まで）**で
課金の線を引いている。人数に課金しないことで、招待そのものにブレーキがかからないようにしている。
[（出典）](https://app-tatsujin.com/miro-free-plan-features-limitations-2026/)

### EventSnapへの示唆

EventSnapは人数上限を持たない設計であり、これはMiroと同じ方向性を既に持っている
（`ASKEN_GROWTH_CASE_STUDY.md` §0 の事実表参照）。将来マネタイズを検討する際の指針として：

> **参加人数には課金しない。** 課金するとしたら、`TIMETREE_GROWTH_CASE_STUDY.md` §5で
> 既に出した結論と同じく、Event Reelの追加テンプレートやタイムカプセルの期間カスタマイズなど、
> **「その場にいる全員で完結する」体験そのものを制限しない拡張**にとどめる。

**→ 判定：LATER（既存の考え方を補強）。** 新しい実装課題は生まれない。

---

## 2. 外部共有が招待ではなく「体験」から始まる — App Clipが既にこれを実現している

Miroのバイラルの核心は、**招待を頼む前に、相手が先に価値を体験すること**にある。
ボードを共有された相手がその場で価値を実感し、それが新しいアカウント作成につながる。
さらにMiroの成長チームは「1人が何人連れてくるか」を執拗に追跡・改善し続けた。
[（出典）](https://medium.com/pm101/how-miro-grows-tactical-lessons-from-the-17-5b-whiteboard-f56ec812f500)

### EventSnapへの示唆：構造は既にApp Clipで実現済み。欠けているのは計測

`ASKEN_GROWTH_CASE_STUDY.md` §4 で確認した通り、**EventSnapのApp Clipは
Miroの「共有された相手が先に価値を体験する」という構造を、招待コード無しで既に実現している。**
未インストールでもイベントの様子をその場で見られる設計は、Miro以上に摩擦が少ない。

新しい示唆は、**運用の姿勢**にある。Miroが「1人が何人連れてくるか」を執拗に測り続けたのに対し、
EventSnapには計測コードが1行も無い（`ASKEN_GROWTH_CASE_STUDY.md` §0）。
**構造が優れていても、計測が無ければその優位性を検証も改善もできない。**

**→ 判定：既存の`ASKEN_GROWTH_CASE_STUDY.md` §6（計測）の優先度を再確認。**
新しい施策ではなく、**「App Clipからのインストール転換率」を1人あたり何件の新規イベント参加に
つながっているか、という指標で追い続けること**が、Miro事例から得る唯一の実務的な教訓である。

---

## 3. テンプレートギャラリー — Event Reelの3テンプレートは正しい方向

Miroは300種類以上のテンプレートで「空白のキャンバス」を見せず、即座に使い始められるようにしている。
[（出典）](https://aslead.nri.co.jp/products/miro/column/miro-function-plan-explanation.html)

### EventSnapへの示唆：確認のみ

EventSnapの Event Reel（Editorial/Bold/Minimalの3テンプレート）は、既に同じ原理
（選ぶだけで使える、ゼロから作らせない）に基づいている。**変更の必要はない。**
Miroが300種類まで拡張したのに対しEventSnapは3種類だが、これは規模の違いであり、
**現時点で拡張を急ぐ理由にはならない**（利用データが無いため、どのテンプレートが
効いているかも分からない。これも計測（§2）が先という結論を補強する）。

**→ 判定：確認のみ。**

---

## 4. Land and Expand — 法人・団体展開の「入り口」をもう1つ増やす

Miro最大の特徴は、契約してから配る（あすけんのB2B2C型）のではなく、
**1人・1チームが自発的に使い始め、その価値が組織内で自然に伝播し、
後から会社が正式に契約する**という、ボトムアップ型の拡大順序である。

### EventSnapへの示唆：トップダウンとボトムアップ、両方の入り口を持てる

`ASKEN_GROWTH_CASE_STUDY.md` §5 で提案した法人・団体展開（学園祭実行委員会・結婚式場等）は、
**トップダウン型**（団体の代表者と先に交渉し、団体として導入してもらう）だった。
Miroの事例は、EventSnapに**もう1つの自然な入り口**があることを示す：

```
トップダウン型（あすけん型、既存§5の提案）：
  結婚式場のプランナーに営業する → 式場として正式採用してもらう
  → 毎週の挙式でEventSnapを標準提供する

ボトムアップ型（Miro型、この節の新しい示唆）：
  1組のカップルが自分の結婚式でEventSnapを個人的に使う
    → ゲストが体験し、「これいいね」と感じる
    → 別の結婚式でも新郎新婦が個人的に使い始める
    → 同じ式場で複数回使われた実績ができる
    → その時点で式場側から「うちで正式に案内したい」と声がかかる
```

**EventSnapはRotashと違い、どちらの入り口も無理なく成立する**
（Rotash向け資料ではトップダウンが設計思想と衝突するリスクを指摘したが、
EventSnapは人数上限が無く「決断を迫らない」制約がRotashほど強くないため）。

**→ 判定：`ASKEN_GROWTH_CASE_STUDY.md` §5 に実行順序の選択肢を追加する。**
最初から団体へ営業をかける（トップダウン）のではなく、**まず個人利用の実績
（1つの結婚式場で複数回使われた、等）を積んでから、その式場・団体へ正式導入を
持ちかける方がリスクが低い。** これはPre-PMF段階（計測もまだ無い状態）の
EventSnapにとって、特に妥当な順序である。

---

## 5. まとめ

| 節 | 判定 | 既存資料との関係 |
|---|---|---|
| §1 人数ではなく資源に課金 | **LATER**（原則を記録） | 将来のマネタイズ方針を補強 |
| §2 外部共有からの流入＋執拗な計測文化 | **既存の計測課題(§6)を再確認** | App Clipの構造は既に優れている。計測の欠如が唯一の穴 |
| §3 テンプレートギャラリー | **確認のみ** | Event Reelの3テンプレートは正しい方向 |
| §4 Land and Expand | **`ASKEN_GROWTH_CASE_STUDY.md` §5への補足** | トップダウンに加え、ボトムアップ（個人利用の実績を積んでから団体へ）という選択肢を追加 |

**この資料の結論：**
MiroはEventSnapに直接移植できる機能的な示唆はほとんど無い。
最大の発見は§2——**EventSnapの招待導線（App Clip）は既にMiro級の構造を持っているが、
それを測る仕組みが無いために、その優位性を誰も検証できていない**ことが、
2つのB2B/コンシューマー双方の事例（あすけん・Miro）を通じて重ねて確認された。
そして§4は、法人展開を急いでトップダウンで進める前に、**個人利用の実績を積む
ボトムアップの順序**が選択肢としてあることを示している。

---

## 出典

- [リモートワークで急成長、オンラインホワイトボード「Miro」が日本で始動 — ASCII.jp](https://ascii.jp/elem/000/004/075/4075677/)
- [How Miro Grows: Tactical Lessons From The $17.5B Whiteboard — Medium (PM101)](https://medium.com/pm101/how-miro-grows-tactical-lessons-from-the-17-5b-whiteboard-f56ec812f500)
- [世界で2300万人が愛用！ホワイトボードSaaS「Miro」のProduct Led Growth戦略"6つの柱" — AllStar SaaS Blog](https://blog.allstarsaas.com/posts/miro-plg)
- [Miro（ミロ）の有料プランと無料プランの違い — 野村総合研究所(NRI) aslead](https://aslead.nri.co.jp/products/miro/column/miro-function-plan-explanation.html)
- [Miro 無料プランの仕様・制限と上手な活用術【2026年版】 — アプリの達人](https://app-tatsujin.com/miro-free-plan-features-limitations-2026/)
