//
//  SocialCardService.swift
//  EventSnap
//
//  SNSシェア画像の生成: Photo → PhotoAnalyzer(1回だけ) → 選ばれたテンプレートで描画
//

import CoreGraphics
import Foundation
import UIKit

/// 「EventSnapで撮った写真をSNSに載せたくなる」ことを目的にした、写真主役のシェア画像を作る。
///
/// **設計方針**: 写真をキャンバスいっぱいに敷き詰め（枠・丸角・大きな余白は作らない）、
/// `PhotoAnalyzer` が算出した安全ゾーンにタイポグラフィだけを重ねる。
/// テンプレートは3種類（Editorial / Bold / Minimal）あり、**どれを使うかはユーザーが
/// その場で選ぶ**（自動選択はしない）。ただし画像解析（Vision）は1回だけ行い、
/// その結果を3テンプレートで使い回すことで、切り替えるたびに待たされないようにしている。
enum SocialCardService {

    static let canvasSize = PhotoAnalyzer.canvasSize

    /// ユーザーが何も選ばなかった場合に最初に表示するテンプレート。
    /// Editorialは被写体の有無や明暗を問わず破綻しにくいため既定にしている。
    static let defaultTemplate: SocialCardTemplate = .editorial

    /// 写真を解析する（重い処理はここだけ）。テンプレートを切り替えるたびに呼び直す必要はない。
    static func analyze(_ image: UIImage) -> PhotoAnalysisResult {
        PhotoAnalyzer.analyze(image)
    }

    /// 解析済みの結果を使って、指定したテンプレートで1枚描画する（軽い処理）。
    static func render(
        template: SocialCardTemplate,
        image: UIImage,
        analysis: PhotoAnalysisResult,
        eventName: String,
        date: Date,
        momentIndex: Int,
        momentTotal: Int
    ) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true

        return UIGraphicsImageRenderer(size: canvasSize, format: format).image { ctx in
            SocialCardDrawing.drawPhotoFullBleed(image, analysis: analysis, canvasSize: canvasSize)
            template.rendererType.draw(
                cg: ctx.cgContext,
                canvasSize: canvasSize,
                analysis: analysis,
                eventName: eventName,
                date: date,
                momentIndex: momentIndex,
                momentTotal: momentTotal
            )
        }
    }

    /// 解析から描画まで一括で行う便利関数(自動生成される既定画像用)。
    static func makeCard(
        from image: UIImage,
        eventName: String,
        date: Date,
        momentIndex: Int,
        momentTotal: Int,
        template: SocialCardTemplate = defaultTemplate
    ) -> UIImage {
        let analysis = analyze(image)
        return render(
            template: template,
            image: image,
            analysis: analysis,
            eventName: eventName,
            date: date,
            momentIndex: momentIndex,
            momentTotal: momentTotal
        )
    }
}

// MARK: - テンプレートの種類

/// ユーザーがワンタップで切り替える3種類。色違いではなく「写真の見せ方」自体が異なる。
enum SocialCardTemplate: String, CaseIterable, Identifiable {
    /// 雑誌・写真集のように写真を美しく見せる
    case editorial
    /// 大胆なタイポグラフィでスクロールを止める
    case bold
    /// 写真そのものを最大限に活かす
    case minimal

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .editorial: return "Editorial"
        case .bold: return "Bold"
        case .minimal: return "Minimal"
        }
    }

    fileprivate var rendererType: SocialCardRenderer.Type {
        switch self {
        case .editorial: return EditorialRenderer.self
        case .bold: return BoldRenderer.self
        case .minimal: return MinimalRenderer.self
        }
    }
}

/// 各テンプレートが実装するプロトコル。テンプレートごとに完全に独立したファイル/型にでき、
/// 将来自動選択(TemplateSelector)を足すときも「選ぶロジック」と「描くロジック」を分離できる。
protocol SocialCardRenderer {
    static func draw(
        cg: CGContext,
        canvasSize: CGSize,
        analysis: PhotoAnalysisResult,
        eventName: String,
        date: Date,
        momentIndex: Int,
        momentTotal: Int
    )
}

