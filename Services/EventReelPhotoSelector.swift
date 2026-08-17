//
//  EventReelPhotoSelector.swift
//  EventSnap
//
//  複数のシェアOK写真の中から、Event Reel 1件分(2〜5枚)を選ぶアルゴリズム
//

import Foundation
import UIKit

/// 「最新の写真」でも「ランダム」でもなく、写真の中身と分布を見て
/// Event Reelに使う数枚を選ぶ。
///
/// **評価軸: Event Memory Value**
///
/// 単に「写真として綺麗か」（露出・構図・サリエンシーなどの技術的品質）だけでなく、
/// 「イベントの記憶として価値があるか」を評価に加える。技術的には破綻していない
/// ソファ・壁・床だけの写真が、人物も被写体も写った写真より高く評価されて
/// メインに選ばれてしまう、という失敗を避けるための拡張。
///
/// **やっていること**:
/// 1. 同一撮影者・近接時刻(90秒以内)、または同一撮影者・近い色味(5分以内かつ
///    アクセントカラーが近い)の写真は「同じ瞬間/同じ構図のバースト」とみなし、
///    各グループの思い出価値が最も高い1枚だけを代表として残す
/// 2. 残った候補を撮影時刻でN個(=選びたい枚数)の区間に均等分割する。
///    これにより「撮影時間の分散」が結果に構造的に反映される
/// 3. 各区間で「思い出価値スコア + まだ選ばれていない撮影者ならボーナス」が
///    最も高い1枚を選ぶ。区間に該当写真が無い場合は後から残り候補で埋め合わせる
/// 4. メイン写真は単純な最高スコアではなく、複数人物・被写体の明確さ・
///    他の選出写真との内容の重複具合まで見て別途選ぶ（`pickMain`）。
///    残りは撮影順に並べる(レイアウト側で使う自然な時系列)
enum EventReelPhotoSelector {

    /// 解析済みの1候補。呼び出し側が`PhotoAnalyzer.analyze`をあらかじめ
    /// (サムネイルなどで)実行してから渡す。
    struct Candidate {
        let photo: Photo
        let analysis: PhotoAnalysisResult
    }

    struct Selection {
        /// レイアウト順(先頭がメイン、以降は撮影順のサブ写真)
        let ordered: [Candidate]
        var photoIDs: [UUID] { ordered.map { $0.photo.id } }
    }

    /// 同一撮影者・近接時刻の写真を「同じ瞬間」とみなして間引く際のしきい値
    private static let burstWindow: TimeInterval = 90

    /// 「同じ瞬間」ほど近くはないが、同一撮影者・近い時間帯・近い色味なら
    /// 「似た構図の写真」とみなして間引くための、より緩いしきい値。
    private static let similarContentWindow: TimeInterval = 300
    /// アクセントカラーの距離(0〜1、0=同色)がこれ未満なら「近い色味」とみなす
    private static let similarColorThreshold: CGFloat = 0.1

    /// 撮影者が未選出であることの加点(スコアと同じ0〜100スケールに対して控えめに)
    private static let uploaderDiversityBonus: CGFloat = 12

    /// 顔・人物が無い場合に「はっきりした被写体がある」とみなす、
    /// サリエンシー領域の最小面積(画面全体に対する比率)。これ未満しか無ければ
    /// 「壁・床・家具だけ」のような被写体不在の写真とみなす。
    private static let meaningfulSalientArea: CGFloat = 0.02

    /// 候補群からEvent Reel 1件分(target枚、通常2〜5)を選ぶ。
    /// 候補が足りない場合はある分だけ返す(呼び出し側は`ordered.count`を見て判断する)。
    static func select(from candidates: [Candidate], target: Int) -> Selection? {
        guard target >= 1, !candidates.isEmpty else { return nil }

        let sorted = candidates.sorted { $0.photo.uploadedAt < $1.photo.uploadedAt }
        let deduped = collapseSimilar(sorted)
        guard !deduped.isEmpty else { return nil }

        let n = min(target, deduped.count)

        if n == 1 {
            guard let best = deduped.max(by: { memoryValueScore($0.analysis) < memoryValueScore($1.analysis) }) else { return nil }
            return Selection(ordered: [best])
        }

        let segments = timeSegments(deduped, count: n)

        var picked: [Candidate] = []
        var usedUploaders: Set<String> = []

        for segment in segments where !segment.isEmpty {
            guard let best = bestCandidate(in: segment, usedUploaders: usedUploaders) else { continue }
            picked.append(best)
            usedUploaders.insert(best.photo.uploaderID)
        }

        // 区間分割の偏りで目標枚数に届かないことがあるため、
        // 残りの候補(スコア+多様性ボーナス順)で不足分を埋める。
        if picked.count < n {
            let pickedIDs = Set(picked.map { $0.photo.id })
            let leftover = deduped.filter { !pickedIDs.contains($0.photo.id) }
            for candidate in rankedByScore(leftover, usedUploaders: usedUploaders) {
                guard picked.count < n else { break }
                picked.append(candidate)
                usedUploaders.insert(candidate.photo.uploaderID)
            }
        }

        guard !picked.isEmpty else { return nil }

        guard let main = pickMain(from: picked) else { return nil }
        let subs = picked
            .filter { $0.photo.id != main.photo.id }
            .sorted { $0.photo.uploadedAt < $1.photo.uploadedAt }

        return Selection(ordered: [main] + subs)
    }

