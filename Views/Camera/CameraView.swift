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
    @State private var showFilterPicker = false

    var body: some View {
        ZStack {
            // カメラプレビュー（リアルタイムフィルター対応）
            if let previewImage = viewModel.previewImage,
               viewModel.isRealtimeEnabled,
               viewModel.selectedFilter == .beauty {
                // リアルタイムフィルタープレビュー
                Image(uiImage: previewImage)
                    .resizable()
                    .scaledToFill()
                    .rotationEffect(.degrees(90))
                    .ignoresSafeArea()
            } else {
                // 通常のカメラプレビュー
                CameraPreview(session: viewModel.captureSession)
                    .ignoresSafeArea()
            }

            // UI オーバーレイ
            VStack {
                // トップバー
                HStack {
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
                        .padding(.leading)
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
                    }
                    .disabled(viewModel.isProcessing)
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

// MARK: - カメラプレビュー

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)

        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.bounds
        view.layer.addSublayer(previewLayer)

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            if let layer = uiView.layer.sublayers?.first as? AVCaptureVideoPreviewLayer {
                layer.frame = uiView.bounds
            }
        }
    }
}

#Preview {
    CameraView()
}
