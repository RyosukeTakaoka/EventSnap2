//
//  EventViewModel.swift
//  EventSnap
//
//  イベント管理ViewModel
//

import Foundation
import SwiftUI
import Combine
import CloudKit
import WidgetKit

@MainActor
class EventViewModel: ObservableObject {
    @Published var currentEvent: Event?
    @Published var participants: [Participant] = []
    @Published var recentEvents: [Event] = []
    @Published var isLoading = false
    @Published var error: String?

    /// イベント作成／参加の直後に開くべきタブ
    @Published var pendingTab: AppTab?

    /// Widgetからのディープリンクで、その場で開くべきEvent Reel。
    /// `MainTabView`がこれを見てシェア画面をシートとして直接開く。
    @Published var pendingReelID: UUID?

    /// 公開通知をタップして、その場で開くべき写真。
    /// `MainTabView`がこれを見てフルスクリーンで直接開く。
    @Published var pendingRevealPhotoID: UUID?

    private let eventRepository = EventRepository.shared
    private var cancellables = Set<AnyCancellable>()

    // MARK: - 初期化

    init() {
        observeRepository()

        self.currentEvent = eventRepository.currentEvent
        self.participants = eventRepository.participants
        self.recentEvents = eventRepository.recentEvents

        if currentEvent == nil {
            // 前回開いていたイベントを復元する（無ければ何も起きない）
            Task { await eventRepository.restoreEvent() }
        }
    }

    // MARK: - イベント作成

    func createEvent(name: String = "新しいイベント") async {
        isLoading = true
        error = nil

        // 作成に取り掛かる前の参加履歴で判定する
        // （Repeat Organizer Rate = 過去にも自分がイベントを作ったことがあるか）。
        let isRepeatOrganizer = recentEvents.contains { $0.creatorID == DeviceIdentity.current }

        do {
            let event = try await eventRepository.createEvent(name: name)
            // 作った直後は人を呼びたいので招待画面から始める
            self.pendingTab = .invite
            print("✅ イベント作成成功: \(event.name) / \(event.id.uuidString)")
            AnalyticsService.eventCreated(isRepeatOrganizer: isRepeatOrganizer)
        } catch {
            // 「失敗しました」だけだと原因が分からず詰まってしまうので、
            // iCloud未サインインなどの理由をそのまま出す
            self.error = Self.message(for: error, fallback: "イベントの作成に失敗しました")
            print("❌ イベント作成エラー: \(error)")
        }

        isLoading = false
    }

    // MARK: - イベント参加

    /// イベントに参加する。
    ///
    /// 呼ばれるのは **QRコードの読み取りとApp Clip / Universal Link だけ**。
    /// その場に居合わせた人しか入れない、というEventSnapの前提を守るため、
    /// コードを伝えるだけで参加できる経路は用意しない。
    func joinEvent(eventID: String) async {
        isLoading = true
        error = nil

        do {
            try await eventRepository.joinEvent(eventID: eventID)
            // 参加した側はまず何が撮られているか見たいはずなのでアルバムへ
            self.pendingTab = .album
            print("✅ イベント参加成功")
            AnalyticsService.eventJoined()
        } catch {
            self.error = Self.message(for: error, fallback: "イベントへの参加に失敗しました")
            print("❌ イベント参加エラー: \(error)")
        }

        isLoading = false
    }

    // MARK: - グループ切り替え

    func switchEvent(to event: Event) async {
        // 切り替え前のイベントのLive Activityは、切り替え先で作り直すため、
        // ここで即座に閉じておく。
        if let previous = currentEvent, previous.id != event.id {
            await EventActivityManager.endImmediately(eventID: previous.id)
        }
        await eventRepository.switchEvent(to: event)

        // 切り替え先イベントの写真・状態をすぐに取り込み、Widget/Live Activityを
        // 切り替え先の内容で作り直す。これを呼ばないと、次にアプリがフォアグラウンド
        // 復帰する(`scenePhase == .active`)までWidget/Live Activityが切り替え前の
        // イベントの情報を表示し続けてしまう(「切り替えたのに反映されない」不具合)。
        await SyncCoordinator.refreshTimeCapsules()
    }

