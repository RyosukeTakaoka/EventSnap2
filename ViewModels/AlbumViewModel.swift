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
            print("✅ 写真取得成功: \(photoRepository.photos.count)枚")
        } catch {
            self.error = "写真の取得に失敗しました"
            print("❌ 写真取得エラー: \(error)")
        }

        isLoading = false
    }

    // MARK: - リアルタイム同期設定

    func setupRealtimeSync() async {
        guard let eventID = eventRepository.currentEvent?.id else {
            return
        }

        await photoRepository.setupSubscription(for: eventID)
    }

    // MARK: - Repository監視

    private func observeRepository() {
        photoRepository.$photos
            .assign(to: &$photos)
    }

    // MARK: - 画像ダウンロード

    func downloadImage(for photo: Photo) async -> UIImage? {
        // CloudKitから画像をダウンロード
        guard let url = photo.imageURL else {
            return nil
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return UIImage(data: data)
        } catch {
            print("❌ 画像ダウンロード失敗: \(error)")
            return nil
        }
    }
}
