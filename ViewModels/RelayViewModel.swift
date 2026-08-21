//
//  RelayViewModel.swift
//  EventSnap
//
//  RelayViewModel
//

import Foundation
import SwiftUI
import Combine

/// Relayの進行状況グリッドに並べる1人分の表示情報
struct RelayParticipantRow: Identifiable {
    let participant: Participant
    let slot: RelaySlot

    var id: String { participant.id }
    var isSelf: Bool { participant.id == DeviceIdentity.current }
}

@MainActor
final class RelayViewModel: ObservableObject {
    @Published var session: RelaySession?
    @Published var isLoading = false
    @Published var isStarting = false
    @Published var error: String?

    private let relayRepository = RelayRepository.shared
    private let eventRepository = EventRepository.shared
    private let photoRepository = PhotoRepository.shared
    private var cancellables = Set<AnyCancellable>()

    init() {
        relayRepository.$currentSession
            .receive(on: DispatchQueue.main)
            .assign(to: &$session)
    }

    // MARK: - 参加可否

    /// 終了したイベントには新しい写真を追加できない（Relayも例外ではない）。
    var canAddNewMoment: Bool {
        eventRepository.currentEvent?.isActive ?? false
    }

    var participants: [Participant] { eventRepository.participants }

    /// 進行状況グリッド用。Relayの並び順（`participantOrder`）で返す。
    var rows: [RelayParticipantRow] {
        guard let session else { return [] }
        let byID = Dictionary(uniqueKeysWithValues: participants.map { ($0.id, $0) })

        return session.slots.compactMap { slot in
            let participant = byID[slot.participantID]
                ?? Participant(id: slot.participantID, deviceName: "参加者")
            return RelayParticipantRow(participant: participant, slot: slot)
        }
    }

    var mySlot: RelaySlot? {
        session?.slot(for: DeviceIdentity.current)
    }

    /// 自分の枠が開放されていて、まだ撮影・選択していない状態か
    var isMyTurnOpen: Bool {
        mySlot?.status == .open
    }

    /// 「もうすぐあなたの番です」の案内を出すべきか。
    /// 自分の枠がまだ`waiting`で、かつ自分より前に`waiting`の人がいない
    /// （＝次に開放されるのが自分）場合だけ表示する。先の方の人にまで
    /// 「もうすぐ」を出すと煩わしいため、直近だけに絞る。
    var isMyTurnComingSoon: Bool {
        guard let session, mySlot?.status == .waiting else { return false }
        guard let myIndex = session.slots.firstIndex(where: { $0.participantID == DeviceIdentity.current }) else { return false }
        return session.slots[..<myIndex].allSatisfy { $0.status != .waiting }
    }

    // MARK: - 読み込み・繰り上げ反映

    /// RelaySessionを取得し、期限切れの繰り上げを反映する。
    /// アプリ起動時・Relay画面を開いた際・silent push受信時、いずれの経路からも必ず呼ぶ
    /// （`NotificationService`と同じ「取りこぼしても復帰する」設計）。
    func loadSession() async {
        guard let event = eventRepository.currentEvent else { return }

        isLoading = true
        defer { isLoading = false }

        let previousStatus = session?.slot(for: DeviceIdentity.current)?.status
        relayRepository.setupSubscription(for: event.id)

        do {
            guard let fetched = try await relayRepository.fetchSession(for: event.id) else { return }

            // 自分の枠が「まだ」から「開放」に変わっていた場合、前の人が前倒しで
            // 撮り終えた可能性がある。予約済みの通知（先の時刻を指している）を
            // 取り消し、その場で即時通知に差し替える。
            let newStatus = fetched.slot(for: DeviceIdentity.current)?.status
            if previousStatus == .waiting, newStatus == .open {
                await RelayNotificationService.shared.notifyTurnOpenedNow(event: event, viewerID: DeviceIdentity.current)
            }

            await RelayNotificationService.shared.scheduleIfNeeded(session: fetched, event: event, viewerID: DeviceIdentity.current)
        } catch {
            print("⚠️ Relayの取得に失敗: \(error)")
        }
    }

    // MARK: - 開始

    func startRelay() async {
        guard let event = eventRepository.currentEvent else { return }
        guard canAddNewMoment else { return }

        isStarting = true
        error = nil
        defer { isStarting = false }

        do {
            let session = try await relayRepository.startRelay(event: event, participantIDs: event.participantIDs)
            await RelayNotificationService.shared.scheduleIfNeeded(session: session, event: event, viewerID: DeviceIdentity.current)
        } catch {
            self.error = EventViewModel.message(for: error, fallback: "Relayの開始に失敗しました")
            print("❌ Relay開始エラー: \(error)")
        }
    }

    // MARK: - 投稿

    /// 新規撮影した写真をRelayに投稿する（アップロード自体は`PhotoRepository`が行う）。
    @discardableResult
    func submitNewPhoto(_ image: UIImage) async -> Bool {
        guard let event = eventRepository.currentEvent, canAddNewMoment else { return false }

        do {
            let photo = try await photoRepository.uploadPhoto(image, eventID: event.id)
            try await relayRepository.completeSlot(eventID: event.id, participantID: DeviceIdentity.current, photoID: photo.id)
            return true
        } catch {
            self.error = EventViewModel.message(for: error, fallback: "Relayへの投稿に失敗しました")
            print("❌ Relay投稿エラー: \(error)")
            return false
        }
    }
}
