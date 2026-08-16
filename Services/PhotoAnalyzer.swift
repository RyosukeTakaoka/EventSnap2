//
//  PhotoAnalyzer.swift
//  EventSnap
//
//  SNSシェア画像のレイアウトを、写真の中身に合わせて決めるための解析
//

import CoreImage
import UIKit
import Vision

/// 写真1枚を解析した結果。
///
/// `SocialCardService` はこれを見て「どこに文字を置いてよいか」「白文字と黒文字の
/// どちらが読みやすいか」「どのテンプレートが似合うか」を判断する。
/// 写真を無視した固定テンプレートにしないための、レイアウトエンジンの入力。
struct PhotoAnalysis {
    /// 文字を置いても被写体と重ならない領域
    let safeZone: SafeZone
    /// `safeZone` 付近が暗いか（暗いなら白文字、明るいなら黒文字が合う）
    let zoneIsDark: Bool
    /// 写真全体が暗い（夜景・ステージ照明など）か
    let isOverallDark: Bool
    /// 顔、または明確に注目を引く被写体を検出できたか
    let hasStrongSubject: Bool
    /// 写真全体の色味を平均した色。アクセントカラーの元にする
    let dominantColor: UIColor

    enum SafeZone: Equatable {
        case top, bottom, left, right

        /// キャンバス上での実際の領域（正規化ではなくピクセル座標）
        func rect(in canvasSize: CGSize) -> CGRect {
            switch self {
            case .top:
                return CGRect(x: 0, y: 0, width: canvasSize.width, height: canvasSize.height * 0.32)
            case .bottom:
                return CGRect(x: 0, y: canvasSize.height * 0.66, width: canvasSize.width, height: canvasSize.height * 0.34)
            case .left:
                return CGRect(x: 0, y: 0, width: canvasSize.width * 0.4, height: canvasSize.height)
            case .right:
                return CGRect(x: canvasSize.width * 0.6, y: 0, width: canvasSize.width * 0.4, height: canvasSize.height)
            }
        }
    }
}

/// Visionフレームワーク（iOS標準、追加ライブラリ不要）で写真を解析する。
///
/// **やっていること**: 顔検出とサリエンシー検出（人物がいない構図でも「注目領域」を
/// 返してくれる）で「重要な被写体がどこにあるか」を掴み、上下左右4つの候補ゾームの
/// うち被写体との重なりが最も小さいものを「安全ゾーン」として選ぶ。
///
/// **精度についての注意**: 完全な自由配置ではなく、あらかじめ用意した4つの帯（上/下/
/// 左/右）から選ぶだけの実務的なヒューリスティック。100%どんな構図でも正しく避けられる
/// わけではないが、固定テンプレートよりは確実に写真に適応する。
enum PhotoAnalyzer {

    static func analyze(_ image: UIImage) -> PhotoAnalysis {
        let dominant = averageColor(of: CIImage(image: image))
        let importantRects = detectImportantRegions(in: image)
        let zone = bestSafeZone(avoiding: importantRects)

        let zoneRect = normalizedRect(for: zone)
        let zoneBrightness = averageBrightness(of: image, inNormalizedRect: zoneRect)
        let overallBrightness = luminance(of: dominant)

        return PhotoAnalysis(
            safeZone: zone,
            zoneIsDark: zoneBrightness < 0.5,
            isOverallDark: overallBrightness < 0.42,
            hasStrongSubject: !importantRects.isEmpty,
            dominantColor: dominant
        )
    }

    // MARK: - Vision: 顔・注目領域の検出

