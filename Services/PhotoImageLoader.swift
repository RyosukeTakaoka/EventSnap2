//
//  PhotoImageLoader.swift
//  EventSnap
//
//  写真画像のダウンロードとキャッシュ
//

import Foundation
import UIKit

/// CloudKitのCKAssetから画像を落としてくる処理を1か所にまとめたもの。
///
/// アルバムタブとタイムカプセルタブが同じ写真を表示するため、
/// キャッシュを共有しないと同じ画像を2回落とすことになる。
@MainActor
final class PhotoImageLoader {
    static let shared = PhotoImageLoader()

    private let cache = NSCache<NSString, UIImage>()
    /// 同じ写真に対する多重ダウンロードを防ぐ
    private var inFlight: [UUID: Task<UIImage?, Never>] = [:]

    private init() {
        cache.countLimit = 200
    }

    /// 写真の本体画像を取得する（キャッシュがあればそれを返す）
    func image(for photo: Photo) async -> UIImage? {
        await load(id: photo.id, url: photo.imageURL, cacheKey: photo.id.uuidString)
    }

    /// グリッド表示用のサムネイル。無ければ本体画像にフォールバックする。
    func thumbnail(for photo: Photo) async -> UIImage? {
        if let url = photo.thumbnailURL {
            if let image = await load(id: photo.id, url: url, cacheKey: photo.id.uuidString + "-thumb") {
                return image
            }
        }
        return await image(for: photo)
    }

    private func load(id: UUID, url: URL?, cacheKey: String) async -> UIImage? {
        if let cached = cache.object(forKey: cacheKey as NSString) {
            return cached
        }

        guard let url else { return nil }

        // 同じ写真を同時に取りに行かないようにする
        if let existing = inFlight[id] {
            return await existing.value
        }

        let task = Task<UIImage?, Never> {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                return UIImage(data: data)
            } catch {
                print("❌ 画像ダウンロード失敗: \(error)")
                return nil
            }
        }
        inFlight[id] = task

        let image = await task.value
        inFlight[id] = nil

        if let image {
            cache.setObject(image, forKey: cacheKey as NSString)
        }
        return image
    }

    func clear() {
        cache.removeAllObjects()
    }
}
