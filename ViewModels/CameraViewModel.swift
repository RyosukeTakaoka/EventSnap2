//
//  CameraViewModel.swift
//  EventSnap
//
//  カメラ撮影ViewModel（修正版）
//

import Foundation
import AVFoundation
import SwiftUI
import Combine

@MainActor
class CameraViewModel: ObservableObject {
    @Published var capturedImage: UIImage?
    @Published var isProcessing = false
    @Published var selectedFilter: FilterType = .none
    @Published var isCameraAuthorized = false
    @Published var showFilterPreview = false

    // ✨ リアルタイムフィルター用プロパティ
    @Published var previewImage: UIImage?
    @Published var isRealtimeEnabled = true
    @Published var beautyIntensity: Double = 0.5

    let captureSession = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput() // ✨ 追加
    private let aiFilterService = AIFilterService()
    private let photoRepository = PhotoRepository.shared
    private let eventRepository = EventRepository.shared

    // カメラ専用のキュー
    private let cameraQueue = DispatchQueue(label: "com.eventsnap.camera")
    private let videoQueue = DispatchQueue(label: "com.eventsnap.video", qos: .userInteractive) // ✨ 追加

    // 🔥 重要: デリゲートを強参照で保持
    private var photoCaptureDelegate: PhotoCaptureDelegate?
    private var videoDelegate: VideoDataOutputDelegate? // ✨ 追加

    // ✨ フレームスロットリング用
    private var lastFrameProcessedTime: Date = .distantPast
    private let frameProcessingInterval: TimeInterval = 0.1 // 10 FPS

