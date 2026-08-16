//
//  SocialCardShareView.swift
//  EventSnap
//
//  SNSシェア画像を「見る→デザインを選ぶ→シェアする」で完結させる画面
//

import SwiftUI

/// Event Reelの代表写真を大きく表示し、Editorial/Bold/Minimalをワンタップで
/// 切り替えながらそのままシェアできる画面。
///
/// **体験の軸**: 常に1枚の完成画像を大きく表示する。3枚を並べて比較させることは
/// しない。写真解析（`PhotoAnalyzer`）はこの画面が開いたときに1回だけ行い、
/// テンプレートを切り替えるたびに再解析はしない（`SocialCardService.render`は
/// 軽い描画処理のみ）。
///
/// デザインを選ぶことは必須ではない。既定のテンプレートで即シェアできる。
struct SocialCardShareView: View {
    let event: Event
    let reel: EventReel

    @State private var heroPhoto: Photo?
    @State private var heroImage: UIImage?
    @State private var analysis: PhotoAnalysisResult?
    @State private var template: SocialCardTemplate = SocialCardService.defaultTemplate
    @State private var renderedImage: UIImage?
    @State private var shareFileURL: URL?
    @State private var isLoading = true
    @State private var loadFailed = false

    var body: some View {
        VStack(spacing: 0) {
            imageArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if analysis != nil {
                Picker("デザイン", selection: $template) {
                    ForEach(SocialCardTemplate.allCases) { t in
                        Text(t.displayName).tag(t)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 14)
            }

            shareButton
                .padding(.horizontal)
                .padding(.top, 14)
                .padding(.bottom, 10)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("シェア画像")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadAndAnalyze() }
        .onChange(of: template) { _, newValue in
            rerender(for: newValue)
        }
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

    // MARK: - 読み込み・解析・描画

    private func loadAndAnalyze() async {
        guard let hero = await ShareCollageBuilder.heroPhoto(for: reel) else {
            isLoading = false
            loadFailed = true
            return
        }
        heroPhoto = hero.photo
        heroImage = hero.image
        // Vision解析はここで1回だけ。テンプレート切り替え時はこの結果を使い回す。
        analysis = SocialCardService.analyze(hero.image)
        isLoading = false
        rerender(for: template)
    }

    private func rerender(for template: SocialCardTemplate) {
        guard let heroPhoto, let heroImage, let analysis else { return }
        let moment = ShareCollageBuilder.momentInfo(for: heroPhoto, event: event)

        let image = SocialCardService.render(
            template: template,
            image: heroImage,
            analysis: analysis,
            eventName: event.name,
            date: heroPhoto.uploadedAt,
            momentIndex: moment.index,
            momentTotal: moment.total
        )
        renderedImage = image
        shareFileURL = Self.writeTempFile(image)
    }

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
