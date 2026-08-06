//
//  CollageService.swift
//  EventSnap
//
//  シェアOKの写真だけを集めたコラージュ画像の生成
//

import Foundation
import UIKit

/// SNSに投稿できるコラージュ画像を組み立てる。
///
/// **重要な設計上の制約**: 使ってよいのは撮影者が明示的に `isShareOK` を
/// ONにした写真だけ。EventSnapは「見せる前提で撮っていない素の写真」を
/// 扱うアプリなので、許可の無い写真が1枚でも混ざってはいけない。
enum CollageService {

    /// Instagram等で最も収まりの良い正方形
    static let canvasSize = CGSize(width: 1080, height: 1080)

    /// 1枚のコラージュに載せる最大枚数（これ以上は小さくなりすぎて意味が無い）
    static let maxPhotos = 9

    private static let gutter: CGFloat = 10
    private static let margin: CGFloat = 36
    private static let footerHeight: CGFloat = 104

    /// コラージュを生成する。
    ///
    /// - Returns: シェアOKの写真が0枚なら **nil**。
    ///            仕様どおりフォールバック画像は作らず、シェア機能自体を出さない。
    static func makeCollage(from images: [UIImage], eventName: String, date: Date) -> UIImage? {
        let images = Array(images.prefix(maxPhotos))
        guard !images.isEmpty else { return nil }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true

        return UIGraphicsImageRenderer(size: canvasSize, format: format).image { ctx in
            let cg = ctx.cgContext

            // 背景（真っ白より少しだけ温かみのある紙色）
            UIColor(white: 0.98, alpha: 1).setFill()
            cg.fill(CGRect(origin: .zero, size: canvasSize))

            let photoArea = CGRect(
                x: margin,
                y: margin,
                width: canvasSize.width - margin * 2,
                height: canvasSize.height - margin * 2 - footerHeight
            )

            for (rect, image) in zip(layout(for: images.count, in: photoArea), images) {
                draw(image, in: rect, context: cg)
            }

            drawFooter(eventName: eventName, date: date, context: cg)
        }
    }

    // MARK: - レイアウト

    /// 枚数に応じた配置。端数が出ないよう、枚数ごとに手で組んでいる。
    private static func layout(for count: Int, in area: CGRect) -> [CGRect] {
        switch count {
        case 1:
            return [area]

        case 2:
            return columns(2, in: area)

        case 3:
            // 左に大きく1枚、右に2枚
            let (left, right) = area.split(ratio: 0.6, gutter: gutter, axis: .horizontal)
            return [left] + rows(2, in: right)

        case 4:
            return grid(rows: 2, cols: 2, in: area)

        case 5:
            // 上に2枚、下に3枚
            let (top, bottom) = area.split(ratio: 0.5, gutter: gutter, axis: .vertical)
            return columns(2, in: top) + columns(3, in: bottom)

        case 6:
            return grid(rows: 2, cols: 3, in: area)

        case 7:
            // 上に大きく1枚、下に3枚 x 2段
            let (top, bottom) = area.split(ratio: 0.4, gutter: gutter, axis: .vertical)
            return [top] + grid(rows: 2, cols: 3, in: bottom)

        case 8:
            let (top, bottom) = area.split(ratio: 0.5, gutter: gutter, axis: .vertical)
            return columns(2, in: top) + grid(rows: 2, cols: 3, in: bottom)

        default:
            return grid(rows: 3, cols: 3, in: area)
        }
    }

    private static func grid(rows: Int, cols: Int, in area: CGRect) -> [CGRect] {
        let w = (area.width - gutter * CGFloat(cols - 1)) / CGFloat(cols)
        let h = (area.height - gutter * CGFloat(rows - 1)) / CGFloat(rows)

        return (0..<rows).flatMap { r in
            (0..<cols).map { c in
                CGRect(
                    x: area.minX + (w + gutter) * CGFloat(c),
                    y: area.minY + (h + gutter) * CGFloat(r),
                    width: w,
                    height: h
                )
            }
        }
    }

    private static func columns(_ n: Int, in area: CGRect) -> [CGRect] {
        grid(rows: 1, cols: n, in: area)
    }

    private static func rows(_ n: Int, in area: CGRect) -> [CGRect] {
        grid(rows: n, cols: 1, in: area)
    }

    // MARK: - 描画