// MARK: - A. Editorial(雑誌の写真ページのような静けさ)

/// 写真を主役にした、控えめで洗練されたタイポグラフィ。
/// 「おしゃれな写真をそのまま投稿したい」と思えることを目標にする。
enum EditorialRenderer: SocialCardRenderer {
    static func draw(
        cg: CGContext,
        canvasSize: CGSize,
        analysis: PhotoAnalysisResult,
        eventName: String,
        date: Date,
        momentIndex: Int,
        momentTotal: Int
    ) {
        let zoneInfo = analysis.bestZone
        let zone = zoneInfo.zone
        let ink: UIColor = zoneInfo.isDark ? .white : UIColor(white: 0.1, alpha: 1)
        let sub = ink.withAlphaComponent(0.75)
        let inset: CGFloat = 72

        var kicker = SocialCardDrawing.dateString(date).uppercased()
        kicker += "   MEMORIES \(String(format: "%02d", max(momentIndex, 1)))"
        let kickerFont = SocialCardDrawing.bebasNeue(size: 32)
        let kickerHeight = kickerFont.ascender - kickerFont.descender

        let maxWidth: CGFloat = {
            switch zone {
            case .top, .bottom: return canvasSize.width - inset * 2
            case .left, .right: return canvasSize.width * 0.42 - inset
            }
        }()

        let (lines, titleFont) = SocialCardDrawing.fitTitle(
            eventName, weight: .black, maxWidth: maxWidth,
            maxLines: (zone == .left || zone == .right) ? 4 : 2, maxSize: 66, minSize: 38
        )
        let lineHeight = titleFont.ascender - titleFont.descender
        let titleBlockHeight = CGFloat(lines.count) * lineHeight * 1.08

        let x: CGFloat = zone == .right ? canvasSize.width - inset - maxWidth : inset

        switch zone {
        case .top:
            var y = inset
            SocialCardDrawing.drawTracked(kicker, at: CGPoint(x: x, y: y), font: kickerFont, color: sub, tracking: 3)
            y += kickerHeight + 20
            SocialCardDrawing.drawLines(lines, font: titleFont, color: ink, x: x, y: &y, lineHeight: lineHeight * 1.08)

        case .bottom:
            var y = canvasSize.height - inset - titleBlockHeight - kickerHeight - 20
            SocialCardDrawing.drawLines(lines, font: titleFont, color: ink, x: x, y: &y, lineHeight: lineHeight * 1.08)
            y += 4
            SocialCardDrawing.drawTracked(kicker, at: CGPoint(x: x, y: y), font: kickerFont, color: sub, tracking: 3)

        case .left, .right:
            var y = (canvasSize.height - titleBlockHeight - kickerHeight - 20) / 2
            SocialCardDrawing.drawLines(lines, font: titleFont, color: ink, x: x, y: &y, lineHeight: lineHeight * 1.08)
            y += 4
            SocialCardDrawing.drawTracked(kicker, at: CGPoint(x: x, y: y), font: kickerFont, color: sub, tracking: 3)
        }

        let brandCorner: SocialCardDrawing.Corner = (zone == .bottom) ? .topTrailing : .bottomTrailing
        SocialCardDrawing.drawBrandMark(canvasSize: canvasSize, corner: brandCorner, ink: ink)
    }
}

// MARK: - B. Bold(スクロールを止める大胆な見出し)