    enum FilterType: String, CaseIterable, Identifiable {
        case none = "なし"
        case beauty = "美肌"
        case bright = "明るく"
        case vintage = "レトロ"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .none: return "camera"
            case .beauty: return "sparkles"
            case .bright: return "sun.max"
            case .vintage: return "photo.on.rectangle"
            }
        }
    }

    // MARK: - カメラ権限確認

    func checkCameraPermission() async {
        print("🔍 カメラ権限を確認中...")
        
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            print("✅ カメラ権限が許可されています")
            isCameraAuthorized = true
            setupCamera()

        case .notDetermined:
            print("⚠️ カメラ権限がまだ決定されていません。許可をリクエストします...")
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            isCameraAuthorized = granted
            if granted {
                print("✅ カメラ権限が許可されました")
                setupCamera()
            } else {
                print("❌ カメラ権限が拒否されました")
            }

        case .denied, .restricted:
            print("❌ カメラ権限が拒否されているか制限されています")
            isCameraAuthorized = false

        @unknown default:
            print("❌ 不明なカメラ権限ステータス")
            isCameraAuthorized = false
        }
    }

    // MARK: - カメラセッション設定

    func setupCamera() {
        print("📷 カメラセットアップ開始...")

        captureSession.sessionPreset = .photo

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: camera) else {
            print("❌ カメラデバイスが見つかりません")
            return
        }

        if captureSession.canAddInput(input) {
            captureSession.addInput(input)
            print("✅ カメラ入力を追加しました")
        }

        // 写真出力を追加
        if captureSession.canAddOutput(photoOutput) {
            captureSession.addOutput(photoOutput)
            print("✅ 写真出力を追加しました")
        }

        // ✨ ビデオ出力を追加（リアルタイムプレビュー用）
        videoOutput.setSampleBufferDelegate(nil, queue: nil) // 既存のデリゲートをクリア
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoOutput.alwaysDiscardsLateVideoFrames = true // パフォーマンス最適化

        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
            print("✅ ビデオ出力を追加しました")

            // デリゲート設定
            let delegate = VideoDataOutputDelegate { [weak self] pixelBuffer in
                self?.processVideoFrame(pixelBuffer)
            }
            self.videoDelegate = delegate
            videoOutput.setSampleBufferDelegate(delegate, queue: videoQueue)
            print("✅ ビデオデリゲートを設定しました")
        }

        // ✅ バックグラウンドスレッドで実行
        cameraQueue.async { [weak self] in
            self?.captureSession.startRunning()
            print("✅ カメラセッション開始")
        }
    }

    // MARK: - 撮影

    func capturePhoto() {
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("📸 撮影開始")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        
        guard !isProcessing else {
            print("⚠️ 既に処理中です")
            return
        }

        isProcessing = true
        print("🔄 処理状態をtrueに設定")

        let settings = AVCapturePhotoSettings()
        settings.flashMode = .auto
        
        print("📷 写真キャプチャを開始します...")
        print("🔍 photoOutputの状態: \(photoOutput)")
        print("🔍 captureSessionの状態: isRunning=\(captureSession.isRunning)")

        // 🔥 重要: デリゲートを強参照で保持
        let delegate = PhotoCaptureDelegate { [weak self] image in
            print("\n【コールバック】写真キャプチャのコールバックが呼ばれました")
            
            guard let self = self else {
                print("❌ selfがnilです")
                return
            }
            
            guard let image = image else {
                print("❌ 画像がnilです")
                Task { @MainActor in
                    self.isProcessing = false
                    self.photoCaptureDelegate = nil // クリーンアップ
                    print("🔄 処理状態をfalseに設定（画像なし）")
                }
                return
            }
            
            print("✅ 画像取得成功")
            print("📐 画像サイズ: \(image.size)")

            Task { @MainActor in
                print("\n【メインスレッド】画像処理を開始します")
                
                // フィルター適用
                print("🎨 フィルター適用開始: \(self.selectedFilter.rawValue)")
                let filterStartTime = Date()
                let processedImage = await self.applySelectedFilter(to: image)
                let filterTime = Date().timeIntervalSince(filterStartTime)
                print("✅ フィルター適用完了（\(String(format: "%.2f", filterTime))秒）")
                
                self.capturedImage = processedImage
                print("✅ capturedImageに画像を設定しました")

                // 自動アップロード
                print("\n📤 自動アップロード開始...")
                let uploadStartTime = Date()
                await self.uploadPhoto(processedImage)
                let uploadTime = Date().timeIntervalSince(uploadStartTime)
                print("✅ アップロード完了（\(String(format: "%.2f", uploadTime))秒）")

                self.isProcessing = false
                self.photoCaptureDelegate = nil // クリーンアップ
                print("🔄 処理状態をfalseに設定")
                print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                print("✅ 全ての処理が完了しました")
                print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
            }
        }
        
        // デリゲートを保持
        self.photoCaptureDelegate = delegate
        print("✅ PhotoCaptureDelegateを作成・保持しました")
        
        // 写真をキャプチャ
        photoOutput.capturePhoto(with: settings, delegate: delegate)
        print("✅ capturePhoto()メソッドを呼び出しました")
    }

    // MARK: - フィルター適用

    private func applySelectedFilter(to image: UIImage) async -> UIImage {
        print("  🎨 選択されたフィルター: \(selectedFilter.rawValue)")
        
        switch selectedFilter {
        case .none:
            print("  ✅ フィルターなし - そのまま返します")
            return image

        case .beauty:
            print("  🌟 美肌フィルター適用中...")
            let result = await aiFilterService.applyBeautyFilter(to: image)
            print("  ✅ 美肌フィルター適用完了")
            return result

        case .bright:
            print("  ☀️ 明るさフィルター適用中...")
            let result = aiFilterService.applyBrightnessFilter(to: image)
            print("  ✅ 明るさフィルター適用完了")
            return result

        case .vintage:
            print("  📸 レトロフィルター適用中...")
            let result = aiFilterService.applyVintageFilter(to: image)
            print("  ✅ レトロフィルター適用完了")
            return result
        }
    }

    // MARK: - 写真アップロード

    private func uploadPhoto(_ image: UIImage) async {
        print("  📤 アップロード処理開始...")
        
        guard let eventID = eventRepository.currentEvent?.id else {
            print("  ❌ アップロード失敗: イベントが見つかりません")
            print("  ⚠️ eventRepository.currentEvent = \(eventRepository.currentEvent != nil ? "存在" : "nil")")
            return
        }

        print("  📋 イベントID: \(eventID.uuidString)")

        do {
            print("  🔄 PhotoRepositoryにアップロード中...")
            try await photoRepository.uploadPhoto(
                image,
                eventID: eventID,
                filterName: selectedFilter != .none ? selectedFilter.rawValue : nil
            )
            print("  ✅ 写真を自動共有しました")
        } catch {
            print("  ❌ アップロード失敗: \(error.localizedDescription)")
            print("  🔍 エラー詳細: \(error)")
        }
    }

    // MARK: - カメラ制御

    func startSession() {
        print("▶️ カメラセッション開始をリクエスト")
        // ✅ バックグラウンドスレッドで実行
        cameraQueue.async { [weak self] in
            guard let self = self else { return }
            if !self.captureSession.isRunning {
                self.captureSession.startRunning()
                print("✅ カメラセッションを開始しました")
            } else {
                print("⚠️ カメラセッションは既に実行中です")
            }
        }
    }

    func stopSession() {
        print("⏸️ カメラセッション停止をリクエスト")
        // ✅ バックグラウンドスレッドで実行
        cameraQueue.async { [weak self] in
            guard let self = self else { return }
            if self.captureSession.isRunning {
                self.captureSession.stopRunning()
                print("✅ カメラセッションを停止しました")
            } else {
                print("⚠️ カメラセッションは既に停止しています")
            }
        }
    }

    // MARK: - リアルタイムフレーム処理

    /// ビデオフレームを処理（リアルタイムフィルター適用）
    nonisolated private func processVideoFrame(_ pixelBuffer: CVPixelBuffer) {
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            guard self.isRealtimeEnabled, self.selectedFilter == .beauty else { return }

            // フレームスロットリング（0.1秒間隔）
            let now = Date()
            guard now.timeIntervalSince(self.lastFrameProcessedTime) >= self.frameProcessingInterval else {
                return
            }
            self.lastFrameProcessedTime = now

            // 現在の強度を取得
            let intensity = self.beautyIntensity
            let filterService = self.aiFilterService

            // フィルター適用（バックグラウンドで実行）
            Task.detached { [weak self] in
                guard let filteredImage = filterService.applyRealtimeBeautyFilter(
                    to: pixelBuffer,
                    intensity: intensity
                ) else {
                    return
                }

                // UIImageに変換
                guard let uiImage = filterService.convertToUIImage(from: filteredImage) else {
                    return
                }

                // メインスレッドでUIを更新
                await MainActor.run { [weak self] in
                    self?.previewImage = uiImage
                }
            }
        }
    }
}

