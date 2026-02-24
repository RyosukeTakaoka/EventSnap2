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
    @Published var isLoading = false
    @Published var error: String?
    @Published var hasJoinedEvent = false

    private let eventRepository = EventRepository.shared
    private var cancellables = Set<AnyCancellable>() // ← 追加

    // MARK: - 初期化
    
    init() {
        print("🎬 EventViewModel初期化開始")
        observeRepository() // ← これを追加！
        
        // Repositoryから現在のイベントを同期
        self.currentEvent = eventRepository.currentEvent
        self.participants = eventRepository.participants
        
        // イベントが既に存在するかチェック
        if currentEvent != nil {
            self.hasJoinedEvent = true
            print("✅ 既存のイベントを読み込みました: \(currentEvent?.name ?? "")")
        } else {
            print("⚠️ イベントがまだ作成されていません")
        }
    }

    // MARK: - イベント作成

    func createEvent(name: String = "新しいイベント") async {
        isLoading = true
        error = nil

        do {
            let event = try await eventRepository.createEvent(name: name)
            self.hasJoinedEvent = true
            print("✅ イベント作成成功: \(event.name)")
            print("📋 イベントID: \(event.id.uuidString)")
        } catch {
            self.error = "イベントの作成に失敗しました"
            print("❌ イベント作成エラー: \(error)")
        }

        isLoading = false
    }

    // MARK: - イベント参加

    func joinEvent(eventID: String) async {
        isLoading = true
        error = nil

        do {
            try await eventRepository.joinEvent(eventID: eventID)
            self.hasJoinedEvent = true
            print("✅ イベント参加成功")
            print("📋 参加したイベントID: \(eventID)")
        } catch {
            self.error = "イベントへの参加に失敗しました"
            print("❌ イベント参加エラー: \(error)")
        }

        isLoading = false
    }

    // MARK: - イベント更新

    func refreshEvent() async {
        do {
            try await eventRepository.refreshEvent()
            print("✅ イベント情報を更新しました")
        } catch {
            print("❌ イベント更新エラー: \(error)")
        }
    }

    // MARK: - イベント終了

    func endEvent() async {
        do {
            try await eventRepository.endEvent()
            self.hasJoinedEvent = false
            print("✅ イベント終了")
        } catch {
            self.error = "イベントの終了に失敗しました"
            print("❌ イベント終了エラー: \(error)")
        }
    }

    // MARK: - Repository監視

    private func observeRepository() {
        print("👀 EventRepositoryの監視を開始します")
        
        // EventRepositoryの変更を監視
        eventRepository.$currentEvent
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                print("🔄 currentEventが更新されました: \(event?.name ?? "nil")")
                self?.currentEvent = event
                if event != nil {
                    self?.hasJoinedEvent = true
                }
            }
            .store(in: &cancellables)

        eventRepository.$participants
            .receive(on: DispatchQueue.main)
            .sink { [weak self] participants in
                print("🔄 participantsが更新されました: \(participants.count)人")
                self?.participants = participants
            }
            .store(in: &cancellables)
    }
}
