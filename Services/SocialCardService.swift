//
//  SocialCardService.swift
//  EventSnap
//
//  SNSシェア画像の生成: Photo → PhotoAnalyzer → テンプレート選択 → 描画
//

import CoreGraphics
import Foundation
import UIKit

/// 「EventSnapで撮った写真をSNSに載せたくなる」ことを目的にした、写真主役のシェア画像を作る。
///
/// **設計方針**: 写真をキャンバスいっぱいに敷き詰め（枠・丸角・大きな余白は作らない）、
/// `PhotoAnalyzer` が算出した安全ゾーン（被写体と重ならない領域）にタイポグラフィだけを
/// 重ねる。固定テンプレートではなく、写真の中身（被写体の有無・明暗）に応じて
/// 3つのテンプレート（Editorial / Festival / Minimal）を自動選択する。
///
/// ブランド表示は「EVENTSNAP」という小さなワードマークのみ。バッジや広告文言は使わない。
enum SocialCardService {

    static let canvasSize = CGSize(width: 1080, height: 1920)

    /// SNSシェア画像を1枚生成する。
    ///
    /// - Parameters:
    ///   - image: 主役にする写真（1枚）
    ///   - eventName: イベント名
    ///   - date: 添える日付
    ///   - momentIndex: この瞬間の主が参加者の中で何番目か（1始まり）。テンプレートによっては
    ///     使わない（Minimalは表示しない）
    ///   - momentTotal: 参加者の総数
    static func makeCard(
        from image: UIImage,
        eventName: String,
        date: Date,
        momentIndex: Int,
        momentTotal: Int
    ) -> UIImage {
        let analysis = PhotoAnalyzer.analyze(image)
        let template = selectTemplate(for: analysis)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true

        return UIGraphicsImageRenderer(size: canvasSize, format: format).image { ctx in
            drawPhotoFullBleed(image, canvasSize: canvasSize)
            let cg = ctx.cgContext

            switch template {
            case .editorial:
                drawEditorial(cg: cg, analysis: analysis, eventName: eventName, date: date, momentIndex: momentIndex)
            case .festival:
                drawFestival(cg: cg, analysis: analysis, eventName: eventName, date: date, momentIndex: momentIndex, momentTotal: momentTotal)
            case .minimal:
                drawMinimal(analysis: analysis, eventName: eventName)
            }
        }
    }

    // MARK: - テンプレート自動選択

    private enum Template { case editorial, festival, minimal }

    /// v1のヒューリスティック。将来的にはアスペクト比・彩度・顔の数なども加味して精緻化する想定。
    ///
    /// - 顔や明確な被写体がある写真は、それを邪魔しない上品な配置(Editorial)が合う
    /// - 被写体が曖昧でも全体が暗い(夜景・ステージ照明など)写真は、コントラストが効く
    ///   大胆な見出し(Festival)が映える
    /// - それ以外(明るく穏やかで被写体が曖昧)は、写真そのものを信じて引き算する(Minimal)
    private static func selectTemplate(for analysis: PhotoAnalysis) -> Template {
        if analysis.hasStrongSubject {
            return .editorial
        } else if analysis.isOverallDark {
            return .festival
        } else {
            return .minimal
        }
    }

    // MARK: - 写真(フルブリード)

    private static func drawPhotoFullBleed(_ image: UIImage, canvasSize: CGSize) {
        let scale = max(canvasSize.width / image.size.width, canvasSize.height / image.size.height)
        let drawSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let origin = CGPoint(x: (canvasSize.width - drawSize.width) / 2, y: (canvasSize.height - drawSize.height) / 2)
        image.draw(in: CGRect(origin: origin, size: drawSize))
    }

    // MARK: - A. Editorial(雑誌の写真ページのような静けさ)

