//
//  MemberCardService.swift
//  EventSnap
//
//  シェア画像の新デザイン案「Member Card」。
//

import Foundation
import UIKit

/// シェア画像を「参加者証明のカード」形式で組み立てる、デザイン検証用の新しいサービス。
///
/// **現時点ではどこからも呼ばれていない（未統合）**。`ShareCollageBuilder` / `CollageService`
/// が使う従来のコラージュ形式（複数枚を敷き詰めるレイアウト）は変更せず、
/// このファイルは完全に独立させてある。ユーザーがこのデザイン案を確認・承認した後に、
/// `ShareCollageBuilder` から呼び出す形へ統合する想定。
///
/// **狙い**: 派手なスタンプやマスキングテープのような装飾は使わず、余白・写真・
/// 硬めのゴシック体だけで「限定されたメンバーである」ことをさりげなく伝える。
/// 「その場にいた9人だけ」のような直接的な排他表現の文言は入れず、
/// 「MEMBER 03/09」という数字と枠組みだけに語らせる。
enum MemberCardService {

    /// Instagramのストーリー / フィード双方で違和感なく使える縦長比率
    static let canvasSize = CGSize(width: 1080, height: 1920)

    private static let margin: CGFloat = 72
    private static let paperColor = UIColor(white: 0.98, alpha: 1)
    private static let inkColor = UIColor(white: 0.12, alpha: 1)
    private static let subInkColor = UIColor(white: 0.45, alpha: 1)

    /// Member Card画像を1枚生成する。
    ///
    /// - Parameters:
    ///   - image: メインで見せる写真（1枚だけ）
    ///   - eventName: カード上部に大きく出すイベント名
    ///   - date: イベント名の下に添える日付
    ///   - memberIndex: このカードの持ち主が、参加者の中で何番目に参加したか（1始まり）。
    ///     将来統合する際は `event.participantIDs.firstIndex(of: DeviceIdentity.current)` 等から求める想定。
    ///   - memberTotal: 参加者の総数
    static func makeCard(
        from image: UIImage,
        eventName: String,
        date: Date,
        memberIndex: Int,
        memberTotal: Int
    ) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true

        return UIGraphicsImageRenderer(size: canvasSize, format: format).image { ctx in
            let cg = ctx.cgContext

            paperColor.setFill()
            cg.fill(CGRect(origin: .zero, size: canvasSize))

            let headerBottom = drawHeader(eventName: eventName, date: date, context: cg)
            let footerTop = drawFooter(memberIndex: memberIndex, memberTotal: memberTotal, context: cg)

            let photoArea = CGRect(
                x: margin,
                y: headerBottom + 40,
                width: canvasSize.width - margin * 2,
                height: footerTop - 40 - (headerBottom + 40)
            )
            drawPhoto(image, in: photoArea, context: cg)
        }
    }

    // MARK: - ヘッダー（イベント名・日付）

    /// - Returns: ヘッダーが占めた領域の下端Y座標
    @discardableResult
    private static func drawHeader(eventName: String, date: Date, context cg: CGContext) -> CGFloat {
        let titleFont = notoSansJP(weight: .black, size: 64)
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: inkColor,
        ]

        let maxWidth = canvasSize.width - margin * 2
        let displayTitle = truncated(eventName, attributes: titleAttrs, maxWidth: maxWidth)
        let titleSize = (displayTitle as NSString).size(withAttributes: titleAttrs)
        let titleY: CGFloat = 112

        (displayTitle as NSString).draw(at: CGPoint(x: margin, y: titleY), withAttributes: titleAttrs)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "yyyy.MM.dd"

        let dateAttrs: [NSAttributedString.Key: Any] = [
            .font: notoSansJP(weight: .bold, size: 30),
            .foregroundColor: subInkColor,
        ]
        let dateY = titleY + titleSize.height + 12
        (formatter.string(from: date) as NSString).draw(at: CGPoint(x: margin, y: dateY), withAttributes: dateAttrs)
        let dateHeight = (formatter.string(from: date) as NSString).size(withAttributes: dateAttrs).height

        return dateY + dateHeight
    }

    // MARK: - メイン写真

    private static func drawPhoto(_ image: UIImage, in rect: CGRect, context cg: CGContext) {
        cg.saveGState()

        // 装飾を足す代わりに、柔らかい影だけでカードらしい厚みを出す
        cg.setShadow(offset: CGSize(width: 0, height: 10), blur: 28, color: UIColor.black.withAlphaComponent(0.18).cgColor)
        UIBezierPath(roundedRect: rect, cornerRadius: 28).fill()
        cg.restoreGState()

        cg.saveGState()
        let clipPath = UIBezierPath(roundedRect: rect, cornerRadius: 28)
        clipPath.addClip()

        let scale = max(rect.width / image.size.width, rect.height / image.size.height)
        let drawSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let origin = CGPoint(x: rect.midX - drawSize.width / 2, y: rect.midY - drawSize.height / 2)
        image.draw(in: CGRect(origin: origin, size: drawSize))

        cg.restoreGState()
    }

    // MARK: - フッター（MEMBER連番・EventSnapバッジ)

    /// - Returns: フッターが占める領域の上端Y座標（写真エリアの下限として使う）
    private static func drawFooter(memberIndex: Int, memberTotal: Int, context cg: CGContext) -> CGFloat {
        let footerHeight: CGFloat = 176
        let footerTop = canvasSize.height - margin - footerHeight

        drawMemberBadge(index: memberIndex, total: memberTotal, top: footerTop, context: cg)
        drawAppBadge(bottom: canvasSize.height - margin)

        return footerTop
    }

    /// 「MEMBER 03/09」。数字と枠だけで特別感を出す、控えめなカード風バッジ。
    private static func drawMemberBadge(index: Int, total: Int, top: CGFloat, context cg: CGContext) {
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: notoSansJP(weight: .bold, size: 22),
            .foregroundColor: subInkColor,
            .kern: 3,
        ]
        let numberAttrs: [NSAttributedString.Key: Any] = [
            .font: notoSansJP(weight: .black, size: 44),
            .foregroundColor: inkColor,
        ]

        let label = "MEMBER" as NSString
        let number = memberNumberText(index: index, total: total) as NSString

        let labelSize = label.size(withAttributes: labelAttrs)
        let numberSize = number.size(withAttributes: numberAttrs)

        let paddingH: CGFloat = 28
        let paddingV: CGFloat = 18
        let innerGap: CGFloat = 6

        let contentWidth = max(labelSize.width, numberSize.width)
        let contentHeight = labelSize.height + innerGap + numberSize.height
        let boxWidth = contentWidth + paddingH * 2
        let boxHeight = contentHeight + paddingV * 2

        let box = CGRect(x: margin, y: top, width: boxWidth, height: boxHeight)

        cg.saveGState()
        let border = UIBezierPath(roundedRect: box, cornerRadius: 14)
        inkColor.withAlphaComponent(0.16).setStroke()
        border.lineWidth = 1.5
        border.stroke()
        cg.restoreGState()

        label.draw(at: CGPoint(x: box.minX + paddingH, y: box.minY + paddingV), withAttributes: labelAttrs)
        number.draw(
            at: CGPoint(x: box.minX + paddingH, y: box.minY + paddingV + labelSize.height + innerGap),
            withAttributes: numberAttrs
        )
    }

    /// 「EventSnapで撮影」。控えめだが視認性は保つ、右下の小さなバッジ。
    private static func drawAppBadge(bottom: CGFloat) {
        let text = "EventSnapで撮影" as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: notoSansJP(weight: .bold, size: 24),
            .foregroundColor: subInkColor,
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
}
