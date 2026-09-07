//
//  NotificationService.swift
//  EventSnap
//
//  タイムカプセルの公開通知
//

import Foundation
import UserNotifications
import Combine
import UIKit

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
final class NotificationService: ObservableObject {
    static let shared = NotificationService()

    /// 公開通知をタップして、対象の写真をフルスクリーンで開くための行き先。
    struct RevealTarget: Equatable {
        let eventID: UUID
        let photoID: UUID
    }

    /// 公開通知がタップされたときに立つ。`EventSnapApp`が監視し、対象イベントへ
    /// 切り替えたうえで対象写真をフルスクリーン表示する。処理し終えたら`nil`に戻す。
    @Published var pendingReveal: RevealTarget?

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
        // 撮影モードでは通知許可を要求しない。
        // 許可ダイアログがスクリーンショットに写り込むのを防ぐ。
        guard !ScreenshotMode.suppressesLiveServices else { return false }

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
        // 撮影モードではローカル通知を予約しない
        guard !ScreenshotMode.suppressesLiveServices else { return }

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

    // MARK: - リアクションの通知

    /// 自分の写真に付いた新しいリアクションを知らせる。
    ///
    /// タイムカプセルの公開通知と違って**予約ではなく即時**に出す。
    /// リアクションが作られた瞬間に`CKQuerySubscription`のサイレントプッシュが
    /// 届き、`SyncCoordinator`がリアクションを取り直したところで呼ばれる。
    ///
    /// 通知するのは **自分がアップロードした写真に、他の人が付けたリアクション** だけ。
    /// 一度知らせたものは`UserDefaults`に記録して二度と鳴らさない
    /// （フォアグラウンド復帰のたびに`SyncCoordinator`が走るため、
    /// 記録が無いと同じリアクションで何度も鳴ってしまう）。
    func notifyNewReactions(_ reactions: [Reaction], photos: [Photo], event: Event, viewerID: String) async {
        guard !ScreenshotMode.suppressesLiveServices else { return }
        guard await isAuthorized else { return }

        // 自分がアプリを見ている最中に、自分宛ての通知をバナーで被せない。
        // (`AppDelegate.willPresent`が前面でも表示する設定のため、ここで止める)
        guard UIApplication.shared.applicationState != .active else { return }

        let myPhotoIDs = Set(photos.filter { $0.uploaderID == viewerID }.map(\.id))
        let candidates = reactions.filter { myPhotoIDs.contains($0.photoID) && $0.reactorID != viewerID }

        var alreadyNotified = Set(UserDefaults.standard.stringArray(forKey: Self.notifiedReactionsKey) ?? [])
        let fresh = candidates.filter { !alreadyNotified.contains($0.id) }

        // 記録は「今も存在するリアクション」だけに絞って持ち続ける。
        // そうしないとイベントを重ねるほど際限なく増えていく。
        // (取り消されたリアクションが押し直された場合は、もう一度鳴ってよい)
        alreadyNotified = Set(candidates.map(\.id))
        UserDefaults.standard.set(Array(alreadyNotified), forKey: Self.notifiedReactionsKey)

        guard !fresh.isEmpty else { return }

        // 1リアクション1通知にすると、まとめて押されたときに通知が連打される。
        // 写真ごとに1件へまとめる。
        for (photoID, group) in Dictionary(grouping: fresh, by: \.photoID) {
            let emojis = Self.uniqueJoined(group.map(\.emoji), separator: "", limit: 3)
            let names = Self.uniqueJoined(group.map(\.displayName), separator: "、", limit: 2)

            let content = UNMutableNotificationContent()
            content.title = event.name
            content.body = "\(names)があなたの写真に \(emojis) でリアクションしました"
            content.sound = .default
            content.userInfo = [
                "eventID": event.id.uuidString,
                "photoID": photoID.uuidString,
                "type": Self.reactionType,
            ]

            await deliverImmediately(content, identifier: "reaction-\(photoID.uuidString)-\(Date().timeIntervalSince1970)")
        }
    }

    // MARK: - 久しぶりの投稿の通知

