//
//  EventSnapClipRootView.swift
//  EventSnapClip
//
//  App Clipの画面遷移。
//
//    起動(Universal Link) ──eventIDを解析──▶ 読み込み中 ──▶ イベントプレビュー
//                                                 │
//                                                 └─(失敗/見つからない)─▶ エラー表示
//
//  以前は「撮影はできるが投稿はできない」というカメラ主体の設計で、撮った写真の
//  見せ先が「アプリをダウンロードしてください」という案内だけだった。今回、撮影機能を
//  完全に廃止し、代わりに「QRコードで読み取ったイベントの、今の様子（写真・
//  Event Reel風のプレビュー）をその場で見られる」閲覧専用の体験に作り替えた。
//
//  CloudKitのPublic Databaseを読み取り専用で使用する（EventPreviewLoader参照）。
//  書き込みはこのターゲットのどこにも存在しない。カメラ権限も一切要求しない。
//

import SwiftUI

struct EventSnapClipRootView: View {
    @State private var event: Event?
    @State private var photos: [Photo] = []
    @State private var reelImage: UIImage?
    @State private var errorMessage: String?
    @State private var showGetAppScreen = false

    var body: some View {
        Group {
            if let event {
                EventPreviewScreen(
                    event: event,
                    photos: photos,
                    reelImage: reelImage,
                    onGetApp: { showGetAppScreen = true }
                )
            } else if let errorMessage {
                EventLoadErrorScreen(message: errorMessage)
            } else {
                EventLoadingScreen()
            }
        }
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { userActivity in
            guard let url = userActivity.webpageURL else { return }
            handle(url: url)
        }
        .fullScreenCover(isPresented: $showGetAppScreen) {
            GetAppScreen()
        }
    }

    private func handle(url: URL) {
        guard let eventID = Self.extractEventID(from: url) else {
            errorMessage = "このイベントは見つかりませんでした"
            return
        }
        Task { await load(eventID: eventID) }
    }

    private func load(eventID: UUID) async {
        errorMessage = nil
        do {
            guard let fetchedEvent = try await EventPreviewLoader.fetchEvent(id: eventID) else {
                errorMessage = "このイベントは見つかりませんでした"
                return
            }
            let fetchedPhotos = try await EventPreviewLoader.fetchPhotos(for: eventID)
            // タイムカプセルでまだ公開されていない写真は、撮影者本人を含め誰にも
            // 見せない仕様（TimeCapsuleService参照）。App Clipでも同じ扱いにする。
            let revealedPhotos = fetchedPhotos.filter { $0.isRevealed() }

            event = fetchedEvent
            photos = Array(revealedPhotos.prefix(6))
            await buildPreviewReel(event: fetchedEvent, revealedPhotos: revealedPhotos)
        } catch {
            errorMessage = "読み込みに失敗しました。ネットワーク接続を確認してください。"
        }
    }

    /// シェアOKの写真から、代表的な数枚(最大5枚)でその場でEvent Reel風の1枚を合成する。
    ///
    /// メインアプリのShareCollageBuilder/EventReelPhotoSelectorが行うような、
    /// バースト間引き・時間帯分散・撮影者の多様性ボーナスといった複雑な選定は
    /// App Clipには不要なため、直近の写真を単純に選ぶだけの簡易ロジックに留める。
    /// 生成した画像はCloudKit・ShareCollageStoreのどちらにも書き込まない。
    /// その場限りのローカル描画で、画面を離れれば消える。
    private func buildPreviewReel(event: Event, revealedPhotos: [Photo]) async {
        let shareApproved = revealedPhotos
            .filter { $0.isShareOK }
            .sorted { $0.uploadedAt < $1.uploadedAt }
        guard shareApproved.count >= 2 else { return }

        let picked = Array(shareApproved.suffix(5))

        var inputs: [MultiPhotoRenderer.PhotoInput] = []
        for photo in picked {
            guard let image = await PhotoImageLoader.shared.image(for: photo) else { continue }
            let analysis = PhotoAnalyzer.analyze(image)
            inputs.append(MultiPhotoRenderer.PhotoInput(image: image, importanceCenter: analysis.importanceCenter))
        }
        guard inputs.count >= 2 else { return }

        reelImage = SocialCardService.renderEventReel(
            photos: inputs,
            eventName: event.name,
            date: picked.last?.uploadedAt ?? event.createdAt,
            participantCount: event.participantIDs.count,
            photoCount: revealedPhotos.count
        )
    }

    /// Universal Link（`https://{host}/event/{eventID}`、またはクエリの`?eventID=`）から
    /// イベントIDを取り出す。`EventSnapApp.extractEventID`と同じ解析方式
    /// （パス2番目が"event"、または`eventID`クエリパラメータ）。
    private static func extractEventID(from url: URL) -> UUID? {
        let components = url.pathComponents
        if components.count >= 3, components[1] == "event", let id = UUID(uuidString: components[2]) {
            return id
        }
        if let urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let queryItems = urlComponents.queryItems,
           let eventIDItem = queryItems.first(where: { $0.name == "eventID" }),
           let value = eventIDItem.value,
           let id = UUID(uuidString: value) {
            return id
        }
        return nil
    }
}

// MARK: - イベントプレビュー画面

private struct EventPreviewScreen: View {
    let event: Event
    let photos: [Photo]
    let reelImage: UIImage?
    let onGetApp: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header

                if let reelImage {
                    reelSection(reelImage)
                }

                if !photos.isEmpty {
                    recentPhotosSection
                }

                ctaButton
                    .padding(.top, 4)
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(event.name)
                .font(.largeTitle.bold())
            Text(event.createdAt.formatted(date: .abbreviated, time: .omitted))
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.top, 12)
    }

    private func reelSection(_ image: UIImage) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("今の様子")
                .font(.headline)
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(color: .black.opacity(0.15), radius: 14, y: 6)
        }
    }

    private var recentPhotosSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("最近の写真")
                    .font(.headline)
                Spacer()
                Text("もっと見るにはアプリで")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 2),
                    GridItem(.flexible(), spacing: 2),
                    GridItem(.flexible(), spacing: 2),
                ],
                spacing: 2
            ) {
                ForEach(photos) { photo in
                    PreviewPhotoThumbnail(photo: photo)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private var ctaButton: some View {
        Button(action: onGetApp) {
            Text("アプリをダウンロードして参加する")
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(14)
        }
    }
}

/// アルバムグリッドの1マス分（メインアプリのPhotoCellに相当する、App Clip専用の
/// 最小実装。AlbumView.swiftはこのターゲットのメンバーではないため独立させている）。
private struct PreviewPhotoThumbnail: View {
    let photo: Photo
    @State private var image: UIImage?

    var body: some View {
        Rectangle()
            .fill(Color(.systemGray5))
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    ProgressView()
                        .scaleEffect(0.7)
                }
            }
            .clipped()
            .task {
                image = await PhotoImageLoader.shared.thumbnail(for: photo)
            }
    }
}

// MARK: - 読み込み中

private struct EventLoadingScreen: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("イベントを読み込んでいます…")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }
}

// MARK: - 読み込み失敗

private struct EventLoadErrorScreen: View {
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 44))
                .foregroundColor(.secondary)

            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }
}

#Preview {
    EventSnapClipRootView()
}
