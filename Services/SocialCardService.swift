//
//  SocialCardService.swift
//  EventSnap
//
//  SNSシェア画像の生成: Photo → PhotoAnalyzer(1回だけ) → 選ばれたテンプレートで描画
//

import CoreGraphics
import Foundation
import UIKit
import SwiftUI

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

    /// 複数写真のEvent Reel(自動編集された縦長シェア画像)を1枚描画する。
    ///
    /// 単写真用の`render`/`makeCard`とは別経路にしている。`MultiPhotoRenderer`は
    /// `SocialCardRenderer`プロトコルに乗らない。写真を複数受け取る都合上、
    /// 「1枚をキャンバスいっぱいに敷いてから文字を重ねる」という
    /// `render`の前提(`drawPhotoFullBleed`を先に呼ぶ)と根本的に構造が違うため。
    static func renderEventReel(
        photos: [MultiPhotoRenderer.PhotoInput],
        eventName: String,
        date: Date,
        participantCount: Int,
        photoCount: Int
    ) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true

        return UIGraphicsImageRenderer(size: canvasSize, format: format).image { ctx in
            MultiPhotoRenderer.draw(
                cg: ctx.cgContext,
                canvasSize: canvasSize,
                photos: photos,
                eventName: eventName,
                date: date,
                participantCount: participantCount,
                photoCount: photoCount
            )
        }
    }

    /// 「フォトダンプ」スタイル(均等グリッドに余白なく敷き詰める)のEvent Reelを
    /// 1枚描画する。`MultiPhotoRenderer`（メイン写真を大きく、残りを雑誌風に配置）
    /// とは独立した、選べるもう1つのレイアウト。
    ///
    /// **現時点ではUI上の選択肢としては使わない**（既存のEvent Reel生成フローは
    /// 一切変更していない）。呼び出し側が明示的にこの関数を呼んだときだけ使われる。
    static func renderGridPhotoDump(
        photos: [MultiPhotoRenderer.PhotoInput],
        eventName: String,
        date: Date
    ) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true

        return UIGraphicsImageRenderer(size: canvasSize, format: format).image { ctx in
            GridPhotoDumpRenderer.draw(
                cg: ctx.cgContext,
                canvasSize: canvasSize,
                photos: photos,
                eventName: eventName,
                date: date
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

        // 添え文字は単なる日付テキストではなく、テープ留め風の装飾＋SNAP番号タグ＋
        // 日付タグの「ひとかたまり」にする。チェキに手書きで書き足したような、
        // 雑誌の堅さを少し崩す遊び心をここに集約する。
        SocialCardDrawing.drawMemoryCluster(
            cg: cg, canvasSize: canvasSize, zone: secondaryZone,
            date: date, momentIndex: momentIndex, ink: captionInk, accent: analysis.accentColor, inset: inset
        )

        // ブランドは添え文字と同じ帯の反対側の端に、ごく小さく
        let brandCorner = SocialCardDrawing.Corner.corner(endOf: secondaryZone)
        SocialCardDrawing.drawBrandMark(cg: cg, canvasSize: canvasSize, corner: brandCorner, ink: captionInk, opacity: 0.7)
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

        // 2. 日付を「背景要素」として使うゴースト数字。以前はゾーン中央に写真幅の
        //    92%で置いていたため被写体を覆いすぎていた。タイトルと反対側の端に
        //    寄せてサイズも抑え、「余白から数字がはみ出す」背景グラフィックに変える
        //    （写真・被写体を覆う面積を最小限にしつつ、Boldらしい強さは残す）。
        let day = Calendar.current.component(.day, from: date)
        let titleIsLeading = zone != .right
        SocialCardDrawing.drawGhostNumber(
            String(format: "%02d", day), in: zoneRect, ink: ink,
            anchor: titleIsLeading ? .trailing : .leading, widthRatio: 0.6, opacity: 0.16
        )

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
        let blockY: CGFloat = {
            switch zone {
            case .top: return inset + 4
            case .bottom: return canvasSize.height - inset - blockHeight
            case .left, .right: return (canvasSize.height - blockHeight) / 2
            }
        }()

        // タイトルにごくわずかな傾きを与え、「静止したポスター」ではなく
        // 「勢いのある1枚」に見せる。傾けすぎると読みにくく安っぽくなるため、
        // 気づく程度に留める（Bold ≠ 派手、という方針を守る）。
        let rotation: CGFloat = -0.035
        cg.saveGState()
        cg.translateBy(x: x, y: blockY)
        cg.rotate(by: rotation)
        var localY: CGFloat = 0
        SocialCardDrawing.drawLines(lines, font: titleFont, color: ink, x: 0, y: &localY, lineHeight: lineHeight * 0.94, softShadow: true, shadowStrength: 1.4)
        cg.restoreGState()

        // 4. アクセントカラーの太いエッジストライプ。タイトルと反対側の辺に置くので
        //    文字とは絶対にぶつからない。
        SocialCardDrawing.drawAccentStripe(cg: cg, canvasSize: canvasSize, avoiding: zone, color: accent)

        // 5. 端に沿わせた縦書き風のSNAP番号ステッカー(フェス/イベントポスターの
        //    定番モチーフを、ブランドグラデーションで塗ったEventSnap独自のものに)
        SocialCardDrawing.drawRotatedSnapSticker(cg: cg, canvasSize: canvasSize, momentIndex: momentIndex, onRight: zone != .right)

        let creditAtTop = (zone == .bottom)
        let creditCorner: SocialCardDrawing.Corner = creditAtTop ? .topLeading : .bottomLeading
        SocialCardDrawing.drawBrandMark(cg: cg, canvasSize: canvasSize, corner: creditCorner, ink: ink, opacity: 0.8, dateSuffix: date)
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

        let tagHeight = SocialCardDrawing.dateTagSize(date: date).height
        let markHeight: CGFloat = 4
        let gapAboveMark: CGFloat = 14
        let gapBelowMark: CGFloat = 12

        let blockHeight = CGFloat(lines.count) * lineHeight * 1.12 + gapAboveMark + markHeight + gapBelowMark + tagHeight

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

        // 「何もしていない」ように見えないよう、SNAP番号タグ＋日付タグを
        // ごく小さく1組だけ添える。Minimalの静けさは保ちつつ、要素ゼロにはしない。
        let snapSize = SocialCardDrawing.drawSnapTag(cg: cg, at: CGPoint(x: x, y: y), index: momentIndex, ink: ink, filled: false)
        SocialCardDrawing.drawDateTag(cg: cg, at: CGPoint(x: x + snapSize.width + 8, y: y), date: date, ink: ink, filled: false)

        let brandCorner: SocialCardDrawing.Corner = (zone == .bottom) ? .topTrailing : .bottomTrailing
        SocialCardDrawing.drawBrandMark(cg: cg, canvasSize: canvasSize, corner: brandCorner, ink: ink, opacity: 0.55)
    }
}

