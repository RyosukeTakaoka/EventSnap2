import SwiftUI
import UserNotifications
import CloudKit

@main
struct EventSnapApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var eventViewModel = EventViewModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(eventViewModel)
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { userActivity in
                    handleUniversalLink(userActivity)
                }
                .onChange(of: scenePhase) { _, phase in
                    // 復帰のたびに公開通知を予約し直す。
                    // サイレントプッシュを取りこぼしていても、ここで追いつける。
                    if phase == .active {
                        Task { await SyncCoordinator.refreshTimeCapsules() }
                    }
                }
        }
    }

    /// Universal Link / App Clip URLの処理
    private func handleUniversalLink(_ userActivity: NSUserActivity) {
        guard let incomingURL = userActivity.webpageURL else {
            print("❌ URLが見つかりません")
            return
        }

        print("📥 Universal Link受信: \(incomingURL)")

        if let eventID = extractEventID(from: incomingURL) {
            print("✅ イベントID抽出成功: \(eventID)")
            Task {
                await eventViewModel.joinEvent(eventID: eventID)
            }
        } else if let code = extractInviteCode(from: incomingURL) {
            print("✅ 招待コード抽出成功: \(code)")
            Task {
                await eventViewModel.joinEvent(inviteCode: code)
            }
        } else {
            print("❌ イベントIDの抽出に失敗しました")
        }
    }

    /// URLからイベントIDを抽出
    private func extractEventID(from url: URL) -> String? {
        // URLパターン: https://eventsnap.example.com/event/{eventID}
        let components = url.pathComponents

        if components.count >= 3 && components[1] == "event" {
            return components[2]
        }

        if let urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let queryItems = urlComponents.queryItems,
           let eventIDItem = queryItems.first(where: { $0.name == "eventID" }),
           let eventID = eventIDItem.value {
            return eventID
        }

        return nil
    }

    /// URLから招待コードを抽出（https://.../join/ABC123 形式）
    private func extractInviteCode(from url: URL) -> String? {
        let components = url.pathComponents

        if components.count >= 3, components[1] == "join" {
            let code = InviteCode.normalize(components[2])
            return InviteCode.isValid(code) ? code : nil
        }

        if let urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let item = urlComponents.queryItems?.first(where: { $0.name == "code" }),
           let raw = item.value {
            let code = InviteCode.normalize(raw)
            return InviteCode.isValid(code) ? code : nil
        }

        return nil
    }
}

// MARK: - AppDelegate

/// リモート通知の受け取り口。
///
/// タイムカプセルの公開通知は各端末のローカル通知で鳴らすが、
/// 「いつ公開されるどの写真があるか」は他人の端末で決まるので、
/// 写真が追加されたことをサイレントプッシュで知り、予約を取り直す。
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        // CloudKitのサブスクリプション通知を受け取るために必要
        application.registerForRemoteNotifications()
        return true
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any]
    ) async -> UIBackgroundFetchResult {
        // CloudKitからの通知か確認する
        guard CKNotification(fromRemoteNotificationDictionary: userInfo) != nil else {
            return .noData
        }

        print("📬 サイレントプッシュを受信。タイムカプセルの予約を更新します")
        await SyncCoordinator.refreshTimeCapsules()
        return .newData
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("❌ リモート通知の登録に失敗: \(error.localizedDescription)")
    }

    /// アプリを開いている間も通知を出す（公開の瞬間に気づいてほしいため）
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }
}

// MARK: - 同期

/// 写真の取得とタイムカプセル通知の予約をまとめて行う
enum SyncCoordinator {
    @MainActor
    static func refreshTimeCapsules() async {
        guard let event = EventRepository.shared.currentEvent else { return }

        do {
            try await PhotoRepository.shared.fetchPhotos(for: event.id)
        } catch {
            print("⚠️ 写真の同期に失敗: \(error)")
            return
        }

        await NotificationService.shared.scheduleReveals(
            for: PhotoRepository.shared.allPhotos,
            eventName: event.name,
            viewerID: DeviceIdentity.current
        )
    }
}
