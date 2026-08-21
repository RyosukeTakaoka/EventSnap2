//
//  RelayTurnCameraView.swift
//  EventSnap
//
//  Relayで自分の番が開放されたときの、その場限りの撮影画面
//

import SwiftUI
import AVFoundation
import Combine

/// 通常のカメラタブ（`CameraView`/`CameraViewModel`）とは独立した、Relay専用の
/// 撮影画面。シェアOK・あとで公開のトグルは持たない（Relayの投稿はその場で
/// バトンを渡す1枚であり、通常撮影の選択肢とは意味が異なるため混在させない）。
/// `CameraPreview`（`CameraView.swift`）・`CameraOrientation`・
/// `PhotoCaptureDelegate`（`CameraViewModel.swift`）はファイルスコープの
/// 汎用部品としてそのまま再利用する。
struct RelayTurnCameraView: View {
    @ObservedObject var viewModel: RelayViewModel
    @StateObject private var camera = RelayCameraCaptureModel()
    @Environment(\.dismiss) private var dismiss

    @State private var isSubmitting = false

    var body: some View {
        ZStack {
            CameraPreview(session: camera.captureSession, mirrored: camera.cameraPosition == .front)
                .ignoresSafeArea()

            VStack {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 36, height: 36)
                            .background(Color.black.opacity(0.55))
                            .foregroundColor(.white)
                            .clipShape(Circle())
                    }
                    .padding(.leading)

                    Spacer()

                    Button {
                        camera.switchCamera()
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath.camera")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 36, height: 36)
                            .background(Color.black.opacity(0.55))
                            .foregroundColor(.white)
                            .clipShape(Circle())
                    }
                    .padding(.trailing)
                }
                .padding(.top, 8)

                Spacer()

                if isSubmitting {
                    HStack {
                        ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white))
                        Text("投稿中...").foregroundColor(.white)
                    }
                    .padding()
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(12)
                    .padding(.bottom, 12)
                }

                Button {
                    capture()
                } label: {
                    ZStack {
                        Circle().fill(Color.white).frame(width: 70, height: 70)
                        Circle().stroke(Color.white, lineWidth: 3).frame(width: 80, height: 80)
                    }
                }
                .disabled(camera.isProcessing || isSubmitting)
                .padding(.bottom, 40)
            }
        }
        .task { await camera.checkCameraPermission() }
        .onAppear { camera.startSession() }
        .onDisappear { camera.stopSession() }
    }

    private func capture() {
        camera.capturePhoto { image in
            guard let image else { return }
            Task { @MainActor in
                isSubmitting = true
                let success = await viewModel.submitNewPhoto(image)
                isSubmitting = false
                if success { dismiss() }
            }
        }
    }
}

// MARK: - 撮影専用の軽量カメラモデル

/// `CameraViewModel`の撮影セッション管理部分だけを踏襲し、シェアOK・あとで公開の
/// トグルや自動アップロードなど、通常撮影フロー固有のロジックは持たない。
@MainActor
final class RelayCameraCaptureModel: ObservableObject {
    @Published var isProcessing = false
    @Published var isCameraAuthorized = false
    @Published var cameraPosition: AVCaptureDevice.Position = .front

    let orientation = CameraOrientation()
    let captureSession = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private var videoDeviceInput: AVCaptureDeviceInput?
    private let cameraQueue = DispatchQueue(label: "com.eventsnap.relaycamera")
    private var photoCaptureDelegate: PhotoCaptureDelegate?
    private var orientationCancellable: AnyCancellable?

    func checkCameraPermission() async {
        guard !ScreenshotMode.suppressesLiveServices else { return }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            isCameraAuthorized = true
            setupCamera()
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            isCameraAuthorized = granted
            if granted { setupCamera() }
        case .denied, .restricted:
            isCameraAuthorized = false
        @unknown default:
            isCameraAuthorized = false
        }
    }

    private func setupCamera() {
        captureSession.sessionPreset = .photo

        guard let cameraDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: cameraPosition),
              let input = try? AVCaptureDeviceInput(device: cameraDevice) else { return }

        if captureSession.canAddInput(input) {
            captureSession.addInput(input)
            videoDeviceInput = input
        }

        if captureSession.canAddOutput(photoOutput) {
            captureSession.addOutput(photoOutput)
        }

        orientation.start()
        observeOrientation()
        updatePhotoOutputOrientation()

        cameraQueue.async { [weak self] in
            self?.captureSession.startRunning()
        }
    }

    func switchCamera() {
        let newPosition: AVCaptureDevice.Position = cameraPosition == .front ? .back : .front

        guard let cameraDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: newPosition),
              let newInput = try? AVCaptureDeviceInput(device: cameraDevice) else { return }

        cameraQueue.async { [weak self] in
            guard let self else { return }
            self.captureSession.beginConfiguration()
            if let currentInput = self.videoDeviceInput {
                self.captureSession.removeInput(currentInput)
            }
            if self.captureSession.canAddInput(newInput) {
                self.captureSession.addInput(newInput)
                self.videoDeviceInput = newInput
            }
            self.captureSession.commitConfiguration()

            Task { @MainActor in
                self.cameraPosition = newPosition
                self.photoOutput.connection(with: .video)?.applyMirroring(newPosition == .front)
            }
        }
    }

    private func observeOrientation() {
        orientationCancellable = orientation.$current
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updatePhotoOutputOrientation() }
    }

    private func updatePhotoOutputOrientation() {
        guard let connection = photoOutput.connection(with: .video) else { return }
        connection.apply(rotationAngle: orientation.captureRotationAngle, videoOrientation: orientation.captureVideoOrientation)
        connection.applyMirroring(cameraPosition == .front)
    }

    func capturePhoto(completion: @escaping (UIImage?) -> Void) {
        guard !ScreenshotMode.suppressesLiveServices else { return }
        guard !isProcessing else { return }

        isProcessing = true

        let settings = AVCapturePhotoSettings()
        settings.flashMode = .auto

        let delegate = PhotoCaptureDelegate { [weak self] image in
            Task { @MainActor in
                self?.isProcessing = false
                self?.photoCaptureDelegate = nil
                completion(image?.normalizedUp())
            }
        }

        photoCaptureDelegate = delegate
        photoOutput.capturePhoto(with: settings, delegate: delegate)
    }

    func startSession() {
        guard !ScreenshotMode.suppressesLiveServices else { return }
        orientation.start()
        updatePhotoOutputOrientation()
        cameraQueue.async { [weak self] in
            guard let self, !self.captureSession.isRunning else { return }
            self.captureSession.startRunning()
        }
    }

    func stopSession() {
        orientation.stop()
        cameraQueue.async { [weak self] in
            guard let self, self.captureSession.isRunning else { return }
            self.captureSession.stopRunning()
        }
    }
}

#Preview {
    RelayTurnCameraView(viewModel: RelayViewModel())
}