// MARK: - D. MultiPhoto(複数写真の自動編集Event Reel)

/// EventSnapが「シェアOKの写真から自動的に選んだ複数枚」を、1枚の縦長画像に
/// まとめるレンダラー。Editorial/Bold/Minimalとは違い、`SocialCardRenderer`
/// プロトコルには乗らない(1枚をフルブリードで敷く前提が合わないため)。
///
/// **狙い**: 「写真を加工するアプリ」ではなく「複数の写真からイベントの
/// 思い出を自動編集してくれるアプリ」を、見た瞬間に伝える1枚にする。
/// 写真そのものはクロップ以外ほぼ無加工。メイン写真を大きく、残りを
/// 小さく並べ、余白のある雑誌の1ページのような構成にする。
enum MultiPhotoRenderer {

    /// 描画に必要な最小限の情報。フル解析結果ではなく`importanceCenter`
    /// (重要領域の重心)だけを受け取る。選定時点(サムネイル解析)で
    /// 計算済みの正規化座標をそのまま使い回せるため、本番描画のために
    /// もう一度Visionを走らせる必要が無い。
    struct PhotoInput {
        let image: UIImage
        let importanceCenter: CGPoint
    }

    /// 背景色。写真同士に余白を作る構成のため、Editorial/Bold/Minimalのような
    /// 「写真で埋め尽くす」設計ではなく、あえて写真の外側が見える紙面にしている。
    static let backgroundColor = UIColor(red: 0.98, green: 0.965, blue: 0.945, alpha: 1)

