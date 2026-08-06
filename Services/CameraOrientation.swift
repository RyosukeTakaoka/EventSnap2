//
//  CameraOrientation.swift
//  EventSnap
//
//  端末の物理的な向きを監視してキャプチャの回転角に変換する
//

import Foundation
import AVFoundation
import UIKit
import Combine

/// 「横で撮ったのに縦になる」問題を解くための向き管理。
///
/// ## なぜ必要か
///
/// このアプリは `Info.plist` で **Portrait のみ** に固定している。
/// そのため端末を横にしても `UIInterfaceOrientation` は `.portrait` のままで、
/// さらに `AVCaptureConnection` の回転角を誰も設定していなかったので、
/// 横に構えて撮っても常に「縦向きの写真」としてタグ付けされていた。
///
/// ## 方針
///
/// UIを回転対応にするとレイアウト全体の作り直しになるので、そうはしない。
/// 代わりに **加速度センサーが返す物理的な端末の向き**（`UIDevice.orientation`）を
/// 監視して、**写真出力の接続だけ**を回す。純正カメラアプリと同じやり方で、
/// 縦固定UIのまま横写真が撮れるようになる。
///
/// プレビューは `.portrait` に固定したままにする。画面自体が端末と一緒に
/// physically 回るので、見ている人の目には世界が正しい向きで映る。
@MainActor
final class CameraOrientation: ObservableObject {

    /// 直近の「有効な」端末の向き。
    /// 平置き（faceUp / faceDown）や unknown のときは更新せず、直前の値を保つ。
    @Published private(set) var current: UIDeviceOrientation = .portrait

    private var observer: AnyCancellable?

    init() {
        current = Self.sanitize(UIDevice.current.orientation) ?? .portrait
    }

    // deinit では後始末をしない。UIDevice はメインアクター隔離されているため、
    // どのスレッドから呼ばれるか分からない deinit から触るのは安全ではない。
    // 監視の停止は stopSession() から明示的に stop() を呼ぶ。

    /// 監視を開始する（カメラ画面が表示されている間だけ動かす）
    func start() {
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()

        observer = NotificationCenter.default
            .publisher(for: UIDevice.orientationDidChangeNotification)
            .compactMap { _ in Self.sanitize(UIDevice.current.orientation) }
            .removeDuplicates()
            .sink { [weak self] orientation in
                self?.current = orientation
            }
    }

    func stop() {
        observer?.cancel()
        observer = nil
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
    }

    /// 平置き・不明を弾く
    private static func sanitize(_ orientation: UIDeviceOrientation) -> UIDeviceOrientation? {
        switch orientation {
        case .portrait, .portraitUpsideDown, .landscapeLeft, .landscapeRight:
            return orientation
        default:
            return nil
        }
    }

    // MARK: - 撮影用の回転角

    /// 撮影した写真が正しい向きになる回転角（度）。iOS 17+ の
    /// `AVCaptureConnection.videoRotationAngle` にそのまま渡せる。
    ///
    /// 0° が `.landscapeRight` に対応する、というのが AVFoundation の基準。
    /// `UIDeviceOrientation` の landscapeLeft / landscapeRight は
    /// インターフェースの向きとは**左右が逆**になる点に注意（端末を左に倒すと
    /// 画面は右向きになる）。
    var captureRotationAngle: CGFloat {
        switch current {
        case .portrait:           return 90
        case .portraitUpsideDown: return 270
        case .landscapeLeft:      return 0
        case .landscapeRight:     return 180
        default:                  return 90
        }
    }

    /// iOS 16 向けのフォールバック
    var captureVideoOrientation: AVCaptureVideoOrientation {
        switch current {
        case .portrait:           return .portrait
        case .portraitUpsideDown: return .portraitUpsideDown
        case .landscapeLeft:      return .landscapeRight
        case .landscapeRight:     return .landscapeLeft
        default:                  return .portrait
        }
    }

    /// 撮影された写真が横向きになるか（UI表示の出し分けに使う）
    var isLandscape: Bool {
        current == .landscapeLeft || current == .landscapeRight
    }
}

// MARK: - 接続への適用

extension AVCaptureConnection {

    /// この接続の回転角を設定する。
    /// iOS 17 以降は `videoRotationAngle`、それ以前は `videoOrientation` を使う。
    func apply(rotationAngle: CGFloat, videoOrientation: AVCaptureVideoOrientation) {
        if #available(iOS 17.0, *) {
            if isVideoRotationAngleSupported(rotationAngle) {
                self.videoRotationAngle = rotationAngle
            }
        } else {
            if isVideoOrientationSupported {
                self.videoOrientation = videoOrientation
            }
        }
    }

    /// プレビューと同じ見え方に固定する（縦固定UI用）
    func applyPortrait() {
        apply(rotationAngle: 90, videoOrientation: .portrait)
    }

    /// フロントカメラの鏡像設定。
    /// `UIImage` の orientation を `.upMirrored` に決め打ちするのではなく、
    /// **接続側で鏡像化する**ことで、下流の画像処理が向きを気にせずに済む。
    func applyMirroring(_ mirrored: Bool) {
        guard isVideoMirroringSupported else { return }
        automaticallyAdjustsVideoMirroring = false
        isVideoMirrored = mirrored
    }
}
