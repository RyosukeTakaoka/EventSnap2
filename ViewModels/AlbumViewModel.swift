//
//  AlbumViewModel.swift
//  EventSnap
//
//  アルバムViewModel
//

import Foundation
import SwiftUI
import Combine

@MainActor
class AlbumViewModel: ObservableObject {
    @Published var photos: [Photo] = []
    @Published var isLoading = false
    @Published var error: String?

    private let photoRepository = PhotoRepository.shared
    private let eventRepository = EventRepository.shared
    private var cancellables = Set<AnyCancellable>()

    init() {
        observeRepository()
    }

    // MARK: - 写真取得

    func fetchPhotos() async {
        guard let eventID = eventRepository.currentEvent?.id else {
            print("❌ イベントが見つかりません")
            return
        }

        isLoading = true

        do {
            try await photoRepository.fetchPhotos(for: eventID)
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
        photoRepository.$photos
            .receive(on: DispatchQueue.main)
            .assign(to: &$photos)

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

    // MARK: - 画像ダウンロード

    func downloadImage(for photo: Photo) async -> UIImage? {
        await PhotoImageLoader.shared.image(for: photo)
    }

    func thumbnail(for photo: Photo) async -> UIImage? {
        await PhotoImageLoader.shared.thumbnail(for: photo)
    }
}