/// 3案の中で最もSNS上のインパクトを重視する。写真を壊さず、
/// 「写真＋タイポグラフィで1つの作品」になることを目指す。
enum BoldRenderer: SocialCardRenderer {
    static func draw(
        cg: CGContext,
        canvasSize: CGSize,
        analysis: PhotoAnalysisResult,
        eventName: String,
        date: Date,
        momentIndex: Int,
        momentTotal: Int
    ) {
        let zoneInfo = analysis.bestZone
        let zone = zoneInfo.zone
        let ink: UIColor = zoneInfo.isDark ? .white : UIColor(white: 0.08, alpha: 1)
        let inset: CGFloat = 64

        // 写真から抽出したアクセントカラーを少し混ぜたグラデーションスクリムだけを敷き、
        // 視認性を確保する(箱ではないので写真は隠れない)
        SocialCardDrawing.drawScrim(cg: cg, zone: zone, canvasSize: canvasSize, tint: analysis.accentColor, dark: zoneInfo.isDark)

        let maxWidth: CGFloat = {
            switch zone {
            case .top, .bottom: return canvasSize.width - inset * 2
            case .left, .right: return canvasSize.width * 0.62 - inset
            }
        }()

        let (lines, titleFont) = SocialCardDrawing.fitTitle(
            eventName, weight: .black, maxWidth: maxWidth, maxLines: 3, maxSize: 132, minSize: 60
        )
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
        SocialCardDrawing.drawLines(lines, font: titleFont, color: ink, x: x, y: &y, lineHeight: lineHeight * 0.98)

        // 端に沿わせた縦書き風の小さな番号(フェス/イベントポスターの定番モチーフ)
        let figure = "\(String(format: "%02d", max(momentIndex, 1))) / \(String(format: "%02d", max(momentTotal, momentIndex, 1)))"
        SocialCardDrawing.drawRotatedFigure(cg: cg, text: figure, canvasSize: canvasSize, onRight: zone != .right, ink: ink)

        let creditAtTop = (zone == .bottom)
        SocialCardDrawing.drawCredit(canvasSize: canvasSize, date: date, ink: ink, atTop: creditAtTop)
    }
}

// MARK: - C. Minimal(写真を信じて引き算する)

/// 装飾を最小限に。「この写真なら何も足さない方が良い」場合に強いデザイン。
enum MinimalRenderer: SocialCardRenderer {
    static func draw(
        cg: CGContext,
        canvasSize: CGSize,
        analysis: PhotoAnalysisResult,
        eventName: String,
        date: Date,
        momentIndex: Int,
        momentTotal: Int
    ) {
        let zoneInfo = analysis.bestZone
        let zone = zoneInfo.zone
        let ink: UIColor = zoneInfo.isDark ? .white : UIColor(white: 0.1, alpha: 1)
        let inset: CGFloat = 76

        let maxWidth: CGFloat = {
            switch zone {
            case .top, .bottom: return canvasSize.width - inset * 2
            case .left, .right: return canvasSize.width * 0.44 - inset
            }
        }()

        let (lines, font) = SocialCardDrawing.fitTitle(
            eventName, weight: .bold, maxWidth: maxWidth, maxLines: 2, maxSize: 46, minSize: 30
        )
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
        SocialCardDrawing.drawLines(lines, font: font, color: ink, x: x, y: &y, lineHeight: lineHeight * 1.12, kern: 0.5)

        let brandCorner: SocialCardDrawing.Corner = (zone == .bottom) ? .topTrailing : .bottomTrailing
        SocialCardDrawing.drawBrandMark(canvasSize: canvasSize, corner: brandCorner, ink: ink, opacity: 0.55)
    }
}

// MARK: - 共通の描画ヘルパー(全テンプレートが共有する)

enum SocialCardDrawing {

    // MARK: 写真(被写体を維持するフルブリードクロップ)

    static func drawPhotoFullBleed(_ image: UIImage, analysis: PhotoAnalysisResult, canvasSize: CGSize) {
        let scale = max(canvasSize.width / image.size.width, canvasSize.height / image.size.height)
        let crop = PhotoAnalyzer.coverCrop(imageSize: image.size, canvasSize: canvasSize, importanceCenter: analysis.importanceCenter)
        let drawSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        image.draw(in: CGRect(origin: CGPoint(x: -crop.minX, y: -crop.minY), size: drawSize))
    }

    // MARK: ブランド表記

