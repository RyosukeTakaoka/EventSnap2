//
//  AIFilterService.swift
//  EventSnap
//
//  AI顔加工・フィルターサービス
//

import Foundation
import Vision
import CoreImage
import UIKit
import AVFoundation

class AIFilterService {

    // 共有CIContext（パフォーマンス最適化）
    private let context = CIContext(options: [.useSoftwareRenderer: false])

    // 顔検出キャッシュ（1秒間保持）- スレッドセーフ
    private let cacheQueue = DispatchQueue(label: "com.eventsnap.aifilter.cache")
    private var _cachedFaceRects: [CGRect] = []
    private var _lastFaceDetectionTime: Date = .distantPast

    private var cachedFaceRects: [CGRect] {
        get { cacheQueue.sync { _cachedFaceRects } }
        set { cacheQueue.sync(flags: .barrier) { self._cachedFaceRects = newValue } }
    }

    private var lastFaceDetectionTime: Date {
        get { cacheQueue.sync { _lastFaceDetectionTime } }
        set { cacheQueue.sync(flags: .barrier) { self._lastFaceDetectionTime = newValue } }
    }

    // MARK: - 美肌フィルター

    /// 美肌フィルターを適用
    func applyBeautyFilter(to image: UIImage) async -> UIImage {
        guard let ciImage = CIImage(image: image) else { return image }

        // 顔検出
        let faces = await detectFaces(in: ciImage)

        guard !faces.isEmpty else {
            // 顔が検出されない場合は全体に軽い処理
            return applySoftFilter(to: image)
        }

        // 顔領域に美肌効果適用
        return applyBeautyToFaces(image: image, ciImage: ciImage, faces: faces)
    }

    /// Vision で顔検出
    private func detectFaces(in image: CIImage) async -> [VNFaceObservation] {
        return await withCheckedContinuation { continuation in
            let request = VNDetectFaceRectanglesRequest { request, error in
                if let error = error {
                    print("❌ 顔検出エラー: \(error)")
                    continuation.resume(returning: [])
                    return
                }

                guard let results = request.results as? [VNFaceObservation] else {
                    continuation.resume(returning: [])
                    return
                }

                print("✅ 顔検出成功: \(results.count)人")
                continuation.resume(returning: results)
            }

            let handler = VNImageRequestHandler(ciImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                print("❌ 顔検出リクエスト失敗: \(error)")
                continuation.resume(returning: [])
            }
        }
    }

    /// 顔領域に美肌処理を適用
    private func applyBeautyToFaces(image: UIImage, ciImage: CIImage, faces: [VNFaceObservation]) -> UIImage {
        var outputImage = ciImage

        for face in faces {
            // 正規化された座標から実際の座標に変換
            let faceRect = VNImageRectForNormalizedRect(
                face.boundingBox,
                Int(ciImage.extent.width),
                Int(ciImage.extent.height)
            )

            // 顔領域を拡張（より自然な効果）
            let expandedRect = faceRect.insetBy(dx: -faceRect.width * 0.1, dy: -faceRect.height * 0.1)

            // 🔧 ここを修正！
            // 顔領域にブラー適用（美肌効果）
            let croppedImage = outputImage.cropped(to: expandedRect)
            let faceImage = croppedImage.applyingGaussianBlur(sigma: 3.0)
            
            // 元画像とブレンド（透明度で調整）
            let blendFilter = CIFilter(name: "CISourceOverCompositing")
            blendFilter?.setValue(faceImage, forKey: kCIInputImageKey)
            blendFilter?.setValue(outputImage, forKey: kCIInputBackgroundImageKey)

            if let blendedImage = blendFilter?.outputImage {
                outputImage = blendedImage
            }
        }

        // 全体的に明るさとコントラストを調整
        let colorFilter = CIFilter(name: "CIColorControls")
        colorFilter?.setValue(outputImage, forKey: kCIInputImageKey)
        colorFilter?.setValue(1.05, forKey: kCIInputSaturationKey) // 彩度
        colorFilter?.setValue(0.05, forKey: kCIInputBrightnessKey) // 明るさ

        if let finalImage = colorFilter?.outputImage,
           let cgImage = context.createCGImage(finalImage, from: finalImage.extent) {
            return UIImage(cgImage: cgImage)
        }

        return image
    }

