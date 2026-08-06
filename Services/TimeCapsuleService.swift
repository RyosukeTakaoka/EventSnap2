//
//  TimeCapsuleService.swift
//  EventSnap
//
//  写真の遅延公開（タイムカプセル）の選定と判定
//

import Foundation

/// イベントが終わってもアプリを開く理由を作るための遅延公開の仕組み。
///
/// 撮った写真の一部を「まだ見られない写真」として伏せておき、
/// 2週間かけて小分けに公開していく。
enum TimeCapsuleService {

    // MARK: - 調整パラメータ

    /// 自動でタイムカプセルに選ばれる確率。
    /// 高すぎるとその場で見られる写真が減ってアプリの基本体験が壊れるので控えめにする。
    static let autoSelectionRate: Double = 0.2

    /// 公開までの最短時間。
    /// あまり早いと「遅延公開」の意味が無く、その場で見えるのと変わらなくなる。
    static let minimumDelay: TimeInterval = 6 * 60 * 60      // 6時間

    /// 公開までの最長時間（仕様: 2週間以内）
    static let maximumDelay: TimeInterval = 14 * 24 * 60 * 60 // 14日

    // MARK: - 選定

    /// この写真をタイムカプセルにするか決める。
    ///
    /// - Parameters:
    ///   - forcedByUser: 撮影者本人が明示的に「あとで公開」を選んだか。
    ///                   選んでいれば必ずタイムカプセルになる。
    /// - Returns: タイムカプセルなら公開予定日時、そうでなければ nil
    static func decideRevealDate(
        capturedAt: Date = Date(),
        forcedByUser: Bool = false
    ) -> Date? {
        let selected = forcedByUser || Double.random(in: 0..<1) < autoSelectionRate
        guard selected else { return nil }

        // 一括ではなく写真ごとにバラけた時刻にすることで、
        // 「日をかけて少しずつ公開される」体験になる。
        let delay = Double.random(in: minimumDelay...maximumDelay)
        return capturedAt.addingTimeInterval(delay)
    }

    // MARK: - 振り分け

    /// 写真を「今すぐ見えるもの」と「まだ見えないもの」に分ける。
    ///
    /// 未公開のタイムカプセル写真は、**撮影者本人にだけ**見えるようにする
    /// （自分が何を伏せたかは分かってよい）。
    static func partition(
        _ photos: [Photo],
        viewerID: String,
        now: Date = Date()
    ) -> (visible: [Photo], locked: [Photo]) {
        var visible: [Photo] = []
        var locked: [Photo] = []

        for photo in photos {
            if photo.isRevealed(asOf: now) {
                visible.append(photo)
            } else if photo.uploaderID == viewerID {
                // 自分が伏せた写真。アルバムには出さず、カプセルタブでロック表示する。
                locked.append(photo)
            } else {
                locked.append(photo)
            }
        }

        return (visible, locked)
    }

    /// 通常のアルバムに出すべき写真（＝公開済み）
    static func albumPhotos(_ photos: [Photo], now: Date = Date()) -> [Photo] {
        photos.filter { $0.isRevealed(asOf: now) }
    }

    /// タイムカプセルとして公開済みの写真（新しい順）
    static func revealedCapsules(_ photos: [Photo], now: Date = Date()) -> [Photo] {
        photos
            .filter { $0.isTimeCapsule && $0.isRevealed(asOf: now) }
            .sorted { ($0.revealDate ?? $0.uploadedAt) > ($1.revealDate ?? $1.uploadedAt) }
    }

    /// まだロックされている写真（公開が近い順）
    static func lockedCapsules(_ photos: [Photo], now: Date = Date()) -> [Photo] {
        photos
            .filter { $0.isTimeCapsule && !$0.isRevealed(asOf: now) }
            .sorted { ($0.revealDate ?? .distantFuture) < ($1.revealDate ?? .distantFuture) }
    }

    // MARK: - 表示用の文言

    /// 正確な公開日時は見せず、ぼかした残り時間を返す。
    /// 「あと何日か分かるが、いつ来るかは分からない」くらいの粒度にする。
    static func vagueCountdown(for photo: Photo, now: Date = Date()) -> String {
        guard let days = photo.daysUntilReveal(asOf: now) else { return "まもなく公開" }

        switch days {
        case ..<1:  return "まもなく公開"
        case 1:     return "もうすぐ公開"
        case 2...3: return "数日後に公開"
        case 4...7: return "今週中に公開"
        default:    return "2週間以内に公開"
        }
    }
}
