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
    /// イベント写真集の1ページ。雑誌の表紙のように写真を美しく見せる
    case editorial
    /// イベントポスター。巨大タイポグラフィと写真で1枚のグラフィックを作る
    case bold
    /// 意図的に削ぎ落とした、写真そのものを最大限に活かす1枚
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

/// 各テンプレートが実装するプロトコル。テンプレートごとに完全に独立した型にでき、
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

// MARK: - A. Editorial(イベント写真集の1ページ)

/// 単に写真＋小さい文字ではなく「雑誌の表紙」を目指す。
/// 大きなタイトル・細いライン・小さな添え文字・大きな余白でコントラストを作る。
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
        let titleZone = analysis.bestZone
        let zone = titleZone.zone
        let ink: UIColor = titleZone.isDark ? .white : UIColor(white: 0.08, alpha: 1)
        let secondaryZone = zone.opposite

        // タイトルは写真の端に寄せて置く（写真の外へ逃げるような、攻めた余白の取り方）。
        // 添え文字・ブランドは通常のinsetのままにして、要素ごとに緊張感の差を作る。
        let titleInset: CGFloat = 48
        let inset: CGFloat = 72

        let maxWidth: CGFloat = {
            switch zone {
            case .top, .bottom: return canvasSize.width - titleInset * 2
            // PhotoAnalyzerが安全ゾーンとして評価した幅（40%）を大きく超えないようにする。
            // ここを広げすぎると、スコアリングでは避けたはずの被写体側に文字が
            // はみ出しかねない。
            case .left, .right: return canvasSize.width * 0.42 - titleInset
            }
        }()

        let (lines, titleFont) = SocialCardDrawing.fitTitle(
            eventName, weight: .black, maxWidth: maxWidth,
            maxLines: (zone == .left || zone == .right) ? 5 : 3, maxSize: 84, minSize: 42
        )
        let lineHeight = titleFont.ascender - titleFont.descender
        let titleBlockHeight = CGFloat(lines.count) * lineHeight * 1.05

        let titleX: CGFloat = zone == .right ? canvasSize.width - titleInset - maxWidth : titleInset
        let ruleWidth: CGFloat = min(96, maxWidth * 0.3)

        switch zone {
        case .top:
            var y = titleInset + 8
            SocialCardDrawing.drawLines(lines, font: titleFont, color: ink, x: titleX, y: &y, lineHeight: lineHeight * 1.05, softShadow: true)
            SocialCardDrawing.drawRule(cg: cg, from: CGPoint(x: titleX, y: y + 10), width: ruleWidth, color: ink.withAlphaComponent(0.7))

        case .bottom:
            var y = canvasSize.height - titleInset - titleBlockHeight
            SocialCardDrawing.drawRule(cg: cg, from: CGPoint(x: titleX, y: y - 20), width: ruleWidth, color: ink.withAlphaComponent(0.7))
            SocialCardDrawing.drawLines(lines, font: titleFont, color: ink, x: titleX, y: &y, lineHeight: lineHeight * 1.05, softShadow: true)

        case .left, .right:
            var y = (canvasSize.height - titleBlockHeight) / 2
            SocialCardDrawing.drawRule(cg: cg, from: CGPoint(x: titleX, y: y - 20), width: ruleWidth, color: ink.withAlphaComponent(0.7))
            SocialCardDrawing.drawLines(lines, font: titleFont, color: ink, x: titleX, y: &y, lineHeight: lineHeight * 1.05, softShadow: true)
        }

        // 添え文字（日付・MEMORIES番号）。タイトルとは反対側の帯に、小さく静かに置く。
        // タイトルと添え文字のサイズ差そのものが「雑誌のレイアウト」らしいコントラストを作る。
        //
        // 反対側の帯はタイトル側とは明るさが違うことがあるため、ink色は
        // タイトル側のものを使い回さず、その帯自身の明暗判定から選び直す。
        let secondaryIsDark = analysis.textZones.first(where: { $0.zone == secondaryZone })?.isDark ?? titleZone.isDark
        let captionInk: UIColor = secondaryIsDark ? .white : UIColor(white: 0.08, alpha: 1)

        // 帯全体の平均明度で選んだink色は、添え文字を置く角だけで見ると
        // 実際には合わないことがある（部分的に明暗が混ざった写真など）。
        // ソフトシャドウだけでは白文字/黒文字が背景と同化するケースまでは
        // 救えないため、ごく控えめな中立色のスクリムを保険として敷く
        // （アクセントカラーは混ぜず、Editorialの静けさを保つ）。
        let neutralBase: UIColor = secondaryIsDark ? .black : .white
        SocialCardDrawing.drawScrim(cg: cg, zone: secondaryZone, canvasSize: canvasSize, tint: neutralBase, dark: secondaryIsDark, strength: 0.3)

        var caption = SocialCardDrawing.dateString(date).uppercased()
        caption += "\nMEMORIES \(String(format: "%02d", max(momentIndex, 1)))"
        SocialCardDrawing.drawCaptionBlock(
            cg: cg, canvasSize: canvasSize, zone: secondaryZone, text: caption,
            color: captionInk.withAlphaComponent(0.85), inset: inset
        )

        // ブランドは添え文字と同じ帯の反対側の端に、ごく小さく
        let brandCorner = SocialCardDrawing.Corner.corner(endOf: secondaryZone)
        SocialCardDrawing.drawBrandMark(canvasSize: canvasSize, corner: brandCorner, ink: captionInk, opacity: 0.7)
    }
}