    /// 「しばらく途切れていたイベントで、また誰かが撮った」ことを知らせる。
    ///
    /// ## なぜこの通知が要るか
    ///
    /// EventSnapはイベント用なので、何も知らせないと「後で思い出したときに
    /// 開く」以外にアプリを開く動機が無い。特に、打ち上げや二次会など
    /// **本編が終わったあとに誰かが撮り始めた**タイミングは、
    /// 参加者にとって一番知りたい瞬間なのに一番気づかれにくい。
    ///
    /// 逆に、撮影が続いている最中に1枚ごとへ通知を出すと、ただの連打になる。
    /// そこで「**直前の写真から`quietPeriod`以上あいてからの投稿**」に絞って、
    /// 場が再開したことだけを知らせる。
    func notifyRestartedShooting(photos: [Photo], event: Event, viewerID: String) async {
        guard !ScreenshotMode.suppressesLiveServices else { return }
        guard await isAuthorized else { return }
        guard UIApplication.shared.applicationState != .active else { return }

        // 伏せられているタイムカプセルは見に行っても何も見えないので数えない。
        // 「見られる写真が増えた」ときだけ知らせる。
        let visible = TimeCapsuleService.albumPhotos(photos).sorted { $0.uploadedAt < $1.uploadedAt }
        guard let latest = visible.last, visible.count >= 2 else { return }

        // 自分が撮った写真では鳴らさない
        guard latest.uploaderID != viewerID else { return }

        // 直前の写真との間隔が空いていなければ、まだ撮影が続いている最中。
        let previous = visible[visible.count - 2]
        guard latest.uploadedAt.timeIntervalSince(previous.uploadedAt) >= Self.quietPeriod else { return }

        // 参加した直後に過去の写真を取り込んだだけ、というときに鳴らさないための保険。
        // 「今まさに撮られた」ものだけを対象にする。
        guard Date().timeIntervalSince(latest.uploadedAt) <= Self.freshnessWindow else { return }

        var notified = Set(UserDefaults.standard.stringArray(forKey: Self.notifiedRestartKey) ?? [])
        guard !notified.contains(latest.id.uuidString) else { return }

        // 記録は現存する写真の分だけ残す（際限なく増えないように）
        notified.insert(latest.id.uuidString)
        let alivePhotoIDs = Set(photos.map { $0.id.uuidString })
        UserDefaults.standard.set(Array(notified.intersection(alivePhotoIDs)), forKey: Self.notifiedRestartKey)

        let trimmedName = latest.uploaderName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let who = trimmedName.isEmpty ? "誰か" : "\(trimmedName)さん"

        let content = UNMutableNotificationContent()
        content.title = event.name
        content.body = "\(who)がまた写真を撮り始めました"
        content.sound = .default
        content.userInfo = [
            "eventID": event.id.uuidString,
            "photoID": latest.id.uuidString,
            "type": Self.restartType,
        ]

        await deliverImmediately(content, identifier: "restart-\(latest.id.uuidString)")
    }

    /// 予約ではなく、その場で通知を出す（`trigger: nil`）。
    private func deliverImmediately(_ content: UNMutableNotificationContent, identifier: String) async {
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        do {
            try await center.add(request)
        } catch {
            print("❌ 通知の送信に失敗 (\(identifier)): \(error)")
        }
    }

    // MARK: - 通知タップ

    /// 通知の`userInfo`から対象イベント・対象写真を取り出し、`pendingReveal`にセットする。
    ///
    /// 公開通知・リアクション・撮影再開のどれも「対象の写真を開く」で行き先は同じなので、
    /// 3種類とも同じ仕組みに乗せている（`EventSnapApp.handleNotificationReveal`）。
    func handleNotificationTap(userInfo: [AnyHashable: Any]) {
        let handledTypes = ["timeCapsuleReveal", Self.reactionType, Self.restartType]

        guard let type = userInfo["type"] as? String, handledTypes.contains(type),
              let eventIDString = userInfo["eventID"] as? String,
              let eventID = UUID(uuidString: eventIDString),
              let photoIDString = userInfo["photoID"] as? String,
              let photoID = UUID(uuidString: photoIDString)
        else { return }

        pendingReveal = RevealTarget(eventID: eventID, photoID: photoID)
    }

    // MARK: - 設定値

    /// 「撮影が再開した」とみなす、直前の写真からの間隔。
    ///
    /// 短くしすぎると撮影中の連打になり、長くしすぎると二次会の開始に
    /// 気づけない。**ここを変えるだけで調整できる**ようにまとめてある。
    static let quietPeriod: TimeInterval = 3 * 60 * 60   // 3時間

    /// 「今まさに撮られた」とみなす猶予。イベントに参加した直後に過去の写真を
    /// まとめて取り込んだだけ、というときに通知が鳴らないようにするための保険。
    private static let freshnessWindow: TimeInterval = 30 * 60   // 30分

    private static let reactionType = "photoReaction"
    private static let restartType = "shootingRestarted"

    private static let notifiedReactionsKey = "notifiedReactionIDs"
    private static let notifiedRestartKey = "notifiedRestartPhotoIDs"

    // MARK: - 文言

    private static let prefix = "timecapsule-"

    private func notificationID(for photo: Photo) -> String {
        Self.prefix + photo.id.uuidString
    }

    /// 重複を取り除いて先頭`limit`件までを連ねる。それ以上あれば「ほか」を付ける。
    /// 通知本文が長くなりすぎないようにするためのもの。
    private static func uniqueJoined(_ values: [String], separator: String, limit: Int) -> String {
        var seen = Set<String>()
        let unique = values.filter { seen.insert($0).inserted }
        let head = unique.prefix(limit).joined(separator: separator)
        return unique.count > limit ? head + "ほか" : head
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