    /// 全体ソフトフィルター
    private func applySoftFilter(to image: UIImage) -> UIImage {
        guard let ciImage = CIImage(image: image) else { return image }

        let filter = CIFilter(name: "CIColorControls")
        filter?.setValue(ciImage, forKey: kCIInputImageKey)
        filter?.setValue(1.1, forKey: kCIInputSaturationKey)
        filter?.setValue(0.1, forKey: kCIInputBrightnessKey)

        if let outputImage = filter?.outputImage,
           let cgImage = context.createCGImage(outputImage, from: outputImage.extent) {
            return UIImage(cgImage: cgImage)
        }

        return image
    }

    // MARK: - 基本フィルター

    /// 明るさ調整フィルター
    func applyBrightnessFilter(to image: UIImage, intensity: Double = 0.3) -> UIImage {
        guard let ciImage = CIImage(image: image) else { return image }

        let filter = CIFilter(name: "CIColorControls")
        filter?.setValue(ciImage, forKey: kCIInputImageKey)
        filter?.setValue(intensity, forKey: kCIInputBrightnessKey)

        if let outputImage = filter?.outputImage,
           let cgImage = context.createCGImage(outputImage, from: outputImage.extent) {
            return UIImage(cgImage: cgImage)
        }

        return image
    }

    /// ビンテージフィルター
    func applyVintageFilter(to image: UIImage) -> UIImage {
        guard let ciImage = CIImage(image: image) else { return image }

        let filter = CIFilter(name: "CIPhotoEffectTransfer")
        filter?.setValue(ciImage, forKey: kCIInputImageKey)

        if let outputImage = filter?.outputImage,
           let cgImage = context.createCGImage(outputImage, from: outputImage.extent) {
            return UIImage(cgImage: cgImage)
        }

        return image
    }

    // MARK: - 笑顔検出（オプション機能）

    /// 複数画像からベストスマイルを選出
    func detectBestSmile(in images: [UIImage]) async -> UIImage? {
        var bestImage: UIImage?
        var maxSmileScore: Float = 0

        for image in images {
            guard let ciImage = CIImage(image: image) else { continue }

            let smileScore = await detectSmileScore(in: ciImage)
            if smileScore > maxSmileScore {
                maxSmileScore = smileScore
                bestImage = image
            }
        }

        print("✅ ベストスマイル検出完了（スコア: \(maxSmileScore)）")
        return bestImage
    }