// MARK: - B. Bold(イベントポスター)

/// 写真と文字を別々に置くのではなく「写真＋巨大タイポグラフィ＝1枚のグラフィック」にする。
/// 巨大なイベント名・背景化した巨大な日付数字・写真から抽出したアクセントカラーの
/// エッジストライプ、という強い要素を少数だけ組み合わせる。
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
        let ink: UIColor = zoneInfo.isDark ? .white : UIColor(white: 0.05, alpha: 1)
        let accent = analysis.accentColor
        let inset: CGFloat = 48

        // 1. 視認性確保のためのスクリム（写真の色を混ぜているので、写真から浮かない）
        SocialCardDrawing.drawScrim(cg: cg, zone: zone, canvasSize: canvasSize, tint: accent, dark: zoneInfo.isDark, strength: 0.62)

        let zoneRect = zone.rect(in: canvasSize)

        // 2. 日付を「背景要素」として使う巨大なゴースト数字。タイトルと同じゾーンの中に
        //    低い不透明度で置き、タイトルの後ろに沈める（写真そのものを暗くする処理は避け、
        //    あくまで文字レイヤーの中で完結させる）。
        let day = Calendar.current.component(.day, from: date)
        SocialCardDrawing.drawGhostNumber(String(format: "%02d", day), in: zoneRect, ink: ink)

        // 3. 巨大なイベント名。画面幅の70〜100%を狙って攻めたサイズにする。
        let maxWidth: CGFloat = {
            switch zone {
            case .top, .bottom: return canvasSize.width - inset * 2
            case .left, .right: return canvasSize.width * 0.66 - inset
            }
        }()

        let (lines, titleFont) = SocialCardDrawing.fitTitle(
            eventName, weight: .black, maxWidth: maxWidth, maxLines: 3, maxSize: 190, minSize: 66
        )
        let lineHeight = titleFont.ascender - titleFont.descender
        let blockHeight = CGFloat(lines.count) * lineHeight * 0.94

        let x: CGFloat = zone == .right ? canvasSize.width - inset - maxWidth : inset
        var y: CGFloat = {
            switch zone {
            case .top: return inset + 4
            case .bottom: return canvasSize.height - inset - blockHeight
            case .left, .right: return (canvasSize.height - blockHeight) / 2
            }
        }()
        SocialCardDrawing.drawLines(lines, font: titleFont, color: ink, x: x, y: &y, lineHeight: lineHeight * 0.94, softShadow: true, shadowStrength: 1.4)

        // 4. アクセントカラーの太いエッジストライプ。タイトルと反対側の辺に置くので
        //    文字とは絶対にぶつからない。
        SocialCardDrawing.drawAccentStripe(cg: cg, canvasSize: canvasSize, avoiding: zone, color: accent)

        // 5. 端に沿わせた縦書き風の小さな番号(フェス/イベントポスターの定番モチーフ)
        let figure = "\(String(format: "%02d", max(momentIndex, 1))) / \(String(format: "%02d", max(momentTotal, momentIndex, 1)))"
        SocialCardDrawing.drawRotatedFigure(cg: cg, text: figure, canvasSize: canvasSize, onRight: zone != .right, ink: ink)

        let creditAtTop = (zone == .bottom)
        SocialCardDrawing.drawCredit(canvasSize: canvasSize, date: date, ink: ink, atTop: creditAtTop)
    }
}