    static func draw(
        cg: CGContext,
        canvasSize: CGSize,
        photos: [PhotoInput],
        eventName: String,
        date: Date,
        participantCount: Int,
        photoCount: Int
    ) {
        guard !photos.isEmpty else { return }

        let ink = UIColor(white: 0.1, alpha: 1)
        let secondaryInk = ink.withAlphaComponent(0.5)
        let accent = SocialCardDrawing.brandGradientStart

        backgroundColor.setFill()
        cg.fill(CGRect(origin: .zero, size: canvasSize))

        let margin: CGFloat = 22
        let gap: CGFloat = 8
        let captionHeight: CGFloat = 268

        let photoArea = CGRect(
            x: margin, y: margin,
            width: canvasSize.width - margin * 2,
            height: canvasSize.height - margin - captionHeight
        )

        let tileRects = computeTileRects(photoArea: photoArea, rows: rows(for: photos.count), gap: gap)
        for (index, rect) in tileRects.enumerated() where index < photos.count {
            drawTilePhoto(photos[index].image, importanceCenter: photos[index].importanceCenter, in: rect, cg: cg)
        }

        // MARK: キャプション(写真とは独立した紙面。写真の邪魔をしない)
        let captionRect = CGRect(x: margin, y: photoArea.maxY + gap, width: canvasSize.width - margin * 2, height: captionHeight - gap)
        let inset: CGFloat = 6
        let x = captionRect.minX + inset

        let (titleLines, titleFont) = SocialCardDrawing.fitTitle(
            eventName, weight: .black, maxWidth: captionRect.width - inset * 2, maxLines: 2, maxSize: 58, minSize: 34
        )
        let titleLineHeight = titleFont.ascender - titleFont.descender

        var y = captionRect.minY + inset + 4
        SocialCardDrawing.drawLines(titleLines, font: titleFont, color: ink, x: x, y: &y, lineHeight: titleLineHeight * 1.05)

        y += 10
        SocialCardDrawing.drawRule(cg: cg, from: CGPoint(x: x, y: y), width: 56, color: accent)
        y += 22

        let dateFont = SocialCardDrawing.bebasNeue(size: 30)
        SocialCardDrawing.drawTracked(SocialCardDrawing.dateString(date), at: CGPoint(x: x, y: y), font: dateFont, color: ink.withAlphaComponent(0.75), tracking: 2, shadow: false)
        y += (dateFont.ascender - dateFont.descender) + 12

        // 「9人で撮影された42枚の思い出」を、広告的にならない範囲で短く伝える
        let statsFont = SocialCardDrawing.bebasNeue(size: 23)
        let statsText = statsLine(participantCount: participantCount, photoCount: max(photoCount, photos.count))
        SocialCardDrawing.drawTracked(statsText, at: CGPoint(x: x, y: y), font: statsFont, color: secondaryInk, tracking: 2, shadow: false)

        SocialCardDrawing.drawBrandMark(cg: cg, canvasSize: canvasSize, corner: .bottomTrailing, ink: ink, opacity: 0.75, shadow: false)
    }

    /// 「1 PEOPLE」のような不自然な英語を避け、単数/複数を正しく出し分ける。
    static func statsLine(participantCount: Int, photoCount: Int) -> String {
        let people = max(participantCount, 1)
        let photos = max(photoCount, 1)
        let peopleWord = people == 1 ? "PERSON" : "PEOPLE"
        let photoWord = photos == 1 ? "PHOTO" : "PHOTOS"
        return "\(people) \(peopleWord)  ·  \(photos) \(photoWord)"
    }

    // MARK: - レイアウト(枚数ごとの行構成)

    private struct Row { let heightRatio: CGFloat; let columns: Int }

    /// 写真枚数(2〜5)ごとの行構成。「メイン1枚を大きく、残りを小さく」を
    /// 基本にしつつ、枚数に応じて自然な段組みになるようにする。
    /// 6枚以上は呼び出し側(選定アルゴリズム)で作らない前提だが、
    /// 万一渡された場合も5枚と同じレイアウトで受け止める(クラッシュしない)。
    private static func rows(for count: Int) -> [Row] {
        switch count {
        case ...1: return [Row(heightRatio: 1, columns: 1)]
        case 2: return [Row(heightRatio: 0.62, columns: 1), Row(heightRatio: 0.38, columns: 1)]
        case 3: return [Row(heightRatio: 0.58, columns: 1), Row(heightRatio: 0.42, columns: 2)]
        case 4: return [Row(heightRatio: 0.50, columns: 1), Row(heightRatio: 0.25, columns: 2), Row(heightRatio: 0.25, columns: 1)]
        default: return [Row(heightRatio: 0.46, columns: 1), Row(heightRatio: 0.27, columns: 2), Row(heightRatio: 0.27, columns: 2)]
        }
    }

    private static func computeTileRects(photoArea: CGRect, rows: [Row], gap: CGFloat) -> [CGRect] {
        var rects: [CGRect] = []
        let totalGapHeight = gap * CGFloat(max(rows.count - 1, 0))
        let usableHeight = photoArea.height - totalGapHeight
        var y = photoArea.minY

        for row in rows {
            let rowHeight = usableHeight * row.heightRatio
            let totalGapWidth = gap * CGFloat(max(row.columns - 1, 0))
            let colWidth = (photoArea.width - totalGapWidth) / CGFloat(row.columns)
            var x = photoArea.minX
            for _ in 0..<row.columns {
                rects.append(CGRect(x: x, y: y, width: colWidth, height: rowHeight))
                x += colWidth + gap
            }
            y += rowHeight + gap
        }
        return rects
    }

