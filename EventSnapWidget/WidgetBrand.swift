//
//  WidgetBrand.swift
//  EventSnapWidget
//
//  SocialCardServiceのビジュアル言語(ブランドグラデーション・オフホワイト・余白)を
//  Widget/Live Activity側でも共有するための、最小限の色定義。
//
//  SocialCardService本体(Core Graphics製の描画エンジン)はメインアプリだけの
//  重い処理なのでこのターゲットには含めない。Widgetは「無加工写真+控えめな
//  ブランド装飾」という思想だけを、ネイティブSwiftUIの色として引き継ぐ。
//

import SwiftUI

enum WidgetBrand {
    static let gradientStart = Color(red: 0.42, green: 0.55, blue: 0.96)
    static let gradientEnd = Color(red: 0.92, green: 0.44, blue: 0.72)
    static let background = Color(red: 0.98, green: 0.965, blue: 0.945)
    static let ink = Color(red: 0.1, green: 0.1, blue: 0.1)

    static var gradient: LinearGradient {
        LinearGradient(colors: [gradientStart, gradientEnd], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// 「EVENTSNAP」の小さなワードマーク。広告的にならないよう、常に控えめなサイズで使う。
    static func brandMark(dotSize: CGFloat = 6) -> some View {
        HStack(spacing: 5) {
            Circle().fill(gradient).frame(width: dotSize, height: dotSize)
            Text("EVENTSNAP")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .tracking(1)
                .foregroundStyle(.secondary)
        }
    }
}