    // MARK: - 重複・類似写真の間引き

    /// 同一撮影者・近接時刻(バースト)、または同一撮影者・近い時間帯かつ近い色味
    /// (似た構図の可能性が高い)の写真を1グループにまとめ、各グループの中で
    /// 最も思い出価値の高い1枚だけを残す。`sortedByTime`は撮影順であること。
    private static func collapseSimilar(_ sortedByTime: [Candidate]) -> [Candidate] {
        var groups: [[Candidate]] = []

        for candidate in sortedByTime {
            if let lastCandidate = groups.last?.last, isLikelyDuplicate(lastCandidate, candidate) {
                groups[groups.count - 1].append(candidate)
            } else {
                groups.append([candidate])
            }
        }

        return groups.compactMap { group in
            group.max { memoryValueScore($0.analysis) < memoryValueScore($1.analysis) }
        }
    }

    /// 2枚が「同じ瞬間、または似た構図の写真」とみなせるか。
    /// 重いVision/MLモデルは使わず、`PhotoAnalyzer`が既に算出済みの情報
    /// (撮影者・撮影時刻・アクセントカラー)だけで判定する簡易ヒューリスティック。
    private static func isLikelyDuplicate(_ a: Candidate, _ b: Candidate) -> Bool {
        guard a.photo.uploaderID == b.photo.uploaderID else { return false }
        let interval = abs(a.photo.uploadedAt.timeIntervalSince(b.photo.uploadedAt))

        if interval <= burstWindow { return true }
        if interval <= similarContentWindow,
           colorDistance(a.analysis.accentColor, b.analysis.accentColor) < similarColorThreshold {
            return true
        }
        return false
    }

    /// 2色の距離を0(同色)〜1(最大に異なる)で返す、RGB空間での単純なユークリッド距離。
    private static func colorDistance(_ c1: UIColor, _ c2: UIColor) -> CGFloat {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        c1.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        c2.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let d = sqrt(pow(r1 - r2, 2) + pow(g1 - g2, 2) + pow(b1 - b2, 2))
        return d / sqrt(3) // RGB単位立方体の対角線長で正規化 → 0〜1
    }

    // MARK: - 時間セグメント分割

    /// 撮影時刻の範囲を`count`個の等間隔な区間に分け、各候補を対応する区間に振り分ける。
    /// 撮影時刻の差がほぼ無い場合(全て同時刻など)は順番で均等分割する。
    private static func timeSegments(_ sortedByTime: [Candidate], count: Int) -> [[Candidate]] {
        guard count > 1, sortedByTime.count > 1 else { return [sortedByTime] }

        var segments: [[Candidate]] = Array(repeating: [], count: count)

        guard let first = sortedByTime.first?.photo.uploadedAt,
              let last = sortedByTime.last?.photo.uploadedAt,
              last > first
        else {
            for (i, candidate) in sortedByTime.enumerated() {
                let index = min(i * count / sortedByTime.count, count - 1)
                segments[index].append(candidate)
            }
            return segments
        }

        let span = last.timeIntervalSince(first)
        for candidate in sortedByTime {
            let t = candidate.photo.uploadedAt.timeIntervalSince(first) / span
            let index = min(Int(t * Double(count)), count - 1)
            segments[index].append(candidate)
        }
        return segments
    }

    // MARK: - スコアリング

    private static func bestCandidate(in candidates: [Candidate], usedUploaders: Set<String>) -> Candidate? {
        rankedByScore(candidates, usedUploaders: usedUploaders).first
    }

    private static func rankedByScore(_ candidates: [Candidate], usedUploaders: Set<String>) -> [Candidate] {
        candidates
            .map { candidate -> (Candidate, CGFloat) in
                var score = memoryValueScore(candidate.analysis)
                if !usedUploaders.contains(candidate.photo.uploaderID) {
                    score += uploaderDiversityBonus
                }
                return (candidate, score)
            }
            .sorted { $0.1 > $1.1 }
            .map { $0.0 }
    }

    /// この写真に、Vision解析上「はっきりした被写体」があるとみなせるか
    /// (顔・人物・十分な大きさのサリエンシー領域のいずれか)。
    private static func hasClearSubject(_ analysis: PhotoAnalysisResult) -> Bool {
        if !analysis.faceRegions.isEmpty || !analysis.personRegions.isEmpty { return true }
        return analysis.salientRegions.contains { $0.width * $0.height > meaningfulSalientArea }
    }

