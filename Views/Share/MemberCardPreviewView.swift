//
//  MemberCardPreviewView.swift
//  EventSnap
//
//  MemberCardServiceの見た目をXcodeのプレビュー/シミュレータだけで
//  すぐ確認できるようにした検証用画面。
//

import SwiftUI

/// `MemberCardService` の出力を確認するためだけの画面。
///
/// **本編のナビゲーションには一切組み込んでいない**。Xcodeでこのファイルを開き、
/// プレビューキャンバス（もしくはこのViewを一時的に呼び出したシミュレータ実行）で
/// デザイン案を見るための、動作確認専用のコードである。
struct MemberCardPreviewView: View {
    @State private var eventName = "文化祭2026"
    @State private var memberIndex = 3
    @State private var memberTotal = 9

    private var cardImage: UIImage {
        MemberCardService.makeCard(
            from: Self.samplePhoto,
            eventName: eventName,
            date: Date(),
            memberIndex: memberIndex,
            memberTotal: memberTotal
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(uiImage: cardImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .cornerRadius(20)
                    .shadow(color: .black.opacity(0.15), radius: 16, y: 6)
                    .padding(.horizontal)

                // 確認用の簡易コントロール。実装後は不要になるが、
                // 文字量や参加人数による見え方の違いをその場で試せるようにしている。
                VStack(alignment: .leading, spacing: 14) {
                    TextField("イベント名", text: $eventName)
                        .textFieldStyle(.roundedBorder)

                    Stepper("あなたの順番: \(memberIndex)", value: $memberIndex, in: 1...memberTotal)
                    Stepper("参加者総数: \(memberTotal)", value: $memberTotal, in: memberIndex...999)
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .navigationTitle("Member Card（検証用）")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// 実写真の代わりに使う、確認用のダミー画像
    private static let samplePhoto: UIImage = {
        let size = CGSize(width: 1200, height: 1500)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let cg = ctx.cgContext
            if let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [
                    UIColor(red: 0.98, green: 0.78, blue: 0.55, alpha: 1).cgColor,
                    UIColor(red: 0.93, green: 0.47, blue: 0.55, alpha: 1).cgColor,
                    UIColor(red: 0.42, green: 0.47, blue: 0.86, alpha: 1).cgColor,
                ] as CFArray,
                locations: [0, 0.55, 1]
            ) {
                cg.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: 0, y: 0),
                    end: CGPoint(x: size.width, y: size.height),
                    options: []
                )
            }
        }
    }()
}

#Preview {
    NavigationView {
        MemberCardPreviewView()
    }
}