    private static func drawEditorial(cg: CGContext, analysis: PhotoAnalysis, eventName: String, date: Date, momentIndex: Int) {
        let ink: UIColor = analysis.zoneIsDark ? .white : UIColor(white: 0.1, alpha: 1)
        let sub = ink.withAlphaComponent(0.75)
        let inset: CGFloat = 72
        let zone = analysis.safeZone

        var kicker = dateString(date).uppercased()
        kicker += "   MEMORIES \(String(format: "%02d", max(momentIndex, 1)))"
        let kickerFont = bebasNeue(size: 32)
        let kickerHeight = kickerFont.ascender - kickerFont.descender

        let maxWidth: CGFloat = {
            switch zone {
            case .top, .bottom: return canvasSize.width - inset * 2
            case .left, .right: return canvasSize.width * 0.42 - inset
            }
        }()

        let (lines, titleFont) = fitTitle(eventName, weight: .black, maxWidth: maxWidth, maxLines: zone == .left || zone == .right ? 4 : 2, maxSize: 66, minSize: 38)
        let lineHeight = titleFont.ascender - titleFont.descender
        let titleBlockHeight = CGFloat(lines.count) * lineHeight * 1.08

        let x: CGFloat = zone == .right ? canvasSize.width - inset - maxWidth : inset

        switch zone {
        case .top:
            var y = inset
            drawTracked(kicker, at: CGPoint(x: x, y: y), font: kickerFont, color: sub, tracking: 3)
            y += kickerHeight + 20
            drawLines(lines, font: titleFont, color: ink, x: x, y: &y, lineHeight: lineHeight * 1.08)

        case .bottom:
            var y = canvasSize.height - inset - titleBlockHeight - kickerHeight - 20
            drawLines(lines, font: titleFont, color: ink, x: x, y: &y, lineHeight: lineHeight * 1.08)
            y += 4
            drawTracked(kicker, at: CGPoint(x: x, y: y), font: kickerFont, color: sub, tracking: 3)

        case .left, .right:
            var y = (canvasSize.height - titleBlockHeight - kickerHeight - 20) / 2
            drawLines(lines, font: titleFont, color: ink, x: x, y: &y, lineHeight: lineHeight * 1.08)
            y += 4
            drawTracked(kicker, at: CGPoint(x: x, y: y), font: kickerFont, color: sub, tracking: 3)
        }

        // 見出しゾーンとぶつからない側の隅に、控えめなブランド表記を1つだけ
        let brandCorner: Corner = (zone == .bottom) ? .topTrailing : .bottomTrailing
        drawBrandMark(corner: brandCorner, ink: ink)
    }

    // MARK: - B. Festival(スクロールを止める大胆な見出し)

    private static func drawFestival(cg: CGContext, analysis: PhotoAnalysis, eventName: String, date: Date, momentIndex: Int, momentTotal: Int) {
        let ink: UIColor = analysis.zoneIsDark ? .white : UIColor(white: 0.08, alpha: 1)
        let inset: CGFloat = 64
        let zone = analysis.safeZone

        // 写真の色味を少し混ぜたグラデーションスクリムだけを敷き、視認性を確保する
        // (箱ではないので写真は隠れない)
        drawScrim(cg: cg, zone: zone, tint: analysis.dominantColor, dark: analysis.zoneIsDark)

        let maxWidth: CGFloat = {
            switch zone {
            case .top, .bottom: return canvasSize.width - inset * 2
            case .left, .right: return canvasSize.width * 0.62 - inset
            }
        }()

        let (lines, titleFont) = fitTitle(eventName, weight: .black, maxWidth: maxWidth, maxLines: 3, maxSize: 132, minSize: 60)
        let lineHeight = titleFont.ascender - titleFont.descender
        let blockHeight = CGFloat(lines.count) * lineHeight * 0.98

        let x: CGFloat = zone == .right ? canvasSize.width - inset - maxWidth : inset
        var y: CGFloat = {
            switch zone {
            case .top: return inset + 16
            case .bottom: return canvasSize.height - inset - blockHeight
            case .left, .right: return (canvasSize.height - blockHeight) / 2
            }
        }()
        drawLines(lines, font: titleFont, color: ink, x: x, y: &y, lineHeight: lineHeight * 0.98)

        // 端に沿わせた縦書き風の小さな番号(フェスポスターの定番モチーフ)
        let figure = "\(String(format: "%02d", max(momentIndex, 1))) / \(String(format: "%02d", max(momentTotal, momentIndex, 1)))"
        drawRotatedFigure(cg: cg, text: figure, onRight: zone != .right, ink: ink)

        // ポスターのクレジット行のような、控えめなブランド表記
        let creditAtTop = (zone == .bottom)
        drawFestivalCredit(date: date, ink: ink, atTop: creditAtTop)
    }

    // MARK: - C. Minimal(写真を信じて引き算する)

