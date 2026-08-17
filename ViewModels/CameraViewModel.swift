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
    @Published var isCameraAuthorized = false

    /// この写真をEvent Reel（SNSシェア用の画像）に使ってよいか（機能B）。
    /// **既定はOFF**。一度ONにしたら、本人が明示的にOFFに戻すまで次の撮影にも
    /// 引き継がれる（イベント中はまとめてシェアOKにしたい、という使い方を想定）。
    ///
    /// 「あとで公開」との併用を許す。両方ONで撮った写真は一旦タイムカプセルとして
    /// 伏せられ、Event Reelを組む瞬間にシェアを優先してタイムカプセル状態を解除する
    /// （`PhotoRepository.releaseSharedTimeCapsules`）。撮影時点でどちらの意図か
    /// 決めきれないことがあるため、選択肢を狭めず両方選べるようにしている。
    @Published var shareOK = false

    /// この写真をタイムカプセル（遅延公開）にするか（機能A）。
    /// 撮影者本人による明示的な指定。OFFでも一定確率で自動選定される。
    /// シェアOKと併用可能（詳細は `shareOK` のコメントを参照）。
    @Published var saveAsTimeCapsule = false

    /// 直前の撮影がタイムカプセルになったか（撮影後のフィードバック表示用）
    @Published var lastCaptureWasTimeCapsule = false

    /// 現在使用中のカメラ（インカメラ/アウトカメラ）
    @Published var cameraPosition: AVCaptureDevice.Position = .front

    /// 端末の物理的な向き。横で撮った写真を横のまま保存するために使う。
    let orientation = CameraOrientation()

    let captureSession = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private var videoDeviceInput: AVCaptureDeviceInput?
    private let photoRepository = PhotoRepository.shared
    private let eventRepository = EventRepository.shared

    // カメラ専用のキュー
    private let cameraQueue = DispatchQueue(label: "com.eventsnap.camera")

    // 🔥 重要: デリゲートを強参照で保持
    private var photoCaptureDelegate: PhotoCaptureDelegate?

    // 端末の向きの購読
    private var orientationCancellable: AnyCancellable?

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

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: cameraPosition),
              let input = try? AVCaptureDeviceInput(device: camera) else {
            print("❌ カメラデバイスが見つかりません")
            return
        }

        if captureSession.canAddInput(input) {
            captureSession.addInput(input)
            videoDeviceInput = input
            print("✅ カメラ入力を追加しました")
        }

        // 写真出力を追加
        if captureSession.canAddOutput(photoOutput) {
            captureSession.addOutput(photoOutput)
            print("✅ 写真出力を追加しました")
        }

        // 端末の向きの監視を開始し、写真出力の回転角を追従させる
        orientation.start()
        observeOrientation()
        updatePhotoOutputOrientation()

        // ✅ バックグラウンドスレッドで実行
        cameraQueue.async { [weak self] in
            self?.captureSession.startRunning()
            print("✅ カメラセッション開始")
        }
    }

    // MARK: - カメラ切り替え（イン/アウト）

    /// インカメラ・アウトカメラを切り替える
    func switchCamera() {
        let newPosition: AVCaptureDevice.Position = cameraPosition == .front ? .back : .front

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: newPosition),
              let newInput = try? AVCaptureDeviceInput(device: camera) else {
            print("❌ 切り替え先のカメラが見つかりません: \(newPosition)")
            return
        }

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
                self.applyMirroringForCurrentPosition()
                print("🔄 カメラを切り替えました: \(newPosition == .front ? "イン" : "アウト")")
            }
        }
    }

    /// 現在のカメラ（イン/アウト）に応じて鏡像設定をやり直す
    private func applyMirroringForCurrentPosition() {
        let mirrored = cameraPosition == .front
        photoOutput.connection(with: .video)?.applyMirroring(mirrored)
    }

    // MARK: - 向きの追従

    private func observeOrientation() {
        orientationCancellable = orientation.$current
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updatePhotoOutputOrientation()
            }
    }

    /// 写真出力の接続だけを端末の物理的な向きに合わせる。
    ///
    /// プレビューは縦固定のままにしておく（画面ごと回るので見た目は正しい）。
    /// ここを追従させることで「横に構えて撮った写真が横のまま保存される」ようになる。
    private func updatePhotoOutputOrientation() {
        guard let connection = photoOutput.connection(with: .video) else { return }

        connection.apply(
            rotationAngle: orientation.captureRotationAngle,
            videoOrientation: orientation.captureVideoOrientation
        )
        // インカメラは見たままに合わせて鏡像で保存する。アウトカメラは鏡像にしない。
        connection.applyMirroring(cameraPosition == .front)

        print("🔄 撮影の向きを更新: \(orientation.current.rawValue) / \(orientation.captureRotationAngle)°")
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

                // 🔄 向きをピクセルに焼き込んでから処理する。
                // CIImage と Vision は imageOrientation を見てくれないので、
                // ここで .up に正規化しておかないと横向きの写真が崩れる。
                let processedImage = image.normalizedUp()
                print("📐 正規化後のサイズ: \(processedImage.size) (横向き: \(processedImage.isLandscape))")

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

    // MARK: - 写真アップロード

    private func uploadPhoto(_ image: UIImage) async {
        print("  📤 アップロード処理開始...")

        guard let event = eventRepository.currentEvent else {
            print("  ❌ アップロード失敗: イベントが見つかりません")
            return
        }

        // 終了したイベントには新しい写真を追加できない。
        // UI側（CameraView）でシャッターを無効化しているが、念のためここでも防ぐ。
        guard event.isActive else {
            print("  ❌ アップロード失敗: イベントは終了しています")
            return
        }

        let eventID = event.id
        print("  📋 イベントID: \(eventID.uuidString)")

        do {
            print("  🔄 PhotoRepositoryにアップロード中...")
            let uploaded = try await photoRepository.uploadPhoto(
                image,
                eventID: eventID,
                isShareOK: shareOK,
                forceTimeCapsule: saveAsTimeCapsule
            )

            lastCaptureWasTimeCapsule = uploaded.isTimeCapsule

            // シェアOKは一度ONにしたら、本人がOFFにするまで継続する仕様。
            // 撮影のたびに自動でリセットしない（「あとで公開」は毎回リセットする）。
            saveAsTimeCapsule = false

            if uploaded.isTimeCapsule {
                print("  ⏳ タイムカプセルとして保存しました（公開予定: \(uploaded.revealDate.map(String.init(describing:)) ?? "不明")）")
            } else {
                print("  ✅ 写真を自動共有しました")
            }

            // シェアOKの写真が増えたので、新しいEvent Reelの生成条件を満たしていないか確認する。
            // イベント終了を待たず、この1枚が増えた時点でイベント中に作る。
            if uploaded.isShareOK, let event = eventRepository.currentEvent {
                await ShareCollageBuilder.buildIfNeeded(for: event)
            }
        } catch {
            print("  ❌ アップロード失敗: \(error.localizedDescription)")
            print("  🔍 エラー詳細: \(error)")
        }
    }

    // MARK: - カメラ制御

    func startSession() {
        print("▶️ カメラセッション開始をリクエスト")
        orientation.start()
        updatePhotoOutputOrientation()
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
        orientation.stop()
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
