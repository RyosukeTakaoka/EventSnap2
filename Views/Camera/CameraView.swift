//
//  CameraView.swift
//  EventSnap
//
//  カメラ撮影画面
//

import SwiftUI
import AVFoundation

struct CameraView: View {
    @StateObject private var viewModel = CameraViewModel()
    @ObservedObject private var eventRepository = EventRepository.shared
    @ObservedObject private var tutorial = TutorialManager.shared

    /// カメラ画面で扱う初回チュートリアルのステップだけを対象にする
    /// （アルバム側のステップは`AlbumView`が別途面倒を見る）。
    private static let cameraSteps: Set<TutorialStep> = [.shutter, .shareOK, .laterReveal, .shutterForLaterReveal]

    /// 終了したイベントには新しい写真を追加できない
    private var isEventActive: Bool {
        eventRepository.currentEvent?.isActive ?? true
    }

    var body: some View {
        ZStack {
            // 通常は本物のカメラプレビュー。撮影モードのときだけFixture画像を敷く
            // （シミュレータのAVCaptureSessionは黒い映像しか返さず、実機でも
            //  「撮影中の画」を再現性のある形では作れないため）。
            // `cameraBackgroundImage`はReleaseビルドでは常にnilで、
            // このifごと最適化で消える＝出荷時の挙動は従来と同一。
            if let background = ScreenshotMode.cameraBackgroundImage {
                Image(uiImage: background)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .ignoresSafeArea()
            } else {
                CameraPreview(session: viewModel.captureSession, mirrored: viewModel.cameraPosition == .front)
                    .ignoresSafeArea()
            }

            // UI オーバーレイ
            VStack {
                // トップバー
                HStack {
                    // イン/アウトカメラ切り替え
                    Button {
                        viewModel.switchCamera()
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath.camera")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 36, height: 36)
                            .background(Color.black.opacity(0.55))
                            .foregroundColor(.white)
                            .clipShape(Circle())
                    }
                    .padding(.leading)
                    .accessibilityLabel("カメラを切り替え")

                    Spacer()
                }
                .padding(.top, 8)

                Spacer()

                if !isEventActive {
                    // 終了したイベントでは撮影オプションの代わりに案内を出す
                    HStack {
                        Image(systemName: "lock.fill")
                        Text("このイベントは終了しています。新しい写真は追加できません。")
                            .font(.caption)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(14)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 18)
                }

                // 処理中インジケーター
                if viewModel.isProcessing {
                    HStack {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        Text("処理中...")
                            .foregroundColor(.white)
                    }
                    .padding()
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(12)
                    .padding(.bottom, 12)
                }

                // ボトムコントロール
                // シャッターボタンを中央に固定し、撮影オプション（シェア許可・
                // タイムカプセル）はその左側に縦に並べる（以前はシャッターの
                // 真上に横並びで置いていたが、押し間違いを避けるため場所を分けた）。
                ZStack {
                    Button {
                        viewModel.capturePhoto()
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color.white)
                                .frame(width: 70, height: 70)

                            Circle()
                                .stroke(Color.white, lineWidth: 3)
                                .frame(width: 80, height: 80)
                        }
                        .opacity(isEventActive ? 1 : 0.4)
                    }
                    .disabled(viewModel.isProcessing || !isEventActive)
                    .tutorialTarget(.shutter)

                    if isEventActive {
                        HStack {
                            VStack(spacing: 10) {
                                CaptureOptionToggle(
                                    isOn: $viewModel.shareOK,
                                    icon: "square.and.arrow.up",
                                    label: "シェアOK",
                                    tint: .green
                                )
                                .tutorialTarget(.shareOK)

                                CaptureOptionToggle(
                                    isOn: $viewModel.saveAsTimeCapsule,
                                    icon: "hourglass",
                                    label: "あとで公開",
                                    tint: .orange
                                )
                                .tutorialTarget(.laterReveal)
                            }
                            Spacer()
                        }
                        .padding(.leading, 28)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 40)
            }

            // カメラのタブ切り替えを促す案内だけは、対象UIがこの画面に無い
            // （タブバー自体をハイライト対象にしていない）ため、スポットライトではなく
            // 下向き矢印の小さな案内にする。
            if tutorial.currentStep == .goToAlbum {
                TutorialBottomHint(text: "次はアルバムを見てみよう")
            }
        }
        // 初回チュートリアル: 実際のシャッター・トグルの実測フレームを読み取り、
        // その上にハイライトを重ねるだけで、偽物のUIは一切作らない
        // （`TutorialManager`のコメント参照）。
        .overlayPreferenceValue(TutorialAnchorKey.self) { anchors in
            if let step = tutorial.currentStep, Self.cameraSteps.contains(step) {
                let content = step.content
                TutorialSpotlightOverlay(
                    manager: tutorial,
                    anchors: anchors,
                    target: content.target,
                    title: content.title,
                    message: content.message,
                    actionLabel: content.actionLabel
                )
            }
        }
        .task {
            await viewModel.checkCameraPermission()
        }
        .onAppear {
            viewModel.startSession()
            tutorial.startIfNeeded()
        }
        .onDisappear {
            viewModel.stopSession()
        }
        // iPhone 16以降のカメラコントロールボタン（と音量ボタン）でもシャッターを切れるようにする。
        // シャッターボタンの`.disabled`と同じ条件でしか反応させない。
        .cameraControlCapture(isEnabled: !viewModel.isProcessing && isEventActive) {
            viewModel.capturePhoto()
        }
    }
}