    /// タイル矩形にクリップして写真を敷く。`PhotoAnalyzer.coverCrop`は
    /// 任意の`canvasSize`に対応しているため、キャンバス全体用の
    /// `drawPhotoFullBleed`と全く同じロジックを1タイル分に適用できる。
    private static func drawTilePhoto(_ image: UIImage, importanceCenter: CGPoint, in rect: CGRect, cg: CGContext) {
        guard rect.width > 0, rect.height > 0 else { return }
        cg.saveGState()
        cg.clip(to: rect)

        let scale = max(rect.width / image.size.width, rect.height / image.size.height)
        let crop = PhotoAnalyzer.coverCrop(imageSize: image.size, canvasSize: rect.size, importanceCenter: importanceCenter)
        let drawSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        image.draw(in: CGRect(x: rect.minX - crop.minX, y: rect.minY - crop.minY, width: drawSize.width, height: drawSize.height))

        cg.restoreGState()
    }
}

// MARK: - E. GridPhotoDump(均等グリッドで敷き詰める「フォトダンプ」スタイル)

/// Instagram等で実際に流行している「photo dump」スタイル(均等なグリッドに
/// 余白なく写真を敷き詰め、文字を写真の上に直接重ねる)を再現する。
///
/// `MultiPhotoRenderer`（メイン写真を大きく、残りを雑誌風の余白付きレイアウトで
/// 並べる）とは対照的に、「全ての写真を対等に、隙間なく並べる」ことを狙う。
/// `MultiPhotoRenderer`は一切変更せず、独立した実装として追加する。
///
/// **現時点ではUI上の選択肢としては使わない**（既存のEvent Reel生成フローは
/// 変更していない）。`SocialCardService.renderGridPhotoDump(...)`から
/// 明示的に呼び出せる、独立したレンダラー関数として用意するだけ。
enum GridPhotoDumpRenderer {

    static func draw(
        cg: CGContext,
        canvasSize: CGSize,
        photos: [MultiPhotoRenderer.PhotoInput],
        eventName: String,
        date: Date
    ) {
        guard !photos.isEmpty else { return }

        let layout = gridLayout(for: photos.count)
        let cellCount = layout.rows * layout.columns

        // 枚数がレイアウトのマス目数に満たない場合(3,5,7枚など)は、選ばれた
        // 写真を1枚も間引かず、最後の写真を引き伸ばして余ったマス目を埋める。
        var tilePhotos = Array(photos.prefix(cellCount))
        if let last = tilePhotos.last {
            while tilePhotos.count < cellCount {
                tilePhotos.append(last)
            }
        }

        let rects = gridRects(rows: layout.rows, columns: layout.columns, canvasSize: canvasSize)
        for (index, rect) in rects.enumerated() where index < tilePhotos.count {
            drawTile(tilePhotos[index], in: rect, cg: cg)
        }

        drawCaption(cg: cg, canvasSize: canvasSize, eventName: eventName, date: date)

        // 写真で埋め尽くされた背景の上に乗るため、MultiPhotoRenderer（紙面色の
        // 背景に対して濃いink）とは異なりinkは白にしている。それ以外(corner・
        // opacity・shadow: false)はMultiPhotoRendererの呼び出しと同じ、控えめな
        // 主張度合いに揃えている。
        SocialCardDrawing.drawBrandMark(cg: cg, canvasSize: canvasSize, corner: .bottomTrailing, ink: .white, opacity: 0.85, shadow: false)
    }

    // MARK: - レイアウト(枚数ごとのグリッド構成)

    private struct Layout {
        let rows: Int
        let columns: Int
    }

    /// 2/4/6/8枚を基本形とする。これらに一致しない枚数(3,5,7枚など)は、
    /// 直近の大きい方の基本形に丸める(余ったマス目は最後の写真の引き伸ばしで埋める。
    /// `draw(cg:canvasSize:photos:eventName:date:)`参照)。9枚以上は8枠に丸め、
    /// 先頭8枚だけを使う(呼び出し側で目標2〜5枚程度に絞る想定のため、実運用では
    /// 起こりにくい)。
    private static func gridLayout(for count: Int) -> Layout {
        switch count {
        case ...2: return Layout(rows: 2, columns: 1)
        case 3...4: return Layout(rows: 2, columns: 2)
        case 5...6: return Layout(rows: 3, columns: 2)
        default: return Layout(rows: 4, columns: 2)
        }
    }

    /// 行・列とも均等なマス目に分割する。`MultiPhotoRenderer.computeTileRects`と
    /// 違い、行の高さ比率が可変ではなく完全に均等、かつ余白(gap)も無いため、
    /// より単純な計算で済む。
    private static func gridRects(rows: Int, columns: Int, canvasSize: CGSize) -> [CGRect] {
        let cellWidth = canvasSize.width / CGFloat(columns)
        let cellHeight = canvasSize.height / CGFloat(rows)

        var rects: [CGRect] = []
        for row in 0..<rows {
            for col in 0..<columns {
                rects.append(CGRect(
                    x: CGFloat(col) * cellWidth,
                    y: CGFloat(row) * cellHeight,
                    width: cellWidth,
                    height: cellHeight
                ))
            }
        }
        return rects
    }

