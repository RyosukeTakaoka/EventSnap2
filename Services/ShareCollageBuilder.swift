//
//  ShareCollageBuilder.swift
//  EventSnap
//
//  イベント中に育っていくEvent Reelの生成の段取り
//

import Foundation
import UIKit

/// 「シェアOKのまだ使っていない写真を5枚集める → 画像を落とす → コラージュにする →
/// 履歴に追加保存する」という一連の流れをまとめたもの。
///
/// イベント終了を待たず、**イベント中に**シェアOKの写真が5枚集まるたびに
/// 新しいEvent Reelを作る。古いReelは上書きせず、履歴として残す
/// （写真5枚 → Reel #1、さらに5枚 → Reel #2、…と育っていく）。
///
/// Event Reelは固定スナップショットではない。写真のシェアOKが後からOFFに
/// なった場合は `removeFromReels` で該当Reelの中身を更新する。
enum ShareCollageBuilder {

    /// この枚数のまだ使われていないシェアOK写真が集まるごとに、新しいEvent Reelを1件作る
    static let photosPerReel = 5

    /// イベント中の自動生成チェック。
    ///
    /// 写真がアップロードされた・定期同期が走った・写真がシェアOKにされた、
    /// といったタイミングで呼ぶ想定。**すでに何らかのReelに使われた写真は候補から除く**
    /// （`ShareCollageStore.usedPhotoIDs`）ため、古い写真が後からシェアOKにされても
    /// 過去のReelを勝手に書き換えることはなく、次のReelの材料になるだけ。
    /// 同期の間隔が空いて一度に大量のシェアOK写真が増えていた場合は、
    /// 取りこぼさないよう作れるだけ複数のReelをまとめて作る。
    ///
    /// - Returns: 実際に生成されたEvent Reel（新しい順）。1件も作らなければ空配列
    @MainActor
    @discardableResult
    static func buildIfNeeded(for event: Event) async -> [EventReel] {
        let approved = PhotoRepository.shared.shareApprovedPhotos(for: event.id) // 古い順
        let store = ShareCollageStore.shared
        let used = store.usedPhotoIDs(for: event.id)

        var candidates = approved.filter { !used.contains($0.id) }
        var created: [EventReel] = []

        while candidates.count >= photosPerReel {
            let batch = Array(candidates.prefix(photosPerReel))

            guard let image = await renderCollage(from: batch, event: event) else {
                print("⚠️ Event Reel用の画像取得に失敗したため、このバッチは今回スキップします")
                break
            }

            do {
                let reel = try store.addReel(image, for: event.id, photoIDs: batch.map(\.id))
                created.append(reel)
                candidates.removeFirst(photosPerReel)
            } catch {
                print("❌ Event Reelの保存に失敗: \(error)")
                break
            }
        }

        return created
    }

    /// shareOKがOFFに変わった写真を、既存のEvent Reelから取り除く。
    ///
    /// プライバシー保護のための操作（間違えてONにした・写っている人から削除希望が
    /// あった等）。該当する写真を含むReelがあれば、その写真を除いた残りで画像を
    /// 作り直す。残りが0枚になったReelは削除する。`index`・`builtAt` は変えない
    /// （生成した記録自体は保持し、中身だけを更新する）。
    ///
    /// この写真は `shareApprovedPhotos` にもう出てこなくなるため、
    /// 今後生成されるReelにも一切使われない。
    @MainActor
    static func removeFromReels(photoID: UUID, event: Event) async {
        let store = ShareCollageStore.shared
        let affected = store.reels(for: event.id).filter { $0.photoIDs.contains(photoID) }
        guard !affected.isEmpty else { return }

        let photosByID = Dictionary(
            uniqueKeysWithValues: PhotoRepository.shared.shareApprovedPhotos(for: event.id).map { ($0.id, $0) }
        )

        for reel in affected {
            let remainingIDs = reel.photoIDs.filter { $0 != photoID }
            let remainingPhotos = remainingIDs.compactMap { photosByID[$0] }

            do {
                if remainingPhotos.isEmpty {
                    try store.updateReel(reel, newPhotoIDs: [], newImage: nil)
                } else if let image = await renderCollage(from: remainingPhotos, event: event) {
                    try store.updateReel(reel, newPhotoIDs: remainingIDs, newImage: image)
                }
            } catch {
                print("❌ Event Reel #\(reel.index) の更新に失敗: \(error)")
            }
        }
    }

    // MARK: - 内部

    @MainActor
    private static func renderCollage(from photos: [Photo], event: Event) async -> UIImage? {
        print("🖼 Event Reel生成: シェアOK \(photos.count)枚")

        // 元画像を落とす。取得できなかったものは黙って飛ばす。
        var images: [UIImage] = []
        for photo in photos {
            if let image = await PhotoImageLoader.shared.image(for: photo) {
                images.append(image)
            }
        }

        guard !images.isEmpty else { return nil }

        return CollageService.makeCollage(from: images, eventName: event.name, date: Date())
    }
}