    private static func drawMinimal(analysis: PhotoAnalysis, eventName: String) {
        let ink: UIColor = analysis.zoneIsDark ? .white : UIColor(white: 0.1, alpha: 1)
        let inset: CGFloat = 76
        let zone = analysis.safeZone

        let maxWidth: CGFloat = {
            switch zone {
            case .top, .bottom: return canvasSize.width - inset * 2
            case .left, .right: return canvasSize.width * 0.44 - inset
            }
        }()

        let (lines, font) = fitTitle(eventName, weight: .bold, maxWidth: maxWidth, maxLines: 2, maxSize: 46, minSize: 30)
        let lineHeight = font.ascender - font.descender
        let blockHeight = CGFloat(lines.count) * lineHeight * 1.12

        let x: CGFloat = zone == .right ? canvasSize.width - inset - maxWidth : inset
        var y: CGFloat = {
            switch zone {
            case .top: return inset
            case .bottom: return canvasSize.height - inset - blockHeight
            case .left, .right: return (canvasSize.height - blockHeight) / 2
            }
        }()
        for line in lines {
            (line as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: [.font: font, .foregroundColor: ink, .kern: 0.5])
            y += lineHeight * 1.12
        }

        let brandCorner: Corner = (zone == .bottom) ? .topTrailing : .bottomTrailing
        drawBrandMark(corner: brandCorner, ink: ink, opacity: 0.55)
    }

    // MARK: - 共通: ブランド表記

    private enum Corner { case topLeading, topTrailing, bottomLeading, bottomTrailing }

    /// 「EVENTSNAP」の小さなワードマークだけ。バッジ・背景チップ・広告的な文言は使わない。
    private static func drawBrandMark(corner: Corner, ink: UIColor, opacity: CGFloat = 0.85, inset: CGFloat = 44) {
        let text = "EVENTSNAP"
        let font = bebasNeue(size: 26)
        let width = trackedWidth(text, font: font, tracking: 3)
        let height = font.ascender - font.descender

        let x: CGFloat
        let y: CGFloat
        switch corner {
        case .topLeading: x = inset; y = inset
        case .topTrailing: x = canvasSize.width - inset - width; y = inset
        case .bottomLeading: x = inset; y = canvasSize.height - inset - height
        case .bottomTrailing: x = canvasSize.width - inset - width; y = canvasSize.height - inset - height
        }

        drawTracked(text, at: CGPoint(x: x, y: y), font: font, color: ink.withAlphaComponent(opacity), tracking: 3)
    }

    /// Festival用の、ポスター下部のクレジット行のような表記("EVENTSNAP · 日付")
    private static func drawFestivalCredit(date: Date, ink: UIColor, atTop: Bool) {
        let text = "EVENTSNAP  ·  \(dateString(date))"
        let font = bebasNeue(size: 24)
        let y: CGFloat = atTop ? 56 : canvasSize.height - 64
        drawTracked(text, at: CGPoint(x: 64, y: y), font: font, color: ink.withAlphaComponent(0.8), tracking: 2)
    }

    /// フェスポスターの端に沿わせる、縦書き風に90度回転させた小さな番号
    private static func drawRotatedFigure(cg: CGContext, text: String, onRight: Bool, ink: UIColor) {
        let font = bebasNeue(size: 30)
        cg.saveGState()
        if onRight {
            cg.translateBy(x: canvasSize.width - 34, y: canvasSize.height - 64)
        } else {
            cg.translateBy(x: 34, y: 64)
        }
        cg.rotate(by: -.pi / 2)
        drawTracked(text, at: .zero, font: font, color: ink.withAlphaComponent(0.85), tracking: 6)
        cg.restoreGState()
    }

    /// 写真の色味を少し混ぜたグラデーションスクリム。ゾーン内だけに敷き、写真を隠さない。
    private static func drawScrim(cg: CGContext, zone: PhotoAnalysis.SafeZone, tint: UIColor, dark: Bool) {
        let rect = zone.rect(in: canvasSize)
        let base: UIColor = dark ? .black : .white
        let scrimColor = blend(base, tint, 0.25)

        guard let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [scrimColor.withAlphaComponent(0.55).cgColor, scrimColor.withAlphaComponent(0).cgColor] as CFArray,
            locations: [0, 1]
        ) else { return }

        let start: CGPoint
        let end: CGPoint
        switch zone {
        case .top: start = CGPoint(x: rect.midX, y: rect.minY); end = CGPoint(x: rect.midX, y: rect.maxY)
        case .bottom: start = CGPoint(x: rect.midX, y: rect.maxY); end = CGPoint(x: rect.midX, y: rect.minY)
        case .left: start = CGPoint(x: rect.minX, y: rect.midY); end = CGPoint(x: rect.maxX, y: rect.midY)
        case .right: start = CGPoint(x: rect.maxX, y: rect.midY); end = CGPoint(x: rect.minX, y: rect.midY)
        }

