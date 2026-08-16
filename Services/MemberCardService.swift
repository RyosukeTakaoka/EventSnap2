//
//  MemberCardService.swift
//  EventSnap
//
//  シェア画像「Member Card」形式の組み立て
//

import CoreImage
import Foundation
import UIKit

/// シェア画像を「参加者証明のカード」形式で組み立てるサービス。
///
/// **狙い**: 派手なスタンプやマスキングテープのような装飾は使わず、余白・写真・
/// 硬めのゴシック体だけで「限定されたメンバーである」ことをさりげなく伝える。
/// 「その場にいた9人だけ」のような直接的な排他表現の文言は入れず、
/// 「MEMBER 03/09」という数字と枠組みだけに語らせる。
///
/// **統一感のための設計**: 背景・罫線・番号バッジの縁取りは、すべて写真から
/// 抽出した色味（`Palette`）を薄める/濃くするだけで作る。個別に色を足していくと
/// 要素同士がバラバラに見えるため、1枚の写真から派生した1系統の色だけで
/// 画面全体を組み立てることで「上品な余白」に見えるようにしている。
enum MemberCardService {

    /// Instagramのストーリー / フィード双方で違和感なく使える縦長比率
    static let canvasSize = CGSize(width: 1080, height: 1920)

    private static let margin: CGFloat = 72
    /// 番号・タイトルなど、最大の存在感を持たせたい要素だけはトーンに関わらず
    /// ほぼ黒に固定する（写真によって視認性が揺れないようにするため）
    private static let inkColor = UIColor(white: 0.12, alpha: 1)

    /// Member Card画像を1枚生成する。
    ///
    /// - Parameters:
    ///   - image: メインで見せる写真（1枚だけ）
    ///   - eventName: カード上部に大きく出すイベント名
    ///   - date: イベント名の下に添える日付
    ///   - memberIndex: このカードで讃える人が、参加者の中で何番目か（1始まり）
    ///   - memberTotal: 参加者の総数
    static func makeCard(
        from image: UIImage,
        eventName: String,
        date: Date,
        memberIndex: Int,
        memberTotal: Int
    ) -> UIImage {
        let palette = Palette(dominant: dominantColor(of: image))

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true

        return UIGraphicsImageRenderer(size: canvasSize, format: format).image { ctx in
            let cg = ctx.cgContext

            palette.background.setFill()
            cg.fill(CGRect(origin: .zero, size: canvasSize))

            let headerBottom = drawHeader(eventName: eventName, date: date, palette: palette, context: cg)

            // フッター（MEMBERバッジ）を先に確定させ、写真は残りの領域いっぱいに敷く。
            // 写真とバッジの間はここで意図的に大きく空け、視線の流れに「間」を作る。
            let footerHeight: CGFloat = 236
            let footerTop = canvasSize.height - margin - footerHeight
            let gapBeforePhotoFooter: CGFloat = 108

            let photoArea = CGRect(
                x: margin,
                y: headerBottom + 52,
                width: canvasSize.width - margin * 2,
                height: (footerTop - gapBeforePhotoFooter) - (headerBottom + 52)
            )
            drawPhoto(image, in: photoArea, palette: palette, context: cg)

            drawMemberBadge(index: memberIndex, total: memberTotal, top: footerTop, palette: palette, context: cg)
            drawAppBadge(bottom: canvasSize.height - margin, palette: palette)
        }
    }

    // MARK: - ヘッダー（イベント名・日付）

    /// - Returns: ヘッダーが占めた領域の下端Y座標
    @discardableResult
    private static func drawHeader(eventName: String, date: Date, palette: Palette, context cg: CGContext) -> CGFloat {
        let titleFont = notoSansJP(weight: .black, size: 64)
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: inkColor,
        ]

        let maxWidth = canvasSize.width - margin * 2
        let displayTitle = truncated(eventName, attributes: titleAttrs, maxWidth: maxWidth)
        let titleY: CGFloat = 104

        (displayTitle as NSString).draw(at: CGPoint(x: margin, y: titleY), withAttributes: titleAttrs)