    /// タイル矩形にクリップして写真を敷く。`MultiPhotoRenderer.drawTilePhoto`と
    /// 同じ考え方(`PhotoAnalyzer.coverCrop`)だが、gapが無い分クリップ矩形の
    /// 計算がより単純なため、`MultiPhotoRenderer`を変更せずに独立して実装している。
    private static func drawTile(_ input: MultiPhotoRenderer.PhotoInput, in rect: CGRect, cg: CGContext) {
        guard rect.width > 0, rect.height > 0 else { return }
        cg.saveGState()
        cg.clip(to: rect)

        let image = input.image
        let scale = max(rect.width / image.size.width, rect.height / image.size.height)
        let crop = PhotoAnalyzer.coverCrop(imageSize: image.size, canvasSize: rect.size, importanceCenter: input.importanceCenter)
        let drawSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        image.draw(in: CGRect(x: rect.minX - crop.minX, y: rect.minY - crop.minY, width: drawSize.width, height: drawSize.height))

        cg.restoreGState()
    }

    // MARK: - キャプション(写真の上に直接重ねる)

    /// イベント名・日付を画面中央あたりに、写真の上へ直接重ねる。独立したカードや
    /// 矩形の背景は作らない。文字色は要件通り常に白固定で、影・縁取り・
    /// 半透明の背景板などの視認性補助は一切付けない。
    ///
    /// **簡略化した実装（既知の限界）**: どの写真の上に重なっても読める配置を
    /// Vision解析等で厳密に自動判定するのではなく、常にキャンバス中央に固定して
    /// いる。偶数行・偶数列のグリッド(2×2, 4×2等)では、中央はちょうど4枚の
    /// タイルの継ぎ目が交わる点になるため、被写体の中心がそこに来る構図は
    /// 比較的少ないという前提に基づく簡易ヒューリスティック(3行グリッド(3×2)では
    /// 継ぎ目の片側だけになるため、必ずしもこの前提は成り立たない)。文字色が
    /// 常に白固定という制約上、明るい写真が中央に来た場合は視認性が落ちる
    /// 可能性がある。実写真で読みにくいケースが多いようであれば、中央タイルだけ
    /// 簡易的な明度サンプリングを行って配置を上下にずらす、といった改善が今後の課題。
    private static func drawCaption(cg: CGContext, canvasSize: CGSize, eventName: String, date: Date) {
        let ink = UIColor.white
        let maxWidth = canvasSize.width * 0.82

        let (nameLines, nameFont) = SocialCardDrawing.fitTitle(
            eventName, weight: .black, maxWidth: maxWidth, maxLines: 2, maxSize: 76, minSize: 40
        )
        let nameLineHeight = nameFont.ascender - nameFont.descender

        let dateFont = SocialCardDrawing.notoSansJP(weight: .bold, size: 32)
        let dateLineHeight = dateFont.ascender - dateFont.descender

        let gapBetween: CGFloat = 14
        let blockHeight = CGFloat(nameLines.count) * nameLineHeight * 1.08 + gapBetween + dateLineHeight

        var y = canvasSize.height / 2 - blockHeight / 2

        for line in nameLines {
            let width = (line as NSString).size(withAttributes: [.font: nameFont]).width
            let x = canvasSize.width / 2 - width / 2
            (line as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: [.font: nameFont, .foregroundColor: ink])
            y += nameLineHeight * 1.08
        }

        y += gapBetween
        let dateText = SocialCardDrawing.dateString(date)
        let dateWidth = (dateText as NSString).size(withAttributes: [.font: dateFont]).width
        (dateText as NSString).draw(
            at: CGPoint(x: canvasSize.width / 2 - dateWidth / 2, y: y),
            withAttributes: [.font: dateFont, .foregroundColor: ink.withAlphaComponent(0.88)]
        )
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

        /// 指定ゾーンの帯・列の「終端」に対応する隅（開始端は`drawMemoryCluster`が使う）
        static func corner(endOf zone: SafeZone) -> Corner {
            switch zone {
            case .top: return .topTrailing
            case .bottom: return .bottomTrailing
            case .left: return .bottomLeading
            case .right: return .bottomTrailing
            }
        }
    }

