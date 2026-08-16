//
//  SocialCardPreviewView.swift
//  EventSnap
//
//  SocialCardServiceの出力(3テンプレート自動選択)をXcodeのプレビュー/
//  シミュレータだけですぐ確認できるようにした検証用画面。
//

import SwiftUI

/// `SocialCardService` の出力を確認するためだけの画面。
///
/// **本編のナビゲーションには一切組み込んでいない**。用意したサンプル写真は
/// 明るい/暗い/被写体が中央寄りの3パターンにしてあり、`TemplateSelector` が
/// 実際にどのテンプレートを選ぶかをこの場で確認できる。
struct SocialCardPreviewView: View {
    private enum SamplePhoto: String, CaseIterable, Identifiable {
        case brightScene = "明るい風景(Minimal想定)"
        case darkStage = "暗いステージ(Festival想定)"
        case portrait = "人物中心(Editorial想定)"

        var id: String { rawValue }
    }

    @State private var sample: SamplePhoto = .brightScene
    @State private var eventName = "文化祭2026"

    private var cardImage: UIImage {
        SocialCardService.makeCard(
            from: Self.image(for: sample),
            eventName: eventName,
            date: Date(),
            momentIndex: 3,
            momentTotal: 9
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(uiImage: cardImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(.horizontal)

                VStack(alignment: .leading, spacing: 14) {
                    Picker("サンプル写真", selection: $sample) {
                        ForEach(SamplePhoto.allCases) { s in
                            Text(s.rawValue).tag(s)
                        }
                    }
                    .pickerStyle(.segmented)

                    TextField("イベント名", text: $eventName)
                        .textFieldStyle(.roundedBorder)
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .navigationTitle("Social Card(検証用)")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - 確認用のダミー写真

    private static func image(for sample: SamplePhoto) -> UIImage {
        switch sample {
        case .brightScene: return gradientPhoto(colors: [
            UIColor(red: 0.75, green: 0.9, blue: 1.0, alpha: 1),
            UIColor(red: 0.95, green: 0.97, blue: 0.85, alpha: 1),
        ])
        case .darkStage: return gradientPhoto(colors: [
            UIColor(red: 0.05, green: 0.05, blue: 0.12, alpha: 1),
            UIColor(red: 0.25, green: 0.05, blue: 0.3, alpha: 1),
        ])
        case .portrait: return gradientPhoto(colors: [
            UIColor(red: 0.9, green: 0.75, blue: 0.6, alpha: 1),
            UIColor(red: 0.6, green: 0.4, blue: 0.35, alpha: 1),
        ], withCenterBlob: true)
        }
    }

    private static func gradientPhoto(colors: [UIColor], withCenterBlob: Bool = false) -> UIImage {
        let size = CGSize(width: 1200, height: 1500)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let cg = ctx.cgContext
            if let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors.map(\.cgColor) as CFArray,
                locations: nil
            ) {
                cg.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: 0, y: 0),
                    end: CGPoint(x: size.width, y: size.height),
                    options: []
                )
            }

            // 「人物」の代わりに、中央にそれらしい楕円を置いて被写体検出の動作確認をしやすくする
            if withCenterBlob {
                UIColor(white: 0.15, alpha: 0.85).setFill()
                let blob = CGRect(x: size.width * 0.32, y: size.height * 0.22, width: size.width * 0.36, height: size.height * 0.5)
                UIBezierPath(ovalIn: blob).fill()
            }
        }
    }
}

#Preview {
    NavigationView {
        SocialCardPreviewView()
    }
}
