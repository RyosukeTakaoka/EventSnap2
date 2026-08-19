//
//  TutorialOverlay.swift
//  EventSnap
//
//  初回チュートリアルの「実際のUIをハイライトする」オーバーレイ。
//
//  対象のビューには`.tutorialTarget(_:)`を付けるだけでよい。本物のCameraView/
//  AlbumViewの部品にタグ付けするだけなので、チュートリアル専用の偽物ビューは
//  一切増えない。タグの実測フレームは`anchorPreference`で親まで伝わり、
//  ここでハイライトの穴を切り抜く。
//

import SwiftUI

/// チュートリアルでハイライトできる、実際のUI上の対象。
enum TutorialTarget: Hashable {
    case shutter
    case shareOK
    case laterReveal
    case albumGrid
    case lockedPhoto
}

/// タグ付けされたビューの実測フレームを集める`PreferenceKey`。
struct TutorialAnchorKey: PreferenceKey {
    static var defaultValue: [TutorialTarget: Anchor<CGRect>] = [:]

    static func reduce(
        value: inout [TutorialTarget: Anchor<CGRect>],
        nextValue: () -> [TutorialTarget: Anchor<CGRect>]
    ) {
        value.merge(nextValue()) { _, new in new }
    }
}

extension View {
    /// このビューを、チュートリアルのスポットライト対象として登録する。
    func tutorialTarget(_ target: TutorialTarget) -> some View {
        anchorPreference(key: TutorialAnchorKey.self, value: .bounds) { anchor in
            [target: anchor]
        }
    }

    /// `isActive`のときだけ`tutorialTarget(_:)`を付ける。
    /// （例: アルバムのグリッドで「最初の1枚だけ」をハイライト対象にしたい場合）
    @ViewBuilder
    func tutorialTarget(_ target: TutorialTarget, isActive: Bool) -> some View {
        if isActive {
            tutorialTarget(target)
        } else {
            self
        }
    }
}

/// 全画面を覆うが、ハイライト対象の矩形だけ穴が空いた形。
/// `clipShape`に使うことで、穴の内側は本物のUIがそのままタップできる
/// （見た目をぼかすだけの`.mask`と違い、穴の部分は当たり判定も素通しになる）。
private struct SpotlightHoleShape: Shape {
    var rect: CGRect
    var cornerRadius: CGFloat

    func path(in bounds: CGRect) -> Path {
        var path = Path(bounds)
        if rect != .zero {
            path.addPath(Path(roundedRect: rect, cornerRadius: cornerRadius))
        }
        return path
    }
}

/// 実際のUIの上に重ねる、チュートリアルのスポットライト演出。
///
/// 対象UIの周りだけ明るく残し、それ以外を暗くする。派手な演出はせず、
/// 「ここを触ればいい」と分かる程度の軽いアニメーションに留める。
struct TutorialSpotlightOverlay: View {
    @ObservedObject var manager: TutorialManager
    let anchors: [TutorialTarget: Anchor<CGRect>]
    let target: TutorialTarget?
    let title: String
    let message: String
    let actionLabel: String?
    var onAdvance: () -> Void = {}

    var body: some View {
        GeometryReader { proxy in
            let rect = spotlightRect(in: proxy)

            ZStack {
                Color.black.opacity(0.62)
                    .clipShape(SpotlightHoleShape(rect: rect, cornerRadius: 18), style: FillStyle(eoFill: true))
                    .ignoresSafeArea()

                if rect != .zero {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white, lineWidth: 2)
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                        .allowsHitTesting(false)
                }

                calloutCard
                    .position(calloutPosition(for: rect, in: proxy.size))

                VStack {
                    HStack {
                        Spacer()
                        skipButton
                    }
                    Spacer()
                }
                .padding(.top, 8)
                .padding(.trailing, 16)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: target)
        .transition(.opacity)
    }

    private func spotlightRect(in proxy: GeometryProxy) -> CGRect {
        guard let target, let anchor = anchors[target] else { return .zero }
        return proxy[anchor].insetBy(dx: -10, dy: -10)
    }

    private var skipButton: some View {
        Button("スキップ") { manager.skip() }
            .font(.footnote.weight(.semibold))
            .foregroundColor(.white.opacity(0.9))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.45), in: Capsule())
    }

    private var calloutCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.bold))
            Text(message)
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)

            if let actionLabel {
                Button(actionLabel) { onAdvance() }
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Color.white, in: Capsule())
                    .foregroundColor(.black)
                    .padding(.top, 2)
            }
        }
        .foregroundColor(.white)
        .padding(14)
        .frame(maxWidth: 260, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .environment(\.colorScheme, .dark)
    }

    private func calloutPosition(for rect: CGRect, in size: CGSize) -> CGPoint {
        guard rect != .zero else {
            return CGPoint(x: size.width / 2, y: size.height / 2)
        }
        let x = min(max(rect.midX, 140), max(size.width - 140, 140))
        let preferAbove = rect.midY > size.height * 0.55
        let y = preferAbove ? max(rect.minY - 90, 100) : min(rect.maxY + 100, size.height - 80)
        return CGPoint(x: x, y: y)
    }
}

/// アンカー対象がない案内（例: 「アルバムタブを開いてみよう」）用の、
/// タブバーの上に添える小さな吹き出し。スポットライトほど大掛かりにせず、
/// 下向きの矢印だけで「ここ」を示す。
struct TutorialBottomHint: View {
    let text: String

    var body: some View {
        VStack {
            Spacer()
            HStack(spacing: 6) {
                Text(text)
                    .font(.subheadline.weight(.semibold))
                Image(systemName: "arrow.down")
            }
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.black.opacity(0.75), in: Capsule())
            .padding(.bottom, 6)
        }
        .allowsHitTesting(false)
        .transition(.opacity)
    }
}
