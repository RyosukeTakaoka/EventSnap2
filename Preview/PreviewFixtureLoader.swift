//
//  PreviewFixtureLoader.swift
//  EventSnap
//
//  Fixtureを既存のRepository/Storeへ注入する入口。
//

#if DEBUG

import Foundation
import UIKit

/// 撮影用の状態を、**既存のシングルトンにそのまま流し込む**。
///
/// ## なぜシングルトンへの注入なのか
///
/// このアプリでは`EventViewModel`が3インスタンス生成される
/// （`EventSnapApp` / `HomeView` / `MainTabView`）一方、それらは
/// `EventRepository.shared`の`@Published`をミラーしているだけで、
/// 唯一の情報源はシングルトン側にある。したがって注入先はシングルトン一択。
///
/// `@Published`は購読時に現在値を即座に配信するため、ここで先に値を入れておけば
/// あとから生成される`AlbumViewModel`等は初期化時点で正しい状態を受け取る。
/// **Viewにも既存ViewModelにも手を入れずに済む。**
@MainActor
enum PreviewFixtureLoader {

    /// Event Reelシーンで開くReel（`ShareCollageStore`が採番した実ID）
    private(set) static var showcaseReelID: UUID?

    /// カメラ画面の背景に敷く画像
    private(set) static var cameraBackgroundImage: UIImage?

    /// QR読み取りファインダーの背景に敷く画像（`.inviteOverlay`シーン用）
    private(set) static var qrScanBackgroundImage: UIImage?

    private static var installed = false

    /// Fixtureが注入済みか。本番コード側の guard（`ScreenshotMode.suppressesLiveServices`）が
    /// 参照する。SwiftUI Previewからの`install`でもCloudKit等を止めたいため、
    /// 「撮影モードで起動しているか」ではなく「注入されたか」で判定する。
    static var isInstalled: Bool { installed }

    /// 撮影モードで起動していれば、Fixtureを1回だけ注入する。
    /// `EventSnapApp.init()`から呼ばれる。
    static func installIfNeeded() {
        guard ScreenshotMode.isActive, !installed else { return }
        install(scene: ScreenshotMode.scene)
    }

    /// Fixtureを注入する（SwiftUI Previewからも直接呼ぶ）。
    static func install(scene: ScreenshotScene) {
        installed = true

        let anchor = Date()

        // ── 1. 画像をローカルの file:// として用意する ──────────────
        // CKAsset.fileURL と同じ形になるので、PhotoImageLoader は無改造で読める。
        let materials = PreviewImageFactory.materialize(count: PreviewFixtureData.photoCount)

        // ── 2. イベントと写真を組み立てる ───────────────────────
        let event = PreviewFixtureData.event(anchor: anchor)
        let photos = PreviewFixtureData.photos(
            for: scene,
            anchor: anchor,
            imageURLs: materials.imageURLs,
            thumbnailURLs: materials.thumbnailURLs
        )

        var imageIndexByPhotoID: [UUID: Int] = [:]
        for spec in PreviewFixtureData.photoSpecs(for: scene) {
            imageIndexByPhotoID[PreviewFixtureData.photoID(spec.index)] = spec.index
        }

        // ── 3. PhotoRepositoryへ注入 ───────────────────────────
        // 公開済み／ロック中の振り分けは本番と同じ TimeCapsuleService に任せる。
        PhotoRepository.shared.allPhotos = photos
        PhotoRepository.shared.photos = TimeCapsuleService.albumPhotos(photos)

        // ── 4. Event Reelを本番の描画経路で作る ────────────────────
        showcaseReelID = PreviewReelFactory.install(
            event: event,
            photos: photos,
            imageIndexByPhotoID: imageIndexByPhotoID
        )

        // `preview-camera-bg.jpg`が用意されていればそれを、無ければ従来通り
        // Fixture写真の1枚（`cameraBackgroundIndex`）を背景に使う。
        cameraBackgroundImage = PreviewImageFactory.bundledCameraBackground()
            ?? PreviewImageFactory.loadImage(at: cameraBackgroundIndex)

        // QR読み取りファインダーの背景は専用ファイルのみを見る
        // （フォールバック用の適当な写真流用は「読み取り中」らしく見えないため）。
        qrScanBackgroundImage = PreviewImageFactory.bundledQRScanBackground()

        // ── 5. EventRepositoryへ注入 ──────────────────────────
        // `currentEvent`は最後に入れる。HomeViewの fullScreenCover がこれを見て
        // MainTabViewを提示するため、写真・Reelが揃ってから切り替える。
        //
        // なお `saveCurrentEventID` は呼ばれない（private かつ直接代入のため）ので、
        // UserDefaultsの `currentEventID` / `joinedEventIDs` は汚れない。
        EventRepository.shared.participants = PreviewFixtureData.participants(joinedAt: event.createdAt)
        EventRepository.shared.recentEvents = [event, PreviewFixtureData.pastEvent(anchor: anchor)]
        EventRepository.shared.currentEvent = event

        let lockedCount = TimeCapsuleService.lockedCapsules(photos).count
        let reelCount = ShareCollageStore.shared.reels(for: event.id).count
        let unseenCount = ShareCollageStore.shared.unseenReelCount(for: event.id)
        print("📸 [Screenshot] Fixtureを注入しました scene=\(scene.rawValue)")
        print("   event: \(event.name) / \(event.id.uuidString)")
        print("   photos: 公開済み \(photos.count - lockedCount)枚 / ロック中 \(lockedCount)枚")
        print("   reels: \(reelCount)件（未読 \(unseenCount)件）")
    }

    /// カメラ背景に使う写真の番号（暗すぎず、UIオーバーレイが読みやすいもの）
    private static let cameraBackgroundIndex = 3
}

#endif
