import SwiftUI
import UserNotifications
import CloudKit
import WidgetKit

@main
struct EventSnapApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var eventViewModel = EventViewModel()
    @Environment(\.scenePhase) private var scenePhase

    /// App Store提出用スクリーンショットの撮影モードでのみ、Fixtureを注入する。
    /// 通常起動では何も起きず、Releaseビルドでは呼び出しごと消える
    /// （`Preview/ScreenshotMode.swift`を参照）。
    init() {
        ScreenshotMode.installFixturesIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            // HomeViewには必ずこのインスタンスを渡す。このアプリは
            // `@EnvironmentObject`を使っていないため、`.environmentObject(...)`で
            // 渡すだけではHomeView側の独自インスタンスに上書きされ、
            // handleDeepLink等でのpendingTab更新が一切届かなくなる
            // （詳細はHomeView.swiftのコメント参照）。
            HomeView(eventViewModel: eventViewModel)
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { userActivity in
                    handleUniversalLink(userActivity)
                }
                .onOpenURL { url in
                    handleDeepLink(url)
                }
                .onChange(of: scenePhase) { _, phase in
                    // 復帰のたびに公開通知を予約し直す。
                    // サイレントプッシュを取りこぼしていても、ここで追いつける。
                    if phase == .active {
                        Task { await SyncCoordinator.refreshTimeCapsules() }
                    }
                }
                .onReceive(NotificationService.shared.$pendingReveal.compactMap { $0 }) { target in
                    handleNotificationReveal(target)
                }
        }
    }

    /// 公開通知をタップしたときの行き先を解決する。
    ///
    /// `handleDeepLink`と同じ「参加履歴に見つかる場合だけイベントを切り替える」
    /// 方針を踏襲する。見つかった場合はアルバムタブへ切り替えたうえで、対象写真の
    /// フルスクリーン表示を`MainTabView`に依頼する（`pendingRevealPhotoID`経由）。
    private func handleNotificationReveal(_ target: NotificationService.RevealTarget) {
        Task {
            defer { NotificationService.shared.pendingReveal = nil }

            if eventViewModel.currentEvent?.id != target.eventID {
                guard let match = eventViewModel.recentEvents.first(where: { $0.id == target.eventID }) else {
                    print("⚠️ 通知タップ先のイベントは参加履歴に見つかりませんでした: \(target.eventID)")
                    return
                }
                await eventViewModel.switchEvent(to: match)
            }

            // 通知が届いた直後で、まだこの端末に写真一覧が同期されていない場合に備えて
            // 取り直しておく（見つからなければフルスクリーンは開かず、アルバムだけ開く）。
            try? await PhotoRepository.shared.fetchPhotos(for: target.eventID)

            eventViewModel.pendingTab = .album
            eventViewModel.pendingRevealPhotoID = target.photoID
        }
    }

    /// Widget / Live Activityからの内部ディープリンク(`eventsnap://`)の処理。
    ///
    /// 既存のUniversal Link（`https://eventsnap-website.vercel.app/event/{eventID}`、
    /// `handleUniversalLink`）は「その場に居合わせた人がQR経由で参加する」専用の
    /// 入口であり、こちらとは役割も入口も別なので、既存の処理には一切手を入れない。
    ///
    /// タブ単位のディープリンクに留めている（`AppTab`にEvent Reel/Time Capsule専用の
    /// 画面遷移スタックが無いため）。指定イベントが現在のイベントでなければ、
    /// 参加履歴の中に見つかる場合のみ切り替える（見つからなければ何もしない＝
    /// 参加していないイベントへは飛ばない）。
    ///
    /// **Widgetからの`.eventReel`だけは設定タブへの遷移に留めない**。Widgetの役割は
    /// 「Event Reelを見せて、その場でシェアしてもらう」ことなので、タブ切り替えに
    /// 加えて`pendingReelID`をセットし、`MainTabView`がその場でシェア画面を
    /// シートとして直接開く(Live Activity/Dynamic Islandは`.event`にしか
    /// リンクしないため、この経路には来ない)。
    private func handleDeepLink(_ url: URL) {
        guard let destination = EventSnapDeepLink.parse(url) else { return }

        let eventID: UUID
        let tab: AppTab
        var reelID: UUID?
        switch destination {
        case .event(let id):
            eventID = id
            tab = .album
        case .eventReel(let id, let rID):
            eventID = id
            tab = .settings // シート表示に失敗した場合の保険として、設定タブの「Event Reelを見る」にも行けるようにしておく
            reelID = rID
        case .timeCapsule(let id):
            eventID = id
            tab = .album // タイムカプセルの枠はアルバムタブに混在表示される
        case .camera(let id):
            eventID = id
            tab = .camera // Live Activityのシャッターボタンから直接撮影画面へ
        }

        Task {
            if eventViewModel.currentEvent?.id != eventID {
                guard let match = eventViewModel.recentEvents.first(where: { $0.id == eventID }) else {
                    print("⚠️ ディープリンク先のイベントは参加履歴に見つかりませんでした: \(eventID)")
                    return
                }
                await eventViewModel.switchEvent(to: match)
            }
            eventViewModel.pendingTab = tab
            eventViewModel.pendingReelID = reelID
        }
    }

    /// Universal Link / App Clip URLの処理
    private func handleUniversalLink(_ userActivity: NSUserActivity) {
        guard let incomingURL = userActivity.webpageURL else {
            print("❌ URLが見つかりません")
            return
        }

        print("📥 Universal Link受信: \(incomingURL)")

        // このURLはQRコード（App Clip）にのみ埋め込まれる。
        // 招待コードのような、その場に居なくても入れる経路は持たせない。
        if let eventID = extractEventID(from: incomingURL) {
            print("✅ イベントID抽出成功: \(eventID)")
            Task {
                await eventViewModel.joinEvent(eventID: eventID)
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

    /// 公開通知がタップされたときの入口。
    /// ここでは行き先を`NotificationService.pendingReveal`にセットするだけで、
    /// 実際のイベント切り替え・タブ遷移・フルスクリーン表示は`EventSnapApp`側で行う
    /// （`SwiftUI`の状態はそちらが真の情報源のため）。
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        await NotificationService.shared.handleNotificationTap(
            userInfo: response.notification.request.content.userInfo
        )
    }
}

// MARK: - 同期

/// 写真の同期・タイムカプセル通知の予約・Event Reelの生成チェック・
/// Widget/Live Activityへの状態反映をまとめて行う。
///
/// **重要**: Widget/Live Activity自身はCloudKitにもPhotoAnalyzerにも触れない。
/// ここ(メインアプリ)が同期・生成した結果をApp Group経由でミラーするだけにする
/// （`EventSnapSharedState`のコメントを参照）。
enum SyncCoordinator {
    @MainActor
    static func refreshTimeCapsules() async {
        // 撮影モードでは同期しない。注入済みのFixtureをCloudKitの結果で
        // 上書きしてしまうのを防ぐ（Widget/Live Activityの更新も行わない）。
        guard !ScreenshotMode.suppressesLiveServices else { return }

        guard let event = EventRepository.shared.currentEvent else {
            // 参加中のイベントが無くなった(最後のイベントを離脱した等)場合は、
            // Widgetに前のイベントの情報が残り続けないようクリアする。
            clearWidgetAndActivityIfNeeded()
            return
        }

        do {
            try await PhotoRepository.shared.fetchPhotos(for: event.id)
        } catch {
            print("⚠️ 写真の同期に失敗: \(error)")
            return
        }

        // リアクションの変更もサイレントプッシュで届く（`ReactionRepository.setupSubscription`）。
        // アルバムを開いたままの参加者にもその場で反映されるよう、写真と一緒に取り直す。
        do {
            try await ReactionRepository.shared.fetchReactions(for: event.id)
        } catch {
            print("⚠️ リアクションの同期に失敗: \(error)")
        }

        await NotificationService.shared.scheduleReveals(
            for: PhotoRepository.shared.allPhotos,
            event: event,
            viewerID: DeviceIdentity.current
        )

        // イベント中でも、シェアOKの新着写真があれば
        // 新しいEvent Reelを作る（イベント終了を待たない）
        // ※ Event Reelが新しく生成された場合のWidget/Live Activityへの通知は
        //   ShareCollageBuilder.notifyNewReel が担う(生成の成功可否を最も
        //   近くで知っているのがShareCollageBuilder自身のため)。
        await ShareCollageBuilder.buildIfNeeded(for: event)

        await updateWidgetAndActivity(for: event)
    }

    /// 参加人数・写真枚数・タイムカプセル残数など、Event Reel生成の有無に関わらず
    /// 毎回の同期で変わりうる状態をWidget/Live Activityへ反映する。
    ///
    /// `private`にしていない: `CameraViewModel`が撮影のたびにも直接呼ぶ
    /// (`refreshTimeCapsules`はscenePhaseが`.active`に変わるタイミングでしか
    /// 走らないため、撮影を連投している間は写真枚数がLive Activityに反映されない
    /// ままになる。「次の写真が撮られた」という自然な合図でNEW MEMORY表示を
    /// 通常表示へ戻す仕組みも、この即時反映があって初めて機能する)。
    @MainActor
    static func updateWidgetAndActivity(for event: Event) async {
        let eventPhotos = PhotoRepository.shared.allPhotos.filter { $0.eventID == event.id }
        let photoCount = eventPhotos.count
        let lockedCount = TimeCapsuleService.lockedCapsules(eventPhotos).count

        EventSnapSharedState.updateEventState(
            eventID: event.id, eventName: event.name, participantCount: event.participantIDs.count,
            isActive: event.isActive, photoCount: photoCount, timeCapsuleLockedCount: lockedCount
        )

        // 新規生成時の通知(ShareCollageBuilder.notifyNewReel)だけに頼ると、
        // 「この機能が入る前から存在したReel」や「App Group側のミラーが
        // 何らかの理由で欠けたまま」のケースでWidgetに画像が反映されない。
        // 毎回の同期で、既知の最新Reelと食い違っていれば必ずミラーし直す。
        if let latestReel = ShareCollageStore.shared.reels(for: event.id).first,
           latestReel.id != EventSnapSharedState.load().latestReelID,
           let image = ShareCollageStore.shared.image(for: latestReel) {
            EventSnapSharedState.updateLatestReel(reelID: latestReel.id, builtAt: latestReel.builtAt, image: image)
        }

        WidgetCenter.shared.reloadTimelines(ofKind: "EventSnapWidget")

        guard event.isActive else { return }
        EventActivityManager.startIfNeeded(event: event, participantCount: event.participantIDs.count, photoCount: photoCount)
        await EventActivityManager.updateCounts(
            eventID: event.id, eventName: event.name, participantCount: event.participantIDs.count, photoCount: photoCount
        )
    }

    /// 参加中のイベントが無い状態を、Widgetにも正しく反映する(すでに空なら何もしない)。
    @MainActor
    private static func clearWidgetAndActivityIfNeeded() {
        guard EventSnapSharedState.load().eventID != nil else { return }
        EventSnapSharedState.updateEventState(
            eventID: nil, eventName: nil, participantCount: 0, isActive: false, photoCount: 0, timeCapsuleLockedCount: 0
        )
        WidgetCenter.shared.reloadTimelines(ofKind: "EventSnapWidget")
    }
}