        // NSStringのsize(withAttributes:)は行送り込みの高さを返すため、そのまま次の行の
        // 起点にすると間延びして見える。字形そのものの高さ（ascender〜descender）だけで
        // 詰めることで、イベント名と日付が「1つの情報グループ」に見えるようにする。
        let titleGlyphHeight = titleFont.ascender - titleFont.descender

        let dateFont = notoSansJP(weight: .bold, size: 28)
        let dateAttrs: [NSAttributedString.Key: Any] = [
            .font: dateFont,
            .foregroundColor: palette.accentInk,
        ]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "yyyy.MM.dd"
        let dateString = formatter.string(from: date) as NSString

        let dateY = titleY + titleGlyphHeight + 6
        dateString.draw(at: CGPoint(x: margin, y: dateY), withAttributes: dateAttrs)
        let dateGlyphHeight = dateFont.ascender - dateFont.descender

        // ヘッダーの下にごく短いアクセント罫を1本引き、見出しブロックを1つの
        // まとまりとして「締める」。写真にも同じ色調の縁取りを使い、要素同士を繋ぐ。
        let ruleY = dateY + dateGlyphHeight + 26
        cg.saveGState()
        cg.setStrokeColor(palette.hairline.withAlphaComponent(0.55).cgColor)
        cg.setLineWidth(2.5)
        cg.move(to: CGPoint(x: margin, y: ruleY))
        cg.addLine(to: CGPoint(x: margin + 96, y: ruleY))
        cg.strokePath()
        cg.restoreGState()

