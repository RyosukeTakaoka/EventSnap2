//
//  QRScannerView.swift
//  EventSnap
//
//  QRコード読み取り画面
//

import SwiftUI
import AVFoundation

@available(iOS 17.0, *)
struct QRScannerView: View {
    @ObservedObject var eventViewModel: EventViewModel
    @Environment(\.dismiss) var dismiss
    @State private var scannedCode: String?
    /// カメラの許可が取れているか。nil は確認中。
    @State private var cameraGranted: Bool?
    /// 同じコードで何度も参加処理を走らせない
    @State private var isHandling = false

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()

                switch cameraGranted {
                case true:
                    scanner
                case false:
                    permissionDenied
                case nil:
                    ProgressView().tint(.white)
                default:
                    EmptyView()
                }
            }
            .navigationBarItems(leading: Button("キャンセル") {
                dismiss()
            }.foregroundColor(.white))
            .onChange(of: scannedCode) { _, newValue in
                if let code = newValue {
                    handleScannedCode(code)
                }
            }
            .alert("参加できませんでした",
                   isPresented: Binding(get: { eventViewModel.error != nil },
                                        set: { if !$0 { eventViewModel.error = nil } })) {
                Button("もう一度読み取る", role: .cancel) { eventViewModel.error = nil }
            } message: {
                Text(eventViewModel.error ?? "")
            }
            // カメラの許可を先に取ってからプレビューを組み立てる。
            //
            // 以前は許可を確認せずいきなり AVCaptureSession を開始していた。
            // 初回起動時はまだ許可が無いので、iOSがダイアログを出している間に
            // セッションが空回りし、許可したあとも復帰しないため
            // **黒い画面のまま何も読み取れない**状態になっていた。
            // 一度カメラタブを開いた端末では許可済みなので再現せず、
            // 新しく入れた端末でだけ「読み取れない」と言われる形で出ていた。
            .task { await requestCameraAccess() }
        }
    }

    private var scanner: some View {
        ZStack {
            QRScannerRepresentable(scannedCode: $scannedCode)
                .ignoresSafeArea()

            // スキャンガイド
            VStack {
                Spacer()

                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.white, lineWidth: 3)
                    .frame(width: 250, height: 250)

                Spacer()

                Text("QRコードをフレーム内に収めてください")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(12)
                    .padding()
            }
        }
    }

    private var permissionDenied: some View {
        VStack(spacing: 18) {
            Image(systemName: "camera.fill")
                .font(.system(size: 52))
                .foregroundColor(.white.opacity(0.8))

            Text("カメラを使えません")
                .font(.headline)
                .foregroundColor(.white)

            Text("QRコードを読み取るにはカメラの許可が必要です。\n「設定」＞「EventSnap」からカメラをオンにしてください。")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.85))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button("設定を開く") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 4)
        }
    }

    /// カメラの許可を取る。まだ聞いていなければここで確認ダイアログを出す。
    private func requestCameraAccess() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            cameraGranted = true
        case .notDetermined:
            cameraGranted = await AVCaptureDevice.requestAccess(for: .video)
        default:
            cameraGranted = false
        }
    }

    private func handleScannedCode(_ code: String) {
        // 読み取りは毎フレーム走るので、二重に参加処理を投げないようにする
        guard !isHandling else { return }
        isHandling = true

        Task {
            // URLの場合はイベントIDを抽出、それ以外はそのまま使用
            let eventID = extractEventID(from: code) ?? code
            await eventViewModel.joinEvent(eventID: eventID)

            if eventViewModel.error == nil {
                dismiss()
            } else {
                // 失敗したら閉じずに、もう一度読み取れるようにする。
                // 以前は成否に関わらず閉じていたため、失敗しても
                // 何も起きていないように見えていた。
                scannedCode = nil
                isHandling = false
            }
        }
    }

    /// QRコードのデータからイベントIDを抽出
    /// - URLの場合: https://eventsnap.example.com/event/{eventID} から抽出
    /// - UUIDの場合: そのまま返す
    private func extractEventID(from code: String) -> String? {
        // URLとして解釈できるか試す
        if let url = URL(string: code) {
            let components = url.pathComponents
            // "/event/{eventID}" の形式を想定
            if components.count >= 3 && components[1] == "event" {
                return components[2]
            }

            // クエリパラメータからの抽出も対応
            if let urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let queryItems = urlComponents.queryItems,
               let eventIDItem = queryItems.first(where: { $0.name == "eventID" }),
               let eventID = eventIDItem.value {
                return eventID
            }
        }

        // URLではない場合、UUIDとして扱う
        return code
    }
}

// MARK: - UIViewRepresentable

struct QRScannerRepresentable: UIViewRepresentable {
    @Binding var scannedCode: String?

    class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        var parent: QRScannerRepresentable

        init(parent: QRScannerRepresentable) {
            self.parent = parent
        }

        func metadataOutput(
            _ output: AVCaptureMetadataOutput,
            didOutput metadataObjects: [AVMetadataObject],
            from connection: AVCaptureConnection
        ) {
            if let metadataObject = metadataObjects.first,
               let readableObject = metadataObject as? AVMetadataMachineReadableCodeObject,
               let stringValue = readableObject.stringValue {

                // 振動フィードバック
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()

                parent.scannedCode = stringValue
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .black

        guard let captureDevice = AVCaptureDevice.default(for: .video) else {
            return view
        }

        let captureSession = AVCaptureSession()

        guard let input = try? AVCaptureDeviceInput(device: captureDevice) else {
            return view
        }

        captureSession.addInput(input)

        let metadataOutput = AVCaptureMetadataOutput()
        captureSession.addOutput(metadataOutput)

        metadataOutput.setMetadataObjectsDelegate(context.coordinator, queue: .main)
        metadataOutput.metadataObjectTypes = [.qr]

        let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.bounds
        view.layer.addSublayer(previewLayer)

        DispatchQueue.global(qos: .userInitiated).async {
            captureSession.startRunning()
        }

        // Viewにセッションを保持（stopのため）
        objc_setAssociatedObject(view, "captureSession", captureSession, .OBJC_ASSOCIATION_RETAIN)

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        // プレビューレイヤーのサイズ更新
        DispatchQueue.main.async {
            if let layer = uiView.layer.sublayers?.first as? AVCaptureVideoPreviewLayer {
                layer.frame = uiView.bounds
            }
        }
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        // セッション停止
        if let session = objc_getAssociatedObject(uiView, "captureSession") as? AVCaptureSession {
            session.stopRunning()
        }
    }
}

#Preview {
    if #available(iOS 17.0, *) {
        QRScannerView(eventViewModel: EventViewModel())
    } else {
        // Fallback on earlier versions
    }
}
