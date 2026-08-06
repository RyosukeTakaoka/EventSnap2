//
//  AlbumViewModel.swift
//  EventSnap
//
//  アルバムViewModel
//

import Foundation
import SwiftUI
import Combine

/// アルバムのグリッドに並べる1枠分。
///
/// タイムカプセルタブを独立させず、**アルバムの中に伏せられた写真の枠として
/// そのまま並べる**（グレー表示・プレビュー不可・砂時計マーク）。
/// 公開済みの写真と未公開の写真を撮影順で混ぜて表示するための橋渡し。
enum AlbumGridItem: Identifiable {
    case revealed(Photo)
    case locked(Photo)

    var id: UUID {
        switch self {
        case .revealed(let photo), .locked(let photo): return photo.id
        }
    }

    var uploadedAt: Date {
        switch self {
        case .revealed(let photo), .locked(let photo): return photo.uploadedAt
        }
    }
}

@MainActor
class AlbumViewModel: ObservableObject {
    /// 公開済みの写真
    @Published var photos: [Photo] = []
    /// タイムカプセルでまだ公開されていない写真（参加者全員分。中身はグレーで隠す）
    @Published var locked: [Photo] = []
    @Published var isLoading = false
    @Published var error: String?

    private let photoRepository = PhotoRepository.shared
    private let eventRepository = EventRepository.shared
    private var cancellables = Set<AnyCancellable>()

    /// 公開時刻をまたいだ瞬間に画面へ反映するためのタイマー
    private var tickTimer: AnyCancellable?

    init() {
        observeRepository()
    }

    /// 公開済み写真とロック中の写真を撮影順（新しい順）で混ぜたもの。
    /// ロック中の写真はグレーの枠として並ぶだけで、中身は表示しない。
    var items: [AlbumGridItem] {
        let revealedItems = photos.map(AlbumGridItem.revealed)
        let lockedItems = locked.map(AlbumGridItem.locked)
        return (revealedItems + lockedItems).sorted { $0.uploadedAt > $1.uploadedAt }
    }

    // MARK: - 写真取得

    func fetchPhotos() async {
        guard let event = eventRepository.currentEvent else {
            print("❌ イベントが見つかりません")
            return
        }

        isLoading = true

        do {
            try await photoRepository.fetchPhotos(for: event.id)
            // 未公開の写真に対して公開通知を予約し直す
            await NotificationService.shared.scheduleReveals(
                for: photoRepository.allPhotos,
                event: event,
                viewerID: DeviceIdentity.current
            )
        } catch {
            self.error = "写真の取得に失敗しました"
            print("❌ 写真取得エラー: \(error)")
        }

        isLoading = false
    }

    // MARK: - リアルタイム同期設定

    func setupRealtimeSync() async {
        guard let eventID = eventRepository.currentEvent?.id else { return }
        await photoRepository.setupSubscription(for: eventID)
    }

    // MARK: - Repository監視

    private func observeRepository() {
        photoRepository.$allPhotos
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.recompute() }
            .store(in: &cancellables)

        // 1分ごとに公開判定をやり直す。アプリを開いたまま公開時刻をまたいでも、
        // 待たずにグレーの枠から実際の写真に切り替わる。
        tickTimer = Timer.publish(every: 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.recompute() }

        // グループを切り替えたら、そのイベントの写真を取り直す
        eventRepository.$currentEvent
            .map { $0?.id }
            .removeDuplicates()
            .compactMap { $0 }
            .sink { [weak self] _ in
                Task { await self?.fetchPhotos() }
            }
            .store(in: &cancellables)
    }

    private func recompute() {
        let all = photoRepository.allPhotos
        photos = TimeCapsuleService.albumPhotos(all)
        locked = TimeCapsuleService.lockedCapsules(all)
    }

    // MARK: - 画像ダウンロード

    func downloadImage(for photo: Photo) async -> UIImage? {
        await PhotoImageLoader.shared.image(for: photo)
    }

    func thumbnail(for photo: Photo) async -> UIImage? {
        await PhotoImageLoader.shared.thumbnail(for: photo)
    }
}
