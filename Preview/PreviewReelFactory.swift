//
//  PreviewReelFactory.swift
//  EventSnap
//
//  Fixture写真から、本番と同じ描画経路でEvent Reelを作って保存する。
//

#if DEBUG

import Foundation
import UIKit

/// Event Reelの実物を用意する。
///
/// **画像は本番の`SocialCardService.renderEventReel`（＝`MultiPhotoRenderer`）で
/// 描く。** スクリーンショットに写るのは実際にユーザーが手にするのと同じ
/// 成果物であり、撮影用に似せた別デザインではない。
///
/// `PhotoAnalyzer`（Vision）は通さず、`importanceCenter`に固定値を渡す。
/// Visionの結果は端末・OSバージョンで揺れうるため、ここを固定することで
/// 「何度撮っても同じピクセル」を担保する。`MultiPhotoRenderer`は
/// 正規化済みの重心しか受け取らないので、これで十分に成立する。
@MainActor
enum PreviewReelFactory {

    /// 写真の重要領域の重心。やや上寄りにすると人物写真の顔が残りやすい。
    private static let fixedImportanceCenter = CGPoint(x: 0.5, y: 0.42)

    /// Event Reelを生成して`ShareCollageStore`に保存する。
    ///
    /// - Returns: 撮影で見せる最新のReel ID（1件も作れなければ`nil`）
    @discardableResult
    static func install(
        event: Event,
        photos: [Photo],
        imageIndexByPhotoID: [UUID: Int]
    ) -> UUID? {
        let store = ShareCollageStore.shared

        // 固定UUIDのイベント配下だけを消す。開発中の実イベントのReelには触れない。
        store.deleteAll(for: event.id)

        let groups = PreviewFixtureData.reelGroups(from: photos)
        guard !groups.isEmpty else { return nil }

        for (offset, group) in groups.enumerated() {
            var inputs: [MultiPhotoRenderer.PhotoInput] = []
            var usedIDs: [UUID] = []

            for photo in group {
                guard let index = imageIndexByPhotoID[photo.id],
                      let image = PreviewImageFactory.loadImage(at: index)
                else { continue }
                inputs.append(
                    MultiPhotoRenderer.PhotoInput(image: image, importanceCenter: fixedImportanceCenter)
                )
                usedIDs.append(photo.id)
            }

            guard !inputs.isEmpty else { continue }

            let rendered = SocialCardService.renderEventReel(
                photos: inputs,
                eventName: event.name,
                date: group.map(\.uploadedAt).max() ?? event.createdAt,
                participantCount: event.participantIDs.count,
                photoCount: PreviewFixtureData.displayedPhotoCount
            )

            do {
                _ = try store.addReel(rendered, for: event.id, photoIDs: usedIDs)
            } catch {
                print("⚠️ [Screenshot] Event Reelの保存に失敗: \(error)")
                continue
            }

            // 1件目だけ「既読」にしておくと、以降に作るReelが未読として残り、
            // アルバムのツールバーに未読バッジが出る（LINEのような新着表現）。
            // `markReelsSeen`は公開APIなので、UserDefaultsのキー形式を
            // Fixture側で複製する必要が無い。
            if offset == 0 {
                store.markReelsSeen(for: event.id)
            }
        }

        // `reels(for:)`はindexの降順。先頭が最新＝撮影で見せる1件。
        return store.reels(for: event.id).first?.id
    }
}

#endif
