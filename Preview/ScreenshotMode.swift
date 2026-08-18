//
//  ScreenshotMode.swift
//  EventSnap
//
//  App Store提出用スクリーンショットを撮るための「撮影モード」の判定。
//

import Foundation
import UIKit

/// 撮影する画面。1シーン＝App Store用スクリーンショット1枚。
///
/// 撮影対象は **すべて本番のView実体** であり、マーケティング用に似せた
/// 別Viewは一切作らない（実機と異なる画面を提出しないため）。
enum ScreenshotScene: String, CaseIterable {
    /// ① アルバム: みんなの写真が自動で集まる
    case albumGrid
    /// ② カメラ: 撮った瞬間に共有される
    case camera
    /// ③ タイムカプセル: 一部の写真はあとから届く
    case timeCapsule
    /// ④ Event Reel: 自動編集されたシェア画像
    case eventReel
    /// ⑤ 招待: QRをかざすだけで参加
    case invite
    /// ⑥ 招待+読み取りの合成カット: QRコードとスキャン画面を重ねて見せる
    case inviteOverlay

    /// このシーンを撮るときに最初に開くタブ。
    var initialTab: AppTab {
        switch self {
        case .albumGrid, .timeCapsule, .eventReel: return .album
        case .camera:                              return .camera
        case .invite, .inviteOverlay:              return .invite
        }
    }
}

/// スクリーンショット撮影モード。
///
/// ## 有効化の方法
///
/// Xcodeの Scheme > Run > Arguments に次を追加する（実機・シミュレータ共通）:
///
/// ```
/// -EventSnapScreenshot 1
/// -EventSnapScreenshotScene albumGrid
/// ```
///
/// `-Key value` 形式の起動引数はOSが自動で `NSArgumentDomain` に載せるため、
/// `UserDefaults` からそのまま読める（その起動限りで、永続化はされない）。
/// CI・`xcodebuild` から回す場合のために環境変数 `EVENTSNAP_SCREENSHOT` も見る。
///
/// ## Releaseビルドへの影響
///
/// `#else` 側では `isActive` が **コンパイル時定数 `false`**、`scene` 由来の
/// 値もすべて `nil` を返す固定実装になる。本番コード側に置いた
/// `guard !ScreenshotMode.isActive else { return }` はすべて最適化で消えるため、
/// 出荷バイナリの挙動・サイズへの影響は無い。
///
/// この型だけはDEBUG/Release両方でコンパイルされる（本番ファイル側に
/// `#if DEBUG` を撒かずに済ませるため）。実データを作る `PreviewFixture*` は
/// ファイル全体が `#if DEBUG` で囲われており、Releaseには一切含まれない。
enum ScreenshotMode {

#if DEBUG

    private static let flagKey = "EventSnapScreenshot"
    private static let sceneKey = "EventSnapScreenshotScene"

    /// 撮影モードで起動しているか。
//    static let isActive: Bool = {
//        if ProcessInfo.processInfo.environment["EVENTSNAP_SCREENSHOT"] == "1" { return true }
//        return UserDefaults.standard.bool(forKey: flagKey)
//    }()
    
    //強制撮影
    static let isActive: Bool = {
        return true  // ← 撮影が終わったら必ずこの行を消して元に戻すこと
    }()

//    /// 撮影対象のシーン（指定が無ければアルバム）。
//    static let scene: ScreenshotScene = {
//        guard let raw = UserDefaults.standard.string(forKey: sceneKey)
//                ?? ProcessInfo.processInfo.environment["EVENTSNAP_SCREENSHOT_SCENE"],
//              let scene = ScreenshotScene(rawValue: raw)
//        else { return .albumGrid }
//        return scene
//    }()
    
    //撮影シーン固定
    static let scene: ScreenshotScene = {
        return .albumGrid  // ← .camera / .timeCapsule / .eventReel / .invite に変えれば別シーンが撮れる
    }()