    func leaveEvent(_ event: Event) async {
        await EventActivityManager.endImmediately(eventID: event.id)
        await eventRepository.leaveEvent(event)
        await SyncCoordinator.refreshTimeCapsules()
    }

    func loadRecentEvents() async {
        await eventRepository.loadRecentEvents()
    }

    // MARK: - イベント終了

    /// イベントを終了する。
    ///
    /// Event Reelはイベント中に随時作られているため、終了をきっかけに
    /// 何かを生成する必要はない（`ShareCollageBuilder.buildIfNeeded` 参照）。
    ///
    /// 終了後もWidget/Live Activityは「✨ Event Reel ready」のような形で
    /// 意味のある状態を見せ続ける（Live Activityはシステムに任せて数時間後に
    /// 自動的に片付く。Widgetは`eventState = .ended`のまま残り続ける）。
    func endEvent() async {
        do {
            guard let ended = try await eventRepository.endEvent() else { return }
            print("✅ イベント終了")

            let eventPhotos = PhotoRepository.shared.allPhotos.filter { $0.eventID == ended.id }
            let photoCount = eventPhotos.count
            let lockedCount = TimeCapsuleService.lockedCapsules(eventPhotos).count

            EventSnapSharedState.updateEventState(
                eventID: ended.id, eventName: ended.name, participantCount: ended.participantIDs.count,
                isActive: ended.isActive, photoCount: photoCount, timeCapsuleLockedCount: lockedCount
            )
            WidgetCenter.shared.reloadTimelines(ofKind: "EventSnapWidget")
            await EventActivityManager.markEnded(
                eventID: ended.id, eventName: ended.name, participantCount: ended.participantIDs.count, photoCount: photoCount
            )
        } catch {
            self.error = Self.message(for: error, fallback: "イベントの終了に失敗しました")
            print("❌ イベント終了エラー: \(error)")
        }
    }

    // MARK: - エラーの文言

    /// 何が起きたのか分かる日本語にして返す。
    ///
    /// 以前はすべて「イベントの作成に失敗しました」で潰していたため、
    /// iCloudにサインインしていないだけなのか、通信が悪いのか、
    /// CloudKitのスキーマが本番に反映されていないのかが区別できなかった。
    static func message(for error: Error, fallback: String) -> String {
        if let localized = error as? LocalizedError,
           let description = localized.errorDescription {
            return description
        }

        guard let ckError = error as? CKError else { return fallback }

        switch ckError.code {
        case .notAuthenticated:
            return "iCloudにサインインしていません。\n「設定」アプリからサインインしてください。"
        case .networkUnavailable, .networkFailure:
            return "ネットワークに接続できません。\n通信環境をご確認ください。"
        case .quotaExceeded:
            return "iCloudの空き容量が足りません。"
        case .permissionFailure:
            return "iCloudへの書き込みが許可されていません。\niCloudの設定をご確認ください。"
        case .serviceUnavailable, .requestRateLimited:
            return "iCloudが混み合っています。\nしばらくしてからもう一度お試しください。"
        case .unknownItem:
            return "イベントが見つかりませんでした。\nQRコードをもう一度読み取ってください。"
        case .invalidArguments, .constraintViolation:
            // スキーマ未反映のときにここへ来る。開発者向けの手掛かりを残す。
            return "サーバーの設定に問題があります。\n(\(ckError.localizedDescription))"
        default:
            return "\(fallback)\n(\(ckError.localizedDescription))"
        }
    }

    // MARK: - Repository監視

    private func observeRepository() {
        // MainTabViewを表示するかどうかは HomeView が EventRepository.shared を
        // 直接見て判断する（`currentEvent` の有無だけが真の情報源）ため、
        // ここでは currentEvent をそのまま流し込むだけでよい。
        eventRepository.$currentEvent
            .receive(on: DispatchQueue.main)
            .assign(to: &$currentEvent)

        // assign(to:on:) は self を強参照して循環参照になるため、
        // @Published へ直接流し込む assign(to:&$...) を使う。
        eventRepository.$participants
            .receive(on: DispatchQueue.main)
            .assign(to: &$participants)

        eventRepository.$recentEvents
            .receive(on: DispatchQueue.main)
            .assign(to: &$recentEvents)
    }
}