        cg.saveGState()
        cg.clip(to: rect)
        cg.drawLinearGradient(gradient, start: start, end: end, options: [])
        cg.restoreGState()
    }

    // MARK: - テキスト整形

    /// 幅に収まるよう、フォントサイズを段階的に縮めながら最大行数以内に収める。
    /// 日本語は分かち書きされないため、単語単位ではなく文字単位で折り返す。
    private static func fitTitle(
        _ text: String,
        weight: FontWeight,
        maxWidth: CGFloat,
        maxLines: Int,
        maxSize: CGFloat,
        minSize: CGFloat
    ) -> (lines: [String], font: UIFont) {
        var size = maxSize
        while size > minSize {
            let font = notoSansJP(weight: weight, size: size)
            let lines = wrapText(text, font: font, maxWidth: maxWidth)
            if lines.count <= maxLines { return (lines, font) }
            size -= 4
        }

        let font = notoSansJP(weight: weight, size: minSize)
        var lines = wrapText(text, font: font, maxWidth: maxWidth)
        if lines.count > maxLines {
            lines = Array(lines.prefix(maxLines))
            if var last = lines.last {
                let attrs: [NSAttributedString.Key: Any] = [.font: font]
                while (last + "…" as NSString).size(withAttributes: attrs).width > maxWidth, !last.isEmpty {
                    last.removeLast()
                }
                lines[lines.count - 1] = last + "…"
            }
        }
        return (lines, font)
    }

    private static func wrapText(_ text: String, font: UIFont, maxWidth: CGFloat) -> [String] {
        guard !text.isEmpty else { return [] }
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        var lines: [String] = []
        var current = ""
        for ch in text {
            let candidate = current + String(ch)
            let width = (candidate as NSString).size(withAttributes: attrs).width
            if width > maxWidth, !current.isEmpty {
                lines.append(current)
                current = String(ch)
            } else {
                current = candidate
            }
        }
        if !current.isEmpty { lines.append(current) }
        return lines
    }

    private static func drawLines(_ lines: [String], font: UIFont, color: UIColor, x: CGFloat, y: inout CGFloat, lineHeight: CGFloat) {
        for line in lines {
            (line as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: [.font: font, .foregroundColor: color])
            y += lineHeight
        }
    }

    private static func trackedWidth(_ text: String, font: UIFont, tracking: CGFloat) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let total = text.reduce(CGFloat(0)) { sum, ch in sum + String(ch).size(withAttributes: attrs).width + tracking }
        return total - tracking
    }

    private static func drawTracked(_ text: String, at point: CGPoint, font: UIFont, color: UIColor, tracking: CGFloat) {
        var x = point.x
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        for ch in text {
            let s = String(ch)
            (s as NSString).draw(at: CGPoint(x: x, y: point.y), withAttributes: attrs)
            x += s.size(withAttributes: attrs).width + tracking
        }
    }

    private static func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "yyyy.MM.dd"
        return formatter.string(from: date)
    }

    // MARK: - 色

    private static func blend(_ c1: UIColor, _ c2: UIColor, _ t: CGFloat) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        c1.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        c2.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return UIColor(
            red: r1 + (r2 - r1) * t,
            green: g1 + (g2 - g1) * t,
            blue: b1 + (b2 - b1) * t,
            alpha: 1
        )
    }

    // MARK: - フォント

    private enum FontWeight { case bold, black }

    private static func notoSansJP(weight: FontWeight, size: CGFloat) -> UIFont {
        let name = weight == .black ? "NotoSansJP-Black" : "NotoSansJP-Bold"
        if let font = UIFont(name: name, size: size) { return font }
        print("⚠️ \(name) の読み込みに失敗したため、システムフォントで代用します")
        return .systemFont(ofSize: size, weight: weight == .black ? .heavy : .bold)
    }

    /// 英字の短いコピー(ブランド表記・数字)専用の欧文ディスプレイ書体
    private static func bebasNeue(size: CGFloat) -> UIFont {
        if let font = UIFont(name: "BebasNeue-Regular", size: size) { return font }
        print("⚠️ BebasNeue-Regular の読み込みに失敗したため、システムフォントで代用します")
        return .systemFont(ofSize: size * 0.85, weight: .semibold)
    }
}
