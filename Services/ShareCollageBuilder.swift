//
//  ShareCollageBuilder.swift
//  EventSnap
//
//  イベント終了時のコラージュ生成の段取り
//

import Foundation
import UIKit

/// 「シェアOKの写真を集める → 画像を落とす → コラージュにする → 保存する」
/// という一連の流れをまとめたもの。
enum ShareCollageBuilder {

    /// イベント終了時に呼ぶ。
    ///
    /// - Returns: 生成されたコラージュ。**シェアOKの写真が1枚も無ければ nil**
    ///            （仕様どおり、その場合はコラージュを作らずシェア機能も出さない）
    @MainActor
    @discardableResult
    static func buildIfPossible(for event: Event) async -> UIImage? {
        let repository = PhotoRepository.shared

        // 最新の状態で判断する。他の人が終了間際にシェアOKを付けている可能性がある。
        try? await repository.fetchPhotos(for: event.id)

        // シェアOKとタイムカプセルが重複している写真は、シェアを優先して解除する。
        // 解除された写真はこの時点で通常公開になり、コラージュにも使えるようになる。
        await repository.releaseSharedTimeCapsules(for: event.id)

        let approved = repository.shareApprovedPhotos(for: event.id)

        guard !approved.isEmpty else {
            print("ℹ️ シェアOKの写真が0枚のため、コラージュは生成しません")
            return nil
        }

        print("🖼 コラージュ生成: シェアOK \(approved.count)枚")

        // 元画像を落とす。取得できなかったものは黙って飛ばす。
        var images: [UIImage] = []
        for photo in approved.prefix(CollageService.maxPhotos) {
            if let image = await PhotoImageLoader.shared.image(for: photo) {
                images.append(image)
            }
        }

        guard !images.isEmpty else {
            print("⚠️ シェアOKの写真はあるが、画像を取得できませんでした")
            return nil
        }

        guard let collage = CollageService.makeCollage(
            from: images,
            eventName: event.name,
            date: event.endedAt ?? event.createdAt
        ) else {
            return nil
        }

        do {
            try ShareCollageStore.shared.save(collage, for: event.id)
        } catch {
            print("❌ コラージュの保存に失敗: \(error)")
        }

        return collage
    }
}