    /// アスペクト比を保ったまま矩形いっぱいに敷き詰める（中央基準でトリミング）
    private static func draw(_ image: UIImage, in rect: CGRect, context cg: CGContext) {
        cg.saveGState()

        let path = UIBezierPath(roundedRect: rect, cornerRadius: 12)
        path.addClip()

        // 隙間が出ないよう、短辺を合わせて拡大する
        let scale = max(rect.width / image.size.width, rect.height / image.size.height)
        let drawSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let origin = CGPoint(
            x: rect.midX - drawSize.width / 2,
            y: rect.midY - drawSize.height / 2
        )

        image.draw(in: CGRect(origin: origin, size: drawSize))
        cg.restoreGState()
    }

    /// 下部のイベント名・日付と、隅の小さなアプリ名
    private static func drawFooter(eventName: String, date: Date, context cg: CGContext) {
        let baseY = canvasSize.height - footerHeight - margin + 22

        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 40, weight: .bold),
            .foregroundColor: UIColor(white: 0.12, alpha: 1),
        ]

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "yyyy.MM.dd"

        let dateAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 24, weight: .regular),
            .foregroundColor: UIColor(white: 0.45, alpha: 1),
        ]

        let title = eventName as NSString
        let maxTitleWidth = canvasSize.width - margin * 2 - 190
        var titleSize = title.size(withAttributes: titleAttrs)

        // 長いイベント名は省略する
        var displayTitle = title
        if titleSize.width > maxTitleWidth {
            var truncated = eventName
            while !truncated.isEmpty,
                  (truncated + "…" as NSString).size(withAttributes: titleAttrs).width > maxTitleWidth {
                truncated.removeLast()
            }
            displayTitle = (truncated + "…") as NSString
            titleSize = displayTitle.size(withAttributes: titleAttrs)
        }

        displayTitle.draw(at: CGPoint(x: margin, y: baseY), withAttributes: titleAttrs)
        (formatter.string(from: date) as NSString)
            .draw(at: CGPoint(x: margin, y: baseY + titleSize.height + 4), withAttributes: dateAttrs)

        drawWatermark(context: cg)
    }

    /// 隅の小さなアプリ名。派手にせず、SNSに出しても浮かない程度に留める。
    private static func drawWatermark(context cg: CGContext) {
        let text = "EventSnap" as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 26, weight: .semibold),
            .foregroundColor: UIColor(white: 0.35, alpha: 1),
            .kern: 0.5,
        ]

        let size = text.size(withAttributes: attrs)
        let markSize: CGFloat = 30
        let spacing: CGFloat = 10

        let totalWidth = markSize + spacing + size.width
        let x = canvasSize.width - margin - totalWidth
        let y = canvasSize.height - margin - footerHeight / 2 - size.height / 2 + 22

        // アプリアイコンを模した角丸の小さなマーク
        let markRect = CGRect(x: x, y: y + (size.height - markSize) / 2, width: markSize, height: markSize)
        let markPath = UIBezierPath(roundedRect: markRect, cornerRadius: 8)

        cg.saveGState()
        markPath.addClip()
        if let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                UIColor(red: 0.42, green: 0.55, blue: 0.96, alpha: 1).cgColor,
                UIColor(red: 0.92, green: 0.44, blue: 0.72, alpha: 1).cgColor,
            ] as CFArray,
            locations: [0, 1]
        ) {
            cg.drawLinearGradient(
                gradient,
                start: CGPoint(x: markRect.minX, y: markRect.minY),
                end: CGPoint(x: markRect.maxX, y: markRect.maxY),
                options: []
            )
        }
        cg.restoreGState()

        text.draw(at: CGPoint(x: x + markSize + spacing, y: y), withAttributes: attrs)
    }
}

// MARK: - 矩形の分割

private extension CGRect {
    enum Axis { case horizontal, vertical }

    /// 指定の比率で2つに割る（間に gutter 分の隙間を空ける）
    func split(ratio: CGFloat, gutter: CGFloat, axis: Axis) -> (CGRect, CGRect) {
        switch axis {
        case .horizontal:
            let firstWidth = (width - gutter) * ratio
            return (
                CGRect(x: minX, y: minY, width: firstWidth, height: height),
                CGRect(x: minX + firstWidth + gutter, y: minY,
                       width: width - firstWidth - gutter, height: height)
            )
        case .vertical:
            let firstHeight = (height - gutter) * ratio
            return (
                CGRect(x: minX, y: minY, width: width, height: firstHeight),
                CGRect(x: minX, y: minY + firstHeight + gutter,
                       width: width, height: height - firstHeight - gutter)
            )
        }
    }
}
