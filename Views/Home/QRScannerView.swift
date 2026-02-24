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

    var body: some View {
        NavigationView {
            ZStack {
                // カメラプレビュー
                QRScannerRepresentable(scannedCode: $scannedCode)
                    .ignoresSafeArea()

                // スキャンガイド
                VStack {
                    Spacer()

                    // スキャンエリア
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
            .navigationBarItems(leading: Button("キャンセル") {
                dismiss()
            }.foregroundColor(.white))
            .onChange(of: scannedCode) { _, newValue in
                if let code = newValue {
                    handleScannedCode(code)
                }
            }
        }
    }

    private func handleScannedCode(_ code: String) {
        Task {
            // URLの場合はイベントIDを抽出、それ以外はそのまま使用
            let eventID = extractEventID(from: code) ?? code
            await eventViewModel.joinEvent(eventID: eventID)
            dismiss()
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
