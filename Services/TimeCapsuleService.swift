//
//  TimeCapsuleService.swift
//  EventSnap
//
//  写真の遅延公開（タイムカプセル）の選定と判定。
//  イベント参加者全員で共有する体験として扱う（個人単位の機能ではない）
//

import Foundation

/// イベント参加者全員で共有する、遅延公開の仕組み。
///
/// 撮った写真の一部を「まだ誰にも見えない写真」として伏せておき、
/// 2週間かけて小分けに公開していく。**個人が自分の写真を隠す機能ではなく、
/// イベント参加者全員が同じ条件で待つ、共有の体験**である。
/// 公開された瞬間、参加者全員に「LINE通知のように突然思い出が届く」ことを狙う。
///
/// ## この機能で守るべきこと
///
/// タイムカプセルは **「一定期間後に、参加者全員へ一斉に開く思い出」** であって、
/// 一定時間で消える一時的なものでも、撮影者だけが見られるものでもない。
/// 以下は仕様である。
///
/// - タイムカプセル写真は **削除しない**。`revealDate` まで保持する
/// - `revealDate` までは **撮影者本人を含め、誰にも表示しない**
///   （アルバムにもタイムカプセルタブにも出さない）
/// - **イベントが終了してもタイムカプセル状態は維持する**。
///   イベントの終了・日付変更は公開のトリガーではない
/// - 公開は `revealDate <= 現在時刻` になった時点。参加者全員に通知される
/// - 手動で早めて公開する経路は無い。伏せた写真を捨てたり、
///   個人の判断で公開を早めたりしてはいけない
///
/// 撮影時点では「シェアOK」と排他にしている（`CameraViewModel.shareOK`/
/// `saveAsTimeCapsule`のdidSetを参照）。ただし`PhotoRepository.setShareOK`経由で
/// 事後的にタイムカプセル写真がシェアOKに変更されるなど、両方trueになる経路は
/// 完全には塞がれていない。そのための安全策として、両方trueのまま
/// Event Reel（`ShareCollageBuilder`）を組む直前にシェアを優先して解除する処理
/// （`PhotoRepository.releaseSharedTimeCapsules`）は残している。
enum TimeCapsuleService {

    // MARK: - 調整パラメータ

    /// 自動でタイムカプセルに選ばれる確率。
    /// 高すぎるとその場で見られる写真が減ってアプリの基本体験が壊れるので控えめにする。
    static let autoSelectionRate: Double = 0.15

    /// 公開までの最短時間。
    /// あまり早いと「遅延公開」の意味が無く、その場で見えるのと変わらなくなる。
    static let minimumDelay: TimeInterval = 6 * 60 * 60      // 6時間

    /// 公開までの最長時間（仕様: 2週間以内）
    static let maximumDelay: TimeInterval = 14 * 24 * 60 * 60 // 14日

    // MARK: - 選定

    /// この写真をタイムカプセルにするか決める。
    ///
    /// シェアOKかどうかはここでは見ない。両方trueになることを許し、
    /// Event Reelを組む直前（`PhotoRepository.releaseSharedTimeCapsules`）で
    /// シェアを優先して解除する。
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

    /// 通常のアルバムに出すべき写真（＝公開済み）。
    /// 誰が撮ったかに関わらず、参加者全員に同じ結果になる。
    static func albumPhotos(_ photos: [Photo], now: Date = Date()) -> [Photo] {
        photos.filter { $0.isRevealed(asOf: now) }
    }

    /// タイムカプセルとして公開済みの写真（新しい順）
    static func revealedCapsules(_ photos: [Photo], now: Date = Date()) -> [Photo] {
        photos
            .filter { $0.isTimeCapsule && $0.isRevealed(asOf: now) }
            .sorted { ($0.revealDate ?? $0.uploadedAt) > ($1.revealDate ?? $1.uploadedAt) }
    }

    /// まだロックされている写真（公開が近い順）。
    /// 誰が撮ったかは問わない。参加者は全員、同じ枚数・同じ待ち時間を共有する。
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
