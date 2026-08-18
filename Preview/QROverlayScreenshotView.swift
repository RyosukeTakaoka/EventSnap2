//
//  QROverlayScreenshotView.swift
//  EventSnap
//
//  ⑥ 招待+読み取りの合成カット（`.inviteOverlay`）専用View。
//

#if DEBUG

import SwiftUI

/// QRコードを表示している画面の上に、それを読み取っているカメラの
/// ファインダー風画面を斜めに重ねた合成カット。
///
/// 下レイヤーは本番の`QRCodeView`をそのまま使う（マーケティング用に
/// 似せた別Viewは作らない）。上レイヤーの「読み取り中」画面だけは
/// `QRScannerView`と同じガイド表示を`QRScanFinderView`として簡潔に
/// 再現し、撮影モードのときだけ`preview-qrscan-bg.jpg`を背景に敷く
/// （実機のAVCaptureSessionは撮影モードでは動かせないため）。
struct QROverlayScreenshotView: View {

    init() {
        // `install`はEventRepository.sharedの@Publishedプロパティを書き換える。
        // このViewはHomeView.bodyの分岐に直接埋め込まれているため、無条件に
        // 呼ぶとEventRepositoryの変更→HomeView再描画→この`init`が再度走る…
        // という無限ループになる（`ScreenshotMode.isActive`側のアプリ起動経路では
        // `EventSnapApp.init()`が既に`installIfNeeded()`で1回注入済みなので、
        // ここでの再注入は不要）。SwiftUI Previewから直接使う場合だけ、
        // ここで初回の注入を行う。
        if !PreviewFixtureLoader.isInstalled {
            PreviewFixtureLoader.install(scene: .inviteOverlay)
        }
    }

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            PhoneFrameView {
                QRCodeView(eventViewModel: EventViewModel())
            }
            .rotationEffect(.degrees(-9))
            .offset(x: -55, y: 30)

            PhoneFrameView {
                QRScanFinderView()
            }
            .rotationEffect(.degrees(9))
            .offset(x: 65, y: -30)
        }
    }
}

/// 招待画面の上に重ねる、QR読み取り中のファインダー風画面。
///
/// `QRScannerView.scanner`と同じガイド枠・文言を使い、実際のUIから
/// 大きく外れないようにする。カメラ映像そのものは撮影モードでしか
/// 使わないため、通常時は単色で塗りつぶすだけに留める。
private struct QRScanFinderView: View {
    var body: some View {
        ZStack {
            if let background = ScreenshotMode.qrScanBackgroundImage {
                Image(uiImage: background)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Color.black
            }

            VStack {
                Spacer()

                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.white, lineWidth: 3)
                    .frame(width: 150, height: 150)

                Spacer()

                Text("QRコードをフレーム内に収めてください")
                    .font(.caption)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(10)
                    .padding(.bottom, 24)
                    .padding(.horizontal, 16)
            }
        }
        .clipped()
    }
}

/// 2つの画面をiPhone風の枠に収める、合成カット用の簡易フレーム。
private struct PhoneFrameView<Content: View>: View {
    private let content: Content
    private let size = CGSize(width: 220, height: 460)

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: 36, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 36, style: .continuous)
                    .stroke(Color.black, lineWidth: 10)
            )
            .shadow(color: .black.opacity(0.25), radius: 18, x: 0, y: 10)
    }
}

#endif
