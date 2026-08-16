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

    /// 終了したイベントには新しい写真を追加できない
    private var isEventActive: Bool {
        eventRepository.currentEvent?.isActive ?? true
    }

    var body: some View {
        ZStack {
            CameraPreview(session: viewModel.captureSession, mirrored: viewModel.cameraPosition == .front)
                .ignoresSafeArea()

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

                if isEventActive {
                    PublishSettingPicker(shareOK: $viewModel.shareOK, saveAsTimeCapsule: $viewModel.saveAsTimeCapsule)
                        .padding(.bottom, 18)
                } else {
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

                // ボトムコントロール
                VStack(spacing: 20) {
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
                    }

                    // シャッターボタン
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
                }
                .padding(.bottom, 40)
            }
        }
        .task {
            await viewModel.checkCameraPermission()
        }
        .onAppear {
            viewModel.startSession()
        }
        .onDisappear {
            viewModel.stopSession()
        }
    }
}

// MARK: - 公開設定ピッカー

/// 「シェアOK」「あとで公開」を2つの独立トグルにせず、
/// 「非公開 / あとで公開 / シェアOK」という1つの排他的な選択として扱う。
///
/// `shareOK`がONの間は`saveAsTimeCapsule`は選べない
/// （`CameraViewModel.shareOK`の`didSet`が自動でOFFに戻すため、内部的にも
/// 常にどちらか一方だけがtrueになる）。UI側もそれを素直に反映するだけで、
/// 独自の状態は持たない。
struct PublishSettingPicker: View {
    @Binding var shareOK: Bool
    @Binding var saveAsTimeCapsule: Bool

    private enum Choice: CaseIterable {
        case `private`, later, share

        var label: String {
            switch self {
            case .private: return "非公開"
            case .later: return "あとで公開"
            case .share: return "シェアOK"
            }
        }

        var icon: String {
            switch self {
            case .private: return "lock"
            case .later: return "hourglass"
            case .share: return "square.and.arrow.up"
            }
        }

        var tint: Color {
            switch self {
            case .private: return .gray
            case .later: return .orange
            case .share: return .green
            }
        }
    }

    private var current: Choice {
        if shareOK { return .share }
        if saveAsTimeCapsule { return .later }
        return .private
    }

    var body: some View {
        HStack(spacing: 12) {
            ForEach(Choice.allCases, id: \.self) { choice in
                Button {
                    select(choice)
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: choice.icon)
                            .font(.system(size: 17, weight: .semibold))
                            .frame(width: 44, height: 44)
                            .background(current == choice ? choice.tint.opacity(0.9) : Color.black.opacity(0.55))
                            .foregroundColor(current == choice ? .black : .white)
                            .clipShape(Circle())
                            .overlay(
                                Circle().stroke(current == choice ? Color.clear : Color.white.opacity(0.35), lineWidth: 1)
                            )

                        Text(choice.label)
                            .font(.caption2)
                            .fontWeight(current == choice ? .semibold : .regular)
                            .foregroundColor(current == choice ? .white : .white.opacity(0.6))
                    }
                }
                .accessibilityLabel(choice.label)
                .accessibilityAddTraits(current == choice ? .isSelected : [])
            }
        }
    }

    private func select(_ choice: Choice) {
        withAnimation(.easeInOut(duration: 0.15)) {
            switch choice {
            case .private:
                shareOK = false
                saveAsTimeCapsule = false
            case .later:
                shareOK = false
                saveAsTimeCapsule = true
            case .share:
                // shareOKのdidSetがsaveAsTimeCapsuleを自動でfalseにする
                shareOK = true
            }
        }
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
