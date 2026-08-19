//
//  OnboardingTutorialManager.swift
//  EventSnap
//
//  初回インタラクティブチュートリアルの状態管理。
//
//  説明専用ページを何枚も見せる方式ではなく、実際のCameraView/AlbumViewの上に
//  半透明のオーバーレイを重ね、本物のUI（CaptureOptionToggle・シャッター・
//  アルバムのグリッドなど）をハイライトしながら、ユーザー自身に実際の操作を
//  してもらう。チュートリアル専用の偽物UIは一切作らない。
//
//  各ステップの前進は、原則としてユーザーが実際にそのUIを操作した結果
//  （撮影が完了した、シェアOKがONになった、あとで公開がONになった、
//  アルバムタブに切り替えた等）をきっかけに呼ばれる `handle*` 系メソッドが担う。
//  実際の操作を伴わない説明ステップ（アルバムの案内・通知の案内）だけ、
//  オーバーレイ内の「次へ」ボタンで`advance()`を呼んで進める。
//

import Foundation
import Combine

/// チュートリアルのステップ。
/// `Hashable`は`CameraView`/`AlbumView`が`Set<TutorialStep>`で
/// 「この画面が扱うステップ」を判定するために必要。
enum TutorialStep: Hashable {
    /// 通常撮影を体験させる（何も選ばなくても自動投稿されることを理解させる）
    case shutter
    /// シェアOKを実際にタップして試させる
    case shareOK
    /// あとで公開を実際にタップして試させる
    case laterReveal
    /// あとで公開をONにしたまま、もう一度撮影させる
    case shutterForLaterReveal
    /// アルバムタブへ切り替えるよう促す（実際のタブ操作を待つ）
    case goToAlbum
    /// アルバムのグリッドを説明する
    case albumGrid
    /// 公開待ちの写真枠を説明する（ある場合のみ）
    case lockedPhoto
    /// 公開通知について短く説明して終了する
    case notificationHint
}

/// 1ステップ分の表示内容。
struct TutorialStepContent {
    let title: String
    let message: String
    /// ハイライトする実際のUI（nilなら中央に説明カードだけを出す）
    let target: TutorialTarget?
    /// 押すと`advance()`が呼ばれるボタンのラベル。nilなら実際の操作待ち（ボタンは出さない）
    let actionLabel: String?
}

extension TutorialStep {
    var content: TutorialStepContent {
        switch self {
        case .shutter:
            return TutorialStepContent(
                title: "撮影してみよう",
                message: "写真を撮るだけで、イベントのアルバムに自動で投稿されます。",
                target: .shutter,
                actionLabel: nil
            )
        case .shareOK:
            return TutorialStepContent(
                title: "シェアOK",
                message: "この写真を他の場所でシェアしてOKなときに選べます。タップして試してみよう。",
                target: .shareOK,
                actionLabel: nil
            )
        case .laterReveal:
            return TutorialStepContent(
                title: "あとで公開",
                message: "今は見せず、後から公開できます。イベント写真の約15%程度が、あとで公開の思い出になります。タップして試してみよう。",
                target: .laterReveal,
                actionLabel: nil
            )
        case .shutterForLaterReveal:
            return TutorialStepContent(
                title: "そのまま撮ってみよう",
                message: "「あとで公開」を選んだ状態で撮影すると、この写真は公開待ちになります。",
                target: .shutter,
                actionLabel: nil
            )
        case .goToAlbum:
            return TutorialStepContent(
                title: "アルバムを見てみよう",
                message: "下のタブからアルバムを開いてみましょう。",
                target: nil,
                actionLabel: nil
            )
        case .albumGrid:
            return TutorialStepContent(
                title: "アルバム",
                message: "ここにイベントのみんなの写真が集まります。",
                target: .albumGrid,
                actionLabel: "次へ"
            )
        case .lockedPhoto:
            return TutorialStepContent(
                title: "公開待ちの写真",
                message: "この枠の写真はまだ公開されていません。公開されると通知が届きます。",
                target: .lockedPhoto,
                actionLabel: "次へ"
            )
        case .notificationHint:
            return TutorialStepContent(
                title: "公開の通知",
                message: "あとで公開した写真は、公開されたときに通知が届きます。通知をタップすると、その写真をすぐに見られます。",
                target: nil,
                actionLabel: "はじめる"
            )
        }
    }
}

/// 初回チュートリアルの進行を管理する。
///
/// 完了・スキップの状態は`UserDefaults`にシンプルな真偽値2つで保存する
/// （`EventRepository`や`DeviceIdentity`と同じ、素の`UserDefaults`を使う既存方針に合わせる）。
@MainActor
final class TutorialManager: ObservableObject {
    static let shared = TutorialManager()

    @Published private(set) var currentStep: TutorialStep?

    private enum Keys {
        static let completed = "hasCompletedOnboarding"
        static let skipped = "hasSkippedOnboarding"
    }

    private let defaults = UserDefaults.standard

    private init() {}

    private var isFinished: Bool {
        defaults.bool(forKey: Keys.completed) || defaults.bool(forKey: Keys.skipped)
    }

    // MARK: - 開始・終了

    /// カメラを初めて開いたタイミングで呼ぶ。完了済み・スキップ済みなら何もしない。
    func startIfNeeded() {
        guard !isFinished, currentStep == nil else { return }
        currentStep = .shutter
    }

    /// 設定の「EventSnapの使い方」から、同じチュートリアルを最初から再体験する。
    func restart() {
        defaults.removeObject(forKey: Keys.completed)
        defaults.removeObject(forKey: Keys.skipped)
        currentStep = .shutter
    }

    /// スキップする。主導線にはしないが、いつでも抜けられるようにする。
    func skip() {
        defaults.set(true, forKey: Keys.skipped)
        currentStep = nil
    }

    private func finish() {
        defaults.set(true, forKey: Keys.completed)
        currentStep = nil
    }

    // MARK: - 実際の操作に応じた進行

    /// 撮影（実際のアップロード）が完了したときに呼ぶ。
    func handleCaptureCompleted(wasTimeCapsule: Bool) {
        guard let step = currentStep else { return }
        switch step {
        case .shutter:
            currentStep = .shareOK
        case .shutterForLaterReveal:
            if wasTimeCapsule {
                currentStep = .goToAlbum
            }
        default:
            break
        }
    }

    /// 実際の「シェアOK」トグルの状態が変わったときに呼ぶ。
    func handleShareOKChanged(_ isOn: Bool) {
        guard currentStep == .shareOK, isOn else { return }
        currentStep = .laterReveal
    }

    /// 実際の「あとで公開」トグルの状態が変わったときに呼ぶ。
    func handleTimeCapsuleChanged(_ isOn: Bool) {
        guard currentStep == .laterReveal, isOn else { return }
        currentStep = .shutterForLaterReveal
    }

    /// 実際にタブを切り替えたときに呼ぶ。
    func handleTabChanged(_ tab: AppTab) {
        guard currentStep == .goToAlbum, tab == .album else { return }
        currentStep = .albumGrid
    }

    /// 実際の操作を伴わない説明ステップだけを「次へ」ボタンで進める。
    func advance(hasLockedPhotos: Bool = false) {
        guard let step = currentStep else { return }
        switch step {
        case .albumGrid:
            currentStep = hasLockedPhotos ? .lockedPhoto : .notificationHint
        case .lockedPhoto:
            currentStep = .notificationHint
        case .notificationHint:
            finish()
        default:
            break
        }
    }
}
