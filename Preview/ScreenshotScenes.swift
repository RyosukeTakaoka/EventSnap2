//
//  ScreenshotScenes.swift
//  EventSnap
//
//  5つの撮影シーンをXcode Canvasで確認するためのPreview群。
//

#if DEBUG

import SwiftUI

/// Fixtureを注入してから中身を組み立てるPreview用のホスト。
///
/// `init`で注入するのは、`AlbumView`が`@StateObject`で`AlbumViewModel`を
/// 作る**前に**Repositoryを埋めておく必要があるため（`@Published`は購読時に
/// 現在値を配信するので、先に入れておけば初期化時点で正しい状態になる）。
@MainActor
private struct ScreenshotPreviewHost<Content: View>: View {
    private let content: () -> Content

    init(_ scene: ScreenshotScene, @ViewBuilder content: @escaping () -> Content) {
        PreviewFixtureLoader.install(scene: scene)
        self.content = content
    }

    var body: some View { content() }
}

// MARK: - ① アルバム: みんなの写真が自動で集まる

#Preview("① Album") {
    ScreenshotPreviewHost(.albumGrid) {
        AlbumView(
            eventViewModel: EventViewModel(),
            showEventSwitcher: .constant(false)
        )
    }
}

// MARK: - ② カメラ: 撮った瞬間に共有される

#Preview("② Camera") {
    ScreenshotPreviewHost(.camera) {
        CameraView()
    }
}

// MARK: - ③ タイムカプセル: 一部の写真はあとから届く

#Preview("③ Time Capsule") {
    ScreenshotPreviewHost(.timeCapsule) {
        AlbumView(
            eventViewModel: EventViewModel(),
            showEventSwitcher: .constant(false)
        )
    }
}

// MARK: - ④ Event Reel: 自動編集されたシェア画像

/// 注入済みのFixtureから最新のEvent Reelを取り出して、本番のシェア画面を出す。
private struct EventReelSceneView: View {
    var body: some View {
        NavigationView {
            if let event = EventRepository.shared.currentEvent,
               let reel = ShareCollageStore.shared.reels(for: event.id).first {
                SocialCardShareView(event: event, reel: reel)
            } else {
                Text("Event Reelを生成できませんでした")
                    .foregroundColor(.secondary)
            }
        }
    }
}

#Preview("④ Event Reel") {
    ScreenshotPreviewHost(.eventReel) {
        EventReelSceneView()
    }
}

// MARK: - ⑤ 招待: QRをかざすだけで参加

#Preview("⑤ Invite") {
    ScreenshotPreviewHost(.invite) {
        QRCodeView(eventViewModel: EventViewModel())
    }
}

// MARK: - ⑥ 招待+読み取りの合成カット

#Preview("⑥ Invite Overlay") { QROverlayScreenshotView() }

// MARK: - 通しで確認する（タブ構成込み）

#Preview("MainTabView (Album)") {
    ScreenshotPreviewHost(.albumGrid) {
        MainTabView(initialTab: .album)
    }
}

#endif
