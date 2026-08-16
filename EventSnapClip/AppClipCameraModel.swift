//
//  AppClipCameraModel.swift
//  EventSnapClip
//
//  App Clip専用の最小限のカメラ実装。
//
//  メインアプリの CameraViewModel は PhotoRepository / EventRepository と
//  密結合していて、撮影＝CloudKitへのアップロードが前提になっている。
//  App Clipは「撮るだけ」で投稿はさせない設計なので、あえて別実装にして
//  アップロード経路を一切持ち込まないようにしている。
//
//  向きの扱い（CameraOrientation・UIImage.normalizedUp）はメインアプリと
//  同じファイルをそのまま共有している（このターゲットのSourcesにも
//  同じPBXFileReferenceが追加されている）。
//

import Foundation
import AVFoundation
import UIKit
import Combine

@MainActor
final class AppClipCameraModel: NSObject, ObservableObject {
    @Published var isAuthorized = false
    @Published var permissionDenied = false
    @Published var capturedImage: UIImage?
    @Published var isCapturing = false

    let captureSession = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let orientation = CameraOrientation()
    private let sessionQueue = DispatchQueue(label: "com.eventsnap.appclip.camera")
    private var orientationCancellable: AnyCancellable?

    // MARK: - 権限とセッション

    func requestAccessAndStart() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            isAuthorized = true
        case .notDetermined:
            isAuthorized = await AVCaptureDevice.requestAccess(for: .video)
        default:
            isAuthorized = false
        }

        guard isAuthorized else {
            permissionDenied = true
            return
        }

        setupSession()
        orientation.start()
        observeOrientation()

        let session = captureSession
        sessionQueue.async {
            session.startRunning()
        }
    }

    func stop() {
        orientation.stop()
        orientationCancellable?.cancel()
        let session = captureSession
        sessionQueue.async {
            session.stopRunning()
        }
    }

    private func setupSession() {
        captureSession.sessionPreset = .photo

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else {
            return
        }

        if captureSession.canAddInput(input) {
            captureSession.addInput(input)
        }
        if captureSession.canAddOutput(photoOutput) {
            captureSession.addOutput(photoOutput)
        }

        updatePhotoOutputOrientation()
    }

    /// 端末の向きが変わるたびに、写真出力の回転角だけを追従させる。
    /// プレビューは縦固定のまま（メインアプリのCameraViewと同じ考え方）。
    private func observeOrientation() {
        orientationCancellable = orientation.$current
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updatePhotoOutputOrientation()
            }
    }

    private func updatePhotoOutputOrientation() {
        guard let connection = photoOutput.connection(with: .video) else { return }
        connection.apply(
            rotationAngle: orientation.captureRotationAngle,
            videoOrientation: orientation.captureVideoOrientation
        )
    }

    // MARK: - 撮影

    func capturePhoto() {
        guard !isCapturing else { return }
        isCapturing = true

        let settings = AVCapturePhotoSettings()
        settings.flashMode = .auto

        let delegate = AppClipPhotoCaptureDelegate { [weak self] image in
            Task { @MainActor in
                self?.capturedImage = image?.normalizedUp()
                self?.isCapturing = false
            }
        }
        // デリゲートはコールバックが呼ばれるまで強参照で保持する必要がある
        self.activeDelegate = delegate
        photoOutput.capturePhoto(with: settings, delegate: delegate)
    }

    private var activeDelegate: AppClipPhotoCaptureDelegate?

    /// 撮り直す（プレビューに戻る）
    func retake() {
        capturedImage = nil
    }
}

// MARK: - 撮影デリゲート

private final class AppClipPhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private let completion: (UIImage?) -> Void

    init(completion: @escaping (UIImage?) -> Void) {
        self.completion = completion
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        guard error == nil, let data = photo.fileDataRepresentation() else {
            completion(nil)
            return
        }
        completion(UIImage(data: data))
    }
}