// MARK: - C. Minimal(意図的に削ぎ落とされた1枚)

/// 「写真を活かす」ことが「何もデザインしない」ことにならないよう、
/// 小さな署名のような要素（細いライン・色のアクセント・控えめな日付）を1組だけ添える。
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
        let accent = analysis.accentColor
        let inset: CGFloat = 76

        let maxWidth: CGFloat = {
            switch zone {
            case .top, .bottom: return canvasSize.width - inset * 2
            case .left, .right: return canvasSize.width * 0.44 - inset
            }
        }()

        let (lines, font) = SocialCardDrawing.fitTitle(
            eventName, weight: .bold, maxWidth: maxWidth, maxLines: 2, maxSize: 50, minSize: 30
        )
        let lineHeight = font.ascender - font.descender

        let dateFont = SocialCardDrawing.bebasNeue(size: 22)
        let dateHeight = dateFont.ascender - dateFont.descender
        let markHeight: CGFloat = 4
        let gapAboveMark: CGFloat = 14
        let gapBelowMark: CGFloat = 10
        let gapAboveDate: CGFloat = 8

        let blockHeight = CGFloat(lines.count) * lineHeight * 1.12 + gapAboveMark + markHeight + gapBelowMark + gapAboveDate + dateHeight

        let x: CGFloat = zone == .right ? canvasSize.width - inset - maxWidth : inset
        var y: CGFloat = {
            switch zone {
            case .top: return inset
            case .bottom: return canvasSize.height - inset - blockHeight
            case .left, .right: return (canvasSize.height - blockHeight) / 2
            }
        }()

        SocialCardDrawing.drawLines(lines, font: font, color: ink, x: x, y: &y, lineHeight: lineHeight * 1.12, kern: 0.5, softShadow: true)

        // 小さな署名のようなマーク: 短いアクセントカラーの線
        y += gapAboveMark
        cg.saveGState()
        accent.setFill()
        cg.fill(CGRect(x: x, y: y, width: 28, height: markHeight))
        cg.restoreGState()
        y += markHeight + gapBelowMark

        SocialCardDrawing.drawTracked(SocialCardDrawing.dateString(date), at: CGPoint(x: x, y: y), font: dateFont, color: ink.withAlphaComponent(0.65), tracking: 2)

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

    enum Corner {
        case topLeading, topTrailing, bottomLeading, bottomTrailing

        /// 指定ゾーンの帯・列の「終端」に対応する隅（開始端は`drawCaptionBlock`が使う）
        static func corner(endOf zone: SafeZone) -> Corner {
            switch zone {
            case .top: return .topTrailing
            case .bottom: return .bottomTrailing
            case .left: return .bottomLeading
            case .right: return .bottomTrailing
            }
        }
    }

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

    /// Editorialの添え文字（日付・MEMORIES番号）を、指定ゾーンの「開始端」に小さく置く。
    /// 複数行(`\n`区切り)を想定する。
    static func drawCaptionBlock(cg: CGContext, canvasSize: CGSize, zone: SafeZone, text: String, color: UIColor, inset: CGFloat) {
        let font = bebasNeue(size: 26)
        let lineHeight = font.ascender - font.descender
        let lines = text.components(separatedBy: "\n")

        let x: CGFloat
        var y: CGFloat
        switch zone {
        case .top: x = inset; y = inset
        case .bottom: x = inset; y = canvasSize.height - inset - CGFloat(lines.count) * lineHeight * 1.15
        case .left: x = inset; y = inset
        case .right: x = canvasSize.width - inset - maxTrackedWidth(lines, font: font, tracking: 2); y = inset
        }

        for line in lines {
            drawTracked(line, at: CGPoint(x: x, y: y), font: font, color: color, tracking: 2)
            y += lineHeight * 1.15
        }
    }

    private static func maxTrackedWidth(_ lines: [String], font: UIFont, tracking: CGFloat) -> CGFloat {
        lines.map { trackedWidth($0, font: font, tracking: tracking) }.max() ?? 0
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
    static func drawScrim(cg: CGContext, zone: SafeZone, canvasSize: CGSize, tint: UIColor, dark: Bool, strength: CGFloat = 0.55) {
        let rect = zone.rect(in: canvasSize)
        let base: UIColor = dark ? .black : .white
        let scrimColor = blend(base, tint, 0.25)

        guard let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [scrimColor.withAlphaComponent(strength).cgColor, scrimColor.withAlphaComponent(0).cgColor] as CFArray,
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

    /// タイトルの後ろに沈める、日付などの巨大なゴースト数字。Boldの「数字を背景要素にする」用。
    /// 指定した矩形の幅いっぱいに広がるサイズを、基準サイズでの実測幅から比例計算で求める
    /// （Bebas Neueは文字幅がフォントサイズにほぼ線形に比例するため、1回の実測で求まる）。
    static func drawGhostNumber(_ text: String, in rect: CGRect, ink: UIColor) {
        let referenceSize: CGFloat = 300
        let referenceFont = bebasNeue(size: referenceSize)
        let referenceWidth = (text as NSString).size(withAttributes: [.font: referenceFont]).width
        guard referenceWidth > 0 else { return }

        let targetWidth = rect.width * 0.92
        let fontSize = referenceSize * (targetWidth / referenceWidth)
        let font = bebasNeue(size: fontSize)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: ink.withAlphaComponent(0.14)]
        let size = (text as NSString).size(withAttributes: attrs)
        let point = CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2)
        (text as NSString).draw(at: point, withAttributes: attrs)
    }

    /// タイトルと反対側の辺に置く、アクセントカラーの太いストライプ（額縁にはならない一辺だけの色面）
    static func drawAccentStripe(cg: CGContext, canvasSize: CGSize, avoiding zone: SafeZone, color: UIColor) {
        let thickness: CGFloat = 14
        let rect: CGRect
        switch zone {
        case .top: rect = CGRect(x: 0, y: canvasSize.height - thickness, width: canvasSize.width, height: thickness)
        case .bottom: rect = CGRect(x: 0, y: 0, width: canvasSize.width, height: thickness)
        case .left: rect = CGRect(x: canvasSize.width - thickness, y: 0, width: thickness, height: canvasSize.height)
        case .right: rect = CGRect(x: 0, y: 0, width: thickness, height: canvasSize.height)
        }
        cg.saveGState()
        color.setFill()
        cg.fill(rect)
        cg.restoreGState()
    }

    /// 短い装飾ライン（Editorialの見出し下の細いライン）
    static func drawRule(cg: CGContext, from point: CGPoint, width: CGFloat, color: UIColor) {
        cg.saveGState()
        cg.setStrokeColor(color.cgColor)
        cg.setLineWidth(3)
        cg.move(to: point)
        cg.addLine(to: CGPoint(x: point.x + width, y: point.y))
        cg.strokePath()
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

    /// 英数字の連続（"2026" など）はひとまとまりのトークンとして扱い、途中で
    /// 折り返さない。日本語（かな・漢字）は分かち書きされないため引き続き
    /// 1文字ごとに折り返し可能とする。
    static func wrapText(_ text: String, font: UIFont, maxWidth: CGFloat) -> [String] {
        guard !text.isEmpty else { return [] }
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        func width(_ s: String) -> CGFloat { (s as NSString).size(withAttributes: attrs).width }

        var lines: [String] = []
        var current = ""

        for token in tokenize(text) {
            let candidate = current + token
            if current.isEmpty || width(candidate) <= maxWidth {
                current = candidate
            } else {
                lines.append(current)
                current = token
            }

            // トークン単体（英数字の連続）がそもそも1行に収まらない場合だけ、
            // そのトークンを文字単位でさらに分割する。
            if current == token, width(current) > maxWidth, token.count > 1 {
                var sub = ""
                for ch in token {
                    let candidateChar = sub + String(ch)
                    if !sub.isEmpty, width(candidateChar) > maxWidth {
                        lines.append(sub)
                        sub = String(ch)
                    } else {
                        sub = candidateChar
                    }
                }
                current = sub
            }
        }
        if !current.isEmpty { lines.append(current) }
        return lines
    }

    /// ASCII英数字の連続はひとまとまりのトークンに、それ以外(日本語など)は
    /// 1文字ずつのトークンにする
    private static func tokenize(_ text: String) -> [String] {
        var tokens: [String] = []
        var word = ""
        for ch in text {
            if ch.isASCII, ch.isLetter || ch.isNumber {
                word.append(ch)
            } else {
                if !word.isEmpty { tokens.append(word); word = "" }
                tokens.append(String(ch))
            }
        }
        if !word.isEmpty { tokens.append(word) }
        return tokens
    }

    static func drawLines(
        _ lines: [String], font: UIFont, color: UIColor, x: CGFloat, y: inout CGFloat, lineHeight: CGFloat,
        kern: CGFloat = 0, softShadow: Bool = false, shadowStrength: CGFloat = 1
    ) {
        var attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .kern: kern]
        if softShadow {
            attrs[.shadow] = textShadow(strength: shadowStrength)
        }
        for line in lines {
            (line as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: attrs)
            y += lineHeight
        }
    }

    /// 文字を写真に直接載せても読めるようにする、控えめなドロップシャドウ。
    /// 黒縁取り（ストローク）ではなく、ごく柔らかい影だけを足す方針
    /// （写真全体を暗くしたり、文字を縁取って安っぽく見せたりしない）。
    private static func textShadow(strength: CGFloat = 1) -> NSShadow {
        let shadow = NSShadow()
        shadow.shadowColor = UIColor.black.withAlphaComponent(min(0.32 * strength, 0.5))
        shadow.shadowOffset = CGSize(width: 0, height: 2 * strength)
        shadow.shadowBlurRadius = 8 * strength
        return shadow
    }

    static func trackedWidth(_ text: String, font: UIFont, tracking: CGFloat) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let total = text.reduce(CGFloat(0)) { sum, ch in sum + String(ch).size(withAttributes: attrs).width + tracking }
        return total - tracking
    }

    static func drawTracked(_ text: String, at point: CGPoint, font: UIFont, color: UIColor, tracking: CGFloat) {
        var x = point.x
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .shadow: textShadow(strength: 0.7)]
        for ch in text {
            let s = String(ch)
            (s as NSString).draw(at: CGPoint(x: x, y: point.y), withAttributes: attrs)
            x += s.size(withAttributes: [.font: font]).width + tracking
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

private extension SafeZone {
    /// タイトルが置かれた側と反対側のゾーン。添え文字・ブランドの置き場に使う。
    var opposite: SafeZone {
        switch self {
        case .top: return .bottom
        case .bottom: return .top
        case .left: return .right
        case .right: return .left
        }
    }
}
