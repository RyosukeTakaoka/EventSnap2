//
//  RelayNotificationService.swift
//  EventSnap
//
//  Relayで「自分の番が開放された」ことを知らせる通知
//

import Foundation
import UserNotifications

/// Relayの通知も、タイムカプセルの公開通知（`NotificationService`）と同じ設計思想を踏襲する。
///
/// CloudKitには「指定時刻にサーバー側で処理を走らせる」仕組みが無いため、
/// 「予定時刻に事前予約したローカル通知」＋「silent pushで前倒しを検知したら
/// 予約を今すぐ発火するよう差し替える」の組み合わせで実現する。
///
/// 1. Relay開始時、参加者は自分の枠が開くと**見込まれる**時刻
///    （`RelaySession.predictedOpenDate`。前の人達が誰も早く撮らなかった場合の時刻）に
///    `UNCalendarNotificationTrigger`でローカル通知を予約する
/// 2. 前の人が優先時間内に撮り終えて前倒しでバトンが進むと、CKQuerySubscriptionの
///    silent pushが全端末に届く。各端末はRelaySessionを取得し直し、自分の枠が
///    （見込みより早く）`open`に変わっていたら、予約していた通知を取り消して
///    その場で即時通知に差し替える
/// 3. アプリが完全に閉じられていて2を受け取れなくても、1で予約した通知は
///    OS側が保持しているので、見込み時刻には必ず鳴る（＝最悪でも締切通りには届く）
final class RelayNotificationService {
    static let shared = RelayNotificationService()

    private let center = UNUserNotificationCenter.current()

    private init() {}

    private func identifier(eventID: UUID, participantID: String) -> String {
        "relay-turn-\(eventID.uuidString)-\(participantID)"
    }

    // MARK: - 予約（見込み時刻ベースの事前予約）

    /// RelaySessionの現在の状態から、自分の枠についての通知予約を最新化する。
    ///
    /// - 自分の枠が`waiting`: 見込み時刻に通知を予約し直す（既存の予約があれば置き換える）
    /// - 自分の枠が`open`/`completed`: 予約は不要なので取り消す
    ///   （`open`の場合は`notifyTurnOpenedNow`が別途即時通知を出す）
    func scheduleIfNeeded(session: RelaySession, event: Event, viewerID: String) async {
        guard !ScreenshotMode.suppressesLiveServices else { return }
        let id = identifier(eventID: event.id, participantID: viewerID)

        guard let slot = session.slot(for: viewerID) else { return }

        guard slot.status == .waiting else {
            center.removePendingNotificationRequests(withIdentifiers: [id])
            return
        }

        guard await isAuthorized else { return }
        guard let openDate = session.predictedOpenDate(forParticipantID: viewerID), openDate > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = event.name
        content.body = "もうすぐあなたの番です。Relayの撮影に参加しましょう"
        content.sound = .default
        content.userInfo = [
            "eventID": event.id.uuidString,
            "type": "relayTurn",
        ]

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: openDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)

        center.removePendingNotificationRequests(withIdentifiers: [id])
        do {
            try await center.add(request)
        } catch {
            print("❌ Relay通知の予約に失敗: \(error)")
        }
    }

    // MARK: - 前倒し発火

    /// 前の人が早く撮り終えて、見込みより前に自分の枠が`open`になったことを検知したときに呼ぶ。
    /// 予約済みの（まだ先の時刻を指している）通知を取り消し、その場で即時通知に差し替える。
    func notifyTurnOpenedNow(event: Event, viewerID: String) async {
        guard !ScreenshotMode.suppressesLiveServices else { return }
        guard await isAuthorized else { return }

        let id = identifier(eventID: event.id, participantID: viewerID)
        center.removePendingNotificationRequests(withIdentifiers: [id])

        let content = UNMutableNotificationContent()
        content.title = event.name
        content.body = "あなたの番が開放されました。Relayの撮影に参加しましょう"
        content.sound = .default
        content.userInfo = [
            "eventID": event.id.uuidString,
            "type": "relayTurn",
        ]

        // ごく短い遅延で即時通知として発火させる（`UNTimeIntervalNotificationTrigger`の
        // 最小値は1秒より大きい必要があるため）。
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)

        do {
            try await center.add(request)
        } catch {
            print("❌ Relay即時通知の発火に失敗: \(error)")
        }
    }

    /// このイベントのRelay通知をすべて取り消す（イベント離脱時など）
    func cancelAll(for eventID: UUID, participantIDs: [String]) {
        let ids = participantIDs.map { identifier(eventID: eventID, participantID: $0) }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    private var isAuthorized: Bool {
        get async {
            let settings = await center.notificationSettings()
            return settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional
        }
    }
}