    /// 「EVENTSNAP」の小さなワードマーク＋ブランドグラデーションのドット。
    /// バッジ・背景チップ・広告的な文言は使わない。「広告」ではなく
    /// 「作品のクレジット（フォトクレジット）」として見えることを狙っている。
    /// ドット1つ添えることで、文字を読まなくても「EventSnapのグラデーション」を
    /// 手がかりに一目で分かるようにする。
    static func drawBrandMark(cg: CGContext, canvasSize: CGSize, corner: Corner, ink: UIColor, opacity: CGFloat = 0.85, inset: CGFloat = 44, dateSuffix: Date? = nil, shadow: Bool = true) {
        var text = "EVENTSNAP"
        if let dateSuffix { text += "  ·  " + dateStringShort(dateSuffix) }
        let font = bebasNeue(size: 26)
        let textWidth = trackedWidth(text, font: font, tracking: 3)
        let dotDiameter: CGFloat = 9
        let dotGap: CGFloat = 9
        let height = max(font.ascender - font.descender, dotDiameter)
        let totalWidth = dotDiameter + dotGap + textWidth

        let originX: CGFloat
        let y: CGFloat
        switch corner {
        case .topLeading: originX = inset; y = inset
        case .topTrailing: originX = canvasSize.width - inset - totalWidth; y = inset
        case .bottomLeading: originX = inset; y = canvasSize.height - inset - height
        case .bottomTrailing: originX = canvasSize.width - inset - totalWidth; y = canvasSize.height - inset - height
        }

        let dotRect = CGRect(x: originX, y: y + (height - dotDiameter) / 2, width: dotDiameter, height: dotDiameter)
        cg.saveGState()
        cg.setAlpha(opacity)
        drawBrandChip(cg: cg, rect: dotRect, cornerRadius: dotDiameter / 2)
        cg.restoreGState()

        drawTracked(text, at: CGPoint(x: originX + dotDiameter + dotGap, y: y), font: font, color: ink.withAlphaComponent(opacity), tracking: 3, shadow: shadow)
    }

    // MARK: EventSnapビジュアル言語(ブランドグラデーション・タグ・デコ)

    /// アプリアイコンから採ったEventSnap固有のグラデーション。大きなロゴとしてではなく、
    /// 小さなドット・チップ・タグ・テープとして使うことで「広告」ではなく
    /// 「EventSnapらしい装飾」として機能させる（大きく“EVENTSNAP”と書かない代わりに、
    /// この色そのものをブランドの手がかりにする）。
    static let brandGradientStart = UIColor(red: 0.42, green: 0.55, blue: 0.96, alpha: 1)
    static let brandGradientEnd = UIColor(red: 0.92, green: 0.44, blue: 0.72, alpha: 1)

