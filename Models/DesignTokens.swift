//
//  DesignTokens.swift
//  EventSnap
//
//  アプリ全体で共有する色・角丸・フォントの定義。
//  既存のWidgetBrand（Widget/Live Activity側）と同じ値を土台にし、
//  アプリ本体とWidget/Event Reelの見た目を統一する。
//
//  方針（2026年UIトレンド準拠）:
//  - グラデーションは「特別な場所」だけに絞る（Event Reel、タイムカプセル開封、
//    HomeViewの中央ファインダー枠など）。通常のボタン・背景は単色(primary)を使う。
//  - 彩度はフル彩度ではなく、WidgetBrandと同程度の落ち着いたトーンを維持する。
//

import SwiftUI

enum DesignTokens {

    // MARK: - メインカラー（WidgetBrandと同一値。Widget/Event Reelとの統一のため）
    static let primary = Color(red: 0.42, green: 0.55, blue: 0.96)   // 青紫
    static let secondary = Color(red: 0.92, green: 0.44, blue: 0.72) // ピンク

    /// 特別な演出（HomeView中央ファインダー、Event Reel等）専用。
    /// 通常のボタンやトグルには使わない。
    static let accentGradient = LinearGradient(
        colors: [primary, secondary], startPoint: .topLeading, endPoint: .bottomTrailing
    )

    // MARK: - タイムカプセル（ゴールド系）
    static let capsuleGold = Color(red: 0.83, green: 0.68, blue: 0.21)
    static let capsuleGoldLight = Color(red: 0.96, green: 0.87, blue: 0.55)

    /// タイムカプセルの未公開セル・「あとで公開」トグル専用グラデーション。
    static let capsuleGradient = LinearGradient(
        colors: [capsuleGoldLight, capsuleGold], startPoint: .topLeading, endPoint: .bottomTrailing
    )

    // MARK: - 背景・ベース（WidgetBrandと同一値）
    static let background = Color(red: 0.98, green: 0.965, blue: 0.945)
    static let ink = Color(red: 0.1, green: 0.1, blue: 0.1)

    // MARK: - 角丸
    static let cornerRadiusSmall: CGFloat = 12
    static let cornerRadiusMedium: CGFloat = 20
    static let cornerRadiusLarge: CGFloat = 28

    // MARK: - フォント（既存バンドル済みフォントを活用）
    static func heading(_ size: CGFloat) -> Font {
        .custom("NotoSansJP-Black", size: size)
    }
}
