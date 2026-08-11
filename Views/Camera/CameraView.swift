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
    @State private var showFilterPicker = false

    /// 終了したイベントには新しい写真を追加できない
    private var isEventActive: Bool {
        eventRepository.currentEvent?.isActive ?? true
    }

    var body: some View {
        ZStack {
            // カメラプレビュー（リアルタイムフィルター対応）
            if let previewImage = viewModel.previewImage,
               viewModel.isRealtimeEnabled,
               viewModel.selectedFilter == .beauty {
                // リアルタイムフィルタープレビュー
                //
                // 以前はここで .rotationEffect(.degrees(90)) を掛けていたが、
                // これは「美肌をONにすると画が横に倒れる」のを力技で戻していたもので、
                // 端末を横にすると逆に破綻していた。
                // 回転と鏡像は AVCaptureConnection 側で処理するようにしたので、
                // ここでは何も回さずそのまま表示する。
                Image(uiImage: previewImage)
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
            } else {
                // 通常のカメラプレビュー
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

                    // リアルタイムフィルターON/OFFトグル
                    if viewModel.selectedFilter == .beauty {
                        Button {
                            viewModel.isRealtimeEnabled.toggle()
                        } label: {
                            HStack {
                                Image(systemName: viewModel.isRealtimeEnabled ? "bolt.fill" : "bolt.slash")
                                Text(viewModel.isRealtimeEnabled ? "リアルタイム" : "撮影時のみ")
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(viewModel.isRealtimeEnabled ? Color.yellow.opacity(0.8) : Color.black.opacity(0.6))
                            .foregroundColor(viewModel.isRealtimeEnabled ? .black : .white)
                            .cornerRadius(16)
                        }
                        .padding(.leading, 8)
                    }

                    Spacer()

                    // フィルター選択ボタン
                    Button {
                        showFilterPicker.toggle()
                    } label: {
                        HStack {
                            Image(systemName: viewModel.selectedFilter.icon)
                            Text(viewModel.selectedFilter.rawValue)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.6))
                        .foregroundColor(.white)
                        .cornerRadius(20)
                    }
                    .padding()
                }
                .padding(.top, 8)

                // 美肌強度スライダー
                if viewModel.selectedFilter == .beauty && viewModel.isRealtimeEnabled {
                    HStack {
                        Image(systemName: "sparkles")
                            .foregroundColor(.white)
                        Slider(value: $viewModel.beautyIntensity, in: 0...1)
                            .tint(.yellow)
                        Text("\(Int(viewModel.beautyIntensity * 100))%")
                            .foregroundColor(.white)
                            .font(.caption)
                            .frame(width: 40)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(16)
                    .padding(.horizontal)
                }

                Spacer()

                if isEventActive {
                    // 撮影オプション（シェア許可・タイムカプセル）
                    HStack(spacing: 12) {
                        CaptureOptionToggle(
                            isOn: $viewModel.shareOK,
                            icon: "square.and.arrow.up",
                            label: "シェアOK",
                            tint: .green
                        )

                        CaptureOptionToggle(
                            isOn: $viewModel.saveAsTimeCapsule,
                            icon: "hourglass",
                            label: "あとで公開",
                            tint: .orange
                        )
                    }
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

            // フィルターピッカー
            if showFilterPicker {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture {
                        showFilterPicker = false
                    }

                FilterPickerView(
                    selectedFilter: $viewModel.selectedFilter,
                    onDismiss: { showFilterPicker = false }
                )
                .transition(.move(edge: .bottom))
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

// MARK: - 撮影オプションのトグル

/// シャッターの上に置く小さなトグル。
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
