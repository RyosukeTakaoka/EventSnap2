//
//  SocialCardShareView.swift
//  EventSnap
//
//  SNSシェア画像を「見る→デザインを選ぶ→シェアする」で完結させる画面
//

import SwiftUI

/// Event Reelの完成画像を大きく表示し、そのままシェアできる画面。
///
/// `reel.photoIDs.count`に関わらず、`MultiPhotoRenderer`が自動編集した画像は
/// `ShareCollageStore`に完成品として保存済みのため、常にそれを読み込んで
/// 見せるだけにする（デザインを選び直す余地は無い。EventSnapが「どの写真を選び、
/// どう並べるか」まで決め切っている）。
///
/// 以前は写真1枚だけのReel向けに、Editorial/Bold/Minimalをその場で選び直せる
/// 旧バージョンのUIを後方互換として残していたが、「序盤は間引き後1枚でも
/// Event Reelを即座に成立させる」仕様（`ShareCollageBuilder`）により
/// 1枚だけのReelが通常運用でも生成されるようになった結果、サムネイル
/// （完成画像）と旧UIで選び直した後のプレビューが食い違う問題を招いていた。
/// 表示経路を一本化し、そのような食い違いが起こらないようにする。
struct SocialCardShareView: View {
    let event: Event
    let reel: EventReel

    @State private var renderedImage: UIImage?
    @State private var shareFileURL: URL?
    @State private var isLoading = true
    @State private var loadFailed = false

    var body: some View {
        VStack(spacing: 0) {
            imageArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            shareButton
                .padding(.horizontal)
                .padding(.top, 14)
                .padding(.bottom, 10)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("シェア画像")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            loadMultiPhotoImage()
        }
    }

    /// 複数写真Reelは`ShareCollageBuilder`がすでに完成画像として保存済みのため、
    /// 読み込むだけでよい（再解析・再描画はしない）。
    private func loadMultiPhotoImage() {
        guard let image = ShareCollageStore.shared.image(for: reel) else {
            isLoading = false
            loadFailed = true
            return
        }
        renderedImage = image
        shareFileURL = Self.writeTempFile(image)
        isLoading = false
    }

    // MARK: - 画像表示エリア

    @ViewBuilder
    private var imageArea: some View {
        if let renderedImage {
            Image(uiImage: renderedImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .padding(.horizontal, 4)
                .padding(.top, 8)
        } else if loadFailed {
            VStack(spacing: 14) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 44))
                    .foregroundColor(.secondary)
                Text("画像を作成できませんでした")
                    .foregroundColor(.secondary)
            }
        } else {
            ProgressView()
        }
    }

    // MARK: - シェアボタン

    @ViewBuilder
    private var shareButton: some View {
        if let shareFileURL, let renderedImage {
            ShareLink(
                item: shareFileURL,
                preview: SharePreview("\(event.name) の思い出", image: Image(uiImage: renderedImage))
            ) {
                Label("シェアする", systemImage: "square.and.arrow.up")
                    .fontWeight(.semibold)
            }
            .buttonStyle(.primary)
            // ShareLink自体に完了コールバックが無いため、タップの事実だけを計測する。
            .simultaneousGesture(TapGesture().onEnded {
                AnalyticsService.eventReelShareTapped(photoCount: reel.photoIDs.count)
            })
        } else {
            Button {} label: {
                Label("シェアする", systemImage: "square.and.arrow.up")
                    .fontWeight(.semibold)
            }
            .buttonStyle(.primary)
            .disabled(true)
            .opacity(0.4)
        }
    }

    // MARK: - 読み込み

    /// ShareLinkに渡すための一時ファイル。ShareCollageStoreの永続保存とは別物で、
    /// この画面を離れれば不要になるものなのでtemporaryDirectoryに書き出すだけにしている。
    private static func writeTempFile(_ image: UIImage) -> URL? {
        guard let data = image.jpegData(compressionQuality: 0.92) else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("SocialCard-\(UUID().uuidString).jpg")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            print("❌ シェア用一時ファイルの書き出しに失敗: \(error)")
            return nil
        }
    }
}