// MARK: - カメラコントロール（iPhone 16以降の物理ボタン）対応

private extension View {
    /// カメラコントロールボタンが押し切られた（`.ended`）タイミングでシャッターを切る。
    ///
    /// `onCameraCaptureEvent`はiOS 18以降のAPIで、それ未満の端末では
    /// このメソッド自体が存在しないため`#available`で分岐し、古い端末では何もしない
    /// （その場合も画面上のシャッターボタンは従来どおり使える）。
    @ViewBuilder
    func cameraControlCapture(isEnabled: Bool, action: @escaping () -> Void) -> some View {
        if #available(iOS 18.0, *) {
            onCameraCaptureEvent(isEnabled: isEnabled) { event in
                if event.phase == .ended {
                    action()
                }
            }
        } else {
            self
        }
    }
}

// MARK: - 撮影オプションのトグル

/// シャッターの横に置く小さなトグル。
/// どちらも **押していない状態が既定** で、撮影のたびにOFFへ戻る。
///
/// アイコンのみの丸ボタンにして画面上の情報量を抑えている（文字ラベルは常時表示しない）。
/// 機能自体（タップでON/OFF）は変わらず、ONのときだけ下に短いラベルを出して
/// 何がONになっているか分かるようにする。
struct CaptureOptionToggle: View {
    @Binding var isOn: Bool
    let icon: String
    let label: String
    let tint: Color
    var isDisabled: Bool = false

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { isOn.toggle() }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .background(isOn ? tint.opacity(0.9) : Color.black.opacity(0.55))
                    .foregroundColor(isOn ? .black : .white)
                    .clipShape(Circle())
                    .overlay(
                        Circle().stroke(isOn ? Color.clear : Color.white.opacity(0.35), lineWidth: 1)
                    )

                if isOn {
                    Text(label)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.55))
                        .clipShape(Capsule())
                }
            }
            .opacity(isDisabled ? 0.4 : 1)
        }
        .disabled(isDisabled)
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "オン" : "オフ")
    }
}

// MARK: - カメラプレビュー

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    /// インカメラのときだけ鏡像にする（アウトカメラは鏡像にしない）
    let mirrored: Bool

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)

        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.bounds

        // プレビューは縦固定にする。UIが縦固定なので、端末を横にすると
        // 画面ごと物理的に回り、見ている人の目には世界が正しい向きで映る。
        // 写真の向きは CameraViewModel が撮影出力の接続側で合わせる。
        previewLayer.connection?.applyPortrait()
        previewLayer.connection?.applyMirroring(mirrored)

        view.layer.addSublayer(previewLayer)

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            if let layer = uiView.layer.sublayers?.first as? AVCaptureVideoPreviewLayer {
                layer.frame = uiView.bounds
                layer.connection?.applyMirroring(mirrored)
            }
        }
    }
}

#Preview {
    CameraView()
}
