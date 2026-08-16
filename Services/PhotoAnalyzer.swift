//
//  PhotoAnalyzer.swift
//  EventSnap
//
//  SNSシェア画像のレイアウトを、写真の中身に合わせて決めるための解析
//

import CoreImage
import UIKit
import Vision

/// 写真1枚を解析した結果。3つのテンプレート（Editorial/Bold/Minimal）すべてが
/// この結果を共有して使う。テンプレートを切り替えるたびにVision解析をやり直さない
/// ための、パイプラインの中心となる型。
struct PhotoAnalysisResult {
    /// 顔の領域（UIKit座標系、[0,1]正規化、左上原点）
    let faceRegions: [CGRect]
    /// 人物全体（体）の領域
    let personRegions: [CGRect]
    /// Visionのサリエンシー（注目度）が高いと判定した領域
    let salientRegions: [CGRect]
    /// 写真から抽出した2〜3色の主要色
    let dominantColors: [UIColor]
    /// 主要色の中から選んだ、最もその写真らしい1色（彩度が高いものを優先）
    let accentColor: UIColor
    /// 写真全体の明るさ（0=暗い、1=明るい）
    let overallBrightness: CGFloat
    /// フルブリード表示のクロップ基準点（正規化・画像内座標）。
    /// 顔・人物・注目領域の重心。何も検出できなければ画像の中心。
    let importanceCenter: CGPoint
    /// 文字を置く候補ゾームを、良い順（被写体と重ならず読みやすい順）に並べたもの
    let textZones: [TextZoneCandidate]

    /// 最もスコアの高い、文字を置くのに最適なゾーム
    var bestZone: TextZoneCandidate {
        textZones.first ?? TextZoneCandidate(zone: .bottom, score: 0, isDark: overallBrightness < 0.5)
    }
}

struct TextZoneCandidate {
    let zone: SafeZone
    /// 高いほど「文字を置くのに適している」(被写体と重ならず、背景が単純)
    let score: CGFloat
    /// このゾームの背景が暗いか（暗いなら白文字、明るいなら黒文字が読みやすい）
    let isDark: Bool
}

enum SafeZone: Equatable, CaseIterable {
    case top, bottom, left, right

    /// キャンバス正規化座標([0,1]、左上原点)での領域
    var normalizedRect: CGRect {
        switch self {
        case .top: return CGRect(x: 0, y: 0, width: 1, height: 0.32)
        case .bottom: return CGRect(x: 0, y: 0.66, width: 1, height: 0.34)
        case .left: return CGRect(x: 0, y: 0, width: 0.4, height: 1)
        case .right: return CGRect(x: 0.6, y: 0, width: 0.4, height: 1)
        }
    }

    /// キャンバス上での実際のピクセル領域
    func rect(in canvasSize: CGSize) -> CGRect {
        let n = normalizedRect
        return CGRect(x: n.minX * canvasSize.width, y: n.minY * canvasSize.height, width: n.width * canvasSize.width, height: n.height * canvasSize.height)
    }
}

/// Visionフレームワーク（iOS標準、追加ライブラリ不要）で写真を解析する。
///
/// **やっていること**:
/// 1. 顔検出・人物（体）検出・サリエンシー（注目度）検出を1回のVisionパスで実行
/// 2. 検出結果を、実際にフルブリードで表示される際のクロップ後の座標に変換
/// 3. 上下左右4つの候補ゾームそれぞれについて「顔との重なり」「人物との重なり」
///    「サリエンシーの密度（連続値）」「背景の複雑さ」を総合したスコアを計算
/// 4. スコアの高い順にソートして返す（採用は呼び出し側が決める。今回はユーザーが
///    テンプレートを選ぶため、どのテンプレートも同じ`bestZone`を基本に使う）
///
/// **精度についての注意**: 完全な自由配置ではなく、あらかじめ用意した4つの帯（上/下/
/// 左/右）を評価するだけの実務的なヒューリスティック。100%どんな構図でも正しく
/// 避けられるわけではないが、固定ルールよりは確実に写真に適応する。
enum PhotoAnalyzer {

    /// テンプレート描画時の出力キャンバスサイズ。クロップ計算に必要なため解析側でも参照する。
    static let canvasSize = CGSize(width: 1080, height: 1920)