    enum Corner { case topLeading, topTrailing, bottomLeading, bottomTrailing }

    /// 「EVENTSNAP」の小さなワードマークだけ。バッジ・背景チップ・広告的な文言は使わない。
    /// 「広告」ではなく「作品のクレジット」として見えることを狙っている。
    static func drawBrandMark(canvasSize: CGSize, corner: Corner, ink: UIColor, opacity: CGFloat = 0.85, inset: CGFloat = 44) {
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

    /// Bold用の、ポスター下部のクレジット行のような表記("EVENTSNAP · 日付")
    static func drawCredit(canvasSize: CGSize, date: Date, ink: UIColor, atTop: Bool) {
        let text = "EVENTSNAP  ·  \(dateString(date))"
        let font = bebasNeue(size: 24)
        let y: CGFloat = atTop ? 56 : canvasSize.height - 64
        drawTracked(text, at: CGPoint(x: 64, y: y), font: font, color: ink.withAlphaComponent(0.8), tracking: 2)
    }

    /// ポスターの端に沿わせる、縦書き風に90度回転させた小さな番号
    static func drawRotatedFigure(cg: CGContext, text: String, canvasSize: CGSize, onRight: Bool, ink: UIColor) {
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

    /// 写真から抽出したアクセントカラーを混ぜたグラデーションスクリム。ゾーン内だけに敷き、写真を隠さない。
    static func drawScrim(cg: CGContext, zone: SafeZone, canvasSize: CGSize, tint: UIColor, dark: Bool) {
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

    // MARK: テキスト整形

    /// 幅に収まるよう、フォントサイズを段階的に縮めながら最大行数以内に収める。
    /// 日本語は分かち書きされないため、単語単位ではなく文字単位で折り返す。
    static func fitTitle(
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

    static func wrapText(_ text: String, font: UIFont, maxWidth: CGFloat) -> [String] {
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

    static func drawLines(_ lines: [String], font: UIFont, color: UIColor, x: CGFloat, y: inout CGFloat, lineHeight: CGFloat, kern: CGFloat = 0) {
        for line in lines {
            (line as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: [.font: font, .foregroundColor: color, .kern: kern])
            y += lineHeight
        }
    }

    static func trackedWidth(_ text: String, font: UIFont, tracking: CGFloat) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let total = text.reduce(CGFloat(0)) { sum, ch in sum + String(ch).size(withAttributes: attrs).width + tracking }
        return total - tracking
    }

    static func drawTracked(_ text: String, at point: CGPoint, font: UIFont, color: UIColor, tracking: CGFloat) {
        var x = point.x
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        for ch in text {
            let s = String(ch)
            (s as NSString).draw(at: CGPoint(x: x, y: point.y), withAttributes: attrs)
            x += s.size(withAttributes: attrs).width + tracking
        }
    }

    static func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "yyyy.MM.dd"
        return formatter.string(from: date)
    }

    // MARK: 色

    static func blend(_ c1: UIColor, _ c2: UIColor, _ t: CGFloat) -> UIColor {
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

    // MARK: フォント

    enum FontWeight { case bold, black }

    static func notoSansJP(weight: FontWeight, size: CGFloat) -> UIFont {
        let name = weight == .black ? "NotoSansJP-Black" : "NotoSansJP-Bold"
        if let font = UIFont(name: name, size: size) { return font }
        print("⚠️ \(name) の読み込みに失敗したため、システムフォントで代用します")
        return .systemFont(ofSize: size, weight: weight == .black ? .heavy : .bold)
    }

    /// 英字の短いコピー(ブランド表記・数字)専用の欧文ディスプレイ書体
    static func bebasNeue(size: CGFloat) -> UIFont {
        if let font = UIFont(name: "BebasNeue-Regular", size: size) { return font }
        print("⚠️ BebasNeue-Regular の読み込みに失敗したため、システムフォントで代用します")
        return .systemFont(ofSize: size * 0.85, weight: .semibold)
    }
}
