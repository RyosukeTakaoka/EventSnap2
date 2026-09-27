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
///
/// 写真一覧の取得（`PhotoRepository.fetchPhotos`）では、表示を速くするために
/// 本体画像（`imageAsset`）を取らずサムネイルだけを落としている。そのため
/// `photo.imageURL` が無い写真は、本体画像が必要になった時点で
/// `fullImageURLResolver`（本体アプリでは `PhotoRepository.fetchImageURL`）を使って
/// 1枚分だけ取りに行く。
///
/// このファイルは**App Clipターゲットでもコンパイルされる**。App Clip側には
/// `PhotoRepository.swift` が含まれていないため、直接参照せずクロージャで受け取る。
@MainActor
final class PhotoImageLoader {
    static let shared = PhotoImageLoader()

    private let cache = NSCache<NSString, UIImage>()
    /// 同じ画像に対する多重ダウンロードを防ぐ。
    /// キーはキャッシュキー（本体とサムネイルで別）。以前は写真IDをキーにしていたため、
    /// サムネイルの読み込み中に本体画像を要求すると、サムネイルが本体画像として
    /// 返され、低解像度のままキャッシュされてしまっていた。
    private var inFlight: [String: Task<UIImage?, Never>] = [:]

    /// `photo.imageURL` が無い写真の本体画像URLを取得する処理。
    /// 本体アプリでは `PhotoRepository` の初期化時に設定される。
    var fullImageURLResolver: ((Photo) async -> URL?)?

    private init() {
        cache.countLimit = 200
    }

    /// 写真の本体画像を取得する（キャッシュがあればそれを返す）
    func image(for photo: Photo) async -> UIImage? {
        let knownURL = photo.imageURL
        let resolver = fullImageURLResolver
        return await load(cacheKey: Self.imageKey(photo.id)) {
            if let knownURL { return knownURL }
            return await resolver?(photo)
        }
    }

    /// グリッド表示用のサムネイル。無ければ本体画像にフォールバックする。
    func thumbnail(for photo: Photo) async -> UIImage? {
        // 本体画像がすでに手元にあるなら、それで代用する（追加の通信をしない）
        if let cached = cache.object(forKey: Self.thumbnailKey(photo.id) as NSString)
            ?? cache.object(forKey: Self.imageKey(photo.id) as NSString) {
            return cached
        }
        if let url = photo.thumbnailURL {
            if let image = await load(cacheKey: Self.thumbnailKey(photo.id), resolveURL: { url }) {
                return image
            }
        }
        return await image(for: photo)
    }

    /// アップロード直後の写真を、手元の画像でキャッシュに入れておく。
    /// CloudKitから取り直すまでの間も、アルバムに写真がすぐ表示されるようにするため。
    func store(image: UIImage, thumbnail: UIImage?, for photoID: UUID) {
        cache.setObject(image, forKey: Self.imageKey(photoID) as NSString)
        if let thumbnail {
            cache.setObject(thumbnail, forKey: Self.thumbnailKey(photoID) as NSString)
        }
    }

    private func load(cacheKey: String, resolveURL: @escaping () async -> URL?) async -> UIImage? {
        if let cached = cache.object(forKey: cacheKey as NSString) {
            return cached
        }

        // 同じ画像を同時に取りに行かないようにする
        if let existing = inFlight[cacheKey] {
            return await existing.value
        }

        let task = Task<UIImage?, Never> {
            guard let url = await resolveURL() else { return nil }
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                return UIImage(data: data)
            } catch {
                print("❌ 画像ダウンロード失敗: \(error)")
                return nil
            }
        }
        inFlight[cacheKey] = task

        let image = await task.value
        inFlight[cacheKey] = nil

        if let image {
            cache.setObject(image, forKey: cacheKey as NSString)
        }
        return image
    }

    private static func imageKey(_ id: UUID) -> String { id.uuidString }
    private static func thumbnailKey(_ id: UUID) -> String { id.uuidString + "-thumb" }

    func clear() {
        cache.removeAllObjects()
    }
}
