//
//  EventSnapClipRootView.swift
//  EventSnapClip
//
//  App Clipの画面遷移。
//
//    カメラ ──(撮影)──▶ プレビュー ──(投稿する)──▶ 「続きはアプリで」
//                          │
//                          └─(撮り直す)─▶ カメラへ戻る
//
//  「投稿する」を押しても、写真はどこにも送信されない。フルアプリでしか
//  投稿できないことを案内し、App Storeへ誘導するだけ。CloudKitへの書き込みは
//  このターゲットのどこにも存在しない。
//

import SwiftUI
import AVFoundation

struct EventSnapClipRootView: View {
    @StateObject private var camera = AppClipCameraModel()
    @State private var showGetAppScreen = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let image = camera.capturedImage {
                PreviewScreen(
                    image: image,
                    onRetake: { camera.retake() },
                    onPost: { showGetAppScreen = true }
                )
            } else if camera.isAuthorized {
                CameraScreen(camera: camera)
            } else if camera.permissionDenied {
                PermissionDeniedScreen()
            } else {
                ProgressView().tint(.white)
            }
        }
        .task {
            await camera.requestAccessAndStart()
        }
        .onDisappear {
            camera.stop()
        }
        .fullScreenCover(isPresented: $showGetAppScreen) {
            GetAppScreen()
        }
    }
}

// MARK: - カメラ画面

private struct CameraScreen: View {
    @ObservedObject var camera: AppClipCameraModel

    var body: some View {
        ZStack {
            AppClipCameraPreview(session: camera.captureSession)
                .ignoresSafeArea()

            VStack {
                VStack(spacing: 6) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.title2)
                    Text("EventSnap App Clip")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .padding(.top, 60)
                .shadow(radius: 4)

                Spacer()

                Text("その場の思い出を撮ってみよう")
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.55))
                    .cornerRadius(12)
                    .padding(.bottom, 20)

                Button {
                    camera.capturePhoto()
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
                .disabled(camera.isCapturing)
                .padding(.bottom, 50)
            }
        }
    }
}

// MARK: - 撮影プレビュー(UIKitブリッジ)

private struct AppClipCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        // プレビューは縦固定。端末が物理的に回るので見た目は正しくなる
        // （メインアプリのCameraViewと同じ考え方）。
        layer.connection?.applyPortrait()
        view.layer.addSublayer(layer)
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

// MARK: - 撮影後のプレビュー

private struct PreviewScreen: View {
    let image: UIImage
    let onRetake: () -> Void
    let onPost: () -> Void

    var body: some View {
        VStack {
            Spacer()

            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .cornerRadius(16)
                .padding(.horizontal)

            Spacer()

            HStack(spacing: 16) {
                Button {
                    onRetake()
                } label: {
                    Text("撮り直す")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.white.opacity(0.15))
                        .foregroundColor(.white)
                        .cornerRadius(14)
                }

                Button {
                    onPost()
                } label: {
                    Text("この写真を投稿する")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.white)
                        .foregroundColor(.black)
                        .cornerRadius(14)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 40)
        }
    }
}

// MARK: - カメラ権限が無い場合

private struct PermissionDeniedScreen: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.fill")
                .font(.system(size: 44))
                .foregroundColor(.white.opacity(0.8))

            Text("カメラを使えません")
                .font(.headline)
                .foregroundColor(.white)

            Text("設定アプリからカメラへのアクセスを許可してください。")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }
}

#Preview {
    EventSnapClipRootView()
}
