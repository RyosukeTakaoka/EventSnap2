//
//  TimeCapsuleViewModel.swift
//  EventSnap
//
//  タイムカプセルタブのViewModel（イベント参加者全員で共有する状態を表示する）
//

import Foundation
import SwiftUI
import Combine

@MainActor
final class TimeCapsuleViewModel: ObservableObject {
    /// まだ公開されていない写真（枚数とぼかした残り時間だけ見せる）。
    /// 誰が撮ったかに関わらず、参加者全員が同じ枚数・同じ待ち時間を共有する。
    @Published var locked: [Photo] = []
    /// 公開済みのタイムカプセル写真（新しく公開されたものが上）
    @Published var revealed: [Photo] = []
    @Published var isLoading = false

    private let photoRepository = PhotoRepository.shared
    private let eventRepository = EventRepository.shared
    private var cancellables = Set<AnyCancellable>()

    /// 公開時刻をまたいだ瞬間に画面へ反映するためのタイマー
    private var tickTimer: AnyCancellable?

    init() {
        observeRepository()
        recompute()
    }

    var lockedCount: Int { locked.count }
    var hasAnything: Bool { !locked.isEmpty || !revealed.isEmpty }

    /// 次に公開される写真のぼかした案内文
    var nextRevealHint: String? {
        guard let next = locked.first else { return nil }
        return TimeCapsuleService.vagueCountdown(for: next)
    }

    // MARK: - 取得

    func refresh() async {
        guard let eventID = eventRepository.currentEvent?.id else { return }

        isLoading = true
        do {
            try await photoRepository.fetchPhotos(for: eventID)
            await scheduleNotifications()
        } catch {
            print("❌ タイムカプセルの取得に失敗: \(error)")
        }
        isLoading = false
    }

    /// 未公開の写真に対して公開通知を予約し直す
    func scheduleNotifications() async {
        guard let event = eventRepository.currentEvent else { return }

        await NotificationService.shared.scheduleReveals(
            for: photoRepository.allPhotos,
            event: event,
            viewerID: DeviceIdentity.current
        )
    }

    func image(for photo: Photo) async -> UIImage? {
        await PhotoImageLoader.shared.thumbnail(for: photo)
    }

    // MARK: - 内部

    private func observeRepository() {
        photoRepository.$allPhotos
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.recompute() }
            .store(in: &cancellables)

        // 1分ごとに公開判定をやり直す。アプリを開いたまま公開時刻を
        // またいだ場合でも、待たずに写真が現れる。
        tickTimer = Timer.publish(every: 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.recompute() }
    }

    private func recompute() {
        let all = photoRepository.allPhotos
        locked = TimeCapsuleService.lockedCapsules(all)
        revealed = TimeCapsuleService.revealedCapsules(all)
    }
}
