//
//  PrimaryButtonStyle.swift
//  EventSnap
//
//  HomeViewの主要ボタン(白背景+青文字)を他画面でも揃って使うための共通スタイル。
//

import SwiftUI

/// 白背景・青文字の主要アクションボタン。
/// HomeViewの「新しいイベントを作成」と、EventCreationSheetの「作成する」で
/// 見た目が食い違わないよう、スタイルとして共通化している。
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .fontWeight(.semibold)
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.white)
            .foregroundColor(.blue)
            .cornerRadius(16)
            // HomeViewの濃いグラデーションの上では不要だが、薄い背景の画面
            // (EventCreationSheetなど)では白背景のボタンが背景に溶けて輪郭が
            // 分からなくなるため、常に薄い影で境界をつけておく。
            .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}