    /// **Event Memory Value**: 技術的な品質(露出・構図・サリエンシー)に加えて、
    /// 「イベントの記憶として価値があるか」を反映した0〜100の目安スコア。
    /// 区間内の相対比較・不足分の埋め合わせに使う値であり、
    /// 「最もスコアが高い写真だけを選ぶ」設計ではない。
    ///
    /// 人物がいない写真を一律に低評価にはしない（会場・食事・景色・チケットなど、
    /// イベントの記憶として重要な写真は残す）。ただし顔・人物・はっきりした
    /// サリエンシー領域のいずれも無い写真（壁・床・家具だけ、など被写体が
    /// 定まらない写真）は、技術品質が高くても明確に減点する。
    static func memoryValueScore(_ analysis: PhotoAnalysisResult) -> CGFloat {
        var score: CGFloat = 0

        // 露出(0〜40点): 暗すぎ(<0.15)・白飛び(>0.92)を減点し、0.35〜0.75を満点にする
        let brightness = analysis.overallBrightness
        switch brightness {
        case ..<0.15:
            score += brightness / 0.15 * 20
        case 0.15..<0.35:
            score += 20 + (brightness - 0.15) / 0.2 * 20
        case 0.35...0.75:
            score += 40
        case 0.75...0.92:
            score += 40 - (brightness - 0.75) / 0.17 * 10
        default:
            score += max(0, 30 - (brightness - 0.92) / 0.08 * 30)
        }

        // 顔の写り方(0〜20点): 極端に小さすぎない顔があると加点。大きすぎる場合は少し減点
        if let largestFace = analysis.faceRegions.map({ $0.width * $0.height }).max() {
            if largestFace > 0.01 { score += 20 }
            if largestFace > 0.35 { score -= 5 }
        }

        // 人物の視認性(0〜12点)
        if !analysis.personRegions.isEmpty { score += 12 }

        // 複数人物の存在(0〜8点): 「イベントの記憶」としては1人より複数人が写った
        // 写真の方が価値が高いことが多いため、人物の写り方とは別枠で加点する
        if analysis.faceRegions.count >= 2 || analysis.personRegions.count >= 2 { score += 8 }

        // 構図のきれいさ(0〜15点): PhotoAnalyzerの安全ゾームスコア(被写体と重ならず
        // 背景が単純なほど高い)を、きれいな構図の目安として流用する
        score += max(0, min(analysis.bestZone.score, 100)) * 0.15

        // サリエンシー(0〜8点): はっきりした被写体があるか
        if !analysis.salientRegions.isEmpty { score += 8 }

        // 被写体不在ペナルティ: 顔・人物・意味のあるサリエンシー領域のいずれも
        // 無い場合、技術的な品質(露出・構図の単純さ)だけで高得点になりがちな
        // 「壁・床・家具だけ」のような写真を明確に減点する。
        if !hasClearSubject(analysis) { score -= 20 }

        return max(0, min(score, 100))
    }

    // MARK: - メイン写真の選定

    /// 選ばれた写真たちの中から、大きく見せる「メイン写真」を選ぶ。
    /// 単純な`memoryValueScore`最大ではなく、複数人物・被写体の明確さ・
    /// 他の選出写真との内容の重複具合まで見て総合評価する。
    ///
    /// イベントに人物が1人も写っていない場合は無理に人物写真を作らず、
    /// (被写体不在ペナルティを踏まえた上で)最も意味のある1枚を選ぶ。
    static func pickMain(from picked: [Candidate]) -> Candidate? {
        guard !picked.isEmpty else { return nil }
        return picked.max { mainSuitabilityScore($0, among: picked) < mainSuitabilityScore($1, among: picked) }
    }

    private static func mainSuitabilityScore(_ candidate: Candidate, among picked: [Candidate]) -> CGFloat {
        let analysis = candidate.analysis
        var score = memoryValueScore(analysis)

        // メインとしては「壁・床・家具だけ」を思い出価値スコアよりさらに強く避ける
        // (ソファ・壁・部屋がメインに選ばれてしまう、という代表的な失敗例への対処)
        if !hasClearSubject(analysis) { score -= 20 }

        // 複数人物が写った写真をメインとしてより強く優遇する
        if analysis.faceRegions.count >= 2 || analysis.personRegions.count >= 2 { score += 10 }

        // 極端に被写体が小さい(余白ばかりの)構図は、メインとしての力強さに欠けるため
        // 軽く減点する。サリエンシー領域の合計面積を被写体の目安にする。
        let salientCoverage = analysis.salientRegions.reduce(CGFloat(0)) { $0 + $1.width * $1.height }
        if analysis.faceRegions.isEmpty, analysis.personRegions.isEmpty, salientCoverage < 0.06 {
            score -= 6
        }

        // 既に選ばれた他の写真と内容(アクセントカラー)が近すぎる場合は、
        // メインとしての独自性という観点で少しだけ減点する(僅差の判断材料に留める)。
        let others = picked.filter { $0.photo.id != candidate.photo.id }
        if others.contains(where: { colorDistance($0.analysis.accentColor, analysis.accentColor) < similarColorThreshold }) {
            score -= 6
        }

        return score
    }
}
