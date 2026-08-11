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

@MainActor
class EventViewModel: ObservableObject {
    @Published var currentEvent: Event?
    @Published var participants: [Participant] = []
    @Published var recentEvents: [Event] = []
    @Published var isLoading = false
    @Published var error: String?

    /// イベント作成／参加の直後に開くべきタブ
    @Published var pendingTab: AppTab?

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

        do {
            let event = try await eventRepository.createEvent(name: name)
            // 作った直後は人を呼びたいので招待画面から始める
            self.pendingTab = .invite
            print("✅ イベント作成成功: \(event.name) / \(event.id.uuidString)")
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
        } catch {
            self.error = Self.message(for: error, fallback: "イベントへの参加に失敗しました")
            print("❌ イベント参加エラー: \(error)")
        }

        isLoading = false
    }

    // MARK: - グループ切り替え

    func switchEvent(to event: Event) async {
        await eventRepository.switchEvent(to: event)
    }

    func leaveEvent(_ event: Event) async {
        await eventRepository.leaveEvent(event)
    }

    func loadRecentEvents() async {
        await eventRepository.loadRecentEvents()
    }

    // MARK: - イベント更新

    func refreshEvent() async {
        do {
            try await eventRepository.refreshEvent()
        } catch {
            print("❌ イベント更新エラー: \(error)")
        }
    }

    // MARK: - イベント終了

    /// イベントを終了する。
    ///
    /// Event Reelはイベント中に随時作られているため、終了をきっかけに
    /// 何かを生成する必要はない（`ShareCollageBuilder.buildIfNeeded` 参照）。
    func endEvent() async {
        do {
            try await eventRepository.endEvent()
            print("✅ イベント終了")
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