    /// カメラ画面の背景に敷く画像。
    ///
    /// シミュレータの`AVCaptureSession`は真っ黒な映像しか出さず、実機でも
    /// 「撮影中の画」を再現性のある形では作れないため、撮影モードのときだけ
    /// Fixtureの写真を背景として使う。UIオーバーレイ（シャッター・トグル）は
    /// 本番のものがそのまま乗る。
    @MainActor
    static var cameraBackgroundImage: UIImage? {
        // `isActive`では判定しない。値が入るのは`PreviewFixtureLoader.install`が
        // 走ったときだけであり、通常起動では常に`nil`のままだから。
        // こうしておくとSwiftUI Preview（起動引数を渡せない）からも成立する。
        PreviewFixtureLoader.cameraBackgroundImage
    }

    /// QR読み取りファインダーの背景に敷く画像（`.inviteOverlay`シーン用）。
    ///
    /// `cameraBackgroundImage`と同じ理由で、撮影モードのときだけ静止画に
    /// 差し替える。
    @MainActor
    static var qrScanBackgroundImage: UIImage? {
        PreviewFixtureLoader.qrScanBackgroundImage
    }

    /// Event Reelシーンで、その場でシェア画面を開くためのReel ID。
    ///
    /// `ShareCollageStore.addReel`はReelのUUIDを内部で採番するため、Fixture側で
    /// 固定できない（IDは画面に出ないので、これは決定性に影響しない）。
    /// 生成直後に`PreviewFixtureLoader`が控えた実IDをここで受け取る。
    @MainActor
    static var pendingReelID: UUID? {
        guard scene == .eventReel else { return nil }
        return PreviewFixtureLoader.showcaseReelID
    }

#else

    static var isActive: Bool { false }
    static var scene: ScreenshotScene { .albumGrid }
    @MainActor static var cameraBackgroundImage: UIImage? { nil }
    @MainActor static var qrScanBackgroundImage: UIImage? { nil }
    @MainActor static var pendingReelID: UUID? { nil }

#endif

    /// 撮影モードのときに最初に開くタブ。通常起動では `nil`（既存の挙動のまま）。
    static var initialTab: AppTab? { isActive ? scene.initialTab : nil }

    /// CloudKit・通知許可・カメラ権限・Event Reelの自動生成を止めるべきか。
    ///
    /// 本番コードに入れる guard はすべてこの1つの述語だけを見る。
    ///
    /// - Releaseビルドでは **コンパイル時定数 `false`** になり、guardごと
    ///   最適化で消えるため出荷バイナリへの影響は無い
    /// - Debugビルドでも、撮影モードで起動していない限り `false`
    ///   （＝通常の開発時の挙動は一切変わらない）
    /// - `isActive`だけでなく`PreviewFixtureLoader.isInstalled`も見るのは、
    ///   起動引数を渡せないSwiftUI Previewからも同じ抑止を効かせるため。
    ///   既存の`#Preview`（HomeView等）はFixtureを注入しないので影響を受けない。
    @MainActor
    static var suppressesLiveServices: Bool {
#if DEBUG
        isActive || PreviewFixtureLoader.isInstalled
#else
        false
#endif
    }

    /// 撮影モードのFixtureを注入する。
    ///
    /// 通常起動では何もせず、Releaseビルドでは中身ごと存在しない。
    /// 本番ファイル(`EventSnapApp`)側に`#if DEBUG`を書かずに済ませるための入口。
    @MainActor
    static func installFixturesIfNeeded() {
#if DEBUG
        PreviewFixtureLoader.installIfNeeded()
#endif
    }

    /// Event Reelシーンのとき、その場でシェア画面をシートとして開かせる。
    ///
    /// `MainTabView`が既に持っている`pendingReelID`のシート提示をそのまま使う
    /// （Widgetからの導線と同じ経路なので、撮影のために新しい提示経路を
    /// 増やす必要が無い）。`MainTabView`が乗っている`fullScreenCover`の提示と
    /// 競合しないよう、わずかに遅らせてから設定する。
    @MainActor
    static func applyPendingReel(to viewModel: EventViewModel) {
        guard let reelID = pendingReelID else { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 600_000_000)
            viewModel.pendingReelID = reelID
        }
    }
}