    static func analyze(_ image: UIImage) -> PhotoAnalysisResult {
        let vision = runVision(on: image)
        let dominantColors = sampleDominantColors(of: image)
        let accentColor = pickAccentColor(from: dominantColors)
        let overallBrightness = luminance(of: averageColor(of: CIImage(image: image)))

        let importanceCenter = computeImportanceCenter(
            faces: vision.faces, persons: vision.persons, salient: vision.salient
        )

        // フルブリード表示時に実際に採用されるクロップ窓（スケール後のピクセル空間）
        let crop = coverCrop(imageSize: image.size, canvasSize: canvasSize, importanceCenter: importanceCenter)

        // 検出領域を「クロップ後にキャンバス上でどこに来るか」に変換してからスコアリングする。
        // これをしないと、9:16に収まらない写真で安全ゾームの判定がずれる。
        let facesOnCanvas = vision.faces.map { toCanvasRect($0, imageSize: image.size, crop: crop) }
        let personsOnCanvas = vision.persons.map { toCanvasRect($0, imageSize: image.size, crop: crop) }
        let salientOnCanvas = vision.salient.map { toCanvasRect($0, imageSize: image.size, crop: crop) }

        let textZones = SafeZone.allCases.map { zone -> TextZoneCandidate in
            let zoneRect = zone.normalizedRect
            let faceOverlap = overlapRatio(facesOnCanvas, zoneRect)
            let personOverlap = overlapRatio(personsOnCanvas, zoneRect)
            let saliencyDensity = averageSaliency(vision.saliencyImage, imageRect: zoneImageRect(zoneRect, imageSize: image.size, crop: crop))
            let brightnessVar = brightnessVariance(of: image, inImageRect: zoneImageRect(zoneRect, imageSize: image.size, crop: crop))
            let isDark = averageBrightness(of: image, inImageRect: zoneImageRect(zoneRect, imageSize: image.size, crop: crop)) < 0.5

            // 重みは「顔を最優先で避ける」>「人物」>「注目領域」>「背景の複雑さ」の順。
            // 100点満点から減点していく方式にして、値の意味を読みやすくしている。
            let score = 100
                - faceOverlap * 60
                - personOverlap * 32
                - saliencyDensity * 40
                - brightnessVar * 18

            return TextZoneCandidate(zone: zone, score: score, isDark: isDark)
        }.sorted { $0.score > $1.score }

        return PhotoAnalysisResult(
            faceRegions: vision.faces,
            personRegions: vision.persons,
            salientRegions: vision.salient,
            dominantColors: dominantColors,
            accentColor: accentColor,
            overallBrightness: overallBrightness,
            importanceCenter: importanceCenter,
            textZones: textZones
        )
    }

    // MARK: - フルブリードのクロップ（被写体を維持する）

    /// キャンバスに敷き詰めるためのcover-fitスケールと、写真の重要領域が
    /// なるべく切れないように寄せたクロップ窓（スケール後のピクセル空間）
    static func coverCrop(imageSize: CGSize, canvasSize: CGSize, importanceCenter: CGPoint) -> CGRect {
        let scale = max(canvasSize.width / imageSize.width, canvasSize.height / imageSize.height)
        let scaledSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)

        let desiredCenter = CGPoint(x: importanceCenter.x * scaledSize.width, y: importanceCenter.y * scaledSize.height)
        var originX = desiredCenter.x - canvasSize.width / 2
        var originY = desiredCenter.y - canvasSize.height / 2
        originX = min(max(originX, 0), max(scaledSize.width - canvasSize.width, 0))
        originY = min(max(originY, 0), max(scaledSize.height - canvasSize.height, 0))