        return ruleY
    }

    // MARK: - メイン写真

    private static func drawPhoto(_ image: UIImage, in rect: CGRect, palette: Palette, context cg: CGContext) {
        let cornerRadius: CGFloat = 26

        // 汎用的な黒い影ではなく、写真自身のトーンを落とした影にすることで
        // 「浮いて見える」違和感を無くし、カード全体のトーンに馴染ませる。
        cg.saveGState()
        cg.setShadow(offset: CGSize(width: 0, height: 8), blur: 22, color: palette.shadow.withAlphaComponent(0.28).cgColor)
        UIBezierPath(roundedRect: rect, cornerRadius: cornerRadius).fill()
        cg.restoreGState()

        cg.saveGState()
        let clipPath = UIBezierPath(roundedRect: rect, cornerRadius: cornerRadius)
        clipPath.addClip()

        let scale = max(rect.width / image.size.width, rect.height / image.size.height)
        let drawSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let origin = CGPoint(x: rect.midX - drawSize.width / 2, y: rect.midY - drawSize.height / 2)
        image.draw(in: CGRect(origin: origin, size: drawSize))

        cg.restoreGState()

        // MEMBERバッジと同じ色調の縁取りを重ね、額装のように写真を「カードの一部」に見せる
        cg.saveGState()
        let frame = UIBezierPath(roundedRect: rect, cornerRadius: cornerRadius)
        palette.hairline.withAlphaComponent(0.45).setStroke()
        frame.lineWidth = 1.5
        frame.stroke()
        cg.restoreGState()
    }

    // MARK: - MEMBERバッジ（チケットの半券のような質感）

    /// 「MEMBER 03/09」。証明書やチケットの半券を思わせる、ミシン目とパンチ穴付きのカード。
    private static func drawMemberBadge(index: Int, total: Int, top: CGFloat, palette: Palette, context cg: CGContext) {
        let labelFont = notoSansJP(weight: .bold, size: 22)
        let numberFont = notoSansJP(weight: .black, size: 60)
        let numberAttrs: [NSAttributedString.Key: Any] = [
            .font: numberFont,
            .foregroundColor: inkColor,
        ]

        let label = "MEMBER"
        let labelWidth = kernedWidth(label, font: labelFont, kern: 3)
        let labelHeight = labelFont.ascender - labelFont.descender

        let number = memberNumberText(index: index, total: total) as NSString
        let numberSize = number.size(withAttributes: numberAttrs)

        let paddingH: CGFloat = 32
        let paddingTop: CGFloat = 24
        let paddingBottom: CGFloat = 28
        let rowGap: CGFloat = 16

        let contentWidth = max(labelWidth, numberSize.width)
        let boxWidth = contentWidth + paddingH * 2
        let dividerY = top + paddingTop + labelHeight + rowGap
        let boxHeight = (dividerY - top) + rowGap + numberSize.height + paddingBottom

        let box = CGRect(x: margin, y: top, width: boxWidth, height: boxHeight)
        let boxPath = UIBezierPath(roundedRect: box, cornerRadius: 18)

        // カードを紙面から少し持ち上げる、写真トーンの柔らかい影
        cg.saveGState()
        cg.setShadow(offset: CGSize(width: 0, height: 6), blur: 16, color: palette.shadow.withAlphaComponent(0.22).cgColor)
        palette.cardSurface.setFill()
        boxPath.fill()
        cg.restoreGState()

        // ごく薄い斜線を重ねて、証明書用紙のような手触りを足す（主張しすぎない程度に）
        cg.saveGState()
        boxPath.addClip()
        cg.setStrokeColor(palette.hairline.withAlphaComponent(0.06).cgColor)
        cg.setLineWidth(1)
        var lineX = box.minX - box.height
        while lineX < box.maxX {
            cg.move(to: CGPoint(x: lineX, y: box.maxY))
            cg.addLine(to: CGPoint(x: lineX + box.height, y: box.minY))
            lineX += 14
        }
        cg.strokePath()
        cg.restoreGState()

        // 外枠
        cg.saveGState()
        palette.hairline.withAlphaComponent(0.55).setStroke()
        boxPath.lineWidth = 1.5
        boxPath.stroke()
        cg.restoreGState()

        // ミシン目（破線）
        cg.saveGState()
        cg.setStrokeColor(palette.hairline.withAlphaComponent(0.5).cgColor)
        cg.setLineWidth(1.5)
        cg.setLineDash(phase: 0, lengths: [5, 5])
        cg.move(to: CGPoint(x: box.minX + paddingH - 6, y: dividerY))
        cg.addLine(to: CGPoint(x: box.maxX - paddingH + 6, y: dividerY))
        cg.strokePath()
        cg.restoreGState()

        // チケットの半券のような、左右のパンチ穴（切り取り跡）
        cg.saveGState()
        palette.background.setFill()
        let notchRadius: CGFloat = 10
        UIBezierPath(arcCenter: CGPoint(x: box.minX, y: dividerY), radius: notchRadius, startAngle: 0, endAngle: .pi * 2, clockwise: true).fill()
        UIBezierPath(arcCenter: CGPoint(x: box.maxX, y: dividerY), radius: notchRadius, startAngle: 0, endAngle: .pi * 2, clockwise: true).fill()
        cg.restoreGState()

        drawKerned(label, at: CGPoint(x: box.minX + paddingH, y: top + paddingTop), font: labelFont, color: palette.accentInk, kern: 3)
        number.draw(at: CGPoint(x: box.minX + paddingH, y: dividerY + rowGap), withAttributes: numberAttrs)
    }

    /// 「EventSnapで撮影」。控えめだが視認性は保つ、右下の小さなバッジ。
    private static func drawAppBadge(bottom: CGFloat, palette: Palette) {
        let text = "EventSnapで撮影" as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: notoSansJP(weight: .bold, size: 24),
            .foregroundColor: palette.accentInk,
            .kern: 0.3,
        ]
        let size = text.size(withAttributes: attrs)
        let markSize: CGFloat = 26
        let spacing: CGFloat = 10

        let totalWidth = markSize + spacing + size.width
        let x = canvasSize.width - margin - totalWidth
        let y = bottom - size.height

        let markRect = CGRect(x: x, y: y + (size.height - markSize) / 2, width: markSize, height: markSize)
        let markPath = UIBezierPath(roundedRect: markRect, cornerRadius: 7)

        UIGraphicsGetCurrentContext().map { cg in
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
        }

        text.draw(at: CGPoint(x: x + markSize + spacing, y: y), withAttributes: attrs)
    }

    // MARK: - 色（写真から抽出する1系統の色だけで画面を組み立てる）

    private struct Palette {
        /// 背景。白に写真の色味をごく薄く香らせる程度
        let background: UIColor
        /// MEMBERバッジの地の色。背景よりわずかに濃く、紙の上に乗ったカードに見せる
        let cardSurface: UIColor
        /// 日付・MEMBERラベル・EventSnap表記に使う、読みやすさを保ったアクセント色
        let accentInk: UIColor
        /// 罫線・ミシン目・写真の縁取りに使う色のベース（描画時にalphaで薄める）
        let hairline: UIColor
        /// 写真・バッジの影の色のベース（描画時にalphaで薄める）
        let shadow: UIColor

        init(dominant: UIColor) {
            background = Palette.mix(dominant, .white, 0.92)
            cardSurface = Palette.mix(dominant, .white, 0.85)
            accentInk = Palette.mix(dominant, .black, 0.55)
            hairline = Palette.mix(dominant, .black, 0.2)
            shadow = Palette.mix(dominant, .black, 0.35)
        }

        private static func mix(_ c1: UIColor, _ c2: UIColor, _ t: CGFloat) -> UIColor {
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
    }

    /// 写真全体を平均した色（CIAreaAverageによる正確な平均。背景トーンの元になる）
    private static func dominantColor(of image: UIImage) -> UIColor {
        let fallback = UIColor(white: 0.6, alpha: 1)
        guard let ciImage = CIImage(image: image) else { return fallback }

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

    // MARK: - 表記

    /// 総数の桁数に合わせてゼロ埋めする（例: 9人中3番目 → "03/09"、120人中7番目 → "007/120"）
    static func memberNumberText(index: Int, total: Int) -> String {
        let digits = max(2, String(max(total, 1)).count)
        let paddedIndex = String(format: "%0\(digits)d", max(index, 0))
        let paddedTotal = String(format: "%0\(digits)d", max(total, 0))
        return "\(paddedIndex)/\(paddedTotal)"
    }

    // MARK: - フォント

    private enum FontWeight { case bold, black }

    /// バンドルしたNoto Sans JPを使う。万一読み込めなかった場合のみ、
    /// システムフォントの対応する太さにフォールバックする。
    private static func notoSansJP(weight: FontWeight, size: CGFloat) -> UIFont {
        let name = weight == .black ? "NotoSansJP-Black" : "NotoSansJP-Bold"
        if let font = UIFont(name: name, size: size) {
            return font
        }
        print("⚠️ \(name) の読み込みに失敗したため、システムフォントで代用します")
        return .systemFont(ofSize: size, weight: weight == .black ? .heavy : .bold)
    }

    /// 幅に収まらない場合は末尾を省略して "…" を付ける
    private static func truncated(_ text: String, attributes: [NSAttributedString.Key: Any], maxWidth: CGFloat) -> String {
        let full = text as NSString
        guard full.size(withAttributes: attributes).width > maxWidth else { return text }

        var trimmed = text
        while !trimmed.isEmpty,
              (trimmed + "…" as NSString).size(withAttributes: attributes).width > maxWidth {
            trimmed.removeLast()
        }
        return trimmed + "…"
    }

    /// MEMBERラベルのような、文字間を広げた（トラッキングを効かせた）表記の幅を測る
    private static func kernedWidth(_ text: String, font: UIFont, kern: CGFloat) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let total = text.reduce(CGFloat(0)) { sum, ch in
            sum + String(ch).size(withAttributes: attrs).width + kern
        }
        return total - kern
    }

    /// 文字間を広げながら1文字ずつ描画する
    private static func drawKerned(_ text: String, at point: CGPoint, font: UIFont, color: UIColor, kern: CGFloat) {
        var x = point.x
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        for ch in text {
            let s = String(ch)
            (s as NSString).draw(at: CGPoint(x: x, y: point.y), withAttributes: attrs)
            x += s.size(withAttributes: attrs).width + kern
        }
    }
}
