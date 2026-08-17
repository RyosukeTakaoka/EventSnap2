//
//  SocialCardShareView.swift
//  EventSnap
//
//  SNSシェア画像を「見る→デザインを選ぶ→シェアする」で完結させる画面
//

import SwiftUI

/// Event Reelの完成画像を大きく表示し、そのままシェアできる画面。
///
/// **2種類のReelに対応する**:
/// - 複数写真Reel（`reel.photoIDs.count > 1`、現行の仕様）: `MultiPhotoRenderer`が
///   自動編集した画像は`ShareCollageStore`に完成品として保存済みのため、
///   ここでは読み込んで見せるだけ。デザインを選び直す余地は無い
///   （EventSnapが「どの写真を選び、どう並べるか」まで決め切っている）。
/// - 単写真Reel（`reel.photoIDs.count == 1`、旧バージョンで生成され端末に
///   残っている可能性があるものへの後方互換）: 従来どおりEditorial/Bold/Minimalを
///   ワンタップで切り替えながらシェアできる。写真解析（`PhotoAnalyzer`）は
///   この画面が開いたときに1回だけ行い、テンプレート切り替えのたびには
///   再解析しない（`SocialCardService.render`は軽い描画処理のみ）。
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

    /// 過去バージョンで生成された、写真1枚だけのReelかどうか
    private var isLegacySinglePhotoReel: Bool { reel.photoIDs.count <= 1 }

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
        .task {
            if isLegacySinglePhotoReel {
                await loadAndAnalyze()
            } else {
                loadMultiPhotoImage()
            }
        }
        .onChange(of: template) { _, newValue in
            rerender(for: newValue)
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