    /// - Returns: UIKit座標系（左上原点、[0,1]正規化）での重要領域の一覧
    private static func detectImportantRegions(in image: UIImage) -> [CGRect] {
        guard let cgImage = image.cgImage else { return [] }

        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])

        let faceRequest = VNDetectFaceRectanglesRequest()
        let saliencyRequest = VNGenerateAttentionBasedSaliencyImageRequest()

        do {
            try handler.perform([faceRequest, saliencyRequest])
        } catch {
            print("⚠️ Vision解析に失敗したため、安全ゾーンは既定値にフォールバックします: \(error)")
            return []
        }

        // Visionは左下原点の正規化座標を返すため、上下反転してUIKit系に揃える
        var rects: [CGRect] = (faceRequest.results ?? []).map(\.boundingBox)
        if let salientObjects = saliencyRequest.results?.first?.salientObjects {
            rects += salientObjects.map(\.boundingBox)
        }
        return rects.map { CGRect(x: $0.minX, y: 1 - $0.maxY, width: $0.width, height: $0.height) }
    }

    /// 重要領域との重なりが最も小さい帯を選ぶ。何も検出できなければ、
    /// 定番の構図として下部を返す。
    private static func bestSafeZone(avoiding rects: [CGRect]) -> PhotoAnalysis.SafeZone {
        guard !rects.isEmpty else { return .bottom }

        let candidates: [PhotoAnalysis.SafeZone] = [.bottom, .top, .left, .right]
        return candidates.min { overlapScore(rects, normalizedRect(for: $0)) < overlapScore(rects, normalizedRect(for: $1)) }
            ?? .bottom
    }

    private static func overlapScore(_ rects: [CGRect], _ zone: CGRect) -> CGFloat {
        rects.reduce(CGFloat(0)) { partial, rect in
            let intersection = rect.intersection(zone)
            guard !intersection.isNull else { return partial }
            return partial + intersection.width * intersection.height
        }
    }

    private static func normalizedRect(for zone: PhotoAnalysis.SafeZone) -> CGRect {
        switch zone {
        case .top: return CGRect(x: 0, y: 0, width: 1, height: 0.32)
        case .bottom: return CGRect(x: 0, y: 0.66, width: 1, height: 0.34)
        case .left: return CGRect(x: 0, y: 0, width: 0.4, height: 1)
        case .right: return CGRect(x: 0.6, y: 0, width: 0.4, height: 1)
        }
    }

    // MARK: - 明度・色

    /// 正規化領域（UIKit系・左上原点）の平均輝度
    private static func averageBrightness(of image: UIImage, inNormalizedRect rect: CGRect) -> CGFloat {
        guard let ciImage = CIImage(image: image) else { return 1 }
        let extent = ciImage.extent

        // UIKit系（左上原点）→ CoreImage系（左下原点）に変換してから切り出す
        let cropRect = CGRect(
            x: extent.minX + rect.minX * extent.width,
            y: extent.minY + (1 - rect.maxY) * extent.height,
            width: rect.width * extent.width,
            height: rect.height * extent.height
        ).intersection(extent)

        guard !cropRect.isEmpty else { return luminance(of: averageColor(of: ciImage)) }
        return luminance(of: averageColor(of: ciImage.cropped(to: cropRect)))
    }

    /// CIAreaAverageによる正確な平均色
    private static func averageColor(of ciImage: CIImage?) -> UIColor {
        let fallback = UIColor(white: 0.6, alpha: 1)
        guard let ciImage else { return fallback }

        guard let filter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: ciImage,
            kCIInputExtentKey: CIVector(cgRect: ciImage.extent),
        ]), let outputImage = filter.outputImage else {
            return fallback
        }

        var bitmap = [UInt8](repeating: 0, count: 4)
        let context = CIContext(options: [.workingColorSpace: NSNull()])
        context.render(
            outputImage,
            toBitmap: &bitmap,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )

        return UIColor(
            red: CGFloat(bitmap[0]) / 255,
            green: CGFloat(bitmap[1]) / 255,
            blue: CGFloat(bitmap[2]) / 255,
            alpha: 1
        )
    }

    private static func luminance(of color: UIColor) -> CGFloat {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return 0.299 * r + 0.587 * g + 0.114 * b
    }
}

private extension CGImagePropertyOrientation {
    /// UIImage.Orientation → Visionが期待するCGImagePropertyOrientationへの標準的な変換
    init(_ uiOrientation: UIImage.Orientation) {
        switch uiOrientation {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