    private static func brandGradient() -> CGGradient? {
        CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [brandGradientStart.cgColor, brandGradientEnd.cgColor] as CFArray,
            locations: [0, 1]
        )
    }

    /// ブランドグラデーションで塗りつぶした角丸チップ。ドット・塗りタグに使う。
    static func drawBrandChip(cg: CGContext, rect: CGRect, cornerRadius: CGFloat) {
        guard let gradient = brandGradient() else { return }
        cg.saveGState()
        cg.addPath(UIBezierPath(roundedRect: rect, cornerRadius: cornerRadius).cgPath)
        cg.clip()
        cg.drawLinearGradient(gradient, start: CGPoint(x: rect.minX, y: rect.minY), end: CGPoint(x: rect.maxX, y: rect.maxY), options: [])
        cg.restoreGState()
    }

    private static func pillTagFont() -> UIFont { bebasNeue(size: 20) }

    private static func pillTagSize(_ text: String) -> CGSize {
        let font = pillTagFont()
        let textWidth = trackedWidth(text, font: font, tracking: 2)
        let paddingH: CGFloat = 14
        let paddingV: CGFloat = 7
        return CGSize(width: textWidth + paddingH * 2, height: (font.ascender - font.descender) + paddingV * 2)
    }

    /// 小さな丸ピル型のタグ("SNAP 03" や日付など)。`filled: true` はブランド
    /// グラデーション塗り（Boldのステッカー用）、`false` は輪郭のみ
    /// （Editorial/Minimalの控えめな添え物用）。
    @discardableResult
    static func drawPillTag(cg: CGContext, at point: CGPoint, text: String, ink: UIColor, filled: Bool) -> CGSize {
        let font = pillTagFont()
        let paddingH: CGFloat = 14
        let size = pillTagSize(text)
        let rect = CGRect(origin: point, size: size)
        let cornerRadius = size.height / 2

        cg.saveGState()
        if filled {
            drawBrandChip(cg: cg, rect: rect, cornerRadius: cornerRadius)
        } else {
            let path = UIBezierPath(roundedRect: rect, cornerRadius: cornerRadius).cgPath
            cg.addPath(path)
            cg.setFillColor(ink.withAlphaComponent(0.1).cgColor)
            cg.fillPath()
            cg.addPath(path)
            cg.setStrokeColor(ink.withAlphaComponent(0.75).cgColor)
            cg.setLineWidth(1.4)
            cg.strokePath()
        }
        cg.restoreGState()

        let textColor: UIColor = filled ? .white : ink.withAlphaComponent(0.92)
        let textY = rect.minY + (size.height - (font.ascender - font.descender)) / 2
        drawTracked(text, at: CGPoint(x: rect.minX + paddingH, y: textY), font: font, color: textColor, tracking: 2, shadow: false)
        return size
    }

    static func snapTagText(_ index: Int) -> String { "SNAP \(String(format: "%02d", max(index, 1)))" }

    @discardableResult
    static func drawSnapTag(cg: CGContext, at point: CGPoint, index: Int, ink: UIColor, filled: Bool) -> CGSize {
        drawPillTag(cg: cg, at: point, text: snapTagText(index), ink: ink, filled: filled)
    }

    @discardableResult
    static func drawDateTag(cg: CGContext, at point: CGPoint, date: Date, ink: UIColor, filled: Bool) -> CGSize {
        drawPillTag(cg: cg, at: point, text: dateStringShort(date), ink: ink, filled: filled)
    }

    static func snapTagSize(index: Int) -> CGSize { pillTagSize(snapTagText(index)) }
    static func dateTagSize(date: Date) -> CGSize { pillTagSize(dateStringShort(date)) }

    /// マスキングテープのような、半透明の小さな帯。SNAP/日付タグの近くに
    /// 少しだけ回転させて重ねることで、チェキ・スクラップブック的な「手で
    /// 留めた」手作り感を足す（写真そのものには重ねず、タグの周辺だけに使う）。
    static func drawTapeAccent(cg: CGContext, center: CGPoint, width: CGFloat, height: CGFloat, rotation: CGFloat, tint: UIColor) {
        cg.saveGState()
        cg.translateBy(x: center.x, y: center.y)
        cg.rotate(by: rotation)
        let rect = CGRect(x: -width / 2, y: -height / 2, width: width, height: height)
        cg.addPath(UIBezierPath(roundedRect: rect, cornerRadius: 2).cgPath)
        cg.setFillColor(tint.withAlphaComponent(0.5).cgColor)
        cg.fillPath()
        cg.restoreGState()
    }

    /// Editorial用の「思い出クラスター」: SNAP番号タグ＋日付タグを、テープ留め風の
    /// 小さな装飾と一緒に指定ゾーンの開始端に置く。単なる添え文字ではなく
    /// 「チェキに手書きで書き足したような」ひとかたまりの装飾として機能させる。
    static func drawMemoryCluster(
        cg: CGContext, canvasSize: CGSize, zone: SafeZone,
        date: Date, momentIndex: Int, ink: UIColor, accent: UIColor, inset: CGFloat
    ) {
        let snapSize = snapTagSize(index: momentIndex)
        let dateSize = dateTagSize(date: date)
        let gap: CGFloat = 8
        let totalWidth = snapSize.width + gap + dateSize.width
        let clusterHeight = max(snapSize.height, dateSize.height)

        let x: CGFloat
        let y: CGFloat
        switch zone {
        case .top: x = inset; y = inset
        case .bottom: x = inset; y = canvasSize.height - inset - clusterHeight
        case .left: x = inset; y = inset
        case .right: x = canvasSize.width - inset - totalWidth; y = inset
        }

        drawTapeAccent(cg: cg, center: CGPoint(x: x + 16, y: y - 7), width: 36, height: 15, rotation: -0.3, tint: accent)
        drawSnapTag(cg: cg, at: CGPoint(x: x, y: y), index: momentIndex, ink: ink, filled: false)
        drawDateTag(cg: cg, at: CGPoint(x: x + snapSize.width + gap, y: y), date: date, ink: ink, filled: false)
    }

    /// ポスターの端に沿わせる、縦書き風に90度回転させたSNAP番号のブランド
    /// グラデーション・ステッカー。以前はプレーンな文字だけだったが、グラデーションで
    /// 塗ることで「EventSnapのステッカーが貼られている」ように見せる。
    ///
    /// CTMをそのまま回転させて縁の近くの原点から描くと、回転方向によっては
    /// タグの長辺が画面外へはみ出しうる（原点から縁までの距離がタグの長さより
    /// 短いため）。そのため先に回転済みの1枚の画像として描画してから、
    /// 画面内に収まることが明らかな矩形へ配置する。
    static func drawRotatedSnapSticker(cg: CGContext, canvasSize: CGSize, momentIndex: Int, onRight: Bool) {
        let tagSize = snapTagSize(index: momentIndex)
        let rotatedSize = CGSize(width: tagSize.height, height: tagSize.width)
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false
        format.scale = 1
        let rotatedImage = UIGraphicsImageRenderer(size: rotatedSize, format: format).image { ctx in
            let rcg = ctx.cgContext
            rcg.translateBy(x: rotatedSize.width / 2, y: rotatedSize.height / 2)
            rcg.rotate(by: -.pi / 2)
            rcg.translateBy(x: -tagSize.width / 2, y: -tagSize.height / 2)
            drawSnapTag(cg: rcg, at: .zero, index: momentIndex, ink: .white, filled: true)
        }

        let rect: CGRect = onRight
            ? CGRect(x: canvasSize.width - 40 - rotatedSize.width, y: canvasSize.height - 64 - rotatedSize.height, width: rotatedSize.width, height: rotatedSize.height)
            : CGRect(x: 40, y: 64, width: rotatedSize.width, height: rotatedSize.height)
        rotatedImage.draw(in: rect)
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

    enum GhostAnchor { case center, leading, trailing }

    /// タイトルの後ろに沈める、日付などの巨大なゴースト数字。Boldの「数字を背景要素にする」用。
    /// 指定した矩形の幅いっぱいに広がるサイズを、基準サイズでの実測幅から比例計算で求める
    /// （Bebas Neueは文字幅がフォントサイズにほぼ線形に比例するため、1回の実測で求まる）。
    ///
    /// 以前は常にゾーン中央に置いていたが、それだとタイトルにも被写体にも
    /// 被りやすい。`anchor`でタイトルと反対側の端へ寄せ、「余白から数字が
    /// はみ出す」レイアウトを取れるようにして、写真を覆う面積を減らす。
    static func drawGhostNumber(_ text: String, in rect: CGRect, ink: UIColor, anchor: GhostAnchor = .center, widthRatio: CGFloat = 0.92, opacity: CGFloat = 0.14) {
        let referenceSize: CGFloat = 300
        let referenceFont = bebasNeue(size: referenceSize)
        let referenceWidth = (text as NSString).size(withAttributes: [.font: referenceFont]).width
        guard referenceWidth > 0 else { return }

        let targetWidth = rect.width * widthRatio
        let fontSize = referenceSize * (targetWidth / referenceWidth)
        let font = bebasNeue(size: fontSize)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: ink.withAlphaComponent(opacity)]
        let size = (text as NSString).size(withAttributes: attrs)

        let x: CGFloat
        switch anchor {
        case .center: x = rect.midX - size.width / 2
        case .leading: x = rect.minX - size.width * 0.06
        case .trailing: x = rect.maxX - size.width * 0.94
        }
        let point = CGPoint(x: x, y: rect.midY - size.height / 2)
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

    static func drawTracked(_ text: String, at point: CGPoint, font: UIFont, color: UIColor, tracking: CGFloat, shadow: Bool = true) {
        var x = point.x
        var attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        if shadow { attrs[.shadow] = textShadow(strength: 0.7) }
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

    /// タグ用の短い日付表記("8.17"のような月.日のみ)。小さなピルタグの中では
    /// フルの年号入りだと窮屈になるため専用フォーマットにする。
    static func dateStringShort(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "M.d"
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

// MARK: - Preview (GridPhotoDumpRenderer動作確認用)

/// 単色のプレースホルダー画像を敷き詰めるだけの簡易プレビュー。
/// 実際の写真素材が無くても、2/4/6/8枚それぞれのグリッド構成・文字の
/// 中央配置・ブランドマークの見た目をXcode Canvasで確認できる。
#Preview("GridPhotoDump - 4枚") {
    GridPhotoDumpPreview(count: 4, eventName: "文化祭2026", colors: [.systemRed, .systemBlue, .systemGreen, .systemOrange])
}

#Preview("GridPhotoDump - 6枚") {
    GridPhotoDumpPreview(
        count: 6,
        eventName: "サマーキャンプ",
        colors: [.systemRed, .systemBlue, .systemGreen, .systemOrange, .systemPurple, .systemTeal]
    )
}

#Preview("GridPhotoDump - 3枚(端数、最後の写真で埋める)") {
    GridPhotoDumpPreview(count: 3, eventName: "同窓会2026", colors: [.systemRed, .systemBlue, .systemGreen])
}

private struct GridPhotoDumpPreview: View {
    let count: Int
    let eventName: String
    let colors: [UIColor]

    var body: some View {
        Image(uiImage: renderedImage)
            .resizable()
            .aspectRatio(contentMode: .fit)
    }

    private var renderedImage: UIImage {
        let inputs = colors.prefix(count).map { color -> MultiPhotoRenderer.PhotoInput in
            let placeholder = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 600)).image { _ in
                color.setFill()
                UIRectFill(CGRect(x: 0, y: 0, width: 400, height: 600))
            }
            return MultiPhotoRenderer.PhotoInput(image: placeholder, importanceCenter: CGPoint(x: 0.5, y: 0.5))
        }

        return SocialCardService.renderGridPhotoDump(
            photos: Array(inputs),
            eventName: eventName,
            date: Date()
        )
    }
}