    /// 笑顔スコアを検出
    private func detectSmileScore(in image: CIImage) async -> Float {
        return await withCheckedContinuation { continuation in
            let request = VNDetectFaceLandmarksRequest { request, error in
                if let error = error {
                    print("❌ 笑顔検出エラー: \(error)")
                    continuation.resume(returning: 0)
                    return
                }

                guard let results = request.results as? [VNFaceObservation],
                      let face = results.first,
                      let landmarks = face.landmarks,
                      let mouth = landmarks.outerLips else {
                    continuation.resume(returning: 0)
                    return
                }

                // 口の開き具合から笑顔スコアを計算
                let score = self.calculateSmileScore(from: mouth.normalizedPoints)
                continuation.resume(returning: score)
            }

            let handler = VNImageRequestHandler(ciImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: 0)
            }
        }
    }

    /// 笑顔スコア計算
    private func calculateSmileScore(from points: [CGPoint]) -> Float {
        guard points.count > 4 else { return 0 }

        // 口の縦幅と横幅の比率から笑顔を判定
        let width = abs(points[0].x - points[points.count/2].x)
        let height = abs(points[points.count/4].y - points[3*points.count/4].y)

        return Float(height / max(width, 0.001)) // ゼロ除算回避
    }

    // MARK: - リアルタイムフィルター（高速処理）

    /// PixelBufferに直接美肌フィルターを適用（リアルタイム用）
    func applyRealtimeBeautyFilter(
        to pixelBuffer: CVPixelBuffer,
        intensity: Double = 0.5
    ) -> CIImage? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)

        // 顔検出キャッシュを使用（1秒ごとに更新）
        let shouldDetectFaces = Date().timeIntervalSince(lastFaceDetectionTime) > 1.0

        if shouldDetectFaces {
            // 非同期で顔検出を実行（結果は次回以降に使用）
            Task { [weak self] in
                guard let self = self else { return }
                let faces = await self.detectFaces(in: ciImage)
                let faceRects = faces.map { face in
                    VNImageRectForNormalizedRect(
                        face.boundingBox,
                        Int(ciImage.extent.width),
                        Int(ciImage.extent.height)
                    )
                }
                self.cachedFaceRects = faceRects
                self.lastFaceDetectionTime = Date()
            }
        }

        // キャッシュされた顔領域を使用
        guard !cachedFaceRects.isEmpty else {
            // 顔が検出されていない場合は全体に軽いフィルター
            return applyLightFilter(to: ciImage, intensity: intensity)
        }

        // 顔領域に美肌効果を適用
        return applyFastBeautyToFaces(
            ciImage: ciImage,
            faceRects: cachedFaceRects,
            intensity: intensity
        )
    }

    /// 高速美肌処理（顔領域のみ）
    private func applyFastBeautyToFaces(
        ciImage: CIImage,
        faceRects: [CGRect],
        intensity: Double
    ) -> CIImage {
        var outputImage = ciImage

        for faceRect in faceRects {
            // 顔領域を拡張
            let expandedRect = faceRect.insetBy(
                dx: -faceRect.width * 0.15,
                dy: -faceRect.height * 0.15
            )

            // 高速ブラー処理
            let blurRadius = intensity * 4.0 // 0.5 -> 2.0
            let blurred = outputImage
                .cropped(to: expandedRect)
                .clampedToExtent()
                .applyingGaussianBlur(sigma: blurRadius)
                .cropped(to: expandedRect)

            // 元画像とブレンド
            let blendFilter = CIFilter(name: "CISourceOverCompositing")
            blendFilter?.setValue(blurred, forKey: kCIInputImageKey)
            blendFilter?.setValue(outputImage, forKey: kCIInputBackgroundImageKey)

            if let blended = blendFilter?.outputImage {
                outputImage = blended
            }
        }

        // 軽い色調整
        let brightness = intensity * 0.05
        let saturation = 1.0 + (intensity * 0.1)

        let colorFilter = CIFilter(name: "CIColorControls")
        colorFilter?.setValue(outputImage, forKey: kCIInputImageKey)
        colorFilter?.setValue(saturation, forKey: kCIInputSaturationKey)
        colorFilter?.setValue(brightness, forKey: kCIInputBrightnessKey)

        return colorFilter?.outputImage ?? outputImage
    }

    /// 軽量フィルター（全体適用）
    private func applyLightFilter(to ciImage: CIImage, intensity: Double) -> CIImage {
        let brightness = intensity * 0.1
        let saturation = 1.0 + (intensity * 0.15)

        let filter = CIFilter(name: "CIColorControls")
        filter?.setValue(ciImage, forKey: kCIInputImageKey)
        filter?.setValue(saturation, forKey: kCIInputSaturationKey)
        filter?.setValue(brightness, forKey: kCIInputBrightnessKey)

        return filter?.outputImage ?? ciImage
    }

    /// PixelBufferからUIImageへ高速変換
    func convertToUIImage(from ciImage: CIImage) -> UIImage? {
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}
