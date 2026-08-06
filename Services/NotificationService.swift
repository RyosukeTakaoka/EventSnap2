//
//  NotificationService.swift
//  EventSnap
//
//  タイムカプセルの公開通知
//

import Foundation
import UserNotifications

/// タイムカプセルが公開されたことを知らせる通知。
///
/// ## なぜローカル通知なのか
///
/// 仕様は「公開された瞬間にグループ全員へプッシュ通知」だが、
/// CloudKitには **指定時刻にサーバー側で処理を走らせる仕組みが無い**
/// （CKSubscription が発火するのはレコードが作成・更新された時だけ）。
/// 素直にやるならサーバーを1台立てる必要がある。
///
/// そこで、**公開予定日時が決まった時点で全メンバーの端末がそれぞれ
/// ローカル通知を予約しておく**方式にした。
///
/// 1. 写真がアップロードされる（この時点で revealDate は確定済み）
/// 2. 既存の `CKQuerySubscription` の silent push が全メンバーに届く
/// 3. 各端末が写真一覧を取り直し、未公開のカプセルに対して
///    `UNCalendarNotificationTrigger` を予約する
/// 4. 予約時刻になると各端末で通知が鳴る
///
/// サーバーを増やさずに「全員に、公開の瞬間に」通知できる。
/// アプリ起動時にも予約し直すので、silent push を取りこぼしても復帰する。
@MainActor
final class NotificationService {
    static let shared = NotificationService()

    private init() {}

    /// iOSが1アプリに許す保留中ローカル通知の上限は64件。
    /// 超えると捨てられるため、公開が近いものを優先して予約する。
    ///
    /// これは **1イベントあたり** の上限。複数のイベントに参加していると
    /// 合計で64件を超えうるが、公開が近い順に予約しているので、
    /// 直近に鳴るべき通知から埋まる。アプリを開くたびに予約し直すため、
    /// 遠い先の分は手前の通知が消化されてから入る。
    private let maxScheduled = 56

    private let center = UNUserNotificationCenter.current()

    // MARK: - 許可

    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            print(granted ? "✅ 通知が許可されました" : "⚠️ 通知が拒否されました")
            return granted
        } catch {
            print("❌ 通知の許可リクエストに失敗: \(error)")
            return false
        }
    }

    var isAuthorized: Bool {
        get async {
            let settings = await center.notificationSettings()
            return settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional
        }
    }

    // MARK: - 予約

    /// 未公開のタイムカプセル写真に対して公開通知を予約する。
    ///
    /// 同じ写真IDで予約し直すと上書きされるので、何度呼んでも重複しない。
    func scheduleReveals(for photos: [Photo], event: Event, viewerID: String) async {
        guard await isAuthorized else {
            print("⚠️ 通知が許可されていないため予約をスキップします")
            return
        }

        let now = Date()
        // 公開が近い順に並んでいるので、上限に当たっても直近のものが残る
        let pending = TimeCapsuleService.lockedCapsules(photos, now: now)
            .prefix(maxScheduled)

        // 予約済みのうち、もう存在しない/公開済みになった写真の予約は取り消す。
        //
        // ⚠️ この掃除は **このイベントの予約だけ** を対象にすること。
        // 接頭辞だけで判定すると、渡されたのは今開いているイベントの写真だけなので、
        // 別のイベントのタイムカプセルの予約まで巻き添えで消えてしまう。
        // グループを切り替えただけで、前のイベントの思い出が
        // 公開日を迎えても通知されなくなる、という壊れ方をする。
        let keepIDs = Set(pending.map { notificationID(for: $0) })
        let existing = await center.pendingNotificationRequests()
        let stale = existing
            .filter { request in
                guard request.identifier.hasPrefix(Self.prefix) else { return false }
                guard (request.content.userInfo["eventID"] as? String) == event.id.uuidString
                else { return false }   // 他のイベントの予約には触れない
                return !keepIDs.contains(request.identifier)
            }
            .map(\.identifier)

        if !stale.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: stale)
        }

        let eventName = event.name

        for photo in pending {
            guard let revealDate = photo.revealDate, revealDate > now else { continue }

            let content = UNMutableNotificationContent()
            content.title = eventName
            content.body = message(for: photo, viewerID: viewerID)
            content.sound = .default
            content.userInfo = [
                "eventID": photo.eventID.uuidString,
                "photoID": photo.id.uuidString,
                "type": "timeCapsuleReveal",
            ]

            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: revealDate
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

            let request = UNNotificationRequest(
                identifier: notificationID(for: photo),
                content: content,
                trigger: trigger
            )

            do {
                try await center.add(request)
            } catch {
                print("❌ 通知の予約に失敗 (\(photo.id)): \(error)")
            }
        }

        print("🔔 タイムカプセルの公開通知を \(pending.count) 件予約しました")
    }

    /// このイベントに紐づく予約をすべて取り消す（イベントを離脱したときなど）
    func cancelReveals(for eventID: UUID) async {
        let requests = await center.pendingNotificationRequests()
        let ids = requests
            .filter { ($0.content.userInfo["eventID"] as? String) == eventID.uuidString }
            .map(\.identifier)

        guard !ids.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: ids)
        print("🔕 \(ids.count) 件の公開通知を取り消しました")
    }

    /// 指定した写真の予約だけを取り消す。
    /// シェア優先でタイムカプセルを解除したときに使う。
    func cancelReveals(for photoIDs: [UUID]) async {
        guard !photoIDs.isEmpty else { return }
        let ids = photoIDs.map { Self.prefix + $0.uuidString }
        center.removePendingNotificationRequests(withIdentifiers: ids)
        print("🔕 \(ids.count) 件の公開通知を取り消しました（シェア優先による解除）")
    }

    // MARK: - 文言

    private static let prefix = "timecapsule-"

    private func notificationID(for photo: Photo) -> String {
        Self.prefix + photo.id.uuidString
    }

    private func message(for photo: Photo, viewerID: String) -> String {
        if photo.uploaderID == viewerID {
            return "あなたが残した思い出が公開されました"
        }

        let name = photo.uploaderName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let name, !name.isEmpty {
            return "\(name)さんの新しい思い出が公開されました"
        }
        return "新しい思い出が公開されました"
    }
}
