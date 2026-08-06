//
//  EventViewModel.swift
//  EventSnap
//
//  イベント管理ViewModel
//

import Foundation
import SwiftUI
import Combine

@MainActor
class EventViewModel: ObservableObject {
    @Published var currentEvent: Event?
    @Published var participants: [Participant] = []
    @Published var recentEvents: [Event] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var hasJoinedEvent = false

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

        if currentEvent != nil {
            self.hasJoinedEvent = true
        } else {
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
            self.hasJoinedEvent = true
            // 作った直後は人を呼びたいので招待画面から始める
            self.pendingTab = .invite
            print("✅ イベント作成成功: \(event.name) / \(event.id.uuidString)")
        } catch {
            self.error = "イベントの作成に失敗しました"
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
            self.hasJoinedEvent = true
            // 参加した側はまず何が撮られているか見たいはずなのでアルバムへ
            self.pendingTab = .album
            print("✅ イベント参加成功")
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription
                ?? "イベントへの参加に失敗しました"
            print("❌ イベント参加エラー: \(error)")
        }

        isLoading = false
    }

    // MARK: - グループ切り替え

    func switchEvent(to event: Event) async {
        await eventRepository.switchEvent(to: event)
        self.hasJoinedEvent = true
    }

    func leaveEvent(_ event: Event) async {
        await eventRepository.leaveEvent(event)
        self.hasJoinedEvent = eventRepository.currentEvent != nil
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

    /// 終了直後にコラージュが作れたか（シェア導線の出し分けに使う）
    @Published var didGenerateCollage = false

    func endEvent() async {
        let event = currentEvent

        do {
            try await eventRepository.endEvent()
            print("✅ イベント終了")
        } catch {
            self.error = "イベントの終了に失敗しました"
            print("❌ イベント終了エラー: \(error)")
            return
        }

        // イベントが終わったタイミングでシェア用コラージュを作る（機能B）。
        // シェアOKの写真が0枚なら nil が返り、シェア導線自体を出さない。
        if let event {
            let ended = eventRepository.currentEvent ?? event
            didGenerateCollage = await ShareCollageBuilder.buildIfPossible(for: ended) != nil
        }
    }

    // MARK: - Repository監視

    private func observeRepository() {
        eventRepository.$currentEvent
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                self?.currentEvent = event
                if event != nil { self?.hasJoinedEvent = true }
            }
            .store(in: &cancellables)

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
