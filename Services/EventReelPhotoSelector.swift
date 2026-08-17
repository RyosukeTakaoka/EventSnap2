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
/// **設計方針**: 品質(露出・被写体の写り方・構図)を優先しつつ、撮影時刻・
/// 撮影者が固まらないよう多様性を加点する。「品質を優先しながら多様性を
/// 加点する」という方針のため、多様性は品質の足切りには使わず、
/// 僅差の判断材料としてのみ働く控えめなボーナスにしている。
///
/// **やっていること**:
/// 1. 同一撮影者・近接時刻(90秒以内)の写真は「同じ瞬間のバースト」とみなし、
///    各バーストの最高品質の1枚だけを代表として残す(単純な類似写真の重複排除)
/// 2. 残った候補を撮影時刻でN個(=選びたい枚数)の区間に均等分割する。
///    これにより「撮影時間の分散」が結果に構造的に反映される
///    (例: 同じ場所で連写したA/B/Cが1枚に集約され、食事・移動・景色といった
///    別の時間帯の写真が別々に選ばれやすくなる)
/// 3. 各区間で「品質スコア + まだ選ばれていない撮影者ならボーナス」が最も高い
///    1枚を選ぶ。区間に該当写真が無い場合は後から残り候補で埋め合わせる
/// 4. 選ばれた中で最も品質スコアが高い1枚を「メイン写真」とし、残りは
///    撮影順に並べる(レイアウト側で使う自然な時系列)
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

    /// 撮影者が未選出であることの加点(品質スコアと同じ0〜100スケールに対して控えめに)
    private static let uploaderDiversityBonus: CGFloat = 12

    /// 候補群からEvent Reel 1件分(target枚、通常2〜5)を選ぶ。
    /// 候補が足りない場合はある分だけ返す(呼び出し側は`ordered.count`を見て判断する)。
    static func select(from candidates: [Candidate], target: Int) -> Selection? {
        guard target >= 1, !candidates.isEmpty else { return nil }

        let sorted = candidates.sorted { $0.photo.uploadedAt < $1.photo.uploadedAt }
        let deduped = collapseBursts(sorted)
        guard !deduped.isEmpty else { return nil }

        let n = min(target, deduped.count)

        if n == 1 {
            guard let best = deduped.max(by: { qualityScore($0.analysis) < qualityScore($1.analysis) }) else { return nil }
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
        // 残りの候補(品質+多様性スコア順)で不足分を埋める。
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

        guard let main = picked.max(by: { qualityScore($0.analysis) < qualityScore($1.analysis) }) else { return nil }
        let subs = picked
            .filter { $0.photo.id != main.photo.id }
            .sorted { $0.photo.uploadedAt < $1.photo.uploadedAt }

        return Selection(ordered: [main] + subs)
    }

    // MARK: - バースト間引き

    /// 同一撮影者・`burstWindow`秒以内の写真を1グループにまとめ、
    /// 各グループの最高品質スコアの1枚だけを残す。`sortedByTime`は撮影順であること。
    private static func collapseBursts(_ sortedByTime: [Candidate]) -> [Candidate] {
        var groups: [[Candidate]] = []

        for candidate in sortedByTime {
            if let lastCandidate = groups.last?.last,
               lastCandidate.photo.uploaderID == candidate.photo.uploaderID,
               candidate.photo.uploadedAt.timeIntervalSince(lastCandidate.photo.uploadedAt) <= burstWindow {
                groups[groups.count - 1].append(candidate)
            } else {
                groups.append([candidate])
            }
        }

        return groups.compactMap { group in
            group.max { qualityScore($0.analysis) < qualityScore($1.analysis) }
        }
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
                var score = qualityScore(candidate.analysis)
                if !usedUploaders.contains(candidate.photo.uploaderID) {
                    score += uploaderDiversityBonus
                }
                return (candidate, score)
            }
            .sorted { $0.1 > $1.1 }
            .map { $0.0 }
    }

    /// 露出・被写体の写り方・構図のきれいさから、0〜100の目安スコアを作る。
    /// 「最もスコアが高い写真だけを選ぶ」設計ではなく、区間内の相対比較・
    /// 不足分の埋め合わせにのみ使う値。
    static func qualityScore(_ analysis: PhotoAnalysisResult) -> CGFloat {
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

        // 構図のきれいさ(0〜15点): PhotoAnalyzerの安全ゾームスコア(被写体と重ならず
        // 背景が単純なほど高い)を、きれいな構図の目安として流用する
        score += max(0, min(analysis.bestZone.score, 100)) * 0.15

        // サリエンシー(0〜8点): はっきりした被写体があるか
        if !analysis.salientRegions.isEmpty { score += 8 }

        return max(0, min(score, 100))
    }
}