// MARK: - 撮影デリゲート

class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private let completion: (UIImage?) -> Void

    init(completion: @escaping (UIImage?) -> Void) {
        self.completion = completion
        super.init()
        print("🎬 PhotoCaptureDelegateが初期化されました")
    }
    
    deinit {
        print("🧹 PhotoCaptureDelegateが解放されました")
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        print("\n【PhotoCaptureDelegate】didFinishProcessingPhoto が呼ばれました")
        
        if let error = error {
            print("❌ 撮影エラー: \(error.localizedDescription)")
            completion(nil)
            return
        }

        print("📷 写真データを取得中...")
        guard let imageData = photo.fileDataRepresentation() else {
            print("❌ 写真データの取得に失敗しました")
            completion(nil)
            return
        }
        
        print("✅ 写真データ取得成功（\(imageData.count)バイト）")

        guard let image = UIImage(data: imageData) else {
            print("❌ UIImageへの変換に失敗しました")
            completion(nil)
            return
        }

        print("✅ UIImage変換成功")
        print("📐 画像サイズ: \(image.size)")
        
        completion(image)
    }
    
    // この関数も念のため追加
    func photoOutput(
        _ output: AVCapturePhotoOutput,
        willCapturePhotoFor resolvedSettings: AVCaptureResolvedPhotoSettings
    ) {
        print("📸 willCapturePhotoFor が呼ばれました（撮影開始）")
    }
    
    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didCapturePhotoFor resolvedSettings: AVCaptureResolvedPhotoSettings
    ) {
        print("📸 didCapturePhotoFor が呼ばれました（撮影完了）")
    }
}

// MARK: - ビデオデータ出力デリゲート

class VideoDataOutputDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let frameHandler: (CVPixelBuffer) -> Void

    init(frameHandler: @escaping (CVPixelBuffer) -> Void) {
        self.frameHandler = frameHandler
        super.init()
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        frameHandler(pixelBuffer)
    }
}