        return CGRect(x: originX, y: originY, width: canvasSize.width, height: canvasSize.height)
    }

    /// 顔・人物・注目領域の重心。検出できなければ画像の中心（＝従来の中央クロップと同じ）
    private static func computeImportanceCenter(faces: [CGRect], persons: [CGRect], salient: [CGRect]) -> CGPoint {
        var points: [(CGPoint, CGFloat)] = []
        points += faces.map { (CGPoint(x: $0.midX, y: $0.midY), 3) }
        points += persons.map { (CGPoint(x: $0.midX, y: $0.midY), 2) }
        if faces.isEmpty, persons.isEmpty, let top = salient.first {
            points.append((CGPoint(x: top.midX, y: top.midY), 1))
        }

        guard !points.isEmpty else { return CGPoint(x: 0.5, y: 0.5) }
        let totalWeight = points.reduce(CGFloat(0)) { $0 + $1.1 }
        let x = points.reduce(CGFloat(0)) { $0 + $1.0.x * $1.1 } / totalWeight
        let y = points.reduce(CGFloat(0)) { $0 + $1.0.y * $1.1 } / totalWeight
        return CGPoint(x: x, y: y)
    }

    /// 画像正規化座標の矩形を、クロップ後のキャンバス正規化座標に変換する
    private static func toCanvasRect(_ normalizedImageRect: CGRect, imageSize: CGSize, crop: CGRect) -> CGRect {
        // cropは常にcanvasSizeと同じ大きさなので、cropからは倍率を求められない。
        // coverCropが使うのと同じ計算式で改めて倍率を出す。
        let scale = max(canvasSize.width / imageSize.width, canvasSize.height / imageSize.height)
        let px = CGRect(
            x: normalizedImageRect.minX * imageSize.width * scale,
            y: normalizedImageRect.minY * imageSize.height * scale,
            width: normalizedImageRect.width * imageSize.width * scale,
            height: normalizedImageRect.height * imageSize.height * scale
        )
        let shifted = px.offsetBy(dx: -crop.minX, dy: -crop.minY)
        return CGRect(
            x: shifted.minX / canvasSize.width,
            y: shifted.minY / canvasSize.height,
            width: shifted.width / canvasSize.width,
            height: shifted.height / canvasSize.height
        )
    }

    /// キャンバス正規化座標の矩形を、元画像の正規化座標に逆変換する（明度・サリエンシーのサンプリング用）
    private static func zoneImageRect(_ canvasNormalizedRect: CGRect, imageSize: CGSize, crop: CGRect) -> CGRect {
        let scale = max(canvasSize.width / imageSize.width, canvasSize.height / imageSize.height)
        let px = CGRect(
            x: canvasNormalizedRect.minX * canvasSize.width + crop.minX,
            y: canvasNormalizedRect.minY * canvasSize.height + crop.minY,
            width: canvasNormalizedRect.width * canvasSize.width,
            height: canvasNormalizedRect.height * canvasSize.height
        )
        let normalized = CGRect(
            x: px.minX / scale / imageSize.width,
            y: px.minY / scale / imageSize.height,
            width: px.width / scale / imageSize.width,
            height: px.height / scale / imageSize.height
        )
        return normalized.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    private static func overlapRatio(_ rects: [CGRect], _ zone: CGRect) -> CGFloat {
        guard !rects.isEmpty else { return 0 }
        let zoneArea = zone.width * zone.height
        guard zoneArea > 0 else { return 0 }
        let covered = rects.reduce(CGFloat(0)) { partial, rect in
            let intersection = rect.intersection(zone)
            guard !intersection.isNull else { return partial }
            return partial + intersection.width * intersection.height
        }
        return min(covered / zoneArea, 1)
    }

    // MARK: - Vision: 顔・人物・サリエンシーの検出

    private struct VisionResult {
        let faces: [CGRect]
        let persons: [CGRect]
        let salient: [CGRect]
        let saliencyImage: CIImage?
    }

    private static func runVision(on image: UIImage) -> VisionResult {
        guard let cgImage = image.cgImage else {
            return VisionResult(faces: [], persons: [], salient: [], saliencyImage: nil)
        }

        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])

        let faceRequest = VNDetectFaceRectanglesRequest()
        let personRequest = VNDetectHumanRectanglesRequest()
        let saliencyRequest = VNGenerateAttentionBasedSaliencyImageRequest()

        do {
            try handler.perform([faceRequest, personRequest, saliencyRequest])
        } catch {
            print("⚠️ Vision解析に失敗したため、レイアウトは既定値にフォールバックします: \(error)")
            return VisionResult(faces: [], persons: [], salient: [], saliencyImage: nil)
        }

        // Visionは左下原点の正規化座標を返すため、上下反転してUIKit系(左上原点)に揃える
        func flip(_ rect: CGRect) -> CGRect {
            CGRect(x: rect.minX, y: 1 - rect.maxY, width: rect.width, height: rect.height)
        }

        let faces = (faceRequest.results ?? []).map { flip($0.boundingBox) }
        let persons = (personRequest.results ?? []).map { flip($0.boundingBox) }
        let salient = (saliencyRequest.results?.first?.salientObjects ?? []).map { flip($0.boundingBox) }

        var saliencyImage: CIImage?
        if let pixelBuffer = saliencyRequest.results?.first?.pixelBuffer {
            saliencyImage = CIImage(cvPixelBuffer: pixelBuffer)
        }

        return VisionResult(faces: faces, persons: persons, salient: salient, saliencyImage: saliencyImage)
    }

    /// サリエンシーのヒートマップを、指定した画像内領域(UIKit正規化・左上原点)で平均する。
    /// ヒートマップが無ければ0（＝注目領域なしとして扱う）を返す。
    private static func averageSaliency(_ saliencyImage: CIImage?, imageRect: CGRect) -> CGFloat {
        guard let saliencyImage, !imageRect.isEmpty else { return 0 }
        let extent = saliencyImage.extent
        let cropRect = CGRect(
            x: extent.minX + imageRect.minX * extent.width,
            y: extent.minY + (1 - imageRect.maxY) * extent.height,
            width: imageRect.width * extent.width,
            height: imageRect.height * extent.height
        ).intersection(extent)
        guard !cropRect.isEmpty else { return 0 }
        return luminance(of: averageColor(of: saliencyImage.cropped(to: cropRect)))
    }

    // MARK: - 明度・コントラスト

    private static func averageBrightness(of image: UIImage, inImageRect rect: CGRect) -> CGFloat {
        guard let ciImage = CIImage(image: image) else { return 1 }
        return luminance(of: averageColor(of: cropped(ciImage, toNormalized: rect)))
    }

    /// ゾーム内を4分割し、明るさのばらつき(標準偏差の簡易近似)を見る。
    /// ばらつきが大きい=模様や境界が多い背景で、文字が読みにくくなりやすいため減点材料にする。
    private static func brightnessVariance(of image: UIImage, inImageRect rect: CGRect) -> CGFloat {
        guard let ciImage = CIImage(image: image), !rect.isEmpty else { return 0 }
        let halfW = rect.width / 2
        let halfH = rect.height / 2
        let subRects = [
            CGRect(x: rect.minX, y: rect.minY, width: halfW, height: halfH),
            CGRect(x: rect.minX + halfW, y: rect.minY, width: halfW, height: halfH),
            CGRect(x: rect.minX, y: rect.minY + halfH, width: halfW, height: halfH),
            CGRect(x: rect.minX + halfW, y: rect.minY + halfH, width: halfW, height: halfH),
        ]
        let brightnesses = subRects.map { luminance(of: averageColor(of: cropped(ciImage, toNormalized: $0))) }
        let mean = brightnesses.reduce(0, +) / CGFloat(brightnesses.count)
        let variance = brightnesses.reduce(CGFloat(0)) { $0 + pow($1 - mean, 2) } / CGFloat(brightnesses.count)
        return min(sqrt(variance) * 3, 1) // 3倍して0〜1のスコア域に収まりやすくする
    }

    private static func cropped(_ ciImage: CIImage, toNormalized rect: CGRect) -> CIImage {
        let extent = ciImage.extent
        let cropRect = CGRect(
            x: extent.minX + rect.minX * extent.width,
            y: extent.minY + (1 - rect.maxY) * extent.height,
            width: rect.width * extent.width,
            height: rect.height * extent.height
        ).intersection(extent)
        guard !cropRect.isEmpty else { return ciImage }
        return ciImage.cropped(to: cropRect)
    }

    // MARK: - 色

    /// 画像を上部・中央・下部の3帯に分けて平均色を取り、簡易的な主要色とする(MVP)
    private static func sampleDominantColors(of image: UIImage) -> [UIColor] {
        guard let ciImage = CIImage(image: image) else { return [UIColor(white: 0.6, alpha: 1)] }
        let bands = [
            CGRect(x: 0, y: 0, width: 1, height: 1.0 / 3),
            CGRect(x: 0, y: 1.0 / 3, width: 1, height: 1.0 / 3),
            CGRect(x: 0, y: 2.0 / 3, width: 1, height: 1.0 / 3),
        ]
        return bands.map { averageColor(of: cropped(ciImage, toNormalized: $0)) }
    }

    /// 主要色の中から最も彩度の高い色を選ぶ。全体的に彩度が低い(モノトーンな)写真では、
    /// 全体平均を少し引き締めた色にフォールバックする。
    private static func pickAccentColor(from colors: [UIColor]) -> UIColor {
        let withSaturation = colors.map { color -> (UIColor, CGFloat) in
            var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            color.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
            return (color, s)
        }
        if let best = withSaturation.max(by: { $0.1 < $1.1 }), best.1 > 0.12 {
            return best.0
        }
        return colors.first ?? UIColor(white: 0.5, alpha: 1)
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
