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
///
/// 以前は1枚の黒背景に`clipShape`（`SpotlightHoleShape` + 偶奇塗りつぶし）で
/// 穴をくり抜いていたが、SwiftUIの`clipShape`は見た目上の描画を切り抜くだけで、
/// ヒットテストはクリップ前の元の矩形全体に対して行われる。そのため穴の内側は
/// 視覚的に「何もない」ように見えても、実際にはその位置にも黒いオーバーレイの
/// 透明な当たり判定が残ってしまい、下にある本物のUI（シャッターボタン等）への
/// タップを吸収して反応しなくなっていた。
///
/// 「穴を含む1枚をくり抜く」のではなく、「穴の四辺を、穴を含まない4枚（上下左右）
/// の黒い矩形で囲む」方式に変更する。この方式なら穴の位置には物理的に
/// どのビューも存在しないため、ヒットテストの問題がそもそも起こらない。
private struct SpotlightMask: View {
    let rect: CGRect
    let fullSize: CGSize
    let dimColor = Color.black.opacity(0.62)

    var body: some View {
        if rect == .zero {
            dimColor.ignoresSafeArea()
        } else {
            // 4枚とも`.position(x:y:)`で絶対座標に直接配置する。
            // `.frame(alignment:)`によるZStack内での暗黙の位置合わせに頼ると、
            // `maxHeight`を同時に指定しない限り期待通りに端へ寄らない
            // （高さがcontentの自然なサイズのままZStackの既定alignment(.center)で
            // 中央に置かれてしまう）ため、既存の白枠線と同じ`.position`方式に揃える。
            ZStack {
                // 上（穴の上端まで、幅いっぱい）
                let topHeight = max(rect.minY, 0)
                dimColor
                    .frame(width: fullSize.width, height: topHeight)
                    .position(x: fullSize.width / 2, y: topHeight / 2)

                // 下（穴の下端から画面下まで、幅いっぱい）
                let bottomHeight = max(fullSize.height - rect.maxY, 0)
                dimColor
                    .frame(width: fullSize.width, height: bottomHeight)
                    .position(x: fullSize.width / 2, y: rect.maxY + bottomHeight / 2)

                // 左（穴の高さの範囲だけ、穴の左端まで）
                let leftWidth = max(rect.minX, 0)
                dimColor
                    .frame(width: leftWidth, height: rect.height)
                    .position(x: leftWidth / 2, y: rect.midY)

                // 右（穴の高さの範囲だけ、穴の右端から画面右まで）
                let rightWidth = max(fullSize.width - rect.maxX, 0)
                dimColor
                    .frame(width: rightWidth, height: rect.height)
                    .position(x: rect.maxX + rightWidth / 2, y: rect.midY)
            }
            .ignoresSafeArea()
        }
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
                SpotlightMask(rect: rect, fullSize: proxy.size)

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
